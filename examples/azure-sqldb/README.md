# Azure SQL DB with Vulnerability Assessment — Example

This example shows how to use the `azure-sqldb` module to configure IBM Guardium Data Protection (GDP) Vulnerability Assessment for an existing Azure SQL Database using Entra ID (Azure Active Directory) Service Principal authentication.

## Architecture

```
Terraform apply
├── module.azure_sqldb_va_config
│   ├── Azure Key Vault          ← stores admin + monitoring credentials
│   ├── Azure Function App       ← creates gdmmonitor role/user in all databases
│   ├── Storage Account          ← required by Functions runtime
│   ├── App Service Plan (EP1)   ← supports VNet integration
│   ├── VNet Subnet              ← delegated to Microsoft.Web/serverFarms
│   └── SQL Server Firewall Rules ← optional, for public endpoint access
└── module.azure_sqldb_gdp_connection
    └── IBM GDP connect-datasource-to-va ← registers datasource in Guardium
```

## Quick Start

### 1. Prerequisites

- [ ] Azure SQL Server deployed
- [ ] **Admin App Registration** created in Entra ID and set as Entra ID admin on the SQL Server
  ```bash
  # Azure Portal → SQL Server → Microsoft Entra ID → Set admin
  # OR via CLI:
  az sql server ad-admin create \
    --resource-group <rg> \
    --server-name <server> \
    --display-name <admin-app-reg-display-name> \
    --object-id <admin-app-reg-object-id>
  ```
- [ ] **Monitoring App Registration** created in Entra ID (no SQL permissions needed yet)
- [ ] DigiCert certificates imported into Guardium keystore — see [gdmmonitor-AzureSQLDB.sql](../../tmp/gdmmonitor-AzureSQLDB.sql)
- [ ] Azure CLI authenticated (`az login`)
- [ ] Terraform >= 1.0

### 2. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 4. Invoke the Setup Function

After `terraform apply`, wait 5-10 minutes for the Function App to become active, then run the command from the `function_invoke_command` output:

```bash
terraform output -raw function_invoke_command | bash
```

This creates the `gdmmonitor` role and monitoring user in **every database** on the server.

### 5. Verify in Guardium

- Navigate to: **Harden → Vulnerability Assessment → Datasource Definitions**
- Confirm the datasource `azure-sqldb-va` (or your chosen name) is listed
- Run a test connection to verify Entra ID auth works

## Key Differences from MySQL Module

| Aspect | Azure MySQL | Azure SQL DB |
|---|---|---|
| Auth method | Username + password | Entra ID Service Principal (Client ID + Secret) |
| DB user type | Native SQL user | `FROM EXTERNAL PROVIDER` (Entra ID identity) |
| Firewall resource | `azurerm_mysql_flexible_server_firewall_rule` | `azurerm_mssql_firewall_rule` |
| Connection properties | SSL settings | `authentication=ActiveDirectoryServicePrincipal;...` |
| Setup identities | 1 (admin user) | 2 (admin App Reg + monitoring App Reg) |
| Default port | 3306 | 1433 |

## Guardium Datasource Configuration

The monitoring App Registration authenticates to Guardium as:

| Field | Value |
|---|---|
| Database Type | SQL DB Azure |
| Username | Monitoring App Registration **Client ID** |
| Password | Monitoring App Registration **Client Secret** |
| Host | `<server>.database.windows.net` |
| Port | `1433` |
| Database | `master` |
| Connection Properties | `authentication=ActiveDirectoryServicePrincipal;hostNameInCertificate=*.database.windows.net;loginTimeout=60;` |

## Certificate Setup

Before the Guardium connection will succeed, import two DigiCert certificates into the Guardium keystore. See [gdmmonitor-AzureSQLDB.sql](../../tmp/gdmmonitor-AzureSQLDB.sql) for full instructions.

```bash
# On the Guardium appliance:
curl -o /tmp/DigiCertGlobalRootCA.crt https://cacerts.digicert.com/DigiCertGlobalRootCA.crt
curl -o /tmp/DigiCertSHA2SecureServerCA.crt https://cacerts.digicert.com/DigiCertSHA2SecureServerCA-2.crt
openssl x509 -inform DER -in /tmp/DigiCertGlobalRootCA.crt -out /tmp/DigiCertGlobalRootCA.pem -outform PEM
openssl x509 -inform DER -in /tmp/DigiCertSHA2SecureServerCA.crt -out /tmp/DigiCertSHA2SecureServerCA.pem -outform PEM

# Then on Guardium CLI:
# store certificate keystore trusted console   (alias: digicertglobalroot)
# store certificate keystore trusted console   (alias: digicertsha2secureserverca)
# restart gui
```
