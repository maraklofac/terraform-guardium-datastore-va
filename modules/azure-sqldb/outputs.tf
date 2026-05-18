#
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: Apache-2.0
#

# Azure SQL DB VA Config Module — Outputs

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.va_config_function.name
}

output "function_app_id" {
  description = "Resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.va_config_function.id
}

output "function_app_default_hostname" {
  description = "Default HTTPS hostname of the Azure Function App"
  value       = azurerm_linux_function_app.va_config_function.default_hostname
}

output "key_vault_name" {
  description = "Name of the Key Vault storing all credentials"
  value       = azurerm_key_vault.sqldb_credentials.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.sqldb_credentials.id
}

output "monitor_client_id" {
  description = "Client ID of the monitoring App Registration — use this as the Guardium datasource username"
  value       = var.monitor_client_id
  sensitive   = true
}

output "monitor_app_registration_name" {
  description = "Display name of the monitoring App Registration created in each database"
  value       = var.monitor_app_registration_name
}

output "va_config_completed" {
  description = "Indicates that the VA configuration infrastructure has been deployed"
  value       = "Azure Function infrastructure deployed. Invoke SQLDBVAConfig function to complete database user setup."
}

output "guardium_resolved_ip" {
  description = "IP address of the Guardium server added to the SQL Server firewall (only when enable_public_access = true)"
  value       = var.enable_public_access ? data.dns_a_record_set.guardium_ip[0].addrs[0] : "N/A — public access disabled"
}

output "firewall_rules_created" {
  description = "Status of SQL Server firewall rule creation"
  value       = var.enable_public_access ? "Firewall rules created for Guardium IP: ${data.dns_a_record_set.guardium_ip[0].addrs[0]}" : "Public access disabled — Guardium must connect via Private Link / VPN"
}

output "function_invoke_command" {
  description = "Azure CLI command to manually invoke the VA configuration function"
  value       = <<-EOT
    key=$(az functionapp keys list \
      --resource-group ${var.resource_group_name} \
      --name ${azurerm_linux_function_app.va_config_function.name} \
      --query "functionKeys.default" -o tsv)
    curl -X POST "https://${azurerm_linux_function_app.va_config_function.default_hostname}/api/SQLDBVAConfig?code=$key" \
      -H "Content-Type: application/json" -d '{}'
  EOT
}
