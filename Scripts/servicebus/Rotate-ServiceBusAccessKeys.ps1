<#
.SYNOPSIS
    Rotates Service Bus Namespace or Entity (Queue/Topic) Access Keys (Primary or Secondary) and securely stores them in Azure Key Vault.

    This script provides enterprise-grade key rotation with comprehensive error handling,
    security controls, and verbose logging options.

.DESCRIPTION
    Rotates the specified Service Bus namespace or entity access key (Primary or Secondary) and automatically
    stores the new key value in Azure Key Vault for secure retrieval by applications.

    Key Features:
    - Rotates Primary or Secondary keys for namespaces or entities (Queues/Topics)
    - Secure storage in Azure Key Vault (supports cross-subscription/resource group)
    - Comprehensive error handling and validation
    - Safety confirmations to prevent accidental rotations
    - Verbose logging with security warnings
    - Recovery options for failed Key Vault operations

.PARAMETER ResourceGroup
    The name of the Azure Resource Group containing the Service Bus namespace.

.PARAMETER ServiceBusSubscriptionId
    The Azure Subscription ID containing the Service Bus namespace. Defaults to the current subscription.

.PARAMETER ServiceBusNamespace
    The name of the Service Bus namespace.

.PARAMETER EntityName
    The name of the specific Service Bus entity (Queue or Topic) (optional). If not specified, rotates namespace-level keys.

.PARAMETER EntityType
    The type of the entity. Valid values: "Queue", "Topic". Required if EntityName is specified.

.PARAMETER KeyName
    The name of the authorization rule/key to rotate (e.g., "RootManageSharedAccessKey").

.PARAMETER Rotate
    Specifies which key to rotate. Valid values: "Primary", "Secondary".

.PARAMETER KeyVaultName
    The name of the Azure Key Vault where the rotated key will be stored.

.PARAMETER KeyVaultResourceGroup
    The name of the Azure Resource Group containing the Key Vault. Defaults to the same as ResourceGroup.

.PARAMETER KeyVaultSubscriptionId
    The Azure Subscription ID containing the Key Vault. Defaults to the current subscription.

.PARAMETER SecretExpiryDays
    Number of days after creation until the Key Vault secret expires. Default is 90 days.
    Setting this ensures secrets are rotated regularly for security compliance.

.PARAMETER Force
    Skips the confirmation prompt before rotating the key.

.PARAMETER ShowVerbose
    Enables verbose output, including partial key values (first 8 characters).
    WARNING: May expose sensitive key material in logs/console output.

.PARAMETER ShowRecoveryKey
    Shows the full key value in output when Key Vault storage fails (for recovery purposes).
    WARNING: This will expose sensitive key material in logs/output. Use with extreme caution.

.SECURITY NOTES
    - Avoid using -ShowVerbose or -ShowRecoveryKey in production environments
    - Key material is never logged to files by this script
    - Clear console history after running with key-displaying options
    - Use secure logging solutions that automatically redact sensitive data
    - Keys are stored as SecureString objects in memory and Key Vault

.EXAMPLE
    # Rotate namespace-level keys (interactive)
    .\Rotate-ServiceBusAccessKeys.ps1 -ResourceGroup "my-rg" -ServiceBusNamespace "my-namespace" `
        -KeyName "RootManageSharedAccessKey" -Rotate "Primary" `
        -KeyVaultName "my-keyvault" -SecretNamePrefix "servicebus" `
        -SecretExpiryDays 90

.EXAMPLE
    # Rotate Queue keys (interactive)
    .\Rotate-ServiceBusAccessKeys.ps1 -ResourceGroup "my-rg" -ServiceBusNamespace "my-namespace" `
        -EntityName "my-queue" -EntityType "Queue" -KeyName "SendListen" -Rotate "Primary" `
        -KeyVaultName "my-keyvault" -SecretNamePrefix "servicebus"

.EXAMPLE
    # Force rotation without confirmation (namespace)
    .\Rotate-ServiceBusAccessKeys.ps1 -ResourceGroup "my-rg" -ServiceBusNamespace "my-namespace" `
        -KeyName "RootManageSharedAccessKey" -Rotate "Primary" `
        -KeyVaultName "my-keyvault" -SecretNamePrefix "servicebus" -Force `
        -SecretExpiryDays 30

.EXAMPLE
    # Verbose output (shows partial key values)
    .\Rotate-ServiceBusAccessKeys.ps1 -ResourceGroup "my-rg" -ServiceBusNamespace "my-namespace" `
        -EntityName "my-queue" -EntityType "Queue" -KeyName "SendListen" -Rotate "Primary" `
        -KeyVaultName "my-keyvault" -SecretNamePrefix "servicebus" -ShowVerbose

.EXAMPLE
    # Emergency recovery mode (shows full keys on failure)
    .\Rotate-ServiceBusAccessKeys.ps1 -ResourceGroup "my-rg" -ServiceBusNamespace "my-namespace" `
        -EntityName "my-queue" -EntityType "Queue" -KeyName "SendListen" -Rotate "Primary" `
        -KeyVaultName "my-keyvault" -SecretNamePrefix "servicebus" -ShowRecoveryKey

.EXAMPLE
    # Cross-subscription rotation (Service Bus and Key Vault in different subscriptions)
    .\Rotate-ServiceBusAccessKeys.ps1 -ResourceGroup "servicebus-rg" -ServiceBusSubscriptionId "11111111-1111-1111-1111-111111111111" `
        -ServiceBusNamespace "my-namespace" -EntityName "my-queue" -EntityType "Queue" -KeyName "SendListen" -Rotate "Primary" `
        -KeyVaultName "my-keyvault" -KeyVaultResourceGroup "security-rg" -KeyVaultSubscriptionId "22222222-2222-2222-2222-222222222222" `
        -SecretNamePrefix "servicebus" -Force

.NOTES
    Author: Andrew Wood
    Version: 2.1
    Requires: Az.ServiceBus, Az.KeyVault PowerShell modules
    Azure Context: Must be connected to Azure (run Connect-AzAccount first)

    MINIMUM RBAC PERMISSIONS REQUIRED:

    Key Vault Permissions:
    - Key Vault Secrets Officer (recommended)
      OR
    - Microsoft.KeyVault/vaults/secrets/read
    - Microsoft.KeyVault/vaults/secrets/write

    Service Bus Permissions:
    - Azure Service Bus Data Owner (recommended for both namespace and entity operations)
      OR for namespace-level operations:
    - Microsoft.ServiceBus/namespaces/authorizationRules/read
    - Microsoft.ServiceBus/namespaces/authorizationRules/write
      OR for entity operations:
    - Microsoft.ServiceBus/namespaces/queues/authorizationRules/read
    - Microsoft.ServiceBus/namespaces/queues/authorizationRules/write
      OR
    - Microsoft.ServiceBus/namespaces/topics/authorizationRules/read
    - Microsoft.ServiceBus/namespaces/topics/authorizationRules/write

.LINK
    https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-sas
    https://docs.microsoft.com/en-us/azure/key-vault/secrets/
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ServiceBusSubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ServiceBusNamespace,

    [Parameter(Mandatory = $false)]
    [string]$EntityName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Queue","Topic")]
    [string]$EntityType,

    [Parameter(Mandatory = $true)]
    [string]$KeyName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Primary","Secondary")]
    [string]$Rotate,

    # New parameters for Key Vault output
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [string]$KeyVaultResourceGroup = $ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$KeyVaultSubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$SecretNamePrefix,

    [Parameter(Mandatory = $false)]
    [int]$SecretExpiryDays = 90,

    [switch]$Force,
    [switch]$ShowVerbose,
    [switch]$ShowRecoveryKey
)

# Validate parameters
if ($EntityName -and -not $EntityType) {
    Write-Error "EntityType must be specified when EntityName is provided."
    exit 1
}
if ($EntityType -and -not $EntityName) {
    Write-Error "EntityName must be specified when EntityType is provided."
    exit 1
}

# Set verbose preference
if ($ShowVerbose) {
    $VerbosePreference = "Continue"
}

# Determine rotation scope
$isNamespaceLevel = [string]::IsNullOrEmpty($EntityName)
$scopeDescription = if ($isNamespaceLevel) { "Service Bus Namespace" } else { "Service Bus $EntityType '$EntityName'" }

Write-Host "=== Service Bus Key Rotation Script ===" -ForegroundColor Cyan
Write-Host "Namespace: $ServiceBusNamespace" -ForegroundColor Gray
if (-not $isNamespaceLevel) {
    Write-Host "Entity: $EntityName ($EntityType)" -ForegroundColor Gray
}
Write-Host "Key Name: $KeyName" -ForegroundColor Gray
Write-Host "Rotating: $Rotate Key" -ForegroundColor Gray
Write-Host "Scope: $scopeDescription" -ForegroundColor Gray
Write-Host "Service Bus RG: $ResourceGroup" -ForegroundColor Gray
if ($ServiceBusSubscriptionId) {
    Write-Host "Service Bus Sub: $ServiceBusSubscriptionId" -ForegroundColor Gray
}
Write-Host "Key Vault: $KeyVaultName" -ForegroundColor Gray
Write-Host "Key Vault RG: $KeyVaultResourceGroup" -ForegroundColor Gray
if ($KeyVaultSubscriptionId) {
    Write-Host "Key Vault Sub: $KeyVaultSubscriptionId" -ForegroundColor Gray
}
if ($ShowVerbose) {
    Write-Host "⚠️  VERBOSE MODE: Partial key values may be displayed" -ForegroundColor Yellow
}
if ($ShowRecoveryKey) {
    Write-Host "🔴 SHOW RECOVERY KEY: Full key values may be exposed on errors" -ForegroundColor Red
}
Write-Host "=====================================" -ForegroundColor Cyan

# Ensure needed modules exist
Write-Host "`n[1/8] Checking required modules..." -ForegroundColor Yellow
foreach ($module in @("Az.ServiceBus","Az.KeyVault")) {
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

# Confirm operation if not forced
if (-not $Force) {
    $targetDescription = if ($isNamespaceLevel) {
        "Service Bus namespace '$ServiceBusNamespace'"
    } else {
        "Service Bus $EntityType '$EntityName' in namespace '$ServiceBusNamespace'"
    }
    Write-Host "`n⚠️  WARNING: This will rotate the $Rotate key for $targetDescription" -ForegroundColor Yellow
    Write-Host "   This action cannot be undone and may impact applications using this key." -ForegroundColor Yellow
    $confirmation = Read-Host "   Are you sure you want to continue? (yes/no)"

    if ($confirmation -ne "yes") {
        Write-Host "Operation cancelled by user." -ForegroundColor Red
        exit 0
    }
}

Write-Host "`n[2/8] Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        throw "Not connected to Azure. Please run Connect-AzAccount first."
    }
    Write-Host "  ✓ Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "  ✓ Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
}
catch {
    Write-Error "Failed to verify Azure connection: $_"
    Write-Host "Please run 'Connect-AzAccount' and try again." -ForegroundColor Red
    exit 1
}

Write-Host "`n[3/8] Switching to Service Bus context..." -ForegroundColor Yellow
$serviceBusOriginalContext = $null
try {
    if ($ServiceBusSubscriptionId -and $ServiceBusSubscriptionId -ne $context.Subscription.Id) {
        Write-Host "  Switching to subscription: $ServiceBusSubscriptionId" -ForegroundColor Gray
        $serviceBusOriginalContext = $context
        Set-AzContext -SubscriptionId $ServiceBusSubscriptionId -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Switched to Service Bus subscription" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Using current subscription for Service Bus" -ForegroundColor Green
    }
}
catch {
    Write-Error "Failed to switch to Service Bus subscription: $_"
    exit 1
}

Write-Host "`n[4/8] Fetching current key set..." -ForegroundColor Yellow
try {
    if ($isNamespaceLevel) {
        $keys = Get-AzServiceBusKey `
            -ResourceGroupName $ResourceGroup `
            -Namespace $ServiceBusNamespace `
            -Name $KeyName `
            -ErrorAction Stop
    } else {
        if ($EntityType -eq "Queue") {
            $keys = Get-AzServiceBusKey `
                -ResourceGroupName $ResourceGroup `
                -Namespace $ServiceBusNamespace `
                -Queue $EntityName `
                -Name $KeyName `
                -ErrorAction Stop
        } else {
            $keys = Get-AzServiceBusKey `
                -ResourceGroupName $ResourceGroup `
                -Namespace $ServiceBusNamespace `
                -Topic $EntityName `
                -Name $KeyName `
                -ErrorAction Stop
        }
    }

    Write-Host "  ✓ Successfully retrieved current keys" -ForegroundColor Green
    if ($ShowVerbose) {
        Write-Host "  Current Primary Key: $($keys.PrimaryKey.Substring(0,8))..." -ForegroundColor Gray
        Write-Host "  Current Secondary Key: $($keys.SecondaryKey.Substring(0,8))..." -ForegroundColor Gray
        Write-Host "  ⚠️  WARNING: Partial key display enabled in verbose mode" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Failed to retrieve current keys: $_"
    Write-Host "Please verify:" -ForegroundColor Red
    Write-Host "  - Resource Group '$ResourceGroup' exists" -ForegroundColor Red
    Write-Host "  - Service Bus Namespace '$ServiceBusNamespace' exists" -ForegroundColor Red
    if (-not $isNamespaceLevel) {
        Write-Host "  - $EntityType '$EntityName' exists" -ForegroundColor Red
    }
    Write-Host "  - Authorization Rule '$KeyName' exists" -ForegroundColor Red
    exit 1
}

# Determine which key to rotate
$regenerateTarget = if ($Rotate -eq "Primary") { "PrimaryKey" } else { "SecondaryKey" }

Write-Host "`n[5/8] Regenerating $Rotate key..." -ForegroundColor Yellow
try {
    if ($isNamespaceLevel) {
        $newKeys = New-AzServiceBusKey `
            -ResourceGroupName $ResourceGroup `
            -Namespace $ServiceBusNamespace `
            -Name $KeyName `
            -RegenerateKey $regenerateTarget `
            -ErrorAction Stop
    } else {
        if ($EntityType -eq "Queue") {
            $newKeys = New-AzServiceBusKey `
                -ResourceGroupName $ResourceGroup `
                -Namespace $ServiceBusNamespace `
                -Queue $EntityName `
                -Name $KeyName `
                -RegenerateKey $regenerateTarget `
                -ErrorAction Stop
        } else {
            $newKeys = New-AzServiceBusKey `
                -ResourceGroupName $ResourceGroup `
                -Namespace $ServiceBusNamespace `
                -Topic $EntityName `
                -Name $KeyName `
                -RegenerateKey $regenerateTarget `
                -ErrorAction Stop
        }
    }

    Write-Host "  ✓ $Rotate key regenerated successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to regenerate $Rotate key: $_"
    exit 1
}

# Capture the new key value
$newKeyValue = if ($Rotate -eq "Primary") { $newKeys.PrimaryKey } else { $newKeys.SecondaryKey }

# Build Key Vault secret name
$secretNameBase = if ($isNamespaceLevel) {
    "$SecretNamePrefix-$ServiceBusNamespace-$KeyName"
} else {
    "$SecretNamePrefix-$ServiceBusNamespace-$EntityName-$KeyName"
}
$secretName = "$secretNameBase-$Rotate".ToLower()

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

Write-Host "`n[7/8] Writing new $Rotate key to Key Vault..." -ForegroundColor Yellow
try {
    # Check if Key Vault exists
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop
    Write-Host "  ✓ Key Vault '$KeyVaultName' found" -ForegroundColor Green

    # Calculate expiry date
    $expiryDate = (Get-Date).AddDays($SecretExpiryDays)

    # Store the secret
    $secret = Set-AzKeyVaultSecret `
        -VaultName $KeyVaultName `
        -Name $secretName `
        -SecretValue (ConvertTo-SecureString $newKeyValue -AsPlainText -Force) `
        -Expires $expiryDate `
        -ErrorAction Stop

    Write-Host "  ✓ Secret '$secretName' created/updated successfully" -ForegroundColor Green
    if ($ShowVerbose) {
        Write-Host "  Secret ID: $($secret.Id)" -ForegroundColor Gray
        Write-Host "  Secret Version: $($secret.Version)" -ForegroundColor Gray
        Write-Host "  Expires: $expiryDate" -ForegroundColor Gray
    }
}
catch {
    Write-Error "Failed to write secret to Key Vault: $_"
    Write-Host "Please verify:" -ForegroundColor Red
    Write-Host "  - Key Vault '$KeyVaultName' exists" -ForegroundColor Red
    Write-Host "  - You have permissions to write secrets" -ForegroundColor Red
    Write-Host "  - Secret name '$secretName' is valid" -ForegroundColor Red

    # Attempt to show the new key value for manual recovery
    Write-Host "`n⚠️  IMPORTANT: Key rotation succeeded but Key Vault storage failed!" -ForegroundColor Yellow
    Write-Host "   The new key has been generated but could not be stored in Key Vault." -ForegroundColor Yellow

    if ($ShowRecoveryKey) {
        Write-Host "   🔴 SECURITY WARNING: Displaying full key value as requested!" -ForegroundColor Red
        Write-Host "   New $Rotate Key Value: $newKeyValue" -ForegroundColor Red
        Write-Host "   🔴 IMMEDIATELY store this key securely and clear your command history!" -ForegroundColor Red
    } else {
        Write-Host "   To view the new key value, re-run with -ShowRecoveryKey parameter" -ForegroundColor Yellow
        Write-Host "   WARNING: This will expose the key in your console/logs!" -ForegroundColor Yellow
        Write-Host "   Alternative: Check the Service Bus portal for the new key value" -ForegroundColor Yellow
    }

    exit 1
}

Write-Host "`n[7/8] Validating rotation..." -ForegroundColor Yellow
try {
    # Verify the key was stored correctly
    $storedSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -ErrorAction Stop
    Write-Host "  ✓ Secret validation successful" -ForegroundColor Green

    if ($ShowVerbose) {
        Write-Host "  Stored Secret ID: $($storedSecret.Id)" -ForegroundColor Gray
        Write-Host "  Created: $($storedSecret.Created)" -ForegroundColor Gray
        Write-Host "  Updated: $($storedSecret.Updated)" -ForegroundColor Gray
    }
}
catch {
    Write-Warning "Could not validate stored secret: $_"
}

Write-Host "`n[8/8] Cleanup..." -ForegroundColor Yellow
try {
    # Restore Key Vault context if needed
    if ($originalContext) {
        $targetContext = if ($serviceBusOriginalContext) { $serviceBusOriginalContext } else { $originalContext }
        Write-Host "  Switching back to previous context: $($targetContext.Subscription.Id)" -ForegroundColor Gray
        Set-AzContext -SubscriptionId $targetContext.Subscription.Id -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Restored previous context" -ForegroundColor Green
    }
    
    # Restore Service Bus context if needed
    if ($serviceBusOriginalContext) {
        Write-Host "  Switching back to original subscription: $($serviceBusOriginalContext.Subscription.Id)" -ForegroundColor Gray
        Set-AzContext -SubscriptionId $serviceBusOriginalContext.Subscription.Id -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Restored original context" -ForegroundColor Green
    }
    
    if (-not $originalContext -and -not $serviceBusOriginalContext) {
        Write-Host "  ✓ No context switches needed" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Failed to restore context: $_"
}

Write-Host "`n🎉 ROTATION COMPLETE!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Summary:" -ForegroundColor White
Write-Host "  • Service Bus Namespace: $ServiceBusNamespace" -ForegroundColor White
if (-not $isNamespaceLevel) {
    Write-Host "  • Entity: $EntityName ($EntityType)" -ForegroundColor White
}
Write-Host "  • Authorization Rule: $KeyName" -ForegroundColor White
Write-Host "  • Rotated Key: $Rotate" -ForegroundColor White
Write-Host "  • Key Vault: $KeyVaultName" -ForegroundColor White
Write-Host "  • Secret Name: $secretName" -ForegroundColor White
Write-Host "  • Secret ID: $($secret.Id)" -ForegroundColor White
Write-Host "  • Expires: $expiryDate" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "⚠️  Remember to update any applications using the old key!" -ForegroundColor Yellow
if ($ShowVerbose -or $ShowRecoveryKey) {
    Write-Host "🔒 SECURITY: Clear console history and logs containing key material!" -ForegroundColor Red
}
Write-Host "=====================================" -ForegroundColor Green