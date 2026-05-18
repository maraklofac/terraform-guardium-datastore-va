#
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: Apache-2.0
#

# Azure SQL DB VA Config Module — Main Configuration

locals {
  secret_name  = "${var.name_prefix}-azure-sqldb-va-credentials"
  # Key Vault: alphanumeric + dashes, 3-24 chars
  kv_name      = substr("${replace(var.name_prefix, "_", "-")}-sqldb-kv", 0, 24)
  # Storage Account: lowercase alphanumeric only, 3-24 chars
  storage_name = substr(replace(lower("${var.name_prefix}sqldbva"), "/[^a-z0-9]/", ""), 0, 24)
  zip_file     = "${path.module}/files/function.zip"
  zip_hash     = filesha256(local.zip_file)
}

# ─── DNS lookup for optional Guardium firewall rule ─────────────────────────

data "dns_a_record_set" "guardium_ip" {
  count = var.enable_public_access ? 1 : 0
  host  = var.guardium_hostname
}

# ─── Current Azure client context ───────────────────────────────────────────

data "azurerm_client_config" "current" {}

# ─── Key Vault (stores both admin and monitor credentials) ──────────────────

resource "azurerm_key_vault" "sqldb_credentials" {
  name                       = local.kv_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Access policy for the Terraform principal that provisions this module
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  tags = var.tags
}

# Store all credentials in a single JSON secret.
# The Azure Function reads this to:
#   - authenticate as the admin App Registration and create the monitoring user
# Guardium reads monitor_client_id / monitor_client_secret directly from
# the datasource payload (not from Key Vault at runtime).
resource "azurerm_key_vault_secret" "sqldb_credentials" {
  name = local.secret_name
  value = jsonencode({
    tenant_id                     = var.tenant_id
    admin_client_id               = var.admin_client_id
    admin_client_secret           = var.admin_client_secret
    monitor_client_id             = var.monitor_client_id
    monitor_client_secret         = var.monitor_client_secret
    monitor_app_registration_name = var.monitor_app_registration_name
    endpoint                      = var.db_host
    port                          = var.db_port
  })
  key_vault_id = azurerm_key_vault.sqldb_credentials.id

  depends_on = [azurerm_key_vault.sqldb_credentials]
}

# ─── Storage Account (required by Azure Functions) ───────────────────────────

resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.tags
}

# ─── App Service Plan (Elastic Premium — required for VNet integration) ──────

resource "azurerm_service_plan" "function_plan" {
  name                = "${var.name_prefix}-sqldb-va-plan"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "EP1"

  tags = var.tags
}

# ─── Azure Function App ───────────────────────────────────────────────────────

resource "azurerm_linux_function_app" "va_config_function" {
  name                       = "${var.name_prefix}-sqldb-va-func"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  service_plan_id            = azurerm_service_plan.function_plan.id
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key

  site_config {
    application_stack {
      python_version = "3.9"
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    "KEY_VAULT_NAME"           = azurerm_key_vault.sqldb_credentials.name
    "SECRET_NAME"              = local.secret_name
    "AZURE_SUBSCRIPTION_ID"    = data.azurerm_client_config.current.subscription_id
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ─── Subnet delegated to the Function App ────────────────────────────────────

resource "azurerm_subnet" "function_subnet" {
  name                 = "${var.name_prefix}-sqldb-function-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [var.function_subnet_address_prefix]

  delegation {
    name = "function-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

# ─── VNet integration for the Function App ───────────────────────────────────

resource "azurerm_app_service_virtual_network_swift_connection" "function_vnet_integration" {
  app_service_id = azurerm_linux_function_app.va_config_function.id
  subnet_id      = azurerm_subnet.function_subnet.id

  depends_on = [azurerm_linux_function_app.va_config_function]
}

# ─── Key Vault access policy for the Function App managed identity ───────────

resource "azurerm_key_vault_access_policy" "function_access" {
  key_vault_id = azurerm_key_vault.sqldb_credentials.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.va_config_function.identity[0].principal_id

  secret_permissions = ["Get", "List"]

  depends_on = [azurerm_linux_function_app.va_config_function]
}

# ─── Deploy function code ────────────────────────────────────────────────────

resource "null_resource" "deploy_function" {
  triggers = {
    function_code_hash = local.zip_hash
    function_app_id    = azurerm_linux_function_app.va_config_function.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      az functionapp deployment source config-zip \
        --resource-group ${var.resource_group_name} \
        --name ${azurerm_linux_function_app.va_config_function.name} \
        --src ${local.zip_file} \
        --build-remote true
    EOT
  }

  depends_on = [
    azurerm_linux_function_app.va_config_function,
    azurerm_key_vault_access_policy.function_access,
  ]
}

# Note: The Function must be invoked manually after the deployment completes
# (it may take 5-10 minutes for the function to appear in the Azure Portal).
#
# To invoke:
#   key=$(az functionapp keys list \
#     --resource-group <rg> --name <func-name> \
#     --query "functionKeys.default" -o tsv)
#   curl -X POST "https://<func-name>.azurewebsites.net/api/SQLDBVAConfig?code=$key" \
#     -H "Content-Type: application/json" -d '{}'

# ─── SQL Server firewall rules (optional — public access mode) ───────────────

resource "azurerm_mssql_firewall_rule" "guardium_access" {
  count            = var.enable_public_access ? 1 : 0
  name             = "AllowGuardiumServer"
  server_id        = data.azurerm_mssql_server.existing[0].id
  start_ip_address = data.dns_a_record_set.guardium_ip[0].addrs[0]
  end_ip_address   = data.dns_a_record_set.guardium_ip[0].addrs[0]
}

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  count            = var.enable_public_access ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = data.azurerm_mssql_server.existing[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "additional_rules" {
  for_each         = var.enable_public_access ? var.additional_firewall_rules : {}
  name             = each.key
  server_id        = data.azurerm_mssql_server.existing[0].id
  start_ip_address = each.value.start_ip
  end_ip_address   = each.value.end_ip
}

# Data source to look up the existing SQL Server (needed for firewall rule IDs)
data "azurerm_mssql_server" "existing" {
  count               = var.enable_public_access ? 1 : 0
  name                = var.sql_server_name
  resource_group_name = var.resource_group_name
}
