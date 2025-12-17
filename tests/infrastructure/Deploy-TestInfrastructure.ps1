<#
.SYNOPSIS
    Deploys test infrastructure for Azure Key Rotation testing.

.DESCRIPTION
    Creates a complete test environment including:
    - Resource Group
    - Event Hub Namespace and Event Hub instance
    - Service Bus Namespace and Queue
    - Key Vault
    - Service Principal with required permissions

    All resources are tagged as 'testing' for easy cleanup.

.PARAMETER ResourceGroupName
    Name of the resource group to create. Default: rg-keyrotation-test

.PARAMETER Location
    Azure region for resources. Default: uksouth

.PARAMETER EnvironmentPrefix
    Prefix for resource naming. Default: krtest

.PARAMETER ServicePrincipalName
    Name for the test service principal. Default: sp-keyrotation-test

.PARAMETER SkipCleanup
    If specified, does not delete existing resources before deployment.

.EXAMPLE
    .\Deploy-TestInfrastructure.ps1

.EXAMPLE
    .\Deploy-TestInfrastructure.ps1 -ResourceGroupName "rg-mytest" -Location "uksouth" -EnvironmentPrefix "mytest"

.EXAMPLE
    .\Deploy-TestInfrastructure.ps1 -SkipCleanup

.NOTES
    Requires: Az.Accounts, Az.Resources, Az.EventHub, Az.ServiceBus, Az.KeyVault
    Permissions: Contributor on subscription, Application Administrator in Entra ID
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-keyrotation-test",

    [Parameter(Mandatory = $false)]
    [string]$Location = "uksouth",

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentPrefix = "krtest",

    [Parameter(Mandatory = $false)]
    [string]$ServicePrincipalName = "sp-keyrotation-test",

    [Parameter(Mandatory = $false)]
    [switch]$SkipCleanup
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Key Rotation Test Infrastructure Deployment ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "Location: $Location" -ForegroundColor Gray
Write-Host "Prefix: $EnvironmentPrefix" -ForegroundColor Gray
Write-Host ""

# Generate unique resource names
$timestamp = Get-Date -Format "MMddHHmm"
$eventHubNamespace = "$EnvironmentPrefix-evhns-$timestamp"
$eventHubName = "test-hub"
$serviceBusNamespace = "$EnvironmentPrefix-sbns-$timestamp"
$queueName = "test-queue"
$keyVaultName = "$EnvironmentPrefix-kv-$timestamp"

# Ensure we're logged in
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged into Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "Error checking Azure context: $_" -ForegroundColor Red
    exit 1
}

# Register required resource providers
Write-Host "Registering required Azure resource providers..." -ForegroundColor Cyan
$providers = @(
    "Microsoft.EventHub",
    "Microsoft.ServiceBus",
    "Microsoft.KeyVault"
)

foreach ($provider in $providers) {
    $registration = Get-AzResourceProvider -ProviderNamespace $provider | 
        Where-Object { $_.RegistrationState -eq "Registered" }
    
    if (-not $registration) {
        Write-Host "  Registering $provider..." -ForegroundColor Yellow
        Register-AzResourceProvider -ProviderNamespace $provider | Out-Null
    }
    else {
        Write-Host "  $provider already registered." -ForegroundColor Gray
    }
}

# Wait for registration to complete
Write-Host "Waiting for resource provider registration to complete..." -ForegroundColor Yellow
foreach ($provider in $providers) {
    $timeout = 0
    while ((Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState -ne "Registered" -and $timeout -lt 60) {
        Start-Sleep -Seconds 5
        $timeout += 5
        Write-Host "  Waiting for $provider... ($timeout seconds)" -ForegroundColor Gray
    }
    
    if ((Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState -eq "Registered") {
        Write-Host "✓ $provider registered successfully." -ForegroundColor Green
    }
    else {
        Write-Host "⚠ $provider registration is taking longer than expected. Continuing anyway..." -ForegroundColor Yellow
    }
}
Write-Host ""

# Cleanup existing resources if not skipped
if (-not $SkipCleanup) {
    Write-Host "Checking for existing resource group..." -ForegroundColor Yellow
    $existingRg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($existingRg) {
        Write-Host "Found existing resource group. Deleting..." -ForegroundColor Yellow
        Remove-AzResourceGroup -Name $ResourceGroupName -Force | Out-Null
        Write-Host "Deleted existing resource group." -ForegroundColor Green
        Start-Sleep -Seconds 10  # Wait for deletion to propagate
    }
}

# Create Resource Group
Write-Host "Creating resource group: $ResourceGroupName..." -ForegroundColor Cyan
$rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{
    Purpose = "Testing"
    Project = "AzureKeyRotation"
    CreatedDate = (Get-Date -Format "yyyy-MM-dd")
}
Write-Host "✓ Resource group created." -ForegroundColor Green
Write-Host ""

# Create Event Hub Namespace
Write-Host "Creating Event Hub Namespace: $eventHubNamespace..." -ForegroundColor Cyan
try {
    $eventHubNs = New-AzEventHubNamespace `
        -ResourceGroupName $ResourceGroupName `
        -Name $eventHubNamespace `
        -Location $Location `
        -SkuName "Standard" `
        -Tag @{
            Purpose = "Testing"
            Component = "EventHub"
        }
    Write-Host "✓ Event Hub Namespace created." -ForegroundColor Green

    # Wait for namespace to be fully provisioned
    Write-Host "  Waiting for namespace provisioning..." -ForegroundColor Gray
    Start-Sleep -Seconds 30

    # Create Event Hub
    Write-Host "Creating Event Hub: $eventHubName..." -ForegroundColor Cyan
    $eventHub = New-AzEventHub `
        -ResourceGroupName $ResourceGroupName `
        -NamespaceName $eventHubNamespace `
        -Name $eventHubName `
        -PartitionCount 2
    Write-Host "✓ Event Hub created." -ForegroundColor Green

    # Create Event Hub Authorization Rule
    Write-Host "Creating Event Hub Authorization Rule..." -ForegroundColor Cyan
    $eventHubAuthRule = New-AzEventHubAuthorizationRule `
        -ResourceGroupName $ResourceGroupName `
        -NamespaceName $eventHubNamespace `
        -EventHubName $eventHubName `
        -Name "test-send-listen" `
        -Rights @("Send", "Listen")
    Write-Host "✓ Event Hub Authorization Rule created." -ForegroundColor Green
}
catch {
    Write-Host "Error creating Event Hub resources: $_" -ForegroundColor Red
    throw
}
Write-Host ""

# Create Service Bus Namespace
Write-Host "Creating Service Bus Namespace: $serviceBusNamespace..." -ForegroundColor Cyan
try {
    $serviceBusNs = New-AzServiceBusNamespace `
        -ResourceGroupName $ResourceGroupName `
        -Name $serviceBusNamespace `
        -Location $Location `
        -SkuName "Standard" `
        -Tag @{
            Purpose = "Testing"
            Component = "ServiceBus"
        }
    Write-Host "✓ Service Bus Namespace created." -ForegroundColor Green

    # Wait for namespace to be fully provisioned
    Write-Host "  Waiting for namespace provisioning..." -ForegroundColor Gray
    Start-Sleep -Seconds 30

    # Create Service Bus Queue
    Write-Host "Creating Service Bus Queue: $queueName..." -ForegroundColor Cyan
    $queue = New-AzServiceBusQueue `
        -ResourceGroupName $ResourceGroupName `
        -NamespaceName $serviceBusNamespace `
        -Name $queueName
    Write-Host "✓ Service Bus Queue created." -ForegroundColor Green

    # Create Service Bus Authorization Rule
    Write-Host "Creating Service Bus Authorization Rule..." -ForegroundColor Cyan
    $serviceBusAuthRule = New-AzServiceBusAuthorizationRule `
        -ResourceGroupName $ResourceGroupName `
        -NamespaceName $serviceBusNamespace `
        -QueueName $queueName `
        -Name "test-send-listen" `
        -Rights @("Send", "Listen")
    Write-Host "✓ Service Bus Authorization Rule created." -ForegroundColor Green
}
catch {
    Write-Host "Error creating Service Bus resources: $_" -ForegroundColor Red
    throw
}
Write-Host ""

# Create Key Vault
Write-Host "Creating Key Vault: $keyVaultName..." -ForegroundColor Cyan
try {
    $currentUser = Get-AzContext
    $keyVault = New-AzKeyVault `
        -ResourceGroupName $ResourceGroupName `
        -VaultName $keyVaultName `
        -Location $Location `
        -Sku "Standard" `
        -Tag @{
            Purpose = "Testing"
            Component = "KeyVault"
        }
    Write-Host "✓ Key Vault created." -ForegroundColor Green

    # Wait for Key Vault to be fully provisioned
    Start-Sleep -Seconds 10

    # Get current user's object ID
    Write-Host "Getting current user object ID..." -ForegroundColor Cyan
    $currentUserObjectId = $null
    try {
        $currentUserObjectId = (Get-AzADUser -UserPrincipalName $currentUser.Account.Id -ErrorAction SilentlyContinue).Id
    }
    catch {
        # Ignore error, try alternative method
    }
    
    if (-not $currentUserObjectId) {
        # Try alternative method for service principals or managed identities
        $accountId = $currentUser.Account.Id
        Write-Host "  Attempting to find user by sign-in name: $accountId..." -ForegroundColor Gray
        $currentUserObjectId = (Get-AzADUser -SignedIn -ErrorAction SilentlyContinue).Id
    }

    if (-not $currentUserObjectId) {
        Write-Host "⚠ Could not determine current user Object ID automatically." -ForegroundColor Yellow
        Write-Host "  Please manually grant yourself 'Key Vault Secrets Officer' role on: $keyVaultName" -ForegroundColor Yellow
    }
    else {
        # Set access policy for current user (fallback to access policies instead of RBAC)
        Write-Host "Setting Key Vault access policy for current user..." -ForegroundColor Cyan
        Set-AzKeyVaultAccessPolicy `
            -VaultName $keyVaultName `
            -ResourceGroupName $ResourceGroupName `
            -ObjectId $currentUserObjectId `
            -PermissionsToSecrets Get,List,Set,Delete,Recover,Backup,Restore,Purge `
            -ErrorAction SilentlyContinue | Out-Null
        Write-Host "✓ Access policy configured." -ForegroundColor Green
    }
}
catch {
    Write-Host "Error creating Key Vault: $_" -ForegroundColor Red
    throw
}
Write-Host ""

# Create Service Principal
Write-Host "Creating Service Principal: $ServicePrincipalName..." -ForegroundColor Cyan
try {
    # Check if SP already exists
    $existingSp = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName -ErrorAction SilentlyContinue
    if ($existingSp) {
        Write-Host "  Service Principal already exists. Removing..." -ForegroundColor Yellow
        Remove-AzADServicePrincipal -ObjectId $existingSp.Id -Force
        Start-Sleep -Seconds 5
    }

    # Create new Service Principal
    $sp = New-AzADServicePrincipal -DisplayName $ServicePrincipalName
    Write-Host "✓ Service Principal created." -ForegroundColor Green
    Write-Host "  Application (Client) ID: $($sp.AppId)" -ForegroundColor Gray
    Write-Host "  Object ID: $($sp.Id)" -ForegroundColor Gray

    # Create initial secret
    Write-Host "Creating initial secret for Service Principal..." -ForegroundColor Cyan
    $credential = New-AzADSpCredential -ObjectId $sp.Id -EndDate (Get-Date).AddMonths(12)
    Write-Host "✓ Initial secret created (expires in 12 months)." -ForegroundColor Green
}
catch {
    Write-Host "Error creating Service Principal: $_" -ForegroundColor Red
    throw
}
Write-Host ""

# Output summary
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Resource Group:" -ForegroundColor Cyan
Write-Host "  Name: $ResourceGroupName" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White
Write-Host ""
Write-Host "Event Hub:" -ForegroundColor Cyan
Write-Host "  Namespace: $eventHubNamespace" -ForegroundColor White
Write-Host "  Event Hub: $eventHubName" -ForegroundColor White
Write-Host "  Auth Rule: test-send-listen" -ForegroundColor White
Write-Host ""
Write-Host "Service Bus:" -ForegroundColor Cyan
Write-Host "  Namespace: $serviceBusNamespace" -ForegroundColor White
Write-Host "  Queue: $queueName" -ForegroundColor White
Write-Host "  Auth Rule: test-send-listen" -ForegroundColor White
Write-Host ""
Write-Host "Key Vault:" -ForegroundColor Cyan
Write-Host "  Name: $keyVaultName" -ForegroundColor White
Write-Host ""
Write-Host "Service Principal:" -ForegroundColor Cyan
Write-Host "  Display Name: $ServicePrincipalName" -ForegroundColor White
Write-Host "  Application ID: $($sp.AppId)" -ForegroundColor White
Write-Host ""

# Save configuration to file for test scripts
$config = @{
    ResourceGroup = $ResourceGroupName
    Location = $Location
    EventHubNamespace = $eventHubNamespace
    EventHubName = $eventHubName
    EventHubAuthRule = "test-send-listen"
    ServiceBusNamespace = $serviceBusNamespace
    QueueName = $queueName
    ServiceBusAuthRule = "test-send-listen"
    KeyVaultName = $keyVaultName
    ServicePrincipalAppId = $sp.AppId
    ServicePrincipalObjectId = $sp.Id
    DeploymentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

$configPath = Join-Path $PSScriptRoot "test-config.json"
$config | ConvertTo-Json | Set-Content -Path $configPath
Write-Host "Configuration saved to: $configPath" -ForegroundColor Green
Write-Host ""
Write-Host "You can now run the rotation scripts against this test infrastructure!" -ForegroundColor Yellow
