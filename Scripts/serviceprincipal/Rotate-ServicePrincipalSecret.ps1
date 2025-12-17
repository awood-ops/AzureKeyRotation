<#
.SYNOPSIS
    Rotates Service Principal Client Secrets and securely stores them in Azure Key Vault.

    This script provides enterprise-grade client secret rotation with comprehensive error handling,
    security controls, and verbose logging options.

.DESCRIPTION
    Rotates the specified Service Principal client secret by creating a new credential and automatically
    stores the new secret value in Azure Key Vault for secure retrieval by applications. Optionally
    removes the old secret after rotation.

    Key Features:
    - Creates new client secret with configurable expiration
    - Secure storage in Azure Key Vault (supports cross-subscription/resource group)
    - Optional removal of old secrets after rotation
    - Comprehensive error handling and validation
    - Safety confirmations to prevent accidental rotations
    - Verbose logging with security warnings
    - Recovery options for failed Key Vault operations

.PARAMETER ApplicationId
    The Application (Client) ID of the Service Principal.

.PARAMETER DisplayName
    The display name of the Service Principal (alternative to ApplicationId).

.PARAMETER SecretDisplayName
    Display name for the new client secret. Defaults to "Rotated-<timestamp>".

.PARAMETER SecretExpirationMonths
    Number of months until the new client secret expires. Default is 12 months.
    Maximum allowed by Azure is 24 months.

.PARAMETER RemoveOldSecrets
    If specified, removes all existing client secrets after the new one is created and stored.
    WARNING: This will invalidate all existing secrets immediately!
    This ensures only one secret exists as the source of truth.

.PARAMETER KeyVaultName
    The name of the Azure Key Vault where the rotated secret will be stored.

.PARAMETER KeyVaultResourceGroup
    The name of the Azure Resource Group containing the Key Vault.

.PARAMETER KeyVaultSubscriptionId
    The Azure Subscription ID containing the Key Vault. Defaults to the current subscription.

.PARAMETER SecretName
    The name for the Key Vault secret. If not specified, generates name from service principal details.

.PARAMETER SecretExpiryDays
    Number of days after creation until the Key Vault secret expires. 
    Defaults to match the client secret expiration (SecretExpirationMonths converted to days).
    Setting this ensures secrets are rotated regularly for security compliance.

.PARAMETER Force
    Skips the confirmation prompt before rotating the secret.

.PARAMETER ShowVerbose
    Enables verbose output, including partial secret values (first 8 characters).
    WARNING: May expose sensitive secret material in logs/console output.

.PARAMETER ShowRecoverySecret
    Shows the full secret value in output when Key Vault storage fails (for recovery purposes).
    WARNING: This will expose sensitive secret material in logs/output. Use with extreme caution.

.SECURITY NOTES
    - Avoid using -ShowVerbose or -ShowRecoverySecret in production environments
    - Secret material is never logged to files by this script
    - Clear console history after running with secret-displaying options
    - Use secure logging solutions that automatically redact sensitive data
    - Secrets are stored as SecureString objects in memory and Key Vault

.EXAMPLE
    # Rotate service principal secret (interactive)
    .\Rotate-ServicePrincipalSecret.ps1 -ApplicationId "12345678-1234-1234-1234-123456789012" `
        -SecretDisplayName "Production-Secret" -SecretExpirationMonths 12 `
        -KeyVaultName "my-keyvault" -KeyVaultResourceGroup "my-rg" `
        -SecretName "app-client-secret" -SecretExpiryDays 90

.EXAMPLE
    # Force rotation without confirmation and remove old secrets
    .\Rotate-ServicePrincipalSecret.ps1 -ApplicationId "12345678-1234-1234-1234-123456789012" `
        -SecretDisplayName "Production-Secret" -SecretExpirationMonths 12 `
        -KeyVaultName "my-keyvault" -KeyVaultResourceGroup "my-rg" `
        -SecretName "app-client-secret" -Force -RemoveOldSecrets

.EXAMPLE
    # Rotate using display name instead of Application ID
    .\Rotate-ServicePrincipalSecret.ps1 -DisplayName "my-service-principal" `
        -SecretExpirationMonths 24 -KeyVaultName "my-keyvault" `
        -KeyVaultResourceGroup "my-rg" -SecretName "sp-secret"

.EXAMPLE
    # Verbose output (shows partial secret values)
    .\Rotate-ServicePrincipalSecret.ps1 -ApplicationId "12345678-1234-1234-1234-123456789012" `
        -KeyVaultName "my-keyvault" -KeyVaultResourceGroup "my-rg" `
        -SecretName "app-secret" -ShowVerbose

.EXAMPLE
    # Emergency recovery mode (shows full secret on failure)
    .\Rotate-ServicePrincipalSecret.ps1 -ApplicationId "12345678-1234-1234-1234-123456789012" `
        -KeyVaultName "my-keyvault" -KeyVaultResourceGroup "my-rg" `
        -SecretName "app-secret" -ShowRecoverySecret

.EXAMPLE
    # Cross-subscription rotation (Key Vault in different subscription)
    .\Rotate-ServicePrincipalSecret.ps1 -ApplicationId "12345678-1234-1234-1234-123456789012" `
        -KeyVaultName "my-keyvault" -KeyVaultResourceGroup "security-rg" `
        -KeyVaultSubscriptionId "22222222-2222-2222-2222-222222222222" `
        -SecretName "app-secret" -Force

.NOTES
    Author: Andrew Wood
    Version: 1.0
    Requires: Az.Accounts, Az.Resources, Az.KeyVault PowerShell modules
    Azure Context: Must be connected to Azure (run Connect-AzAccount first)

    MINIMUM RBAC PERMISSIONS REQUIRED:

    Microsoft Entra ID (Azure AD) Permissions:
    - Application Administrator (recommended)
      OR
    - Application.ReadWrite.All (API permission)
      OR
    - Specific application owner

    Key Vault Permissions:
    - Key Vault Secrets Officer (recommended)
      OR
    - Microsoft.KeyVault/vaults/secrets/read
    - Microsoft.KeyVault/vaults/secrets/write

.LINK
    https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
    https://docs.microsoft.com/en-us/azure/key-vault/secrets/
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ApplicationId,

    [Parameter(Mandatory = $false)]
    [string]$DisplayName,

    [Parameter(Mandatory = $false)]
    [string]$SecretDisplayName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 24)]
    [int]$SecretExpirationMonths = 12,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveOldSecrets,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$KeyVaultSubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$SecretName,

    [Parameter(Mandatory = $false)]
    [int]$SecretExpiryDays = -1,  # -1 means use same as client secret expiration

    [switch]$Force,
    [switch]$ShowVerbose,
    [switch]$ShowRecoverySecret
)

# Validate parameters
if (-not $ApplicationId -and -not $DisplayName) {
    Write-Error "Either ApplicationId or DisplayName must be specified."
    exit 1
}

if ($ApplicationId -and $DisplayName) {
    Write-Warning "Both ApplicationId and DisplayName specified. ApplicationId will be used."
}

# Set verbose preference
if ($ShowVerbose) {
    $VerbosePreference = "Continue"
}

Write-Host "=== Service Principal Secret Rotation Script ===" -ForegroundColor Cyan
if ($ApplicationId) {
    Write-Host "Application ID: $ApplicationId" -ForegroundColor Gray
}
if ($DisplayName) {
    Write-Host "Display Name: $DisplayName" -ForegroundColor Gray
}
Write-Host "Secret Expiration: $SecretExpirationMonths months" -ForegroundColor Gray
Write-Host "Key Vault: $KeyVaultName" -ForegroundColor Gray
Write-Host "Key Vault RG: $KeyVaultResourceGroup" -ForegroundColor Gray
if ($KeyVaultSubscriptionId) {
    Write-Host "Key Vault Sub: $KeyVaultSubscriptionId" -ForegroundColor Gray
}
if ($RemoveOldSecrets) {
    Write-Host "⚠️  Remove Old Secrets: YES" -ForegroundColor Yellow
}
if ($ShowVerbose) {
    Write-Host "⚠️  VERBOSE MODE: Partial secret values may be displayed" -ForegroundColor Yellow
}
if ($ShowRecoverySecret) {
    Write-Host "🔴 SHOW RECOVERY SECRET: Full secret values may be exposed on errors" -ForegroundColor Red
}
Write-Host "=====================================" -ForegroundColor Cyan

# Ensure needed modules exist
Write-Host "`n[1/8] Checking required modules..." -ForegroundColor Yellow
foreach ($module in @("Az.Accounts","Az.Resources","Az.KeyVault")) {
    try {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "  Installing $module module..." -ForegroundColor Gray
            Install-Module $module -Force -AllowClobber -ErrorAction Stop
            Write-Host "  ✓ $module module installed successfully" -ForegroundColor Green
        } else {
            Write-Host "  ✓ $module module is available" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to install or verify $module module: $_"
        exit 1
    }
}

Write-Host "`n[2/8] Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        throw "Not connected to Azure. Please run Connect-AzAccount first."
    }
    Write-Host "  ✓ Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "  ✓ Tenant: $($context.Tenant.Id)" -ForegroundColor Green
    Write-Host "  ✓ Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
}
catch {
    Write-Error "Failed to verify Azure connection: $_"
    Write-Host "Please run 'Connect-AzAccount' and try again." -ForegroundColor Red
    exit 1
}

Write-Host "`n[3/8] Retrieving Service Principal..." -ForegroundColor Yellow
try {
    # Get the service principal
    if ($ApplicationId) {
        $app = Get-AzADApplication -ApplicationId $ApplicationId -ErrorAction Stop
        $sp = Get-AzADServicePrincipal -ApplicationId $ApplicationId -ErrorAction Stop
    } else {
        $app = Get-AzADApplication -DisplayName $DisplayName -ErrorAction Stop
        $sp = Get-AzADServicePrincipal -DisplayName $DisplayName -ErrorAction Stop
    }

    if (-not $app) {
        throw "Application not found"
    }
    if (-not $sp) {
        throw "Service Principal not found"
    }

    Write-Host "  ✓ Service Principal found" -ForegroundColor Green
    Write-Host "  Display Name: $($app.DisplayName)" -ForegroundColor Gray
    Write-Host "  Application ID: $($app.AppId)" -ForegroundColor Gray
    Write-Host "  Object ID: $($sp.Id)" -ForegroundColor Gray

    # Store for later use
    $ApplicationId = $app.AppId
}
catch {
    Write-Error "Failed to retrieve Service Principal: $_"
    Write-Host "Please verify:" -ForegroundColor Red
    if ($ApplicationId) {
        Write-Host "  - Application with ID '$ApplicationId' exists" -ForegroundColor Red
    } else {
        Write-Host "  - Application with display name '$DisplayName' exists" -ForegroundColor Red
    }
    Write-Host "  - You have permissions to read the application" -ForegroundColor Red
    exit 1
}

# Get existing secrets
Write-Host "`n[4/8] Checking existing secrets..." -ForegroundColor Yellow
try {
    # Get all credentials first
    $allCredentials = Get-AzADAppCredential -ObjectId $app.Id -ErrorAction Stop
    
    # Filter for secrets only (exclude certificates)
    # Note: Secrets have no CustomKeyIdentifier, certificates do
    $existingSecrets = $allCredentials | Where-Object { 
        $null -eq $_.CustomKeyIdentifier -or $_.CustomKeyIdentifier.Length -eq 0
    }
    
    if ($existingSecrets -and $existingSecrets.Count -gt 0) {
        Write-Host "  ✓ Found $($existingSecrets.Count) existing secret(s)" -ForegroundColor Green
        Write-Host "  All credentials retrieved: $($allCredentials.Count)" -ForegroundColor Gray
        foreach ($secret in $existingSecrets) {
            $preview = $secret.KeyId.ToString().Substring(0,8)
            Write-Host "    - KeyId: $preview... | Expires: $($secret.EndDateTime)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ℹ No existing secrets found" -ForegroundColor Gray
        Write-Host "  Total credentials retrieved: $($allCredentials.Count)" -ForegroundColor Gray
    }
}
catch {
    Write-Warning "Could not retrieve existing secrets: $_"
    $existingSecrets = @()
}

# Confirm operation if not forced
if (-not $Force) {
    Write-Host "`n⚠️  WARNING: This will create a new client secret for '$($app.DisplayName)'" -ForegroundColor Yellow
    if ($RemoveOldSecrets) {
        Write-Host "   ⚠️  All existing secrets will be REMOVED after rotation!" -ForegroundColor Red
        Write-Host "   This will invalidate all applications using the old secrets immediately!" -ForegroundColor Red
    }
    $confirmation = Read-Host "   Are you sure you want to continue? (yes/no)"

    if ($confirmation -ne "yes") {
        Write-Host "Operation cancelled by user." -ForegroundColor Red
        exit 0
    }
}

# Generate secret display name if not provided
if (-not $SecretDisplayName) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $SecretDisplayName = "Rotated-$timestamp"
}

Write-Host "`n[5/8] Creating new client secret..." -ForegroundColor Yellow
try {
    # Calculate expiration date
    $secretEndDate = (Get-Date).AddMonths($SecretExpirationMonths)

    # Create new secret
    $newSecret = New-AzADAppCredential `
        -ObjectId $app.Id `
        -EndDate $secretEndDate `
        -ErrorAction Stop

    Write-Host "  ✓ New client secret created successfully" -ForegroundColor Green
    if ($SecretDisplayName) {
        Write-Host "  Display Name: $SecretDisplayName (note: Azure may not preserve this)" -ForegroundColor Gray
    }
    Write-Host "  Key ID: $($newSecret.KeyId)" -ForegroundColor Gray
    Write-Host "  Expires: $secretEndDate" -ForegroundColor Gray
    
    if ($ShowVerbose) {
        Write-Host "  Secret Value Preview: $($newSecret.SecretText.Substring(0,8))..." -ForegroundColor Gray
        Write-Host "  ⚠️  WARNING: Partial secret display enabled in verbose mode" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Failed to create new client secret: $_"
    Write-Host "Please verify:" -ForegroundColor Red
    Write-Host "  - You have permissions to manage application credentials" -ForegroundColor Red
    Write-Host "  - The application allows secret creation" -ForegroundColor Red
    exit 1
}

# Generate Key Vault secret name if not provided
if (-not $SecretName) {
    $SecretName = "$($app.DisplayName)-client-secret".ToLower() -replace '[^a-z0-9-]', '-'
}

Write-Host "`n[6/8] Switching to Key Vault context..." -ForegroundColor Yellow
$originalContext = $null
try {
    if ($KeyVaultSubscriptionId -and $KeyVaultSubscriptionId -ne $context.Subscription.Id) {
        Write-Host "  Switching to subscription: $KeyVaultSubscriptionId" -ForegroundColor Gray
        $originalContext = $context
        Set-AzContext -SubscriptionId $KeyVaultSubscriptionId -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Switched to Key Vault subscription" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Using current subscription for Key Vault" -ForegroundColor Green
    }
}
catch {
    Write-Error "Failed to switch to Key Vault subscription: $_"
    exit 1
}

Write-Host "`n[7/8] Writing new secret to Key Vault..." -ForegroundColor Yellow
try {
    # Check if Key Vault exists
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $KeyVaultResourceGroup -ErrorAction Stop
    Write-Host "  ✓ Key Vault '$KeyVaultName' found" -ForegroundColor Green

    # Calculate Key Vault secret expiry date (align with client secret if not specified)
    if ($SecretExpiryDays -eq -1) {
        $kvSecretExpiryDate = $secretEndDate
        Write-Host "  Key Vault secret expiry aligned with client secret: $kvSecretExpiryDate" -ForegroundColor Gray
    } else {
        $kvSecretExpiryDate = (Get-Date).AddDays($SecretExpiryDays)
        Write-Host "  Key Vault secret expiry set to $SecretExpiryDays days: $kvSecretExpiryDate" -ForegroundColor Gray
    }

    # Store the secret
    $kvSecret = Set-AzKeyVaultSecret `
        -VaultName $KeyVaultName `
        -Name $SecretName `
        -SecretValue (ConvertTo-SecureString $newSecret.SecretText -AsPlainText -Force) `
        -Expires $kvSecretExpiryDate `
        -ContentType "Service Principal Client Secret - Automatically rotated by script" `
        -Tag @{
            ApplicationId = $ApplicationId
            DisplayName = $app.DisplayName
            SecretKeyId = $newSecret.KeyId
            RotatedDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            RotatedBy = $context.Account.Id
        } `
        -ErrorAction Stop

    Write-Host "  ✓ Secret '$SecretName' created/updated successfully" -ForegroundColor Green
    if ($ShowVerbose) {
        Write-Host "  Secret ID: $($kvSecret.Id)" -ForegroundColor Gray
        Write-Host "  Secret Version: $($kvSecret.Version)" -ForegroundColor Gray
        Write-Host "  Expires: $kvSecretExpiryDate" -ForegroundColor Gray
    }
}
catch {
    Write-Error "Failed to write secret to Key Vault: $_"
    Write-Host "Please verify:" -ForegroundColor Red
    Write-Host "  - Key Vault '$KeyVaultName' exists in resource group '$KeyVaultResourceGroup'" -ForegroundColor Red
    Write-Host "  - You have permissions to write secrets" -ForegroundColor Red
    Write-Host "  - Secret name '$SecretName' is valid" -ForegroundColor Red

    # Attempt to show the new secret value for manual recovery
    Write-Host "`n⚠️  IMPORTANT: Secret rotation succeeded but Key Vault storage failed!" -ForegroundColor Yellow
    Write-Host "   The new secret has been generated but could not be stored in Key Vault." -ForegroundColor Yellow

    if ($ShowRecoverySecret) {
        Write-Host "   🔴 SECURITY WARNING: Displaying full secret value as requested!" -ForegroundColor Red
        Write-Host "   New Client Secret: $($newSecret.SecretText)" -ForegroundColor Red
        Write-Host "   Key ID: $($newSecret.KeyId)" -ForegroundColor Red
        Write-Host "   🔴 IMMEDIATELY store this secret securely and clear your command history!" -ForegroundColor Red
    } else {
        Write-Host "   To view the new secret value, re-run with -ShowRecoverySecret parameter" -ForegroundColor Yellow
        Write-Host "   WARNING: This will expose the secret in your console/logs!" -ForegroundColor Yellow
        Write-Host "   Alternative: Check the Azure Portal for the new secret value" -ForegroundColor Yellow
    }

    exit 1
}

# Remove old secrets if requested (BEFORE switching contexts)
if ($RemoveOldSecrets -and $existingSecrets.Count -gt 0) {
    Write-Host "`n[8/8] Removing old secrets..." -ForegroundColor Yellow
    
    # Switch back to original context if needed (for Entra ID operations)
    if ($originalContext) {
        Write-Host "  Switching back to original context for Entra ID operations..." -ForegroundColor Gray
        Set-AzContext -SubscriptionId $originalContext.Subscription.Id -ErrorAction Stop | Out-Null
    }
    
    $removedCount = 0
    $failedCount = 0
    
    foreach ($oldSecret in $existingSecrets) {
        # Skip the newly created secret
        if ($oldSecret.KeyId -eq $newSecret.KeyId) {
            Write-Host "  ℹ Skipping newly created secret: $($oldSecret.KeyId)" -ForegroundColor Gray
            continue
        }
        
        try {
            Remove-AzADAppCredential -ObjectId $app.Id -KeyId $oldSecret.KeyId -ErrorAction Stop
            Write-Host "  ✓ Removed secret KeyId: $($oldSecret.KeyId.ToString().Substring(0,8))..." -ForegroundColor Green
            $removedCount++
        }
        catch {
            Write-Warning "Failed to remove secret $($oldSecret.KeyId): $_"
            $failedCount++
        }
    }
    
    Write-Host "  Summary: Removed $removedCount secret(s), $failedCount failed" -ForegroundColor $(if ($failedCount -gt 0) { "Yellow" } else { "Green" })
} else {
    Write-Host "`n[8/8] Skipping old secret removal..." -ForegroundColor Yellow
    Write-Host "  ℹ Old secrets remain active. Use -RemoveOldSecrets to remove them." -ForegroundColor Gray
}

Write-Host "`n[9/9] Cleanup..." -ForegroundColor Yellow
try {
    # Restore context if needed
    if ($originalContext) {
        Write-Host "  Switching back to previous subscription: $($originalContext.Subscription.Id)" -ForegroundColor Gray
        Set-AzContext -SubscriptionId $originalContext.Subscription.Id -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Restored previous context" -ForegroundColor Green
    } else {
        Write-Host "  ✓ No context switches needed" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Failed to restore context: $_"
}

Write-Host "`n🎉 ROTATION COMPLETE!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Summary:" -ForegroundColor White
Write-Host "  • Service Principal: $($app.DisplayName)" -ForegroundColor White
Write-Host "  • Application ID: $ApplicationId" -ForegroundColor White
Write-Host "  • Secret Display Name: $SecretDisplayName" -ForegroundColor White
Write-Host "  • Secret Key ID: $($newSecret.KeyId)" -ForegroundColor White
Write-Host "  • Secret Expires: $secretEndDate" -ForegroundColor White
Write-Host "  • Key Vault: $KeyVaultName" -ForegroundColor White
Write-Host "  • KV Secret Name: $SecretName" -ForegroundColor White
Write-Host "  • KV Secret ID: $($kvSecret.Id)" -ForegroundColor White
Write-Host "  • KV Secret Expires: $kvSecretExpiryDate" -ForegroundColor White
if ($RemoveOldSecrets) {
    Write-Host "  • Old Secrets Removed: $removedCount" -ForegroundColor White
}
Write-Host "" -ForegroundColor White
Write-Host "⚠️  Remember to update any applications using the old secret!" -ForegroundColor Yellow
if ($ShowVerbose -or $ShowRecoverySecret) {
    Write-Host "🔒 SECURITY: Clear console history and logs containing secret material!" -ForegroundColor Red
}
Write-Host "=====================================" -ForegroundColor Green
