#
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: Apache-2.0
#

# Azure SQL DB with VA Example — Variables

#------------------------------------------------------------------------------
# General Configuration
#------------------------------------------------------------------------------

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "canadacentral"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "azure-sqldb-monitoring"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
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

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

variable "vnet_name" {
  description = "Name of the existing VNet where the SQL Server is deployed"
  type        = string
}

variable "function_subnet_address_prefix" {
  description = "CIDR block for the Function App subnet (must not overlap existing subnets)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "enable_public_access" {
  description = "Create firewall rules for public endpoint access. Set to false in production (use Private Link / VPN instead)."
  type        = bool
  default     = true
}

variable "guardium_hostname" {
  description = "Hostname or IP of the Guardium server (resolved to IP for firewall rule)"
  type        = string
  default     = ""
}

variable "additional_firewall_rules" {
  description = "Additional SQL Server firewall rules (map of rule name → start_ip + end_ip)"
  type = map(object({
    start_ip = string
    end_ip   = string
  }))
  default = {}
}

#------------------------------------------------------------------------------
# Azure SQL Server Configuration
#------------------------------------------------------------------------------

variable "sql_server_name" {
  description = "Name of the Azure SQL Server resource (used to create firewall rules)"
  type        = string
}

variable "db_host" {
  description = "Fully-qualified hostname of the Azure SQL Server (e.g. myserver.database.windows.net)"
  type        = string
}

variable "db_port" {
  description = "Port for the Azure SQL Server"
  type        = number
  default     = 1433
}

#------------------------------------------------------------------------------
# Entra ID — Admin App Registration
# This identity must be set as the Microsoft Entra ID administrator on the
# SQL Server so the Function can run CREATE USER ... FROM EXTERNAL PROVIDER.
#------------------------------------------------------------------------------

variable "tenant_id" {
  description = "Azure Entra ID Tenant ID"
  type        = string
}

variable "admin_client_id" {
  description = "Client ID of the App Registration that has Entra ID admin rights on the SQL Server"
  type        = string
  sensitive   = true
}

variable "admin_client_secret" {
  description = "Client Secret of the admin App Registration"
  type        = string
  sensitive   = true
}

#------------------------------------------------------------------------------
# Entra ID — Monitoring App Registration (used by Guardium)
# Guardium connects using Client ID as username and Client Secret as password
# with authentication=ActiveDirectoryServicePrincipal.
#------------------------------------------------------------------------------

variable "monitor_client_id" {
  description = "Client ID of the monitoring App Registration (Guardium username)"
  type        = string
  sensitive   = true
}

variable "monitor_client_secret" {
  description = "Client Secret of the monitoring App Registration (Guardium password)"
  type        = string
  sensitive   = true
}

variable "monitor_app_registration_name" {
  description = "Display name of the monitoring App Registration in Entra ID"
  type        = string
}

#------------------------------------------------------------------------------
# Guardium Data Protection (GDP) Connection Configuration
#------------------------------------------------------------------------------

variable "gdp_server" {
  description = "Hostname or IP address of the Guardium server"
  type        = string
}

variable "gdp_port" {
  description = "Port of the Guardium server"
  type        = string
  default     = "8443"
}

variable "gdp_username" {
  description = "Username for Guardium login"
  type        = string
}

variable "gdp_password" {
  description = "Password for Guardium login"
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Guardium OAuth client ID (output of grdapi register_oauth_client)"
  type        = string
  default     = "client1"
}

variable "client_secret" {
  description = "Guardium OAuth client secret"
  type        = string
  sensitive   = true
}

#------------------------------------------------------------------------------
# Guardium Datasource Registration
#------------------------------------------------------------------------------

variable "datasource_name" {
  description = "Unique name for the datasource in Guardium"
  type        = string
  default     = "azure-sqldb-va"
}

variable "datasource_description" {
  description = "Description of the datasource"
  type        = string
  default     = "Azure SQL DB data source onboarded via Terraform"
}

variable "application" {
  description = "Application type for the datasource"
  type        = string
  default     = "Security Assessment"
}

variable "severity_level" {
  description = "Severity classification (LOW, NONE, MED, HIGH)"
  type        = string
  default     = "MED"
}

#------------------------------------------------------------------------------
# Vulnerability Assessment Schedule
#------------------------------------------------------------------------------

variable "enable_vulnerability_assessment" {
  description = "Enable vulnerability assessment for this datasource"
  type        = bool
  default     = true
}

variable "assessment_schedule" {
  description = "Assessment frequency (daily, weekly, monthly)"
  type        = string
  default     = "weekly"
}

variable "assessment_day" {
  description = "Day to run the assessment (e.g. Monday, 1)"
  type        = string
  default     = "Monday"
}

variable "assessment_time" {
  description = "Time to run the assessment in 24-hour format (e.g. 02:00)"
  type        = string
  default     = "02:00"
}

#------------------------------------------------------------------------------
# Notification Configuration
#------------------------------------------------------------------------------

variable "enable_notifications" {
  description = "Enable email notifications for assessment results"
  type        = bool
  default     = true
}

variable "notification_emails" {
  description = "Email addresses to notify about assessment results"
  type        = list(string)
  default     = []
}

variable "notification_severity" {
  description = "Minimum severity for notifications (HIGH, MED, LOW, NONE)"
  type        = string
  default     = "HIGH"
}
