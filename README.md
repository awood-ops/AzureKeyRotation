# Azure Key Rotation

Automated scripts and Azure DevOps pipelines for rotating Azure service credentials and storing them securely in Azure Key Vault.

## Overview

This repository contains PowerShell scripts and Azure DevOps YAML pipelines for automating the rotation of:
- **Event Hub** access keys (primary and secondary)
- **Service Bus** access keys (primary and secondary)
- **Service Principal** client secrets

All rotated credentials are automatically stored in Azure Key Vault with configurable expiration dates and comprehensive metadata.

## Repository Structure

```
AzureKeyRotation/
├── Scripts/
│   ├── eventhub/
│   │   ├── README.md
│   │   └── Rotate-EventHubAccessKeys.ps1
│   ├── servicebus/
│   │   ├── README.md
│   │   └── Rotate-ServiceBusAccessKeys.ps1
│   └── serviceprincipal/
│       ├── README.md
│       └── Rotate-ServicePrincipalSecret.ps1
└── .azuredevops/
    ├── eventhub/
    │   ├── rotate-eventhub-primary-keys.yml
    │   └── rotate-eventhub-secondary-keys.yml
    └── servicebus/
        ├── rotate-servicebus-primary-keys.yml
        └── rotate-servicebus-secondary-keys.yml
```

## Scripts

### Event Hub Key Rotation
**Script:** `Scripts/eventhub/Rotate-EventHubAccessKeys.ps1`

Rotates Event Hub namespace or instance-level access keys and stores them in Azure Key Vault.

**Key Features:**
- Namespace-level or instance-level key rotation
- Primary or secondary key rotation
- Automatic Key Vault storage with metadata
- Configurable secret expiration
- Cross-subscription support
- Comprehensive logging

[View detailed documentation](Scripts/eventhub/README.md)

### Service Bus Key Rotation
**Script:** `Scripts/servicebus/Rotate-ServiceBusAccessKeys.ps1`

Rotates Service Bus namespace or queue/topic-level access keys and stores them in Azure Key Vault.

**Key Features:**
- Namespace, queue, or topic-level key rotation
- Primary or secondary key rotation
- Automatic Key Vault storage with metadata
- Configurable secret expiration
- Cross-subscription support
- Comprehensive logging

[View detailed documentation](Scripts/servicebus/README.md)

### Service Principal Secret Rotation
**Script:** `Scripts/serviceprincipal/Rotate-ServicePrincipalSecret.ps1`

Rotates Service Principal (Azure AD App Registration) client secrets and stores them in Azure Key Vault.

**Key Features:**
- Automatic secret expiration alignment with Key Vault
- Optional removal of old secrets
- Display name or Application ID lookup
- Comprehensive metadata tagging
- Cross-subscription support
- Force rotation capability

[View detailed documentation](Scripts/serviceprincipal/README.md)

## Azure DevOps Pipelines

### Event Hub Rotation Pipelines
- **Primary Keys:** `.azuredevops/eventhub/rotate-eventhub-primary-keys.yml` (Scheduled: 1st of each month)
- **Secondary Keys:** `.azuredevops/eventhub/rotate-eventhub-secondary-keys.yml` (Scheduled: 16th of each month)

### Service Bus Rotation Pipelines
- **Primary Keys:** `.azuredevops/servicebus/rotate-servicebus-primary-keys.yml` (Scheduled: 1st of each month)
- **Secondary Keys:** `.azuredevops/servicebus/rotate-servicebus-secondary-keys.yml` (Scheduled: 16th of each month)

All pipelines support multi-environment deployment (dev, qa, sit, uat, prod) and include comprehensive logging.

## Prerequisites

### PowerShell Modules
- `Az.Accounts` (all scripts)
- `Az.EventHub` (Event Hub rotation)
- `Az.ServiceBus` (Service Bus rotation)
- `Az.Resources` (Service Principal rotation)
- `Az.KeyVault` (all scripts)

### Azure Permissions
- **Event Hub:** Contributor or Event Hub Data Owner on namespace/instance
- **Service Bus:** Contributor or Service Bus Data Owner on namespace/queue/topic
- **Service Principal:** Application Administrator or higher in Azure AD
- **Key Vault:** Key Vault Secrets Officer or Contributor

## Quick Start

### Event Hub Example
```powershell
# Rotate namespace-level primary key
.\Scripts\eventhub\Rotate-EventHubAccessKeys.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789012" `
    -ResourceGroupName "rg-eventhub-prod" `
    -NamespaceName "evhns-prod-001" `
    -AuthorizationRuleName "RootManageSharedAccessKey" `
    -KeyType "Primary" `
    -KeyVaultName "kv-secrets-prod" `
    -SecretExpiryDays 90
```

### Service Bus Example
```powershell
# Rotate namespace-level secondary key
.\Scripts\servicebus\Rotate-ServiceBusAccessKeys.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789012" `
    -ResourceGroupName "rg-servicebus-prod" `
    -NamespaceName "sbns-prod-001" `
    -AuthorizationRuleName "RootManageSharedAccessKey" `
    -KeyType "Secondary" `
    -KeyVaultName "kv-secrets-prod" `
    -SecretExpiryDays 90
```

### Service Principal Example
```powershell
# Rotate Service Principal secret with Key Vault expiration alignment
.\Scripts\serviceprincipal\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId "12345678-1234-1234-1234-123456789012" `
    -KeyVaultName "kv-secrets-prod" `
    -SecretExpiryDays -1 `
    -RemoveOldSecrets
```

## Key Vault Secret Naming Convention

- **Event Hub:** `{EventHubNamespace}--{AuthorizationRuleName}--{KeyType}`
- **Service Bus:** `{ServiceBusNamespace}--{AuthorizationRuleName}--{KeyType}`
- **Service Principal:** `{DisplayName}--ClientSecret` or `sp-{ApplicationId}--ClientSecret`

## Security Best Practices

1. **Dual-Key Rotation:** Use primary/secondary rotation schedule to avoid downtime
2. **Expiration Alignment:** Set Key Vault expiration to match credential lifetime
3. **Metadata Tagging:** All secrets include comprehensive metadata for tracking
4. **Cross-Subscription:** Scripts support credential and Key Vault in different subscriptions
5. **Audit Logging:** All operations include detailed logging with timestamps

## Contributing

Contributions are welcome! Please ensure:
- Scripts follow existing PowerShell best practices
- All parameters are properly documented
- Error handling is comprehensive
- Logging is detailed and consistent

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or feature requests, please open an issue in this repository.