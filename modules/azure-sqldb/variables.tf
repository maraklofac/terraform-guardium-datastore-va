#
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: Apache-2.0
#

# Azure SQL DB VA Config Module Variables

# ─── Database connection ────────────────────────────────────────────────────

variable "db_host" {
  description = "Fully-qualified hostname of the Azure SQL Server (e.g. myserver.database.windows.net)"
  type        = string
}

variable "db_port" {
  description = "Port for the Azure SQL Server"
  type        = number
  default     = 1433
}

# ─── Entra ID — admin identity (used to create the monitoring user) ──────────
# This App Registration (or Managed Identity equivalent) must be configured as
# the Microsoft Entra ID administrator on the SQL Server so it can execute
# CREATE USER ... FROM EXTERNAL PROVIDER across all databases.

variable "tenant_id" {
  description = "Azure Active Directory (Entra ID) Tenant ID"
  type        = string
}

variable "admin_client_id" {
  description = "Client ID of the App Registration that has Entra ID admin rights on the SQL Server (used by the Function to create the monitoring user)"
  type        = string
  sensitive   = true
}

variable "admin_client_secret" {
  description = "Client Secret of the admin App Registration"
  type        = string
  sensitive   = true
}

# ─── Entra ID — monitoring identity (used by Guardium) ───────────────────────
# This App Registration will be created as a user in every database with the
# gdmmonitor role.  Its Client ID and Client Secret are what Guardium uses as
# username and password when connecting with ActiveDirectoryServicePrincipal.

variable "monitor_client_id" {
  description = "Client ID of the monitoring App Registration (used as the Guardium datasource username)"
  type        = string
  sensitive   = true
}

variable "monitor_client_secret" {
  description = "Client Secret of the monitoring App Registration (used as the Guardium datasource password)"
  type        = string
  sensitive   = true
}

variable "monitor_app_registration_name" {
  description = "Display name of the monitoring App Registration in Entra ID — used in 'CREATE USER [name] FROM EXTERNAL PROVIDER'"
  type        = string
}

# ─── Azure infrastructure ────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names created by this module"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose = "guardium-va-config"
    Owner   = "your-email@example.com"
  }
}

# ─── Networking ──────────────────────────────────────────────────────────────

variable "vnet_name" {
  description = "Name of the existing VNet to which the Function App will be integrated"
  type        = string
}

variable "function_subnet_address_prefix" {
  description = "CIDR block for the new subnet that will be delegated to the Function App (e.g. 10.0.3.0/24)"
  type        = string
}

# ─── Firewall / public access ────────────────────────────────────────────────

variable "sql_server_name" {
  description = "Name of the Azure SQL Server resource (used to create firewall rules). Required when enable_public_access = true"
  type        = string
  default     = ""
}

variable "enable_public_access" {
  description = "Add firewall rules to allow Guardium and Azure services to reach the SQL Server over the public endpoint. Set to false for production environments that use Private Link / VPN."
  type        = bool
  default     = false
}

variable "guardium_hostname" {
  description = "Hostname or IP of the Guardium server (resolved to IP for the firewall rule). Required when enable_public_access = true."
  type        = string
  default     = ""
}

variable "additional_firewall_rules" {
  description = "Extra SQL Server firewall rules. Map of rule name → object with start_ip and end_ip."
  type = map(object({
    start_ip = string
    end_ip   = string
  }))
  default = {}
}
