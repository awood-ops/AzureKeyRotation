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

.PARAMETER Scope
    Scope for role assignment. Default: subscription level ("/subscriptions/{id}")
    Examples: 
    - "/subscriptions/{id}" (subscription)
    - "/subscriptions/{id}/resourceGroups/{rg}" (resource group)
    - "/subscriptions/{id}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{name}" (resource)
    Note: If ManagementGroupId is specified, Scope is ignored.

.PARAMETER ManagementGroupId
    Management Group ID for role assignment. When specified, role is assigned at management group scope.
    Example: "mg-corporate" or "00000000-0000-0000-0000-000000000000"

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
    [string]$AzureDevOpsOrganization,

    [Parameter(Mandatory = $false)]
    [string]$AzureDevOpsProject,

    [Parameter(Mandatory = $false)]
    [string]$ServiceConnectionName,

    [Parameter(Mandatory = $false)]
    [switch]$SkipServiceConnection,

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
Write-Host "[1/7] Checking Azure connection..." -ForegroundColor Yellow
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
Write-Host "`n[2/7] Setting subscription context..." -ForegroundColor Yellow
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

# Set scope based on parameters
if ($ManagementGroupId) {
    $Scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
    Write-Host "✓ Using management group scope: $ManagementGroupId" -ForegroundColor Green
}
elseif (-not $Scope) {
    $Scope = "/subscriptions/$SubscriptionId"
}

# Confirm operation
if (-not $Force) {
    Write-Host "`n⚠️  This will:" -ForegroundColor Yellow
    Write-Host "   - Create/update service principal: $ServicePrincipalName" -ForegroundColor Gray
    Write-Host "   - Assign role: $RoleDefinitionName" -ForegroundColor Gray
    Write-Host "   - Scope: $Scope" -ForegroundColor Gray
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
Write-Host "`n[3/7] Creating service principal..." -ForegroundColor Yellow
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

# Assign Azure RBAC role
Write-Host "`n[4/7] Assigning Azure RBAC role..." -ForegroundColor Yellow
try {
    $existingRole = Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction SilentlyContinue
    if ($existingRole) {
        Write-Host "✓ Role assignment already exists" -ForegroundColor Green
    }
    else {
        if ($ManagementGroupId) {
            # For management groups, use the -ManagementGroupName parameter
            New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $RoleDefinitionName -Scope $Scope | Out-Null
        }
        else {
            New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $RoleDefinitionName -Scope $Scope | Out-Null
        }
        Write-Host "✓ Assigned role: $RoleDefinitionName" -ForegroundColor Green
        Write-Host "  Scope: $Scope" -ForegroundColor Gray
    }
}
catch {
    Write-Error "Failed to assign role: $_"
    exit 1
}

# Add additional API permissions if specified
if ($AdditionalApiPermissions -and $AdditionalApiPermissions.Count -gt 0) {
    Write-Host "`n[5/7] Adding API permissions..." -ForegroundColor Yellow
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
    Write-Host "`n[5/7] Skipping API permissions (none specified)..." -ForegroundColor Gray
}

# Create Azure DevOps service connection
if (-not $SkipServiceConnection) {
    Write-Host "`n[6/7] Creating Azure DevOps service connection..." -ForegroundColor Yellow
    
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
    Write-Host "`n[6/7] Skipping Azure DevOps service connection..." -ForegroundColor Gray
    Write-Host "`n[7/7] Skipping federated credential..." -ForegroundColor Gray
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Service Principal:" -ForegroundColor Cyan
Write-Host "  Display Name: $ServicePrincipalName" -ForegroundColor White
Write-Host "  Application ID: $($sp.AppId)" -ForegroundColor White
Write-Host "  Object ID: $($sp.Id)" -ForegroundColor White
Write-Host "  Tenant ID: $($context.Tenant.Id)" -ForegroundColor White
Write-Host ""
Write-Host "Role Assignment:" -ForegroundColor Cyan
Write-Host "  Role: $RoleDefinitionName" -ForegroundColor White
Write-Host "  Scope: $Scope" -ForegroundColor White
Write-Host ""

if (-not $SkipServiceConnection -and $serviceConnectionId) {
    Write-Host "Azure DevOps Service Connection:" -ForegroundColor Cyan
    Write-Host "  Name: $ServiceConnectionName" -ForegroundColor White
    Write-Host "  Organization: $AzureDevOpsOrganization" -ForegroundColor White
    Write-Host "  Project: $AzureDevOpsProject" -ForegroundColor White
    Write-Host "  Connection ID: $serviceConnectionId" -ForegroundColor White
    Write-Host ""
}

Write-Host "✓ Workload identity setup complete!" -ForegroundColor Green
