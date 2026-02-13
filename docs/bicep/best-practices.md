# Bicep Best Practices

Writing maintainable, secure, and efficient Bicep code requires following established best practices. This guide covers essential patterns for production-ready infrastructure.

## Code Organization

### File Structure

Organize your Bicep files logically:

```
📁 infrastructure/
  📁 modules/
    📁 compute/
    📁 networking/
    📁 storage/
    📁 security/
  📁 environments/
    📄 dev.bicepparam
    📄 staging.bicepparam
    📄 prod.bicepparam
  📄 main.bicep
  📄 bicepconfig.json
```

### Naming Conventions

Use consistent naming throughout:

```bicep
// ✅ Good: Clear, descriptive names
param storageAccountName string
param virtualNetworkAddressPrefix string
var resourceGroupLocation = resourceGroup().location

// ❌ Bad: Abbreviations and unclear names
param saName string
param vnetAddrPfx string
var loc = resourceGroup().location
```

## Parameter Design

### Use Decorators Effectively

```bicep
@description('The name of the storage account. Must be globally unique.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('The SKU tier for the App Service Plan')
@allowed([
  'Free'
  'Shared'
  'Basic'
  'Standard'
  'Premium'
  'PremiumV2'
  'PremiumV3'
])
param appServicePlanSku string = 'Standard'

@description('The administrator password for the SQL Server')
@secure()
param sqlAdminPassword string
```

### Use Parameter Files

Create `.bicepparam` files for each environment:

```bicep
// environments/prod.bicepparam
using '../main.bicep'

param environment = 'prod'
param location = 'eastus'
param storageAccountSku = 'Standard_GRS'
param enableDiagnostics = true
param enablePrivateEndpoints = true
```

## Security Best Practices

### Never Expose Secrets

```bicep
// ✅ Good: Reference Key Vault secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

module sqlServer 'modules/sql/main.bicep' = {
  name: 'sqlDeployment'
  params: {
    adminPassword: keyVault.getSecret('sqlAdminPassword')
  }
}

// ❌ Bad: Password as output
output adminPassword string = sqlAdminPassword // NEVER DO THIS
```

### Enable Security Features by Default

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    // Security defaults
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Use Azure AD auth only
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}
```

### Use Managed Identities

```bicep
// Create user-assigned managed identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-identity'
  location: location
}

// Use managed identity for App Service
resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: '${prefix}-app'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    // ...
  }
}
```

## Resource Configuration

### Use API Versions Intentionally

```bicep
// ✅ Good: Specific, recent API version
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  // ...
}

// ❌ Avoid: Very old API versions (missing features/security updates)
resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  // ...
}
```

### Use Resource Dependencies Correctly

```bicep
// Implicit dependency (preferred when possible)
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id  // Creates implicit dependency
  }
}

// Explicit dependency (when implicit isn't possible)
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

resource dnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    privateDnsZone  // Explicit when needed
  ]
}
```

## Tagging Strategy

### Consistent Tags

```bicep
@description('Environment name')
param environment string

@description('Application name')
param applicationName string

@description('Cost center code')
param costCenter string

@description('Owner email')
param ownerEmail string

var commonTags = {
  Environment: environment
  Application: applicationName
  CostCenter: costCenter
  Owner: ownerEmail
  ManagedBy: 'Bicep'
  DeploymentDate: utcNow('yyyy-MM-dd')
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  // ...
}
```

## Error Handling

### Validate Before Deployment

```bash
# Validate the template
az deployment group validate \
  --resource-group rg-myapp \
  --template-file main.bicep \
  --parameters @environments/prod.bicepparam

# What-if deployment
az deployment group what-if \
  --resource-group rg-myapp \
  --template-file main.bicep \
  --parameters @environments/prod.bicepparam
```

### Use Conditions Wisely

```bicep
@description('Deploy diagnostic settings')
param deployDiagnostics bool = true

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string = ''

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  name: 'diag-${storageAccount.name}'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}
```

## Output Management

### Useful Outputs Only

```bicep
// ✅ Good: Outputs needed for downstream operations
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

// ❌ Bad: Unnecessary or sensitive outputs
output everything object = storageAccount
output connectionString string = listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value
```

## Linting and Configuration

### Configure Bicep Linter

Create `bicepconfig.json`:

```json
{
  "analyzers": {
    "core": {
      "enabled": true,
      "rules": {
        "no-hardcoded-location": {
          "level": "warning"
        },
        "no-unused-params": {
          "level": "warning"
        },
        "no-unused-vars": {
          "level": "warning"
        },
        "prefer-interpolation": {
          "level": "warning"
        },
        "secure-parameter-default": {
          "level": "error"
        },
        "adminusername-should-not-be-literal": {
          "level": "error"
        },
        "use-protectedsettings-for-commandtoexecute-secrets": {
          "level": "error"
        }
      }
    }
  }
}
```

## Summary Checklist

!!! abstract "Best Practices Checklist"

    - [ ] Use descriptive parameter names with `@description`
    - [ ] Apply input validation with decorators
    - [ ] Store secrets in Key Vault, not parameters
    - [ ] Enable security features by default
    - [ ] Use managed identities over connection strings
    - [ ] Apply consistent tagging
    - [ ] Use parameter files for environments
    - [ ] Configure the Bicep linter
    - [ ] Validate before deploying
    - [ ] Document with README files

## Next Steps

- [Examples](examples.md) - See these practices in action
- [Modules](modules.md) - Learn modular design patterns
