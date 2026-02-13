# Terraform Modules

Modules are the building blocks of reusable Terraform configurations. They allow you to create abstractions for infrastructure components that can be shared across projects and teams.

## What are Modules?

!!! info "Module Benefits"

    - **Reusability**: Share infrastructure patterns across projects
    - **Encapsulation**: Hide implementation complexity
    - **Consistency**: Enforce standards across deployments
    - **Versioning**: Control changes with semantic versioning

## Module Structure

### Standard Module Layout

```
📁 modules/
  📁 storage-account/
    📄 main.tf
    📄 variables.tf
    📄 outputs.tf
    📄 versions.tf
    📄 README.md
  📁 virtual-network/
    📄 main.tf
    📄 variables.tf
    📄 outputs.tf
    📄 versions.tf
    📄 README.md
📁 environments/
  📁 dev/
    📄 main.tf
    📄 terraform.tfvars
  📁 prod/
    📄 main.tf
    📄 terraform.tfvars
```

## Creating Your First Module

### Example: Storage Account Module

#### modules/storage-account/versions.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.85.0"
    }
  }
}
```

#### modules/storage-account/variables.tf

```hcl
variable "name" {
  description = "The name of the storage account"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The Azure region for the storage account"
  type        = string
}

variable "account_tier" {
  description = "The tier of the storage account"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be Standard or Premium."
  }
}

variable "replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Invalid replication type."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning"
  type        = bool
  default     = false
}

variable "container_soft_delete_days" {
  description = "Days to retain soft-deleted containers"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to the storage account"
  type        = map(string)
  default     = {}
}

variable "network_rules" {
  description = "Network rules for the storage account"
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = {}
}
```

#### modules/storage-account/main.tf

```hcl
resource "azurerm_storage_account" "this" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.account_tier
  account_replication_type = var.replication_type

  # Security settings
  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true

  # Blob properties
  blob_properties {
    versioning_enabled = var.enable_versioning

    container_delete_retention_policy {
      days = var.container_soft_delete_days
    }

    delete_retention_policy {
      days = var.container_soft_delete_days
    }
  }

  # Network rules
  network_rules {
    default_action             = var.network_rules.default_action
    bypass                     = var.network_rules.bypass
    ip_rules                   = var.network_rules.ip_rules
    virtual_network_subnet_ids = var.network_rules.virtual_network_subnet_ids
  }

  tags = var.tags
}
```

#### modules/storage-account/outputs.tf

```hcl
output "id" {
  description = "The ID of the storage account"
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "The primary blob endpoint"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_access_key" {
  description = "The primary access key"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "The primary connection string"
  value       = azurerm_storage_account.this.primary_connection_string
  sensitive   = true
}
```

## Using Modules

### Local Module Reference

```hcl
# main.tf

module "storage" {
  source = "./modules/storage-account"

  name                = "stmyappprod"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  replication_type    = "GRS"
  enable_versioning   = true

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
    ip_rules       = ["203.0.113.0/24"]
  }

  tags = {
    Environment = "prod"
    Project     = "MyApp"
  }
}

# Access module outputs
output "storage_endpoint" {
  value = module.storage.primary_blob_endpoint
}
```

### Remote Module Sources

#### Terraform Registry

```hcl
module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.1.0"

  name                = "stmyapp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}
```

#### GitHub

```hcl
module "network" {
  source = "github.com/myorg/terraform-modules//modules/networking?ref=v1.0.0"

  # Module parameters
}
```

#### Private Git Repository

```hcl
module "security" {
  source = "git::https://github.com/myorg/terraform-modules.git//modules/security?ref=v2.1.0"

  # Module parameters
}
```

## Advanced Module Patterns

### Conditional Resources

```hcl
variable "create_private_endpoint" {
  description = "Whether to create a private endpoint"
  type        = bool
  default     = false
}

resource "azurerm_private_endpoint" "this" {
  count = var.create_private_endpoint ? 1 : 0

  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
}
```

### For_each with Modules

```hcl
variable "storage_accounts" {
  description = "Map of storage accounts to create"
  type = map(object({
    replication_type  = string
    enable_versioning = bool
  }))
}

module "storage_accounts" {
  source   = "./modules/storage-account"
  for_each = var.storage_accounts

  name                = each.key
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  replication_type    = each.value.replication_type
  enable_versioning   = each.value.enable_versioning

  tags = local.common_tags
}
```

### Module Composition

Create higher-level modules by composing smaller ones:

```hcl
# modules/web-app-stack/main.tf

module "storage" {
  source = "../storage-account"

  name                = "${var.name_prefix}st"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

module "app_insights" {
  source = "../app-insights"

  name                = "${var.name_prefix}-insights"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

module "app_service" {
  source = "../app-service"

  name                           = "${var.name_prefix}-app"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  app_insights_connection_string = module.app_insights.connection_string
  tags                           = var.tags
}
```

## Module Best Practices

### Versioning

Always version your modules:

```hcl
module "network" {
  source  = "git::https://github.com/myorg/terraform-modules.git//modules/network?ref=v1.2.0"
  
  # Pinning to a specific version ensures reproducibility
}
```

### Documentation

Create a README.md for each module:

```markdown
# Storage Account Module

Creates an Azure Storage Account with secure defaults.

## Usage

​```hcl
module "storage" {
  source = "./modules/storage-account"

  name                = "stmyapp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}
​```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Storage account name | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| id | Storage account ID |
| name | Storage account name |
```

### Testing Modules

Use Terratest or terraform test:

```hcl
# tests/storage_test.tftest.hcl

run "create_storage_account" {
  command = plan

  variables {
    name                = "sttest123"
    resource_group_name = "rg-test"
    location            = "eastus"
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "TLS version must be 1.2"
  }
}
```

## Summary

!!! abstract "Module Checklist"

    - [ ] Follow standard file structure
    - [ ] Define clear input variables with validation
    - [ ] Expose useful outputs
    - [ ] Version and tag releases
    - [ ] Document with README
    - [ ] Test modules before publishing
    - [ ] Use semantic versioning

## Next Steps

- [Best Practices](best-practices.md) - More patterns and antipatterns
- [Examples](examples.md) - Complete working examples
