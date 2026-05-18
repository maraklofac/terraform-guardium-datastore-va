#
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: Apache-2.0
#

# Azure SQL DB with VA Example — Outputs

output "function_app_name" {
  description = "Name of the deployed Azure Function App"
  value       = module.azure_sqldb_va_config.function_app_name
}

output "function_app_hostname" {
  description = "Default hostname of the Azure Function App"
  value       = module.azure_sqldb_va_config.function_app_default_hostname
}

output "key_vault_name" {
  description = "Name of the Key Vault that stores credentials"
  value       = module.azure_sqldb_va_config.key_vault_name
}

output "monitor_app_registration_name" {
  description = "Display name of the monitoring App Registration created in every database"
  value       = module.azure_sqldb_va_config.monitor_app_registration_name
}

output "va_config_status" {
  description = "Status of the VA configuration deployment"
  value       = module.azure_sqldb_va_config.va_config_completed
}

output "firewall_status" {
  description = "Status of firewall rule creation"
  value       = module.azure_sqldb_va_config.firewall_rules_created
}

output "function_invoke_command" {
  description = "Command to invoke the VA configuration function after deployment"
  value       = module.azure_sqldb_va_config.function_invoke_command
}
