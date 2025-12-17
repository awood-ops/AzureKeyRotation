# Service Bus Key Rotation

[![Azure](https://img.shields.io/badge/Azure-PowerShell-blue.svg)](https://docs.microsoft.com/en-us/powershell/azure/)
[![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue.svg)](https://docs.microsoft.com/en-us/powershell/)

Automated rotation of Azure Service Bus access keys with secure Key Vault storage.

## 📄 Script

### Rotate-ServiceBusAccessKeys.ps1
Enterprise-grade Service Bus key rotation script that rotates namespace or entity-level (Queue/Topic) access keys and securely stores them in Azure Key Vault.

**Key Features:**
- Primary/Secondary key rotation
- Namespace, Queue, or Topic scope
- Cross-subscription support (Service Bus and Key Vault in different subscriptions)
- Automatic Key Vault storage with configurable expiry
- Comprehensive error handling and validation
- Safety confirmations to prevent accidental rotations
- Verbose logging with security warnings
- Recovery options for failed Key Vault operations

## 🚀 Usage Examples

### Basic Namespace Key Rotation
```powershell
.\'Rotate-ServiceBusAccessKeys.ps1 `
    -ResourceGroup "rg-servicebus-prod" `
    -ServiceBusNamespace "sbns-prod-001" `
    -KeyName "RootManageSharedAccessKey" `
    -Rotate "Primary" `
    -KeyVaultName "kv-prod-001" `
    -SecretNamePrefix "servicebus" `
    -SecretExpiryDays 90
```

### Queue Key Rotation
```powershell
.\'Rotate-ServiceBusAccessKeys.ps1 `
    -ResourceGroup "rg-servicebus-prod" `
    -ServiceBusNamespace "sbns-prod-001" `
    -EntityName "my-queue" `
    -EntityType "Queue" `
    -KeyName "SendListen" `
    -Rotate "Primary" `
    -KeyVaultName "kv-prod-001" `
    -SecretNamePrefix "servicebus"
```

### Topic Key Rotation
```powershell
.\'Rotate-ServiceBusAccessKeys.ps1 `
    -ResourceGroup "rg-servicebus-prod" `
    -ServiceBusNamespace "sbns-prod-001" `
    -EntityName "my-topic" `
    -EntityType "Topic" `
    -KeyName "SendListen" `
    -Rotate "Secondary" `
    -KeyVaultName "kv-prod-001" `
    -SecretNamePrefix "servicebus"
```

### Cross-Subscription Rotation
```powershell
.\Rotate-ServiceBusAccessKeys.ps1 `
    -ResourceGroup "rg-servicebus-prod" `
    -ServiceBusSubscriptionId "11111111-1111-1111-1111-111111111111" `
    -ServiceBusNamespace "sbns-prod-001" `
    -KeyName "RootManageSharedAccessKey" `
    -Rotate "Primary" `
    -KeyVaultName "kv-security-prod" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -KeyVaultSubscriptionId "22222222-2222-2222-2222-222222222222" `
    -SecretNamePrefix "servicebus" `
    -Force
```

### Automated Rotation (No Confirmation)
```powershell
.\'Rotate-ServiceBusAccessKeys.ps1 `
    -ResourceGroup "rg-servicebus-prod" `
    -ServiceBusNamespace "sbns-prod-001" `
    -KeyName "RootManageSharedAccessKey" `
    -Rotate "Secondary" `
    -KeyVaultName "kv-prod-001" `
    -SecretNamePrefix "servicebus" `
    -SecretExpiryDays 30 `
    -Force
```

## 📋 Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `ResourceGroup` | Yes | Resource group containing the Service Bus namespace |
| `ServiceBusNamespace` | Yes | Service Bus namespace name |
| `KeyName` | Yes | Authorization rule name (e.g., "RootManageSharedAccessKey") |
| `Rotate` | Yes | Which key to rotate: "Primary" or "Secondary" |
| `KeyVaultName` | Yes | Key Vault name for storing rotated keys |
| `SecretNamePrefix` | Yes | Prefix for Key Vault secret names |
| `EntityName` | No | Specific Queue or Topic name (omit for namespace-level) |
| `EntityType` | Conditional | "Queue" or "Topic" (required if EntityName specified) |
| `ServiceBusSubscriptionId` | No | Subscription ID for Service Bus (defaults to current) |
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

### Service Bus
- **Azure Service Bus Data Owner** (recommended)
  - OR for namespace operations:
    - `Microsoft.ServiceBus/namespaces/authorizationRules/read`
    - `Microsoft.ServiceBus/namespaces/authorizationRules/write`
  - OR for Queue operations:
    - `Microsoft.ServiceBus/namespaces/queues/authorizationRules/read`
    - `Microsoft.ServiceBus/namespaces/queues/authorizationRules/write`
  - OR for Topic operations:
    - `Microsoft.ServiceBus/namespaces/topics/authorizationRules/read`
    - `Microsoft.ServiceBus/namespaces/topics/authorizationRules/write`

### Cross-Subscription
Service connections must have appropriate permissions in **both** subscriptions when using cross-subscription rotation.

## 📦 Prerequisites

- **PowerShell 7+**
- **Azure PowerShell Modules**: 
  ```powershell
  Install-Module Az.ServiceBus, Az.KeyVault -Force
  ```
- **Azure Context**: 
  ```powershell
  Connect-AzAccount
  ```

## 🔄 Azure DevOps Pipelines

Automated pipelines are available in `/.azuredevops/servicebus/`:
- **rotate-servicebus-primary-keys.yml** - Primary key rotation (1st of each month)
- **rotate-servicebus-secondary-keys.yml** - Secondary key rotation (16th of each month)

Pipelines support all environments: dev, qa, sit, uat, prod

## 🔧 Troubleshooting

**Permission Errors:**
- Verify Key Vault Secrets Officer and Service Bus Data Owner roles assigned
- Check Azure context is connected to correct subscription

**Resource Not Found:**
- Confirm Service Bus namespace/entity exists in specified resource group
- Verify authorization rule name is correct
- For entities, ensure EntityType matches actual resource type

**Module Errors:**
- Install required modules: `Install-Module Az.ServiceBus, Az.KeyVault -Force`
- Update modules: `Update-Module Az.ServiceBus, Az.KeyVault`

**Entity Type Validation:**
- EntityType is required when EntityName is specified
- Valid values: "Queue" or "Topic" (case-sensitive)

## 🛡️ Security Best Practices

- **Never use** `-ShowVerbose` or `-ShowRecoveryKey` in production
- Clear console history after running scripts
- Use separate Key Vaults per environment
- Rotate keys on regular schedule (monthly recommended)
- Monitor Key Vault access logs
- Set appropriate secret expiry periods
- Use entity-level authorization rules for fine-grained access control

## 📚 Related Documentation

- [Azure Service Bus SAS Authentication](https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-sas)
- [Azure Key Vault Secrets](https://docs.microsoft.com/en-us/azure/key-vault/secrets/)
- [Service Bus RBAC Roles](https://docs.microsoft.com/en-us/azure/service-bus-messaging/authenticate-application)

---

*Use with appropriate security controls and testing.*
