# Bicep Examples

Real-world examples of Azure infrastructure deployments using Bicep. Each example includes complete, production-ready code.

## Web Application Architecture

### Full-Stack Web App with SQL Database

This example deploys a complete web application with:
- App Service with staging slot
- Azure SQL Database
- Application Insights
- Key Vault for secrets

```bicep
// main.bicep - Full-stack web application

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('SQL administrator username')
param sqlAdminUsername string

@description('SQL administrator password')
@secure()
param sqlAdminPassword string

// Variables
var prefix = 'webapp-${environment}'
var tags = {
  Environment: environment
  Application: 'WebApp'
  ManagedBy: 'Bicep'
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${prefix}-plan'
  location: location
  tags: tags
  sku: {
    name: environment == 'prod' ? 'P1v3' : 'B1'
    tier: environment == 'prod' ? 'PremiumV3' : 'Basic'
  }
  properties: {
    reserved: false
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${prefix}-kv-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
  }
}

// Store SQL password in Key Vault
resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
  }
}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: '${prefix}-sql-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion: '1.2'
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: '${prefix}-db'
  location: location
  tags: tags
  sku: {
    name: environment == 'prod' ? 'S1' : 'Basic'
    tier: environment == 'prod' ? 'Standard' : 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: environment == 'prod' ? 268435456000 : 2147483648
  }
}

// Allow Azure services to access SQL
resource sqlFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Web App
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: '${prefix}-app-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ]
      connectionStrings: [
        {
          name: 'DefaultConnection'
          connectionString: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabase.name};'
          type: 'SQLAzure'
        }
      ]
    }
  }
}

// Staging Slot (for production only)
resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = if (environment == 'prod') {
  parent: webApp
  name: 'staging'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
  }
}

// Outputs
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output keyVaultName string = keyVault.name
```

## Microservices Architecture

### Azure Container Apps Environment

Deploy a microservices environment with Container Apps:

```bicep
// container-apps.bicep - Microservices infrastructure

@description('Environment name')
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

var prefix = 'microservices-${environment}'

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Container Apps Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: '${prefix}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: environment == 'prod'
  }
}

// API Container App
resource apiApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: '${prefix}-api'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE']
        }
      }
      secrets: [
        {
          name: 'registry-password'
          value: 'your-registry-password'
        }
      ]
      registries: [
        {
          server: 'myregistry.azurecr.io'
          username: 'myregistry'
          passwordSecretRef: 'registry-password'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: environment
            }
          ]
        }
      ]
      scale: {
        minReplicas: environment == 'prod' ? 2 : 0
        maxReplicas: 10
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output apiUrl string = 'https://${apiApp.properties.configuration.ingress.fqdn}'
output environmentId string = containerAppEnv.id
```

## Data Platform

### Azure Cosmos DB with Private Endpoints

```bicep
// cosmos-db.bicep - Cosmos DB with private networking

@description('Cosmos DB account name')
param cosmosAccountName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Virtual network resource group')
param vnetResourceGroup string

@description('Virtual network name')
param vnetName string

@description('Subnet name for private endpoint')
param subnetName string

// Existing VNet reference
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroup)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: subnetName
}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: true
      }
    ]
    enableAutomaticFailover: true
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Disabled'
    networkAclBypass: 'AzureServices'
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

// Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
}

// Link DNS Zone to VNet
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoint
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${cosmosAccountName}-pe'
  location: location
  properties: {
    subnet: {
      id: subnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${cosmosAccountName}-connection'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

// DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output cosmosAccountId string = cosmosAccount.id
output cosmosAccountEndpoint string = cosmosAccount.properties.documentEndpoint
```

## Hub-and-Spoke Network

### Enterprise Network Architecture

```bicep
// hub-network.bicep - Hub virtual network

@description('Location for all resources')
param location string = resourceGroup().location

@description('Address prefix for the hub VNet')
param hubAddressPrefix string = '10.0.0.0/16'

// Hub Virtual Network
resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'hub-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
      {
        name: 'SharedServicesSubnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
        }
      }
    ]
  }
}

// Azure Firewall Public IP
resource firewallPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'hub-fw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Azure Firewall
resource firewall 'Microsoft.Network/azureFirewalls@2023-09-01' = {
  name: 'hub-firewall'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: {
            id: hubVnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: firewallPip.id
          }
        }
      }
    ]
    networkRuleCollections: [
      {
        name: 'allow-dns'
        properties: {
          priority: 100
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'dns'
              protocols: ['UDP']
              sourceAddresses: ['10.0.0.0/8']
              destinationAddresses: ['*']
              destinationPorts: ['53']
            }
          ]
        }
      }
    ]
  }
}

// Bastion Public IP
resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'hub-bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Azure Bastion
resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: 'hub-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: hubVnet.properties.subnets[2].id
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

output hubVnetId string = hubVnet.id
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
```

## Next Steps

- [Getting Started](getting-started.md) - Start from the basics
- [Modules](modules.md) - Create reusable components
- [Best Practices](best-practices.md) - Follow production patterns
