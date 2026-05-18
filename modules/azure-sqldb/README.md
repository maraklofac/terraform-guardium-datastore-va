# Azure SQL Database VA Configuration Module

This Terraform module configures Vulnerability Assessment (VA) for Azure SQL Database using **Entra ID (Azure Active Directory) Service Principal** authentication — the same authentication method documented in the IBM Guardium setup scripts for Azure SQL DB.

## Overview

The module creates the following Azure infrastructure:

| Resource | Purpose |
|---|---|
| Azure Key Vault | Stores admin and monitoring App Registration credentials |
| Azure Function App (Python 3.9) | Runs T-SQL to create the `gdmmonitor` role and monitoring user across all databases |
| Azure Storage Account | Required by Azure Functions runtime |
| App Service Plan (EP1) | Elastic Premium tier — supports VNet integration |
| VNet Subnet | Delegated subnet for Function App egress |
| SQL Server Firewall Rules | Optional — allows Guardium and Azure services to reach the public endpoint |

## Authentication Model

This module uses **two App Registrations**:

| App Registration | Used by | Purpose |
|---|---|---|
| **Admin** | Azure Function (setup only) | Must be the Entra ID administrator on the SQL Server; creates the monitoring user |
| **Monitoring** | Guardium (ongoing) | Has only `gdmmonitor` role permissions (read-only VA access) |

Guardium connects using:
- **Username**: monitoring App Registration **Client ID**
- **Password**: monitoring App Registration **Client Secret**
- **Connection Properties**: `authentication=ActiveDirectoryServicePrincipal;hostNameInCertificate=*.database.windows.net;loginTimeout=60;`

## Prerequisites

1. Azure SQL Server already deployed and accessible
2. **Admin App Registration** created in Entra ID and set as the Microsoft Entra ID administrator on the SQL Server
   - Azure Portal → SQL Server → Microsoft Entra ID → Set admin
3. **Monitoring App Registration** created in Entra ID (no special SQL permissions needed — the Function grants them)
4. Certificates imported into Guardium keystore — see [gdmmonitor-AzureSQLDB.sql](../../tmp/gdmmonitor-AzureSQLDB.sql)
5. Azure CLI authenticated and `terraform >= 1.0` installed
6. A VNet with a free subnet CIDR block for the Function App

## Usage

```hcl
module "azure_sqldb_va_config" {
  source = "../../modules/azure-sqldb"

  name_prefix         = "my-sqldb"
  resource_group_name = "my-rg"
  location            = "canadacentral"

  # Network
  vnet_name                      = "my-vnet"
  function_subnet_address_prefix = "10.0.3.0/24"

  # SQL Server endpoint
  db_host = "myserver.database.windows.net"
  db_port = 1433

  # Admin App Registration (Entra ID admin on the SQL Server)
  tenant_id           = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  admin_client_id     = var.admin_client_id
  admin_client_secret = var.admin_client_secret

  # Monitoring App Registration (used by Guardium)
  monitor_client_id             = var.monitor_client_id
  monitor_client_secret         = var.monitor_client_secret
  monitor_app_registration_name = "app-reg-gdmmonitor"

  # Optional: allow Guardium to reach the SQL Server over public endpoint
  enable_public_access = true
  sql_server_name      = "myserver"
  guardium_hostname    = "guardium.example.com"
}
```

## What the Azure Function Does

After deployment, invoke the `SQLDBVAConfig` function (see `function_invoke_command` output). It will:

1. Retrieve all credentials from Key Vault using the Function's managed identity
2. Authenticate to Azure SQL DB using the admin App Registration (Entra ID service principal)
3. List all user databases on the server
4. For **each database** (including `master`):
   - Create `[gdmmonitor]` database role (non-master databases only)
   - Grant VA read permissions to the role (see permissions table below)
   - Create user `[<monitor_app_registration_name>] FROM EXTERNAL PROVIDER`
   - Add the user to the `gdmmonitor` role (non-master databases only)

### Permissions Granted

| Permission | Scope |
|---|---|
| `SELECT` | `sys.all_objects` |
| `SELECT` | `sys.database_firewall_rules` |
| `SELECT` | `sys.database_permissions` |
| `SELECT` | `sys.database_principals` |
| `SELECT` | `sys.database_role_members` |
| `SELECT` | `sys.schemas` |
| `SELECT` | `sys.sql_modules` |
| `SELECT` | `sys.symmetric_keys` |
| `VIEW DATABASE STATE` | database |
| `VIEW DEFINITION` | database |

## Invoking the Function

After `terraform apply` completes, wait 5-10 minutes for the function to become active, then:

```bash
# Get the function key
key=$(az functionapp keys list \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --query "functionKeys.default" -o tsv)

# Invoke the function
curl -X POST "https://<function-app-name>.azurewebsites.net/api/SQLDBVAConfig?code=$key" \
  -H "Content-Type: application/json" -d '{}'
```

The `function_invoke_command` Terraform output contains the exact command pre-populated with your resource names.

The function is **idempotent** — it checks for existing roles/users before creating them and can be safely re-run.

## Alternative: PowerShell Script

If you prefer not to use the Azure Function, the PowerShell script [gdmmonitor-AzureSQLDB-entra.txt](../../tmp/gdmmonitor-AzureSQLDB-entra.txt) performs the same database setup using interactive Entra ID authentication (browser popup). It can be run from Azure Cloud Shell or a local Windows machine.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name_prefix` | Prefix for all resource names | `string` | — | yes |
| `resource_group_name` | Azure resource group | `string` | — | yes |
| `location` | Azure region | `string` | — | yes |
| `vnet_name` | Existing VNet name | `string` | — | yes |
| `function_subnet_address_prefix` | CIDR for Function App subnet | `string` | — | yes |
| `db_host` | Azure SQL Server FQDN | `string` | — | yes |
| `db_port` | SQL Server port | `number` | `1433` | no |
| `tenant_id` | Entra ID Tenant ID | `string` | — | yes |
| `admin_client_id` | Admin App Registration Client ID | `string` | — | yes |
| `admin_client_secret` | Admin App Registration Client Secret | `string` | — | yes |
| `monitor_client_id` | Monitoring App Registration Client ID | `string` | — | yes |
| `monitor_client_secret` | Monitoring App Registration Client Secret | `string` | — | yes |
| `monitor_app_registration_name` | Display name of monitoring App Registration | `string` | — | yes |
| `sql_server_name` | Azure SQL Server resource name (firewall rules) | `string` | `""` | no |
| `enable_public_access` | Add firewall rules for public endpoint | `bool` | `false` | no |
| `guardium_hostname` | Guardium hostname (resolved to IP for firewall) | `string` | `""` | no |
| `additional_firewall_rules` | Extra firewall rules | `map(object)` | `{}` | no |
| `tags` | Resource tags | `map(string)` | `{…}` | no |

## Outputs

| Name | Description |
|---|---|
| `function_app_name` | Name of the Azure Function App |
| `function_app_default_hostname` | HTTPS endpoint of the Function App |
| `key_vault_name` | Name of the Key Vault |
| `monitor_client_id` | Monitoring App Registration Client ID (Guardium username) |
| `monitor_app_registration_name` | Display name used in CREATE USER statements |
| `va_config_completed` | Status message |
| `guardium_resolved_ip` | Resolved Guardium IP (when public access enabled) |
| `firewall_rules_created` | Firewall rule creation status |
| `function_invoke_command` | Ready-to-run curl command to invoke the function |
