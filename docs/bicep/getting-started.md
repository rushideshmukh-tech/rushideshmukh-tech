# Getting Started with Azure Bicep

Azure Bicep is a domain-specific language (DSL) for deploying Azure resources declaratively. It provides a cleaner syntax compared to ARM templates while maintaining full compatibility with the Azure Resource Manager.

## What is Bicep?

!!! info "Bicep at a Glance"

    - **Native Azure IaC**: First-party language from Microsoft
    - **Transparent Abstraction**: Compiles directly to ARM JSON
    - **Zero-day Support**: New Azure features available immediately
    - **Fully Integrated**: Works with Azure CLI, PowerShell, and DevOps tools

## Prerequisites

Before you begin, ensure you have:

- [x] An Azure subscription
- [x] Azure CLI (version 2.20.0 or later)
- [x] VS Code with the Bicep extension

## Installation

### Install Azure CLI with Bicep

=== "Windows"

    ```powershell
    # Install Azure CLI using winget
    winget install Microsoft.AzureCLI

    # Install Bicep
    az bicep install

    # Verify installation
    az bicep version
    ```

=== "macOS"

    ```bash
    # Install Azure CLI
    brew install azure-cli

    # Install Bicep
    az bicep install

    # Verify installation
    az bicep version
    ```

=== "Linux"

    ```bash
    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

    # Install Bicep
    az bicep install

    # Verify installation
    az bicep version
    ```

### VS Code Extension

Install the Bicep extension for the best development experience:

1. Open VS Code
2. Go to Extensions (Ctrl+Shift+X)
3. Search for "Bicep"
4. Install the official Microsoft Bicep extension

## Your First Bicep File

Create a file named `main.bicep`:

```bicep
// main.bicep - Deploy a Storage Account

@description('Location for all resources')
param location string = resourceGroup().location

@description('Storage account name')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageSku string = 'Standard_LRS'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

output storageAccountId string = storageAccount.id
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
```

## Deploy Your First Resource

### Step 1: Login to Azure

```bash
az login
```

### Step 2: Create a Resource Group

```bash
az group create --name rg-bicep-demo --location eastus
```

### Step 3: Deploy the Bicep File

```bash
az deployment group create \
  --resource-group rg-bicep-demo \
  --template-file main.bicep \
  --parameters storageAccountName=stbicepdemo123
```

### Step 4: Verify the Deployment

```bash
az storage account show \
  --name stbicepdemo123 \
  --resource-group rg-bicep-demo \
  --query "{name:name, location:location, sku:sku.name}"
```

## Understanding Bicep Syntax

### Parameters

Parameters allow you to customize deployments:

```bicep
@description('The environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@secure()
param adminPassword string
```

### Variables

Variables simplify complex expressions:

```bicep
var resourcePrefix = 'myapp-${environment}'
var tags = {
  Environment: environment
  ManagedBy: 'Bicep'
}
```

### Resources

Resources are the core building blocks:

```bicep
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${resourcePrefix}-plan'
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  tags: tags
}
```

### Outputs

Outputs expose values after deployment:

```bicep
output appServicePlanId string = appServicePlan.id
```

## What's Next?

Now that you've deployed your first Bicep resource, explore:

- [Bicep Modules](modules.md) - Learn to create reusable modules
- [Best Practices](best-practices.md) - Write production-ready Bicep code
- [Examples](examples.md) - Real-world deployment examples

---

!!! tip "Pro Tip"

    Use `az bicep build` to see the ARM template that Bicep generates. This helps you understand what's happening under the hood!

    ```bash
    az bicep build --file main.bicep --outfile main.json
    ```
