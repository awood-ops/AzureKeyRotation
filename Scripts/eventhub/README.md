# Event Hub Key Rotation

[![Azure](https://img.shields.io/badge/Azure-PowerShell-blue.svg)](https://docs.microsoft.com/en-us/powershell/azure/)
[![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue.svg)](https://docs.microsoft.com/en-us/powershell/)

Automated rotation of Azure Event Hub access keys with secure Key Vault storage.

## 📄 Script

### Rotate-EventHubAccessKeys.ps1
Enterprise-grade Event Hub key rotation script that rotates namespace or instance-level access keys and securely stores them in Azure Key Vault.

**Key Features:**
- Primary/Secondary key rotation
- Namespace or Event Hub instance scope
- Cross-subscription support (Event Hub and Key Vault in different subscriptions)
- Automatic Key Vault storage with configurable expiry
- Comprehensive error handling and validation
- Safety confirmations to prevent accidental rotations
- Verbose logging with security warnings
- Recovery options for failed Key Vault operations

## 🚀 Usage Examples

### Basic Namespace Key Rotation
```powershell
.\'Rotate-EventHubAccessKeys.ps1 `
    -ResourceGroup "rg-eventhub-prod" `
    -Namespace "evhns-prod-001" `
    -KeyName "RootManageSharedAccessKey" `
    -Rotate "Primary" `
    -KeyVaultName "kv-prod-001" `
    -SecretNamePrefix "eventhub" `
    -SecretExpiryDays 90
```

### Event Hub Instance Key Rotation
```powershell
.\'Rotate-EventHubAccessKeys.ps1 `
    -ResourceGroup "rg-eventhub-prod" `
    -Namespace "evhns-prod-001" `
    -EventHubName "eh-prod-instance" `
    -KeyName "SendListen" `
    -Rotate "Primary" `
    -KeyVaultName "kv-prod-001" `
    -SecretNamePrefix "eventhub"
```

### Cross-Subscription Rotation
```powershell
.\Rotate-EventHubAccessKeys.ps1 `
    -ResourceGroup "rg-eventhub-prod" `
    -EventHubSubscriptionId "11111111-1111-1111-1111-111111111111" `
    -Namespace "evhns-prod-001" `
    -KeyName "RootManageSharedAccessKey" `
    -Rotate "Primary" `
    -KeyVaultName "kv-security-prod" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -KeyVaultSubscriptionId "22222222-2222-2222-2222-222222222222" `
    -SecretNamePrefix "eventhub" `
    -Force
```

### Automated Rotation (No Confirmation)
```powershell
.\'Rotate-EventHubAccessKeys.ps1 `
    -ResourceGroup "rg-eventhub-prod" `
    -Namespace "evhns-prod-001" `
    -KeyName "RootManageSharedAccessKey" `
    -Rotate "Secondary" `
    -KeyVaultName "kv-prod-001" `
    -SecretNamePrefix "eventhub" `
    -SecretExpiryDays 30 `
    -Force
```

## 📋 Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `ResourceGroup` | Yes | Resource group containing the Event Hub namespace |
| `Namespace` | Yes | Event Hub namespace name |
| `KeyName` | Yes | Authorization rule name (e.g., "RootManageSharedAccessKey") |
| `Rotate` | Yes | Which key to rotate: "Primary" or "Secondary" |
| `KeyVaultName` | Yes | Key Vault name for storing rotated keys |
| `SecretNamePrefix` | Yes | Prefix for Key Vault secret names |
| `EventHubName` | No | Specific Event Hub instance (omit for namespace-level) |
| `EventHubSubscriptionId` | No | Subscription ID for Event Hub (defaults to current) |
| `KeyVaultResourceGroup` | No | Key Vault resource group (defaults to ResourceGroup) |
| `KeyVaultSubscriptionId` | No | Subscription ID for Key Vault (defaults to current) |
| `SecretExpiryDays` | No | Days until Key Vault secret expires (default: 90) |
| `Force` | No | Skip confirmation prompt |
| `ShowVerbose` | No | Show partial key values (⚠️ security risk) |
| `ShowRecoveryKey` | No | Show full key on failure (⚠️ security risk) |

## 🔐 Required Permissions

### Key Vault
- **Key Vault Secrets Officer** (recommended)
  - OR `Microsoft.KeyVault/vaults/secrets/read` + `Microsoft.KeyVault/vaults/secrets/write`

### Event Hub
- **Event Hubs Data Owner** (recommended)
  - OR for namespace operations:
    - `Microsoft.EventHub/namespaces/authorizationRules/read`
    - `Microsoft.EventHub/namespaces/authorizationRules/write`
  - OR for instance operations:
    - `Microsoft.EventHub/namespaces/eventhubs/authorizationRules/read`
    - `Microsoft.EventHub/namespaces/eventhubs/authorizationRules/write`

### Cross-Subscription
Service connections must have appropriate permissions in **both** subscriptions when using cross-subscription rotation.

## 📦 Prerequisites

- **PowerShell 7+**
- **Azure PowerShell Modules**: 
  ```powershell
  Install-Module Az.EventHub, Az.KeyVault -Force
  ```
- **Azure Context**: 
  ```powershell
  Connect-AzAccount
  ```

## 🔄 Azure DevOps Pipelines

Automated pipelines are available in `/.azuredevops/eventhub/`:
- **rotate-eventhub-primary-keys.yml** - Primary key rotation (1st of each month)
- **rotate-eventhub-secondary-keys.yml** - Secondary key rotation (16th of each month)

Pipelines support all environments: dev, qa, sit, uat, prod

## 🔧 Troubleshooting

**Permission Errors:**
- Verify Key Vault Secrets Officer and Event Hubs Data Owner roles assigned
- Check Azure context is connected to correct subscription

**Resource Not Found:**
- Confirm Event Hub namespace/instance exists in specified resource group
- Verify authorization rule name is correct

**Module Errors:**
- Install required modules: `Install-Module Az.EventHub, Az.KeyVault -Force`
- Update modules: `Update-Module Az.EventHub, Az.KeyVault`

## 🛡️ Security Best Practices

- **Never use** `-ShowVerbose` or `-ShowRecoveryKey` in production
- Clear console history after running scripts
- Use separate Key Vaults per environment
- Rotate keys on regular schedule (monthly recommended)
- Monitor Key Vault access logs
- Set appropriate secret expiry periods

## 📚 Related Documentation

- [Azure Event Hubs SAS Authentication](https://docs.microsoft.com/en-us/azure/event-hubs/authorize-access-shared-access-signature)
- [Azure Key Vault Secrets](https://docs.microsoft.com/en-us/azure/key-vault/secrets/)
- [Event Hubs RBAC Roles](https://docs.microsoft.com/en-us/azure/event-hubs/authorize-access-azure-active-directory)

---

*Use with appropriate security controls and testing.*
