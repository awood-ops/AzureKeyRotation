<#
.SYNOPSIS
    Creates an Azure Workload Identity (service principal) and optionally configures it as an Azure DevOps service connection.

.DESCRIPTION
    This script automates the creation of a workload identity (service principal) in Microsoft Entra ID,
    assigns specified Azure RBAC roles, and optionally creates a federated credential-based service 
    connection in Azure DevOps.

    Key Features:
    - Creates service principal with workload identity (no secrets)
    - Assigns Azure RBAC roles at subscription or resource scope
    - Creates Azure DevOps service connection with federated credentials
    - Supports custom API permissions for the service principal
    - Idempotent - can be run multiple times safely

.PARAMETER ServicePrincipalName
    Display name for the service principal. If not specified, generates name from subscription.

.PARAMETER SubscriptionId
    Azure Subscription ID where the service principal will be granted access.

.PARAMETER RoleDefinitionName
    Azure RBAC role to assign. Default: "Contributor"
    Note: Ignored if RoleAssignments is specified.

.PARAMETER Scope
    Scope for role assignment. Default: subscription level ("/subscriptions/{id}")
    Examples: 
    - "/subscriptions/{id}" (subscription)
    - "/subscriptions/{id}/resourceGroups/{rg}" (resource group)
    - "/subscriptions/{id}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{name}" (resource)
    Note: If ManagementGroupId is specified, Scope is ignored.
    Note: Ignored if RoleAssignments is specified.

.PARAMETER ManagementGroupId
    Management Group ID for role assignment. When specified, role is assigned at management group scope.
    Example: "mg-corporate" or "00000000-0000-0000-0000-000000000000"
    Note: Ignored if RoleAssignments is specified.

.PARAMETER RoleAssignments
    Array of role assignments to create. Each element should have RoleDefinitionName and Scope properties.
    When specified, RoleDefinitionName, Scope, and ManagementGroupId parameters are ignored.
    Format: @(@{RoleDefinitionName="Role"; Scope="/scope/path"}, ...)
    Example:
    @(
        @{RoleDefinitionName="Contributor"; Scope="/subscriptions/{id}"},
        @{RoleDefinitionName="Key Vault Secrets Officer"; Scope="/subscriptions/{id}/resourceGroups/{rg}/providers/Microsoft.KeyVault/vaults/{name}"}
    )

.PARAMETER GrantApplicationOwnership
    Array of Application IDs to grant the service principal ownership of.
    This enables least-privilege secret rotation where the workload identity only manages specific applications.
    When specified, automatically grants Application.ReadWrite.OwnedBy Microsoft Graph API permission with admin consent.
    Format: @("app-id-1", "app-id-2", ...)
    Example: @("12345678-1234-1234-1234-123456789012")

.PARAMETER GrantDirectoryReadersRole
    If specified, assigns the Directory Readers role to the service principal.
    This allows the service principal to read directory objects (users, groups, service principals).
    Useful for automation that needs to read Entra ID information.

.PARAMETER AzureDevOpsOrganization
    Azure DevOps organization name (e.g., "myorg" from dev.azure.com/myorg)

.PARAMETER AzureDevOpsProject
    Azure DevOps project name where the service connection will be created

.PARAMETER ServiceConnectionName
    Name for the Azure DevOps service connection. If not specified, uses service principal name

.PARAMETER SkipServiceConnection
    If specified, skips Azure DevOps service connection creation (only creates service principal)

.PARAMETER AdditionalApiPermissions
    Array of additional Microsoft Graph API permissions to grant.
    Format: @(@{ApiId="..."; PermissionId="..."; Type="Role"})

.PARAMETER GrantAdminConsent
    If specified, automatically grants admin consent for API permissions (requires Global Admin)

.PARAMETER Force
    Skips confirmation prompts

.EXAMPLE
    # Create service principal with Contributor role and DevOps service connection
    .\New-WorkloadIdentity.ps1 `
        -ServicePrincipalName "sp-myapp-prod" `
        -SubscriptionId "11111111-1111-1111-1111-111111111111" `
        -AzureDevOpsOrganization "myorg" `
        -AzureDevOpsProject "MyProject"

.EXAMPLE
    # Create service principal with custom role at resource group scope
    .\New-WorkloadIdentity.ps1 `
        -ServicePrincipalName "sp-storage-reader" `
        -SubscriptionId "11111111-1111-1111-1111-111111111111" `
        -RoleDefinitionName "Storage Blob Data Reader" `
        -Scope "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/my-rg" `
        -SkipServiceConnection

.EXAMPLE
    # Create service principal with role at management group scope
    .\New-WorkloadIdentity.ps1 `
        -ServicePrincipalName "sp-mg-reader" `
        -SubscriptionId "11111111-1111-1111-1111-111111111111" `
        -ManagementGroupId "mg-corporate" `
        -RoleDefinitionName "Reader" `
        -SkipServiceConnection

.EXAMPLE
    # Create service principal with multiple role assignments
    .\New-WorkloadIdentity.ps1 `
        -ServicePrincipalName "sp-keyrotation" `
        -SubscriptionId "11111111-1111-1111-1111-111111111111" `
        -RoleAssignments @(
            @{RoleDefinitionName="Contributor"; Scope="/subscriptions/11111111-1111-1111-1111-111111111111"},
            @{RoleDefinitionName="Key Vault Secrets Officer"; Scope="/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/my-rg/providers/Microsoft.KeyVault/vaults/my-vault"}
        ) `
        -AzureDevOpsOrganization "myorg" `
        -AzureDevOpsProject "MyProject"

.EXAMPLE
    # Create service principal for secret rotation with application ownership (least privilege)
    .\New-WorkloadIdentity.ps1 `
        -ServicePrincipalName "sp-secretrotation" `
        -SubscriptionId "11111111-1111-1111-1111-111111111111" `
        -RoleAssignments @(
            @{RoleDefinitionName="Key Vault Secrets Officer"; Scope="/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/my-rg/providers/Microsoft.KeyVault/vaults/my-vault"}
        ) `
        -GrantApplicationOwnership @("12345678-1234-1234-1234-123456789012", "87654321-4321-4321-4321-210987654321") `
        -GrantDirectoryReadersRole `
        -AzureDevOpsOrganization "myorg" `
        -AzureDevOpsProject "SecretRotation"

.EXAMPLE
    # Create service principal with Graph API permissions
    .\New-WorkloadIdentity.ps1 `
        -ServicePrincipalName "sp-graph-app" `
        -SubscriptionId "11111111-1111-1111-1111-111111111111" `
        -AdditionalApiPermissions @(
            @{ApiId="00000003-0000-0000-c000-000000000000"; PermissionId="62a82d76-70ea-41e2-9197-370581804d09"; Type="Role"}
        ) `
        -GrantAdminConsent `
        -AzureDevOpsOrganization "myorg" `
        -AzureDevOpsProject "MyProject"

.NOTES
    Author: Andrew Wood
    Version: 1.0
    Requires: Az.Accounts, Az.Resources PowerShell modules
    
    Prerequisites:
    - Azure login: Connect-AzAccount
    - Permissions: User Access Administrator or Owner on the subscription/scope
    - For API permissions: Application Administrator or Global Administrator in Entra ID

.LINK
    https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure
    https://learn.microsoft.com/en-us/entra/workload-id/workload-identities-overview
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$ServicePrincipalName,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$RoleDefinitionName = "Contributor",

    [Parameter(Mandatory = $false)]
    [string]$Scope,

    [Parameter(Mandatory = $false)]
    [string]$ManagementGroupId,

    [Parameter(Mandatory = $false)]
    [array]$RoleAssignments,

    [Parameter(Mandatory = $false)]
    [string]$AzureDevOpsOrganization,

    [Parameter(Mandatory = $false)]
    [string]$AzureDevOpsProject,

    [Parameter(Mandatory = $false)]
    [string]$ServiceConnectionName,

    [Parameter(Mandatory = $false)]
    [switch]$SkipServiceConnection,

    [Parameter(Mandatory = $false)]
    [array]$GrantApplicationOwnership,

    [Parameter(Mandatory = $false)]
    [switch]$GrantDirectoryReadersRole,

    [Parameter(Mandatory = $false)]
    [array]$AdditionalApiPermissions,

    [Parameter(Mandatory = $false)]
    [switch]$GrantAdminConsent,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== Workload Identity Creation Script ===" -ForegroundColor Cyan
Write-Host ""

# Validate Azure DevOps parameters
if (-not $SkipServiceConnection -and (-not $AzureDevOpsOrganization -or -not $AzureDevOpsProject)) {
    Write-Error "AzureDevOpsOrganization and AzureDevOpsProject are required when creating a service connection. Use -SkipServiceConnection to skip."
    exit 1
}

# Check Azure context
Write-Host "[1/9] Checking Azure connection..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not connected to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Connected as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "✓ Tenant: $($context.Tenant.Id)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to get Azure context: $_"
    exit 1
}

# Set subscription context
Write-Host "`n[2/9] Setting subscription context..." -ForegroundColor Yellow
try {
    $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    Write-Host "✓ Subscription: $($subscription.Name)" -ForegroundColor Green
    Write-Host "✓ Subscription ID: $SubscriptionId" -ForegroundColor Green
}
catch {
    Write-Error "Failed to set subscription context: $_"
    exit 1
}

# Generate service principal name if not provided
if (-not $ServicePrincipalName) {
    $ServicePrincipalName = "sp-$($subscription.Name)-workload"
    Write-Host "✓ Generated service principal name: $ServicePrincipalName" -ForegroundColor Green
}

# Set scope based on parameters (unless using RoleAssignments)
if (-not $RoleAssignments) {
    if ($ManagementGroupId) {
        $Scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
        Write-Host "✓ Using management group scope: $ManagementGroupId" -ForegroundColor Green
    }
    elseif (-not $Scope) {
        $Scope = "/subscriptions/$SubscriptionId"
    }
}

# Confirm operation
if (-not $Force) {
    Write-Host "`n⚠️  This will:" -ForegroundColor Yellow
    Write-Host "   - Create/update service principal: $ServicePrincipalName" -ForegroundColor Gray
    if ($RoleAssignments) {
        Write-Host "   - Assign roles:" -ForegroundColor Gray
        foreach ($assignment in $RoleAssignments) {
            Write-Host "     * $($assignment.RoleDefinitionName) at $($assignment.Scope)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "   - Assign role: $RoleDefinitionName" -ForegroundColor Gray
        Write-Host "   - Scope: $Scope" -ForegroundColor Gray
    }
    if ($GrantApplicationOwnership -and $GrantApplicationOwnership.Count -gt 0) {
        Write-Host "   - Grant ownership of applications:" -ForegroundColor Gray
        foreach ($appId in $GrantApplicationOwnership) {
            try {
                $app = Get-AzADApplication -ApplicationId $appId -ErrorAction Stop
                Write-Host "     * $($app.DisplayName) ($appId)" -ForegroundColor Gray
            }
            catch {
                Write-Host "     * $appId (unable to retrieve name)" -ForegroundColor Gray
            }
        }
    }
    if ($GrantDirectoryReadersRole) {
        Write-Host "   - Assign Directory Readers role" -ForegroundColor Gray
    }
    if (-not $SkipServiceConnection) {
        Write-Host "   - Create Azure DevOps service connection in: $AzureDevOpsOrganization/$AzureDevOpsProject" -ForegroundColor Gray
    }
    $confirmation = Read-Host "`nContinue? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Create or get service principal
Write-Host "`n[3/9] Creating service principal..." -ForegroundColor Yellow
try {
    $sp = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName -ErrorAction SilentlyContinue
    if ($sp) {
        Write-Host "✓ Service principal already exists" -ForegroundColor Green
        Write-Host "  Application ID: $($sp.AppId)" -ForegroundColor Gray
        Write-Host "  Object ID: $($sp.Id)" -ForegroundColor Gray
    }
    else {
        $sp = New-AzADServicePrincipal -DisplayName $ServicePrincipalName
        Write-Host "✓ Service principal created" -ForegroundColor Green
        Write-Host "  Application ID: $($sp.AppId)" -ForegroundColor Gray
        Write-Host "  Object ID: $($sp.Id)" -ForegroundColor Gray
        
        # Remove any auto-generated secrets (we're using workload identity)
        Start-Sleep -Seconds 5
        Get-AzADApplication -DisplayName $ServicePrincipalName | Remove-AzADAppCredential -ErrorAction SilentlyContinue
        Write-Host "✓ Removed any auto-generated secrets (workload identity uses federated credentials)" -ForegroundColor Green
    }
}
catch {
    Write-Error "Failed to create service principal: $_"
    exit 1
}

# Assign Azure RBAC role(s)
Write-Host "`n[4/9] Assigning Azure RBAC role(s)..." -ForegroundColor Yellow
try {
    if ($RoleAssignments) {
        # Multiple role assignments
        $assignmentCount = 0
        foreach ($assignment in $RoleAssignments) {
            $assignmentRole = $assignment.RoleDefinitionName
            $assignmentScope = $assignment.Scope
            
            $existingRole = Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $assignmentRole -Scope $assignmentScope -ErrorAction SilentlyContinue
            if ($existingRole) {
                Write-Host "  ✓ Role already assigned: $assignmentRole" -ForegroundColor Gray
                Write-Host "    Scope: $assignmentScope" -ForegroundColor Gray
            }
            else {
                New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $assignmentRole -Scope $assignmentScope | Out-Null
                Write-Host "  ✓ Assigned role: $assignmentRole" -ForegroundColor Green
                Write-Host "    Scope: $assignmentScope" -ForegroundColor Gray
                $assignmentCount++
            }
        }
        if ($assignmentCount -gt 0) {
            Write-Host "✓ Assigned $assignmentCount new role(s)" -ForegroundColor Green
        }
        else {
            Write-Host "✓ All role assignments already exist" -ForegroundColor Green
        }
    }
    else {
        # Single role assignment (backward compatibility)
        $existingRole = Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction SilentlyContinue
        if ($existingRole) {
            Write-Host "✓ Role assignment already exists" -ForegroundColor Green
        }
        else {
            New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $RoleDefinitionName -Scope $Scope | Out-Null
            Write-Host "✓ Assigned role: $RoleDefinitionName" -ForegroundColor Green
            Write-Host "  Scope: $Scope" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Error "Failed to assign role: $_"
    exit 1
}

# Grant application ownership if specified
if ($GrantApplicationOwnership -and $GrantApplicationOwnership.Count -gt 0) {
    Write-Host "`n[5/9] Granting application ownership..." -ForegroundColor Yellow
    $ownershipCount = 0
    $failedCount = 0
    
    # Get Graph API token
    $tokenResult = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"
    
    # Extract token - handle SecureString if needed
    if ($tokenResult.Token -is [SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenResult.Token)
        $graphToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    elseif ($tokenResult.Token) {
        $graphToken = $tokenResult.Token
    }
    else {
        Write-Warning "Could not retrieve Graph API token"
        $graphToken = $null
    }
    
    if (-not $graphToken) {
        Write-Warning "Skipping application ownership (could not get Graph API token)"
    }
    else {
        $graphHeaders = @{
            "Authorization" = "Bearer $graphToken"
            "Content-Type" = "application/json"
        }
    
    foreach ($appId in $GrantApplicationOwnership) {
        try {
            # Get the application
            $targetApp = Get-AzADApplication -ApplicationId $appId -ErrorAction Stop
            
            # Add owner using Graph API
            $ownerBody = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($sp.Id)"
            } | ConvertTo-Json
            
            $ownerUri = "https://graph.microsoft.com/v1.0/applications/$($targetApp.Id)/owners/`$ref"
            
            try {
                Invoke-RestMethod -Method Post -Uri $ownerUri -Headers $graphHeaders -Body $ownerBody -ErrorAction Stop
                Write-Host "  ✓ Granted ownership of application: $($targetApp.DisplayName) ($appId)" -ForegroundColor Green
                $ownershipCount++
            }
            catch {
                # Check if error is because already an owner
                $errorMessage = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($_.Exception.Response.StatusCode -eq 409 -or 
                    $_.Exception.Response.StatusCode.value__ -eq 400 -or
                    $errorMessage.error.code -eq "Request_BadRequest" -or
                    $_.Exception.Message -like "*already exist*") {
                    Write-Host "  ✓ Already owner of application: $($targetApp.DisplayName) ($appId)" -ForegroundColor Gray
                }
                else {
                    throw
                }
            }
        }
        catch {
            Write-Warning "Failed to grant ownership of application $appId : $_"
            $failedCount++
        }
    }
    
    if ($ownershipCount -gt 0) {
        Write-Host "✓ Granted ownership of $ownershipCount application(s)" -ForegroundColor Green
    }
    if ($failedCount -gt 0) {
        Write-Warning "Failed to grant ownership of $failedCount application(s)"
    }
    if ($ownershipCount -eq 0 -and $failedCount -eq 0) {
        Write-Host "✓ All application ownerships already exist" -ForegroundColor Green
    }
    
    # Grant Application.ReadWrite.OwnedBy API permission
    Write-Host "`n  Granting Application.ReadWrite.OwnedBy permission..." -ForegroundColor Gray
    try {
        $app = Get-AzADApplication -DisplayName $ServicePrincipalName -ErrorAction Stop
        
        # Microsoft Graph API ID
        $graphApiId = "00000003-0000-0000-c000-000000000000"
        
        # Application.ReadWrite.OwnedBy permission ID
        $appReadWriteOwnedById = "18a4783c-866b-4cc7-a460-3d5e5662c884"
        
        # Check if permission already exists
        $existingPermissions = Get-AzADAppPermission -ApplicationId $app.AppId -ErrorAction SilentlyContinue
        $permissionExists = $existingPermissions | Where-Object { 
            $_.ApiId -eq $graphApiId -and 
            $_.Id -eq $appReadWriteOwnedById -and 
            $_.Type -eq "Role"
        }
        
        if ($permissionExists) {
            Write-Host "  ✓ Application.ReadWrite.OwnedBy permission already exists" -ForegroundColor Gray
        }
        else {
            Add-AzADAppPermission -ApplicationId $app.AppId `
                -ApiId $graphApiId `
                -PermissionId $appReadWriteOwnedById `
                -Type "Role" -ErrorAction Stop
            Write-Host "  ✓ Added Application.ReadWrite.OwnedBy permission" -ForegroundColor Green
        }
        
        # Grant admin consent for application permission (appRoleAssignment)
        Write-Host "  Granting admin consent..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        
        # Get Microsoft Graph service principal
        $graphSp = Get-AzADServicePrincipal -ApplicationId $graphApiId -ErrorAction Stop
        
        # Check if consent already granted (appRoleAssignment exists)
        $consentCheckUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.Id)/appRoleAssignments"
        $existingConsents = Invoke-RestMethod -Method Get -Uri $consentCheckUri -Headers $graphHeaders -ErrorAction SilentlyContinue
        
        $consentExists = $existingConsents.value | Where-Object {
            $_.resourceId -eq $graphSp.Id -and $_.appRoleId -eq $appReadWriteOwnedById
        }
        
        if ($consentExists) {
            Write-Host "  ✓ Admin consent already granted" -ForegroundColor Gray
        }
        else {
            # Grant consent using appRoleAssignments endpoint
            $consentBody = @{
                principalId = $sp.Id
                resourceId = $graphSp.Id
                appRoleId = $appReadWriteOwnedById
            } | ConvertTo-Json
            
            $consentUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.Id)/appRoleAssignments"
            
            try {
                Invoke-RestMethod -Method Post -Uri $consentUri -Headers $graphHeaders -Body $consentBody -ErrorAction Stop | Out-Null
                Write-Host "  ✓ Admin consent granted successfully" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Failed to grant admin consent via Graph API: $_"
                Write-Host "  Trying with az cli..." -ForegroundColor Gray
                az ad app permission admin-consent --id $app.AppId 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  ✓ Admin consent granted via az cli" -ForegroundColor Green
                }
                else {
                    Write-Warning "  Failed to grant admin consent automatically"
                    Write-Host "  ⚠️  Please grant admin consent manually in Azure Portal" -ForegroundColor Yellow
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to add Application.ReadWrite.OwnedBy permission: $_"
        Write-Host "  You may need to add this permission and grant consent manually in Azure Portal" -ForegroundColor Yellow
    }
    }
}
else {
    Write-Host "`n[5/9] Skipping application ownership (none specified)..." -ForegroundColor Gray
}

# Assign Directory Readers role if requested
if ($GrantDirectoryReadersRole) {
    Write-Host "`n[5.5/9] Assigning Directory Readers role..." -ForegroundColor Yellow
    
    # Get Graph API token (reuse if already obtained)
    if (-not $graphToken) {
        $tokenResult = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"
        
        # Extract token - handle SecureString if needed
        if ($tokenResult.Token -is [SecureString]) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenResult.Token)
            $graphToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        elseif ($tokenResult.Token) {
            $graphToken = $tokenResult.Token
        }
        else {
            Write-Warning "Could not retrieve Graph API token"
            $graphToken = $null
        }
    }
    
    if (-not $graphToken) {
        Write-Warning "Skipping Directory Readers role assignment (could not get Graph API token)"
    }
    else {
        try {
            $graphHeaders = @{
                "Authorization" = "Bearer $graphToken"
                "Content-Type" = "application/json"
            }
            
            # Get Directory Readers role template ID
            $roleTemplateId = "88d8e3e3-8f55-4a1e-953a-9b9898b8876b"  # Directory Readers
            
            # Check if role is activated (instantiated) in the directory
            $rolesUri = "https://graph.microsoft.com/v1.0/directoryRoles?`$filter=roleTemplateId eq '$roleTemplateId'"
            $rolesResponse = Invoke-RestMethod -Method Get -Uri $rolesUri -Headers $graphHeaders
            
            if ($rolesResponse.value.Count -eq 0) {
                # Role template needs to be activated first
                Write-Host "  Activating Directory Readers role template..." -ForegroundColor Gray
                $activateUri = "https://graph.microsoft.com/v1.0/directoryRoles"
                $activateBody = @{
                    roleTemplateId = $roleTemplateId
                } | ConvertTo-Json
                
                $roleInstance = Invoke-RestMethod -Method Post -Uri $activateUri -Headers $graphHeaders -Body $activateBody
                $roleId = $roleInstance.id
            }
            else {
                $roleId = $rolesResponse.value[0].id
            }
            
            # Check if already assigned
            $membersUri = "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members"
            $membersResponse = Invoke-RestMethod -Method Get -Uri $membersUri -Headers $graphHeaders
            
            $isAlreadyMember = $membersResponse.value | Where-Object { $_.id -eq $sp.Id }
            
            if ($isAlreadyMember) {
                Write-Host "  ✓ Directory Readers role already assigned" -ForegroundColor Gray
            }
            else {
                # Assign the role
                $assignUri = "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members/`$ref"
                $assignBody = @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($sp.Id)"
                } | ConvertTo-Json
                
                try {
                    Invoke-RestMethod -Method Post -Uri $assignUri -Headers $graphHeaders -Body $assignBody -ErrorAction Stop
                    Write-Host "  ✓ Directory Readers role assigned successfully" -ForegroundColor Green
                }
                catch {
                    # Check if error is because already a member
                    $errorMessage = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($_.Exception.Response.StatusCode.value__ -eq 400 -and
                        ($errorMessage.error.code -eq "Request_BadRequest" -and 
                         $errorMessage.error.message -like "*already exist*")) {
                        Write-Host "  ✓ Directory Readers role already assigned" -ForegroundColor Gray
                    }
                    else {
                        throw
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to assign Directory Readers role: $_"
            Write-Host "  You may need to assign this role manually in Entra ID" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "`n[5.5/9] Skipping Directory Readers role assignment..." -ForegroundColor Gray
}

# Add additional API permissions if specified
if ($AdditionalApiPermissions -and $AdditionalApiPermissions.Count -gt 0) {
    Write-Host "`n[6/9] Adding API permissions..." -ForegroundColor Yellow
    try {
        $app = Get-AzADApplication -DisplayName $ServicePrincipalName
        $existingPermissions = Get-AzADAppPermission -ApplicationId $app.AppId -ErrorAction SilentlyContinue
        
        foreach ($permission in $AdditionalApiPermissions) {
            $exists = $existingPermissions | Where-Object { 
                $_.ApiId -eq $permission.ApiId -and 
                $_.Id -eq $permission.PermissionId -and 
                $_.Type -eq $permission.Type 
            }
            
            if ($exists) {
                Write-Host "  ✓ Permission already exists: $($permission.PermissionId)" -ForegroundColor Gray
            }
            else {
                Add-AzADAppPermission -ApplicationId $app.AppId `
                    -ApiId $permission.ApiId `
                    -PermissionId $permission.PermissionId `
                    -Type $permission.Type
                Write-Host "  ✓ Added permission: $($permission.PermissionId)" -ForegroundColor Green
            }
        }
        
        # Grant admin consent if requested
        if ($GrantAdminConsent) {
            Write-Host "  Granting admin consent..." -ForegroundColor Gray
            Start-Sleep -Seconds 5
            az ad app permission admin-consent --id $app.AppId 2>$null
            Write-Host "  ✓ Admin consent granted" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to add API permissions: $_"
        Write-Host "  You may need to add permissions manually in Azure Portal" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n[6/9] Skipping API permissions (none specified)..." -ForegroundColor Gray
}

# Create Azure DevOps service connection
if (-not $SkipServiceConnection) {
    Write-Host "`n[7/9] Creating Azure DevOps service connection..." -ForegroundColor Yellow
    
    # Set service connection name
    if (-not $ServiceConnectionName) {
        $ServiceConnectionName = $ServicePrincipalName
    }
    
    try {
        # Get Azure DevOps access token
        $tokenResult = Get-AzAccessToken -ResourceUrl "499b84ac-1321-427f-aa17-267ca6975798"
        
        # Extract token - it might be a SecureString or in a Token property
        if ($tokenResult.Token -is [SecureString]) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenResult.Token)
            $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
        elseif ($tokenResult.Token) {
            $token = $tokenResult.Token
        }
        else {
            $token = $tokenResult
        }
        
        if (-not $token) {
            Write-Error "Failed to get Azure DevOps access token"
            throw "No access token obtained"
        }
        
        # Get project ID
        $projectUrl = "https://dev.azure.com/$AzureDevOpsOrganization/_apis/projects/$AzureDevOpsProject" + "?api-version=7.1"
        $headers = @{
            'Authorization' = 'Bearer ' + $token
            'Content-Type' = 'application/json'
        }
        
        try {
            $project = Invoke-RestMethod -Method Get -Uri $projectUrl -Headers $headers
            if ($project -is [string]) {
                $project = $project | ConvertFrom-Json
            }
            $projectId = $project.id
        }
        catch {
            Write-Error "Failed to get project '$AzureDevOpsProject': $($_.Exception.Message)"
            Write-Error "Status Code: $($_.Exception.Response.StatusCode.value__)"
            Write-Error "Status Description: $($_.Exception.Response.StatusDescription)"
            throw
        }
        
        if (-not $projectId) {
            Write-Error "Project ID is null for project '$AzureDevOpsProject'"
            throw "Cannot proceed without valid project ID"
        }
        
        # Check if service connection already exists
        $listUrl = "https://dev.azure.com/$AzureDevOpsOrganization/$AzureDevOpsProject/_apis/serviceendpoint/endpoints?api-version=7.2-preview.4"
        $existingConnections = Invoke-RestMethod -Method Get -Uri $listUrl -Headers $headers
        $existingConnection = $existingConnections.value | Where-Object { $_.name -eq $ServiceConnectionName }
        
        if ($existingConnection) {
            Write-Host "✓ Service connection already exists: $ServiceConnectionName" -ForegroundColor Green
            $serviceConnectionId = $existingConnection.id
        }
        else {
            # Create service connection
            $tenantId = $context.Tenant.Id
            $createUrl = "https://dev.azure.com/$AzureDevOpsOrganization/_apis/serviceendpoint/endpoints?api-version=7.2-preview.4"
            
            # Use string-based JSON body like the original script
            $body = @"
{
    "data": {
        "subscriptionId": "$SubscriptionId",
        "subscriptionName": "$($subscription.Name)",
        "environment": "AzureCloud",
        "scopeLevel": "Subscription",
        "creationMode": "Manual"
    },
    "name": "$ServiceConnectionName",
    "type": "AzureRM",
    "url": "https://management.azure.com/",
    "authorization": {
        "parameters": {
            "tenantid": "$tenantId",
            "serviceprincipalid": "$($sp.AppId)"
        },
        "scheme": "WorkloadIdentityFederation"
    },
    "isShared": false,
    "isReady": true,
    "serviceEndpointProjectReferences": [
        {
            "projectReference": {
                "name": "$AzureDevOpsProject",
                "id": "$projectId"
            },
            "name": "$ServiceConnectionName"
        }
    ]
}
"@
            
            try {
                $response = Invoke-RestMethod -Method Post -Uri $createUrl -Headers $headers -Body $body
                
                $serviceConnection = $response
                $serviceConnectionId = $serviceConnection.id
                
                Write-Host "✓ Service connection created: $ServiceConnectionName" -ForegroundColor Green
                Write-Host "  Connection ID: $serviceConnectionId" -ForegroundColor Gray
            }
            catch {
                # Check if it's a duplicate service connection error
                if ($_.Exception.Response.StatusCode.value__ -eq 409) {
                    Write-Host "✓ Service connection already exists: $ServiceConnectionName" -ForegroundColor Green
                    # Try to get the existing connection by name
                    try {
                        $existingConnection = $existingConnections.value | Where-Object { $_.name -eq $ServiceConnectionName } | Select-Object -First 1
                        if ($existingConnection) {
                            $serviceConnectionId = $existingConnection.id
                            Write-Host "  Connection ID: $serviceConnectionId" -ForegroundColor Gray
                        }
                        else {
                            Write-Warning "Service connection exists but could not retrieve ID. You may need Administrator permissions."
                            $serviceConnectionId = $null
                        }
                    }
                    catch {
                        Write-Warning "Could not retrieve existing service connection details"
                        $serviceConnectionId = $null
                    }
                }
                else {
                    $errorDetails = ""
                    if ($_.ErrorDetails.Message) {
                        $errorDetails = $_.ErrorDetails.Message
                    }
                    Write-Warning "Failed to create Azure DevOps service connection: $errorDetails"
                    throw
                }
            }
        }
        
        # Retrieve the service connection to get the issuer and subject that Azure DevOps generated
        if ($serviceConnectionId) {
            $getUrl = "https://dev.azure.com/$AzureDevOpsOrganization/$AzureDevOpsProject/_apis/serviceendpoint/endpoints/$serviceConnectionId" + "?api-version=7.2-preview.4"
            $serviceConnectionDetails = Invoke-RestMethod -Method Get -Uri $getUrl -Headers $headers
            
            # Get the issuer and subject from Azure DevOps
            $issuer = $serviceConnectionDetails.authorization.parameters.workloadIdentityFederationIssuer
            $subject = $serviceConnectionDetails.authorization.parameters.workloadIdentityFederationSubject
            
            if (-not $issuer -or -not $subject) {
                Write-Warning "Could not retrieve federated credential details from service connection."
                Write-Host "  Attempting to use default values..." -ForegroundColor Yellow
                # Fallback to constructed values (though these may not work)
                if (-not $issuer) {
                    $issuer = "https://vstoken.dev.azure.com/$($context.Tenant.Id)"
                }
                if (-not $subject) {
                    $subject = "sc://$AzureDevOpsOrganization/$AzureDevOpsProject/$ServiceConnectionName"
                }
            }
        }
        else {
            $issuer = $null
            $subject = $null
        }
        
        Write-Host "  Issuer: $issuer" -ForegroundColor Gray
        Write-Host "  Subject: $subject" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Azure DevOps service connection: $_"
        Write-Host "  Error details: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  You may need to create the service connection manually in Azure DevOps" -ForegroundColor Yellow
        $serviceConnectionId = $null
        $issuer = $null
        $subject = $null
    }
    
    # Create federated credential
    if ($issuer -and $subject) {
        Write-Host "`n[7/7] Creating/updating federated credential..." -ForegroundColor Yellow
        try {
            $app = Get-AzADApplication -DisplayName $ServicePrincipalName
            
            # Check if federated credential already exists with the correct subject
            $existingCredential = Get-AzADAppFederatedCredential -ApplicationObjectId $app.Id -ErrorAction SilentlyContinue | 
                Where-Object { $_.Subject -eq $subject }
            
            if ($existingCredential) {
                Write-Host "✓ Federated credential already exists with correct subject" -ForegroundColor Green
                Write-Host "  Name: $($existingCredential.Name)" -ForegroundColor Gray
            }
            else {
                # Check if there's an old credential for this project that needs updating
                $credentialName = "AzureDevOps-$AzureDevOpsProject"
                $oldCredential = Get-AzADAppFederatedCredential -ApplicationObjectId $app.Id -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -eq $credentialName }
                
                if ($oldCredential) {
                    # Remove old credential with incorrect subject
                    Write-Host "  Removing old federated credential with incorrect subject..." -ForegroundColor Yellow
                    Remove-AzADAppFederatedCredential -ApplicationObjectId $app.Id -FederatedCredentialId $oldCredential.Id -ErrorAction Stop
                }
                
                # Create new credential with correct issuer and subject
                New-AzADAppFederatedCredential `
                    -ApplicationObjectId $app.Id `
                    -Issuer $issuer `
                    -Subject $subject `
                    -Audience "api://AzureADTokenExchange" `
                    -Name $credentialName `
                    -ErrorAction Stop
                
                Write-Host "✓ Federated credential created" -ForegroundColor Green
                Write-Host "  Issuer: $issuer" -ForegroundColor Gray
                Write-Host "  Subject: $subject" -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "Failed to create federated credential: $_"
            Write-Host "  You may need to add the federated credential manually in Azure Portal" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "`n[7/7] Skipping federated credential (service connection not created)..." -ForegroundColor Gray
    }
}
else {
    Write-Host "`n[7/9] Skipping Azure DevOps service connection..." -ForegroundColor Gray
    Write-Host "`n[8/9] Skipping federated credential..." -ForegroundColor Gray
    Write-Host "`n[9/9] Summary..." -ForegroundColor Gray
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Service Principal:" -ForegroundColor Cyan
Write-Host "  Display Name: $ServicePrincipalName" -ForegroundColor White
Write-Host "  Application ID: $($sp.AppId)" -ForegroundColor White
Write-Host "  Object ID: $($sp.Id)" -ForegroundColor White
Write-Host "  Tenant ID: $($context.Tenant.Id)" -ForegroundColor White
Write-Host ""
if ($RoleAssignments) {
    Write-Host "Role Assignments:" -ForegroundColor Cyan
    foreach ($assignment in $RoleAssignments) {
        Write-Host "  Role: $($assignment.RoleDefinitionName)" -ForegroundColor White
        Write-Host "  Scope: $($assignment.Scope)" -ForegroundColor White
        Write-Host "" -ForegroundColor White
    }
}
else {
    Write-Host "Role Assignment:" -ForegroundColor Cyan
    Write-Host "  Role: $RoleDefinitionName" -ForegroundColor White
    Write-Host "  Scope: $Scope" -ForegroundColor White
    Write-Host ""
}

if ($GrantApplicationOwnership -and $GrantApplicationOwnership.Count -gt 0) {
    Write-Host "Application Ownership:" -ForegroundColor Cyan
    foreach ($appId in $GrantApplicationOwnership) {
        $targetApp = Get-AzADApplication -ApplicationId $appId -ErrorAction SilentlyContinue
        if ($targetApp) {
            Write-Host "  • $($targetApp.DisplayName) ($appId)" -ForegroundColor White
        }
        else {
            Write-Host "  • $appId (not found)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

if (-not $SkipServiceConnection -and $serviceConnectionId) {
    Write-Host "Azure DevOps Service Connection:" -ForegroundColor Cyan
    Write-Host "  Name: $ServiceConnectionName" -ForegroundColor White
    Write-Host "  Organization: $AzureDevOpsOrganization" -ForegroundColor White
    Write-Host "  Project: $AzureDevOpsProject" -ForegroundColor White
    Write-Host "  Connection ID: $serviceConnectionId" -ForegroundColor White
    Write-Host ""
}

Write-Host "✓ Workload identity setup complete!" -ForegroundColor Green
