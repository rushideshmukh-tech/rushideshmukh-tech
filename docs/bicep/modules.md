# Bicep Modules

Modules are the key to creating reusable, maintainable, and scalable Bicep code. They allow you to encapsulate related resources and share them across projects.

## What are Modules?

!!! info "Module Benefits"

    - **Reusability**: Write once, deploy many times
    - **Encapsulation**: Hide complexity behind simple interfaces
    - **Testing**: Test modules independently
    - **Versioning**: Control module versions for stability

## Creating Your First Module

### Module Structure

A typical module structure looks like this:

```
📁 modules/
  📁 storage/
    📄 main.bicep
    📄 README.md
  📁 networking/
    📄 main.bicep
    📄 README.md
📄 main.bicep
📄 bicepconfig.json
```

### Example: Storage Account Module

Create `modules/storage/main.bicep`:

```bicep
// modules/storage/main.bicep

@description('Storage account name')
@minLength(3)
@maxLength(24)
param name string

@description('Location for the storage account')
param location string = resourceGroup().location

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param sku string = 'Standard_LRS'

@description('Tags to apply to the storage account')
param tags object = {}

@description('Enable blob versioning')
param enableVersioning bool = false

@description('Enable soft delete for containers')
param containerSoftDeleteDays int = 7

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    isVersioningEnabled: enableVersioning
    containerDeleteRetentionPolicy: {
      enabled: true
      days: containerSoftDeleteDays
    }
  }
}

// Outputs
output id string = storageAccount.id
output name string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
```

### Using the Module

Reference the module in your main template:

```bicep
// main.bicep

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

param location string = resourceGroup().location

var storageAccountName = 'st${uniqueString(resourceGroup().id)}${environment}'

// Use the storage module
module storage 'modules/storage/main.bicep' = {
  name: 'storageDeployment'
  params: {
    name: storageAccountName
    location: location
    sku: environment == 'prod' ? 'Standard_GRS' : 'Standard_LRS'
    enableVersioning: environment == 'prod'
    tags: {
      Environment: environment
      ManagedBy: 'Bicep'
    }
  }
}

// Access module outputs
output storageAccountId string = storage.outputs.id
output blobEndpoint string = storage.outputs.primaryBlobEndpoint
```

## Advanced Module Patterns

### Conditional Deployment

Deploy modules conditionally:

```bicep
@description('Deploy monitoring resources')
param deployMonitoring bool = true

module monitoring 'modules/monitoring/main.bicep' = if (deployMonitoring) {
  name: 'monitoringDeployment'
  params: {
    // ...
  }
}
```

### Looping Over Modules

Deploy multiple instances:

```bicep
@description('List of web apps to deploy')
param webApps array = [
  { name: 'app1', sku: 'B1' }
  { name: 'app2', sku: 'S1' }
]

module webApp 'modules/webapp/main.bicep' = [for app in webApps: {
  name: 'webapp-${app.name}'
  params: {
    name: app.name
    sku: app.sku
    location: location
  }
}]
```

### Cross-Scope Deployment

Deploy to different scopes:

```bicep
// Deploy to a different resource group
module networkModule 'modules/network/main.bicep' = {
  name: 'networkDeployment'
  scope: resourceGroup('rg-network')
  params: {
    // ...
  }
}

// Deploy to subscription scope
module policyModule 'modules/policies/main.bicep' = {
  name: 'policyDeployment'
  scope: subscription()
  params: {
    // ...
  }
}
```

## Azure Verified Modules (AVM)

Microsoft provides production-ready modules through Azure Verified Modules:

!!! tip "Azure Verified Modules"

    AVM modules are:
    
    - ✅ Officially supported by Microsoft
    - ✅ Follow best practices
    - ✅ Regularly updated
    - ✅ Well documented

### Using AVM from Bicep Registry

```bicep
// Use Azure Verified Module for Storage Account
module storageAccount 'br/public:avm/res/storage/storage-account:0.9.0' = {
  name: 'storageDeployment'
  params: {
    name: storageAccountName
    location: location
  }
}
```

### Configuring Bicep Registry

Create or update `bicepconfig.json`:

```json
{
  "moduleAliases": {
    "br": {
      "public": {
        "registry": "mcr.microsoft.com",
        "modulePath": "bicep"
      },
      "myRegistry": {
        "registry": "myacr.azurecr.io",
        "modulePath": "bicep/modules"
      }
    }
  }
}
```

## Private Module Registry

### Push to Azure Container Registry

```bash
# Create ACR
az acr create --name myBicepRegistry --resource-group rg-common --sku Basic

# Publish module
az bicep publish \
  --file modules/storage/main.bicep \
  --target br:myBicepRegistry.azurecr.io/bicep/modules/storage:v1.0.0
```

### Reference Private Modules

```bicep
module storage 'br:myBicepRegistry.azurecr.io/bicep/modules/storage:v1.0.0' = {
  name: 'storageDeployment'
  params: {
    // ...
  }
}
```

## Module Best Practices

!!! success "Do's"

    - ✅ Use descriptive parameter names with `@description`
    - ✅ Provide sensible defaults where appropriate
    - ✅ Validate inputs with decorators (`@minLength`, `@allowed`)
    - ✅ Document modules with README files
    - ✅ Version your modules semantically

!!! failure "Don'ts"

    - ❌ Create overly complex modules with too many resources
    - ❌ Hard-code values that should be parameters
    - ❌ Expose sensitive outputs unnecessarily
    - ❌ Skip output definitions for useful values

## Next Steps

- [Best Practices](best-practices.md) - More patterns and practices
- [Examples](examples.md) - Complete working examples
