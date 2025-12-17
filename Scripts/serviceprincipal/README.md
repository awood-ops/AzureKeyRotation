# Service Principal Secret Rotation

[![Azure](https://img.shields.io/badge/Azure-PowerShell-blue.svg)](https://docs.microsoft.com/en-us/powershell/azure/)
[![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue.svg)](https://docs.microsoft.com/en-us/powershell/)

Automated rotation of Azure Service Principal client secrets with secure Key Vault storage.

## 📄 Script

### Rotate-ServicePrincipalSecret.ps1
Enterprise-grade Service Principal client secret rotation script that creates new credentials and securely stores them in Azure Key Vault, with optional removal of old secrets.

**Key Features:**
- Client secret creation with configurable expiration (1-24 months)
- Automatic Key Vault storage with expiration aligned to client secret
- Optional removal of old client secrets after rotation
- Cross-subscription support (Entra ID and Key Vault in different subscriptions)
- Comprehensive error handling and validation
- Safety confirmations to prevent accidental rotations
- Verbose logging with security warnings
- Recovery options for failed Key Vault operations
- Metadata tracking (ApplicationId, DisplayName, SecretKeyId, RotatedDate, RotatedBy)

## 🚀 Usage Examples

### Basic Secret Rotation (Interactive)
```powershell
.\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId "12345678-1234-1234-1234-123456789012" `
    -SecretDisplayName "Production-Secret" `
    -SecretExpirationMonths 12 `
    -KeyVaultName "kv-bhf-prod-uksouth" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -SecretName "app-client-secret"
```

### Force Rotation with Old Secret Removal
```powershell
.\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId "12345678-1234-1234-1234-123456789012" `
    -SecretDisplayName "Production-Secret" `
    -SecretExpirationMonths 12 `
    -KeyVaultName "kv-prod-001" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -SecretName "app-client-secret" `
    -Force `
    -RemoveOldSecrets
```

### Rotation Using Display Name
```powershell
.\Rotate-ServicePrincipalSecret.ps1 `
    -DisplayName "my-service-principal" `
    -SecretExpirationMonths 24 `
    -KeyVaultName "kv-prod-001" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -SecretName "sp-secret"
```

### Cross-Subscription Rotation
```powershell
.\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId "12345678-1234-1234-1234-123456789012" `
    -KeyVaultName "kv-security-prod" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -KeyVaultSubscriptionId "22222222-2222-2222-2222-222222222222" `
    -SecretName "app-secret" `
    -Force
```

### Verbose Output Mode
```powershell
.\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId "12345678-1234-1234-1234-123456789012" `
    -KeyVaultName "kv-prod-001" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -SecretName "app-secret" `
    -ShowVerbose
```

### Emergency Recovery Mode
```powershell
.\Rotate-ServicePrincipalSecret.ps1 `
    -ApplicationId "12345678-1234-1234-1234-123456789012" `
    -KeyVaultName "kv-prod-001" `
    -KeyVaultResourceGroup "rg-security-prod" `
    -SecretName "app-secret" `
    -ShowRecoverySecret
```

## 📋 Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `ApplicationId` | Conditional | Application (Client) ID of the Service Principal |
| `DisplayName` | Conditional | Display name of the Service Principal (alternative to ApplicationId) |
| `SecretDisplayName` | No | Display name for the new client secret (defaults to "Rotated-\<timestamp\>") |
| `SecretExpirationMonths` | No | Months until client secret expires (default: 12, max: 24) |
| `RemoveOldSecrets` | No | Remove all existing client secrets after rotation (⚠️ breaks existing apps) |
| `KeyVaultName` | Yes | Key Vault name for storing rotated secrets |
| `KeyVaultResourceGroup` | Yes | Key Vault resource group |
| `KeyVaultSubscriptionId` | No | Subscription ID for Key Vault (defaults to current) |
| `SecretName` | No | Key Vault secret name (auto-generated if not specified) |
| `SecretExpiryDays` | No | Days until Key Vault secret expires (default: -1 = match client secret) |
| `Force` | No | Skip confirmation prompt |
| `ShowVerbose` | No | Show partial secret values (⚠️ security risk) |
| `ShowRecoverySecret` | No | Show full secret on failure (⚠️ security risk) |

**Note:** Either `ApplicationId` or `DisplayName` must be specified.

## 🔐 Required Permissions

### Microsoft Entra ID (Entra ID)

#### Least-Privilege Model (Recommended for Automation):
- **Application Ownership** of the target Service Principal
- **Directory Readers** role (to read directory objects)
- **Application.ReadWrite.OwnedBy** Graph API permission (with admin consent)

This model allows the workload identity to manage only applications it owns, without needing tenant-wide Application Administrator permissions.

#### Alternative (Interactive Use):
- **Application Administrator** (tenant-wide permissions)
  - OR **Application.ReadWrite.All** API permission

### Key Vault
- **Key Vault Secrets Officer** (recommended)
  - OR `Microsoft.KeyVault/vaults/secrets/read` + `Microsoft.KeyVault/vaults/secrets/write`

### Recommended: Application Ownership Model

Use the `New-WorkloadIdentity.ps1` script to automate setup:

```powershell
..\New-WorkloadIdentity.ps1 `
    -ServicePrincipalName "sp-secretrotation" `
    -SubscriptionId "your-subscription-id" `
    -RoleAssignments @(
        @{RoleDefinitionName="Key Vault Secrets Officer"; Scope="/subscriptions/.../vaults/your-keyvault"}
    ) `
    -GrantApplicationOwnership @("app-id-1", "app-id-2") `
    -GrantDirectoryReadersRole `
    -AzureDevOpsOrganization "yourorg" `
    -AzureDevOpsProject "YourProject"
```

This automatically:
1. Creates the workload identity with federated credentials
2. Grants ownership of specified applications
3. Assigns Directory Readers role
4. Grants Application.ReadWrite.OwnedBy Graph API permission with admin consent
5. Creates Azure DevOps service connection

**Benefits:**
- No tenant-wide Application Administrator permissions
- Workload identity can only manage applications it owns
- Automated Azure DevOps integration
- Fully auditable and traceable

## 📦 Prerequisites

- **PowerShell 7+**
- **Azure PowerShell Modules**: 
  ```powershell
  Install-Module Az.Accounts, Az.Resources, Az.KeyVault -Force
  ```
- **Azure Context**: 
  ```powershell
  Connect-AzAccount
  ```

## 🔄 Key Vault Secret Metadata

The script stores comprehensive metadata with each rotated secret:

### ContentType
```
Service Principal Client Secret - Automatically rotated by script
```

### Tags
- `ApplicationId` - Service Principal Application ID
- `DisplayName` - Service Principal display name
- `SecretKeyId` - Client secret Key ID (for tracking)
- `RotatedDate` - ISO 8601 rotation timestamp
- `RotatedBy` - User who performed rotation

### Expiration Alignment
By default, Key Vault secret expiration is **aligned with client secret expiration** (not 90 days). This prevents operational issues where Key Vault secrets expire before the actual credentials.

## ⚠️ Important Notes

### RemoveOldSecrets Flag
When `-RemoveOldSecrets` is specified:
- All existing client secrets are **immediately invalidated**
- Applications using old secrets will **fail authentication**
- Use only when you're certain all applications have been updated

### Secret Detection
The script filters out certificates and only operates on client secrets using `CustomKeyIdentifier` detection.

## 🔧 Troubleshooting

**Permission Errors:**
- Verify Application Administrator role or application ownership
- Check Key Vault Secrets Officer role assigned
- Confirm Azure context is connected to correct subscription

**Application Not Found:**
- Verify Application ID or Display Name is correct
- Check you have permissions to view the application
- Ensure application exists in current tenant

**Module Errors:**
- Install required modules: `Install-Module Az.Accounts, Az.Resources, Az.KeyVault -Force`
- Update modules: `Update-Module Az.Accounts, Az.Resources, Az.KeyVault`

**Old Secrets Not Removed:**
- Script only removes Entra ID client secrets, not Key Vault secret versions
- Key Vault versions accumulate (this is intentional for audit/recovery)
- Use `-RemoveOldSecrets` flag to clean up client secrets

**Throttling Errors:**
- Script includes automatic retry logic (3 attempts, 5-second delays)
- Graph API may throttle concurrent requests - this is handled automatically
- Transient errors like "concurrent requests" are retried automatically

## 🛡️ Security Best Practices

- **Never use** `-ShowVerbose` or `-ShowRecoverySecret` in production
- Clear console history after running scripts with secret display
- Use separate Key Vaults per environment
- Rotate secrets on regular schedule (quarterly recommended for 12-month secrets)
- Monitor Key Vault access logs
- Use application ownership model for automation (least privilege)
- **Always test rotation** in dev/test before production
- Update applications **before** using `-RemoveOldSecrets`

## 🔄 Recommended Rotation Strategy

1. **Initial Rotation**: Create new secret without removing old ones
2. **Application Update**: Update all applications to use new secret
3. **Validation**: Verify all applications work with new secret
4. **Cleanup**: Run script again with `-RemoveOldSecrets` to invalidate old secrets

## 📚 Related Documentation

- [Azure Service Principal Credentials](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
- [Azure Key Vault Secrets](https://docs.microsoft.com/en-us/azure/key-vault/secrets/)
- [Application Permissions in Entra ID](https://docs.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals)

---

*Use with appropriate security controls and testing.*
