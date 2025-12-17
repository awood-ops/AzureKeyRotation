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
│   ├── New-WorkloadIdentity.ps1                 # Creates service principals with RBAC and Azure DevOps integration
│   ├── eventhub/
│   │   ├── README.md
│   │   └── Rotate-EventHubAccessKeys.ps1
│   ├── servicebus/
│   │   ├── README.md
│   │   └── Rotate-ServiceBusAccessKeys.ps1
│   └── serviceprincipal/
│       ├── README.md
│       └── Rotate-ServicePrincipalSecret.ps1
├── .azuredevops/
│   ├── eventhub/
│   │   ├── rotate-eventhub-primary-keys.yml
│   │   └── rotate-eventhub-secondary-keys.yml
│   ├── servicebus/
│   │   ├── rotate-servicebus-primary-keys.yml
│   │   └── rotate-servicebus-secondary-keys.yml
│   └── serviceprincipal/
│       └── rotate-serviceprincipal-secrets.yml
└── tests/
    ├── infrastructure/
    │   ├── Deploy-TestInfrastructure.ps1
    │   ├── Remove-TestInfrastructure.ps1
    │   └── test-config.json
    └── README.md
```

## Scripts

### Workload Identity Creation
**Script:** `Scripts/New-WorkloadIdentity.ps1`

Automated creation of workload identities (service principals) with Azure RBAC role assignments and Azure DevOps service connection integration.

**Key Features:**
- Creates service principals with federated credentials (no secrets)
- Assigns multiple Azure RBAC roles at various scopes
- Grants application ownership for least-privilege secret rotation
- Automatically grants Application.ReadWrite.OwnedBy Graph API permission
- Assigns Directory Readers role when needed
- Creates Azure DevOps service connections with workload identity federation
- Idempotent - safe to run multiple times
- Comprehensive error handling and validation

**Example:**
```powershell
.\Scripts\New-WorkloadIdentity.ps1 `
    -ServicePrincipalName "sp-secretrotation" `
    -SubscriptionId "12345678-1234-1234-1234-123456789012" `
    -RoleAssignments @(
        @{RoleDefinitionName="Key Vault Secrets Officer"; Scope="/subscriptions/.../providers/Microsoft.KeyVault/vaults/kv-prod"}
    ) `
    -GrantApplicationOwnership @("app-id-to-manage") `
    -GrantDirectoryReadersRole `
    -AzureDevOpsOrganization "myorg" `
    -AzureDevOpsProject "MyProject"
```

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

Rotates Service Principal (Entra ID App Registration) client secrets and stores them in Azure Key Vault.

**Key Features:**
- Automatic secret expiration alignment with Key Vault
- Optional removal of old secrets with retry logic for throttling
- Display name or Application ID lookup
- Comprehensive metadata tagging
- Cross-subscription support
- Least-privilege support via application ownership
- Requires: Directory Readers + Application.ReadWrite.OwnedBy permission
- Force rotation capability

[View detailed documentation](Scripts/serviceprincipal/README.md)

## Azure DevOps Pipelines

### Event Hub Rotation Pipelines
- **Primary Keys:** `.azuredevops/eventhub/rotate-eventhub-primary-keys.yml` (Scheduled: 1st of each month)
- **Secondary Keys:** `.azuredevops/eventhub/rotate-eventhub-secondary-keys.yml` (Scheduled: 16th of each month)

### Service Bus Rotation Pipelines
- **Primary Keys:** `.azuredevops/servicebus/rotate-servicebus-primary-keys.yml` (Scheduled: 1st of each month)
- **Secondary Keys:** `.azuredevops/servicebus/rotate-servicebus-secondary-keys.yml` (Scheduled: 16th of each month)

### Service Principal Rotation Pipeline
- **Secrets:** `.azuredevops/serviceprincipal/rotate-serviceprincipal-secrets.yml` (Scheduled: 8th of each month)

All pipelines use workload identity federation (no secrets) and include comprehensive logging.

## Prerequisites

### PowerShell Modules
- `Az.Accounts` (all scripts)
- `Az.EventHub` (Event Hub rotation)
- `Az.ServiceBus` (Service Bus rotation)
- `Az.Resources` (Service Principal rotation, workload identity creation)
- `Az.KeyVault` (all scripts)

### Azure Permissions

#### For Workload Identity Creation (New-WorkloadIdentity.ps1):
- **Azure RBAC:** User Access Administrator or Owner (to assign roles)
- **Entra ID:** Global Administrator or Privileged Role Administrator (to grant admin consent)
- **Azure DevOps:** Project Collection Administrator or Build Administrator

#### For Key Rotation:
- **Event Hub:** Azure Event Hubs Data Owner on namespace/instance
- **Service Bus:** Azure Service Bus Data Owner on namespace/queue/topic
- **Service Principal (Least-Privilege):**
  - Application ownership of target application(s)
  - Directory Readers role (Entra ID)
  - Application.ReadWrite.OwnedBy Graph API permission (with admin consent)
- **Key Vault:** Key Vault Secrets Officer

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