<#
.SYNOPSIS
    Removes test infrastructure created for Azure Key Rotation testing.

.DESCRIPTION
    Deletes all resources created by Deploy-TestInfrastructure.ps1:
    - Service Principal
    - Resource Group (which cascades to all contained resources)

.PARAMETER ResourceGroupName
    Name of the resource group to delete. Default: rg-keyrotation-test

.PARAMETER ServicePrincipalName
    Name of the test service principal to delete. Default: sp-keyrotation-test

.PARAMETER Force
    Skips confirmation prompts.

.EXAMPLE
    .\Remove-TestInfrastructure.ps1

.EXAMPLE
    .\Remove-TestInfrastructure.ps1 -ResourceGroupName "rg-mytest" -ServicePrincipalName "sp-mytest" -Force

.NOTES
    Requires: Az.Accounts, Az.Resources
    Permissions: Contributor on subscription, Application Administrator in Entra ID
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-keyrotation-test",

    [Parameter(Mandatory = $false)]
    [string]$ServicePrincipalName = "sp-keyrotation-test",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Key Rotation Test Infrastructure Cleanup ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "Service Principal: $ServicePrincipalName" -ForegroundColor Gray
Write-Host ""

# Confirm unless -Force is used
if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to delete ALL test resources? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Ensure we're logged in
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged into Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "Error checking Azure context: $_" -ForegroundColor Red
    exit 1
}

# Delete Service Principal
Write-Host "Deleting Service Principal: $ServicePrincipalName..." -ForegroundColor Cyan
try {
    $sp = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName -ErrorAction SilentlyContinue
    if ($sp) {
        Remove-AzADServicePrincipal -ObjectId $sp.Id -Force
        Write-Host "✓ Service Principal deleted." -ForegroundColor Green
    }
    else {
        Write-Host "  Service Principal not found (may already be deleted)." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error deleting Service Principal: $_" -ForegroundColor Red
}
Write-Host ""

# Delete Resource Group
Write-Host "Deleting Resource Group: $ResourceGroupName..." -ForegroundColor Cyan
Write-Host "  This will delete ALL resources in the group (Event Hub, Service Bus, Key Vault, etc.)" -ForegroundColor Yellow
try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($rg) {
        Remove-AzResourceGroup -Name $ResourceGroupName -Force | Out-Null
        Write-Host "✓ Resource Group deleted." -ForegroundColor Green
    }
    else {
        Write-Host "  Resource Group not found (may already be deleted)." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error deleting Resource Group: $_" -ForegroundColor Red
}
Write-Host ""

# Delete config file if exists
$configPath = Join-Path $PSScriptRoot "test-config.json"
if (Test-Path $configPath) {
    Write-Host "Deleting configuration file..." -ForegroundColor Cyan
    Remove-Item -Path $configPath -Force
    Write-Host "✓ Configuration file deleted." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
