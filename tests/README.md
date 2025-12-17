# Test Environment

This directory contains test infrastructure and scripts for validating the Azure Key Rotation automation.

## Directory Structure

```
tests/
├── infrastructure/
│   ├── Deploy-TestInfrastructure.ps1    # Creates test Azure resources
│   ├── Remove-TestInfrastructure.ps1    # Cleans up test resources
│   └── test-config.json                 # Generated config file (gitignored)
└── README.md                            # This file
```

## Quick Start

### 1. Deploy Test Infrastructure

```powershell
# Deploy with defaults (uksouth region, default naming)
.\tests\infrastructure\Deploy-TestInfrastructure.ps1

# Deploy with custom settings
.\tests\infrastructure\Deploy-TestInfrastructure.ps1 `
    -ResourceGroupName "rg-mytest" `
    -Location "uksouth" `
    -EnvironmentPrefix "mytest"
```

This creates:
- **Resource Group**: Container for all test resources
- **Event Hub Namespace**: With a test Event Hub and authorization rule
- **Service Bus Namespace**: With a test queue and authorization rule
- **Key Vault**: With RBAC enabled for secret storage
- **Service Principal**: With initial client secret for rotation testing

All resources are tagged with `Purpose = "Testing"` for easy identification.

### 2. Test the Rotation Scripts

After deployment, use the generated `test-config.json` to test the rotation scripts:

#### Test Event Hub Key Rotation

```powershell
# Load test configuration
$config = Get-Content .\tests\infrastructure\test-config.json | ConvertFrom-Json

# Test primary key rotation
.\Scripts\eventhub\Rotate-EventHubAccessKeys.ps1 `
    -ResourceGroup $config.ResourceGroup `
    -Namespace $config.EventHubNamespace `
    -EventHubName $config.EventHubName `
    -KeyName $config.EventHubAuthRule `
    -Rotate "Primary" `
    -KeyVaultName $config.KeyVaultName `
    -SecretNamePrefix "eventhub-test" `
    -SecretExpiryDays 30 `
    -Force

# Test secondary key rotation
.\Scripts\eventhub\Rotate-EventHubAccessKeys.ps1 `
    -ResourceGroup $config.ResourceGroup `
    -Namespace $config.EventHubNamespace `
    -EventHubName $config.EventHubName `
    -KeyName $config.EventHubAuthRule `
    -Rotate "Secondary" `
    -KeyVaultName $config.KeyVaultName `
    -SecretNamePrefix "eventhub-test" `
    -SecretExpiryDays 30 `
    -Force
```

#### Test Service Bus Key Rotation

```powershell
# Load test configuration
$config = Get-Content .\tests\infrastructure\test-config.json | ConvertFrom-Json

# Test primary key rotation
.\Scripts\servicebus\Rotate-ServiceBusAccessKeys.ps1 `
    -ResourceGroup $config.ResourceGroup `
    -ServiceBusNamespace $config.ServiceBusNamespace `
    -EntityName $config.QueueName `
    -EntityType "Queue" `
    -KeyName $config.ServiceBusAuthRule `
    -Rotate "Primary" `
    -KeyVaultName $config.KeyVaultName `
    -SecretNamePrefix "servicebus-test" `
    -SecretExpiryDays 30 `
    -Force

# Test secondary key rotation
.\Scripts\servicebus\Rotate-ServiceBusAccessKeys.ps1 `
    -ResourceGroup $config.ResourceGroup `
    -ServiceBusNamespace $config.ServiceBusNamespace `
    -EntityName $config.QueueName `
    -EntityType "Queue" `
    -KeyName $config.ServiceBusAuthRule `
    -Rotate "Secondary" `
    -KeyVaultName $config.KeyVaultName `
    -SecretNamePrefix "servicebus-test" `
    -SecretExpiryDays 30 `
    -Force
```

#### Test Service Principal Secret Rotation

```powershell
# Load test configuration
$config = Get-Content .\tests\infrastructure\test-config.json | ConvertFrom-Json

# Test secret rotation
.\Scripts\serviceprincipal\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId $config.ServicePrincipalAppId `
    -SecretDisplayName "TestRotation" `
    -SecretExpirationMonths 12 `
    -KeyVaultName $config.KeyVaultName `
    -KeyVaultResourceGroup $config.ResourceGroup `
    -SecretName "sp-test-secret" `
    -SecretExpiryDays 365 `
    -Force

# Test with removal of old secrets
.\Scripts\serviceprincipal\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId $config.ServicePrincipalAppId `
    -SecretDisplayName "TestRotation" `
    -SecretExpirationMonths 12 `
    -RemoveOldSecrets `
    -KeyVaultName $config.KeyVaultName `
    -KeyVaultResourceGroup $config.ResourceGroup `
    -SecretName "sp-test-secret" `
    -SecretExpiryDays 365 `
    -Force
```

### 3. Verify Results

Check that secrets were created in Key Vault:

```powershell
# Load test configuration
$config = Get-Content .\tests\infrastructure\test-config.json | ConvertFrom-Json

# List all secrets in the Key Vault
Get-AzKeyVaultSecret -VaultName $config.KeyVaultName | 
    Select-Object Name, Created, Expires, Enabled |
    Format-Table -AutoSize
```

### 4. Cleanup Test Resources

When testing is complete:

```powershell
# Interactive cleanup (prompts for confirmation)
.\tests\infrastructure\Remove-TestInfrastructure.ps1

# Force cleanup (no prompts)
.\tests\infrastructure\Remove-TestInfrastructure.ps1 -Force

# Cleanup custom-named resources
.\tests\infrastructure\Remove-TestInfrastructure.ps1 `
    -ResourceGroupName "rg-mytest" `
    -ServicePrincipalName "sp-mytest" `
    -Force
```

## Prerequisites

- **PowerShell Modules**: Az.Accounts, Az.Resources, Az.EventHub, Az.ServiceBus, Az.KeyVault
- **Azure Permissions**:
  - Contributor role on the subscription (or resource group)
  - Application Administrator role in Entra ID (for Service Principal creation)
- **Azure Login**: Run `Connect-AzAccount` before deploying

## Resource Naming Convention

The deployment script generates unique resource names using a timestamp:

- Event Hub Namespace: `{prefix}-evhns-{timestamp}`
- Service Bus Namespace: `{prefix}-sbns-{timestamp}`
- Key Vault: `{prefix}-kv-{timestamp}`
- Service Principal: `sp-keyrotation-test` (or custom name)

Where `{prefix}` defaults to `krtest` and `{timestamp}` is `MMddHHmm`.

## Cost Considerations

Test infrastructure uses minimal SKUs to reduce costs:
- Event Hub: Standard tier
- Service Bus: Standard tier
- Key Vault: Standard tier

**Estimated cost**: ~£2-4 GBP per day (varies by region)

Remember to clean up resources after testing to avoid ongoing charges!

## Troubleshooting

### Deployment Fails with "Namespace already exists"

If you re-run deployment without cleanup, namespaces may conflict. Either:
1. Run `Remove-TestInfrastructure.ps1` first
2. Use `-SkipCleanup` flag and change the `-EnvironmentPrefix`

### Key Vault Access Denied

Ensure your account has "Key Vault Secrets Officer" role. The deployment script attempts to assign this automatically, but role assignment may take a few minutes to propagate.

### Service Principal Not Found

Service Principal creation requires Application Administrator role in Entra ID. Verify your permissions with:

```powershell
Get-AzADUser -UserPrincipalName (Get-AzContext).Account.Id | 
    Get-AzRoleAssignment | 
    Where-Object { $_.RoleDefinitionName -like "*Application*" }
```

## Best Practices

1. **Use dedicated test subscription**: Isolate test resources from production
2. **Tag all resources**: The deployment script tags resources with `Purpose = "Testing"`
3. **Clean up regularly**: Don't leave test resources running overnight
4. **Document test results**: Keep notes on what works and what needs improvement
5. **Test cross-subscription scenarios**: Deploy Key Vault in different subscription/resource group

## Next Steps

After validating the rotation scripts:
1. Configure Azure DevOps pipelines using the templates in `.azuredevops/`
2. Set up service connections in Azure DevOps
3. Schedule regular rotation runs
4. Monitor rotation jobs and alert on failures

## Support

For issues or questions, please open a GitHub issue or refer to the main repository README.md.
