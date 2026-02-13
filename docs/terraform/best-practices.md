# Terraform Best Practices

Writing maintainable, secure, and scalable Terraform code requires following established best practices. This guide covers essential patterns for production-ready infrastructure.

## Code Organization

### Project Structure

Organize your Terraform projects consistently:

```
📁 infrastructure/
  📁 modules/           # Reusable modules
  📁 environments/
    📁 dev/
      📄 main.tf
      📄 terraform.tfvars
      📄 backend.tf
    📁 staging/
    📁 prod/
  📄 README.md
```

### File Naming Conventions

```
📄 main.tf           # Primary resource definitions
📄 variables.tf      # Input variable declarations
📄 outputs.tf        # Output value definitions
📄 providers.tf      # Provider configurations
📄 versions.tf       # Version constraints
📄 locals.tf         # Local value definitions
📄 data.tf           # Data source definitions
📄 backend.tf        # Backend configuration
```

### Naming Standards

```hcl
# ✅ Good: Descriptive, consistent naming
resource "azurerm_storage_account" "application_logs" {
  name = "stapplogsprod"
  # ...
}

resource "azurerm_virtual_network" "main" {
  name = "vnet-app-prod-eastus"
  # ...
}

# ❌ Bad: Unclear naming
resource "azurerm_storage_account" "sa1" {
  name = "storage1"
  # ...
}
```

## Variable Management

### Use Descriptive Variables

```hcl
variable "app_service_plan_sku" {
  description = "The SKU for the App Service Plan (e.g., B1, S1, P1v2)"
  type        = string
  default     = "B1"

  validation {
    condition = contains([
      "F1", "D1", "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P1v3", "P2v3", "P3v3"
    ], var.app_service_plan_sku)
    error_message = "Invalid App Service Plan SKU."
  }
}
```

### Use Variable Validation

```hcl
variable "environment" {
  description = "The deployment environment"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "cidr_block" {
  description = "The CIDR block for the VNet"
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}
```

### Use Type Constraints

```hcl
variable "network_config" {
  description = "Network configuration"
  type = object({
    vnet_cidr     = string
    subnet_count  = number
    enable_nat    = bool
    dns_servers   = optional(list(string), [])
    tags          = optional(map(string), {})
  })
}
```

## Locals for Computed Values

```hcl
locals {
  # Environment-specific settings
  environment_config = {
    dev = {
      sku        = "B1"
      redundancy = "LRS"
      replicas   = 1
    }
    staging = {
      sku        = "S1"
      redundancy = "ZRS"
      replicas   = 2
    }
    prod = {
      sku        = "P1v3"
      redundancy = "GRS"
      replicas   = 3
    }
  }

  # Current environment settings
  config = local.environment_config[var.environment]

  # Common tags
  common_tags = {
    Environment  = var.environment
    Project      = var.project_name
    ManagedBy    = "Terraform"
    CostCenter   = var.cost_center
    DeployedAt   = timestamp()
  }

  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}"
}
```

## Security Best Practices

### Never Expose Secrets

```hcl
# ✅ Good: Use Key Vault for secrets
data "azurerm_key_vault_secret" "db_password" {
  name         = "database-password"
  key_vault_id = data.azurerm_key_vault.main.id
}

resource "azurerm_mssql_server" "main" {
  name                         = "${local.name_prefix}-sql"
  administrator_login          = var.sql_admin_username
  administrator_login_password = data.azurerm_key_vault_secret.db_password.value
  # ...
}

# ❌ Bad: Secrets in variables or state
variable "db_password" {
  description = "Database password"
  type        = string
  # No sensitive = true, exposed in logs
}
```

### Mark Sensitive Values

```hcl
variable "api_key" {
  description = "API key for external service"
  type        = string
  sensitive   = true
}

output "connection_string" {
  description = "Database connection string"
  value       = azurerm_mssql_database.main.connection_string
  sensitive   = true
}
```

### Secure by Default

```hcl
resource "azurerm_storage_account" "main" {
  name                     = "${local.name_prefix}st"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = local.config.redundancy

  # Security defaults
  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false  # Use Azure AD auth
  
  # Network rules
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  # Encryption
  infrastructure_encryption_enabled = true

  tags = local.common_tags
}
```

## State Management

### Use Remote Backend

```hcl
# backend.tf

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
    use_azuread_auth     = true  # Use Azure AD instead of access keys
  }
}
```

### State Locking

Always enable state locking to prevent concurrent modifications:

```hcl
# Azure backend automatically uses blob leases for locking
# AWS S3 backend needs DynamoDB for locking
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### Environment Isolation

Use separate state files per environment:

```
📁 environments/
  📁 dev/
    📄 backend.tf    # key = "dev.terraform.tfstate"
  📁 prod/
    📄 backend.tf    # key = "prod.terraform.tfstate"
```

## Resource Dependencies

### Implicit Dependencies (Preferred)

```hcl
# Terraform automatically creates dependency
resource "azurerm_app_service" "main" {
  name                = "${local.name_prefix}-app"
  app_service_plan_id = azurerm_app_service_plan.main.id  # Implicit dependency
  # ...
}
```

### Explicit Dependencies

```hcl
# Use depends_on when implicit isn't possible
resource "azurerm_role_assignment" "app_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_app_service.main.identity[0].principal_id

  depends_on = [
    azurerm_app_service.main  # Ensure app exists first
  ]
}
```

## Lifecycle Management

### Prevent Accidental Destruction

```hcl
resource "azurerm_sql_database" "main" {
  name                = "${local.name_prefix}-db"
  resource_group_name = azurerm_resource_group.main.name
  # ...

  lifecycle {
    prevent_destroy = true  # Terraform will error if destroy is attempted
  }
}
```

### Ignore External Changes

```hcl
resource "azurerm_app_service" "main" {
  name = "${local.name_prefix}-app"
  # ...

  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],  # Set by deployment
      site_config[0].scm_type,                    # Set by Azure DevOps
    ]
  }
}
```

### Create Before Destroy

```hcl
resource "azurerm_public_ip" "main" {
  name                = "${local.name_prefix}-pip"
  allocation_method   = "Static"
  # ...

  lifecycle {
    create_before_destroy = true  # Create new before destroying old
  }
}
```

## Error Prevention

### Use Terraform Fmt

```bash
# Format all files
terraform fmt -recursive

# Check formatting (CI/CD)
terraform fmt -check -recursive
```

### Use Terraform Validate

```bash
terraform validate
```

### Use Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.86.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_docs
```

## Documentation

### Generate Documentation

Use terraform-docs:

```bash
terraform-docs markdown table . > README.md
```

### Inline Comments

```hcl
# Security Group for web tier
# Allows HTTP/HTTPS from load balancer only
resource "azurerm_network_security_group" "web" {
  name                = "${local.name_prefix}-web-nsg"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Allow HTTPS from load balancer
  security_rule {
    name                       = "allow-https-from-lb"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}
```

## Testing

### Terraform Test (Built-in)

```hcl
# tests/main.tftest.hcl

variables {
  environment = "dev"
  location    = "eastus"
}

run "verify_storage_security" {
  command = plan

  assert {
    condition     = azurerm_storage_account.main.min_tls_version == "TLS1_2"
    error_message = "Storage account must use TLS 1.2"
  }

  assert {
    condition     = azurerm_storage_account.main.enable_https_traffic_only == true
    error_message = "Storage account must enforce HTTPS"
  }
}
```

## Summary Checklist

!!! abstract "Best Practices Checklist"

    - [ ] Use consistent file and resource naming
    - [ ] Validate all input variables
    - [ ] Use locals for computed values
    - [ ] Never expose secrets in state or logs
    - [ ] Use remote backend with locking
    - [ ] Separate state per environment
    - [ ] Use lifecycle rules appropriately
    - [ ] Format and validate before commit
    - [ ] Document modules and resources
    - [ ] Test infrastructure code

## Next Steps

- [Examples](examples.md) - See these practices in action
- [Modules](modules.md) - Create reusable modules
