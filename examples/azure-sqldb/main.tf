#
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: Apache-2.0
#

# Azure SQL DB with VA Example — Main Configuration

#------------------------------------------------------------------------------
# Step 1: Configure Vulnerability Assessment (VA) on the Azure SQL Server
#         This creates the Key Vault, Function App, and firewall rules.
#         After apply, invoke the function manually to create the monitoring
#         user in each database (see the function_invoke_command output).
#------------------------------------------------------------------------------
module "azure_sqldb_va_config" {
  source = "../../modules/azure-sqldb"

  name_prefix         = var.name_prefix
  resource_group_name = var.resource_group_name
  location            = var.location

  #----------------------------------------
  # Network Configuration
  #----------------------------------------
  vnet_name                      = var.vnet_name
  function_subnet_address_prefix = var.function_subnet_address_prefix

  #----------------------------------------
  # Database Connection
  #----------------------------------------
  db_host = var.db_host
  db_port = var.db_port

  #----------------------------------------
  # Entra ID — admin identity (sets up monitoring user)
  #----------------------------------------
  tenant_id           = var.tenant_id
  admin_client_id     = var.admin_client_id
  admin_client_secret = var.admin_client_secret

  #----------------------------------------
  # Entra ID — monitoring identity (used by Guardium)
  #----------------------------------------
  monitor_client_id             = var.monitor_client_id
  monitor_client_secret         = var.monitor_client_secret
  monitor_app_registration_name = var.monitor_app_registration_name

  #----------------------------------------
  # Firewall Configuration
  #----------------------------------------
  sql_server_name           = var.sql_server_name
  enable_public_access      = var.enable_public_access
  guardium_hostname         = var.guardium_hostname
  additional_firewall_rules = var.additional_firewall_rules

  #----------------------------------------
  # General
  #----------------------------------------
  tags = var.tags
}

#------------------------------------------------------------------------------
# Step 2: Build the Guardium datasource payload from the template and register
#         the Azure SQL DB datasource in Guardium Data Protection (GDP).
#------------------------------------------------------------------------------
locals {
  azure_sqldb_config = templatefile("${path.module}/templates/azureSQLDBVaConf.tpl", {
    datasource_name       = var.datasource_name
    datasource_hostname   = var.db_host
    datasource_port       = var.db_port
    application           = var.application
    datasource_description = var.datasource_description
    severity_level        = var.severity_level
    monitor_client_id     = var.monitor_client_id
    monitor_client_secret = var.monitor_client_secret
  })
  azure_sqldb_config_json_encoded = jsonencode(jsondecode(local.azure_sqldb_config))
}

module "azure_sqldb_gdp_connection" {
  count  = var.enable_vulnerability_assessment ? 1 : 0
  source = "IBM/gdp/guardium//modules/connect-datasource-to-va"

  datasource_payload = local.azure_sqldb_config_json_encoded

  client_secret = var.client_secret
  client_id     = var.client_id
  gdp_password  = var.gdp_password
  gdp_server    = var.gdp_server
  gdp_username  = var.gdp_username
  gdp_port      = var.gdp_port

  #----------------------------------------
  # Vulnerability Assessment Configuration
  #----------------------------------------
  datasource_name                 = var.datasource_name
  enable_vulnerability_assessment = var.enable_vulnerability_assessment
  assessment_schedule             = var.assessment_schedule
  assessment_day                  = var.assessment_day
  assessment_time                 = var.assessment_time

  #----------------------------------------
  # Notification Configuration
  #----------------------------------------
  enable_notifications  = var.enable_notifications
  notification_emails   = var.notification_emails
  notification_severity = var.notification_severity

  tags = var.tags

  depends_on = [module.azure_sqldb_va_config]
}
