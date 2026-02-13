# Terraform Examples

Real-world examples of infrastructure deployments using Terraform. Each example includes complete, production-ready code.

## Web Application Architecture

### Azure Web App with SQL Database

```hcl
# main.tf - Full-stack web application

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "sql_admin_username" {
  description = "SQL Server admin username"
  type        = string
  default     = "sqladmin"
}

# Random suffix for unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Locals
locals {
  name_prefix = "webapp-${var.environment}"
  unique_suffix = random_string.suffix.result
  
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "WebApp"
  }

  sku_map = {
    dev     = { app = "B1", sql = "Basic" }
    staging = { app = "S1", sql = "S0" }
    prod    = { app = "P1v3", sql = "S1" }
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Random password for SQL
resource "random_password" "sql_admin" {
  length           = 32
  special          = true
  override_special = "!@#$%&*"
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.name_prefix}-${local.unique_suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 90
  purge_protection_enabled   = var.environment == "prod"
  enable_rbac_authorization  = true

  tags = local.common_tags
}

data "azurerm_client_config" "current" {}

# Store SQL password in Key Vault
resource "azurerm_key_vault_secret" "sql_password" {
  name         = "sql-admin-password"
  value        = random_password.sql_admin.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [
    azurerm_role_assignment.kv_admin
  ]
}

# Give current user Key Vault admin
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "appi-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = local.common_tags
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  name                = "asp-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = local.sku_map[var.environment].app

  tags = local.common_tags
}

# Web App
resource "azurerm_linux_web_app" "main" {
  name                = "app-${local.name_prefix}-${local.unique_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on        = var.environment != "dev"
    ftps_state       = "Disabled"
    minimum_tls_version = "1.2"

    application_stack {
      dotnet_version = "8.0"
    }
  }

  app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
  }

  connection_string {
    name  = "DefaultConnection"
    type  = "SQLAzure"
    value = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.main.name};Authentication=Active Directory Default;"
  }

  tags = local.common_tags
}

# SQL Server
resource "azurerm_mssql_server" "main" {
  name                         = "sql-${local.name_prefix}-${local.unique_suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"

  azuread_administrator {
    login_username = "AzureAD Admin"
    object_id      = data.azurerm_client_config.current.object_id
  }

  tags = local.common_tags
}

# SQL Database
resource "azurerm_mssql_database" "main" {
  name      = "sqldb-${local.name_prefix}"
  server_id = azurerm_mssql_server.main.id
  sku_name  = local.sku_map[var.environment].sql

  short_term_retention_policy {
    retention_days = 7
  }

  tags = local.common_tags
}

# Allow Azure services to access SQL
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Outputs
output "web_app_url" {
  description = "The URL of the web application"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "sql_server_fqdn" {
  description = "The FQDN of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}
```

## Kubernetes Cluster

### Azure Kubernetes Service (AKS)

```hcl
# aks.tf - Production-ready AKS cluster

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "Number of nodes in the default pool"
  type        = number
  default     = 3
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-${local.name_prefix}"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = "Standard_D4s_v3"
    vnet_subnet_id      = azurerm_subnet.aks.id
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    max_pods            = 110
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 5

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
    admin_group_object_ids = var.aks_admin_group_ids
  }

  auto_scaler_profile {
    balance_similar_node_groups      = true
    max_graceful_termination_sec     = 600
    scale_down_delay_after_add       = "10m"
    scale_down_unneeded              = "10m"
    scale_down_utilization_threshold = 0.5
  }

  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [0, 1, 2, 3, 4]
    }
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count
    ]
  }
}

# User Node Pool for applications
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D8s_v3"
  os_disk_size_gb       = 256
  vnet_subnet_id        = azurerm_subnet.aks.id
  max_pods              = 110
  enable_auto_scaling   = true
  min_count             = 2
  max_count             = 20
  mode                  = "User"

  node_labels = {
    "workload" = "applications"
  }

  node_taints = []

  tags = local.common_tags
}

# Container Registry
resource "azurerm_container_registry" "main" {
  name                = "acr${replace(local.name_prefix, "-", "")}${local.unique_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.environment == "prod" ? "Premium" : "Standard"
  admin_enabled       = false

  dynamic "georeplications" {
    for_each = var.environment == "prod" ? ["westus2"] : []
    content {
      location                = georeplications.value
      zone_redundancy_enabled = true
    }
  }

  tags = local.common_tags
}

# Grant AKS access to ACR
resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}
```

## Networking

### Hub-and-Spoke Network Topology

```hcl
# networking.tf - Hub and spoke network

variable "hub_vnet_cidr" {
  default = "10.0.0.0/16"
}

variable "spoke_vnets" {
  type = map(object({
    cidr         = string
    subnet_count = number
  }))
  default = {
    "dev" = {
      cidr         = "10.1.0.0/16"
      subnet_count = 3
    }
    "prod" = {
      cidr         = "10.2.0.0/16"
      subnet_count = 4
    }
  }
}

# Hub Virtual Network
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.hub_vnet_cidr]

  tags = local.common_tags
}

# Hub Subnets
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_vnet_cidr, 8, 0)]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_vnet_cidr, 8, 1)]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_vnet_cidr, 8, 2)]
}

# Spoke Virtual Networks
resource "azurerm_virtual_network" "spoke" {
  for_each = var.spoke_vnets

  name                = "vnet-spoke-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [each.value.cidr]

  tags = merge(local.common_tags, {
    Spoke = each.key
  })
}

# Spoke Subnets
resource "azurerm_subnet" "spoke_subnets" {
  for_each = {
    for pair in flatten([
      for spoke_key, spoke in var.spoke_vnets : [
        for i in range(spoke.subnet_count) : {
          key        = "${spoke_key}-${i}"
          spoke_key  = spoke_key
          cidr       = spoke.cidr
          index      = i
        }
      ]
    ]) : pair.key => pair
  }

  name                 = "subnet-${each.value.index}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke[each.value.spoke_key].name
  address_prefixes     = [cidrsubnet(each.value.cidr, 8, each.value.index)]
}

# VNet Peering: Hub to Spokes
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spoke_vnets

  name                         = "peer-hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

# VNet Peering: Spokes to Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = var.spoke_vnets

  name                         = "peer-${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}

# Azure Firewall
resource "azurerm_public_ip" "firewall" {
  name                = "pip-firewall"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

resource "azurerm_firewall" "main" {
  name                = "fw-hub"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = local.common_tags
}

output "hub_vnet_id" {
  value = azurerm_virtual_network.hub.id
}

output "firewall_private_ip" {
  value = azurerm_firewall.main.ip_configuration[0].private_ip_address
}
```

## Multi-Region Deployment

### Cosmos DB with Global Distribution

```hcl
# cosmos.tf - Globally distributed Cosmos DB

variable "cosmos_regions" {
  description = "Regions for Cosmos DB replication"
  type        = list(string)
  default     = ["eastus", "westeurope", "southeastasia"]
}

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${local.name_prefix}-${local.unique_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  automatic_failover_enabled = true
  
  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  dynamic "geo_location" {
    for_each = var.cosmos_regions
    content {
      location          = geo_location.value
      failover_priority = index(var.cosmos_regions, geo_location.value)
      zone_redundant    = var.environment == "prod"
    }
  }

  backup {
    type                = "Continuous"
    tier                = var.environment == "prod" ? "Continuous30Days" : "Continuous7Days"
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = local.common_tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "appdb"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "items" {
  name                = "items"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_paths = ["/partitionKey"]

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }

  default_ttl = -1
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_read_endpoints" {
  value = azurerm_cosmosdb_account.main.read_endpoints
}
```

## Next Steps

- [Getting Started](getting-started.md) - Start from the basics
- [Modules](modules.md) - Create reusable components
- [Best Practices](best-practices.md) - Follow production patterns
