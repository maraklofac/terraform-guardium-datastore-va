import os
import json
import logging
from datetime import datetime
import azure.functions as func
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.keyvault.secrets import SecretClient
import pymssql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

KEY_VAULT_NAME = os.environ.get('KEY_VAULT_NAME')
SECRET_NAME = os.environ.get('SECRET_NAME')

REQUIRED_SECRET_KEYS = [
    'admin_client_id',
    'admin_client_secret',
    'tenant_id',
    'monitor_app_registration_name',
    'endpoint',
]

# Databases excluded from role/user setup (system DBs that don't allow external users)
SKIP_DATABASES = {'tempdb', 'model', 'msdb'}


def validate_secret_schema(secret):
    missing = [k for k in REQUIRED_SECRET_KEYS if k not in secret]
    if missing:
        raise ValueError(f"Secret missing required keys: {', '.join(missing)}")
    logger.info("Secret schema validation passed")


def get_credentials():
    """Retrieve configuration from Azure Key Vault using managed identity."""
    logger.info(f"Retrieving credentials from Key Vault: {KEY_VAULT_NAME}")
    kv_uri = f"https://{KEY_VAULT_NAME}.vault.azure.net"
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=kv_uri, credential=credential)
    secret = client.get_secret(SECRET_NAME)
    credentials = json.loads(secret.value)
    validate_secret_schema(credentials)
    logger.info("Credentials retrieved and validated")
    return credentials


def get_sql_access_token(tenant_id, client_id, client_secret):
    """Get an Entra ID access token for Azure SQL Database."""
    logger.info(f"Acquiring access token for tenant {tenant_id}")
    credential = ClientSecretCredential(
        tenant_id=tenant_id,
        client_id=client_id,
        client_secret=client_secret
    )
    token = credential.get_token("https://database.windows.net/.default")
    logger.info("Access token acquired successfully")
    return token.token


def connect_to_db(server, database, access_token):
    """Open a pymssql connection using an Entra ID access token."""
    logger.info(f"Connecting to {server}/{database}")
    return pymssql.connect(server=server, database=database, access_token=access_token)


def safe_identifier(name):
    """Escape a SQL bracket-quoted identifier by doubling any ] characters."""
    return name.replace(']', ']]')


def get_user_databases(server, access_token):
    """List all non-system user databases on the server."""
    conn = connect_to_db(server, 'master', access_token)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT name FROM sys.databases WHERE state = 0 "
        "AND name NOT IN ('master', 'tempdb', 'model', 'msdb') "
        "ORDER BY name"
    )
    databases = [row[0] for row in cursor.fetchall()]
    cursor.close()
    conn.close()
    logger.info(f"Found {len(databases)} user database(s): {databases}")
    return databases


def setup_master_db(server, access_token, app_reg_name):
    """Create the App Registration user in master (authentication only, no role)."""
    ops = []
    conn = connect_to_db(server, 'master', access_token)
    cursor = conn.cursor()

    cursor.execute(
        "SELECT name FROM sys.database_principals WHERE name = %s AND type = 'E'",
        (app_reg_name,)
    )
    if cursor.fetchone():
        logger.info(f"User [{app_reg_name}] already exists in master")
        ops.append({"op": "create_user", "status": "already_exists"})
    else:
        cursor.execute(f"CREATE USER [{safe_identifier(app_reg_name)}] FROM EXTERNAL PROVIDER")
        conn.commit()
        logger.info(f"Created user [{app_reg_name}] in master")
        ops.append({"op": "create_user", "status": "created"})

    cursor.close()
    conn.close()
    return ops


def setup_user_db(server, database, access_token, app_reg_name):
    """Create gdmmonitor role, grant permissions, create user, and add to role."""
    ops = []
    conn = connect_to_db(server, database, access_token)
    cursor = conn.cursor()

    # 1. Create gdmmonitor role if not present
    cursor.execute(
        "SELECT name FROM sys.database_principals WHERE name = 'gdmmonitor' AND type = 'R'"
    )
    if cursor.fetchone():
        logger.info(f"Role [gdmmonitor] already exists in {database}")
        ops.append({"op": "create_role", "status": "already_exists"})
    else:
        cursor.execute("CREATE ROLE [gdmmonitor]")
        conn.commit()
        logger.info(f"Created role [gdmmonitor] in {database}")
        ops.append({"op": "create_role", "status": "created"})

    # 2. Grant permissions required by Guardium VA to the role
    grants = [
        "GRANT SELECT ON sys.all_objects TO gdmmonitor",
        "GRANT SELECT ON sys.database_firewall_rules TO gdmmonitor",
        "GRANT SELECT ON sys.database_permissions TO gdmmonitor",
        "GRANT SELECT ON sys.database_principals TO gdmmonitor",
        "GRANT SELECT ON sys.database_role_members TO gdmmonitor",
        "GRANT SELECT ON sys.schemas TO gdmmonitor",
        "GRANT SELECT ON sys.sql_modules TO gdmmonitor",
        "GRANT SELECT ON sys.symmetric_keys TO gdmmonitor",
        "GRANT VIEW DATABASE STATE TO gdmmonitor",
        "GRANT VIEW DEFINITION TO gdmmonitor",
    ]
    for grant in grants:
        cursor.execute(grant)
    conn.commit()
    logger.info(f"Granted permissions to [gdmmonitor] in {database}")
    ops.append({"op": "grant_permissions", "status": "success"})

    # 3. Create App Registration user if not present
    cursor.execute(
        "SELECT name FROM sys.database_principals WHERE name = %s AND type = 'E'",
        (app_reg_name,)
    )
    if cursor.fetchone():
        logger.info(f"User [{app_reg_name}] already exists in {database}")
        ops.append({"op": "create_user", "status": "already_exists"})
    else:
        cursor.execute(f"CREATE USER [{safe_identifier(app_reg_name)}] FROM EXTERNAL PROVIDER")
        conn.commit()
        logger.info(f"Created user [{app_reg_name}] in {database}")
        ops.append({"op": "create_user", "status": "created"})

    # 4. Add user to gdmmonitor role if not already a member
    cursor.execute(
        """
        SELECT 1 FROM sys.database_role_members rm
        JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
        JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
        WHERE r.name = 'gdmmonitor' AND m.name = %s
        """,
        (app_reg_name,)
    )
    if cursor.fetchone():
        logger.info(f"User [{app_reg_name}] already member of [gdmmonitor] in {database}")
        ops.append({"op": "add_to_role", "status": "already_member"})
    else:
        cursor.execute(f"ALTER ROLE [gdmmonitor] ADD MEMBER [{safe_identifier(app_reg_name)}]")
        conn.commit()
        logger.info(f"Added [{app_reg_name}] to [gdmmonitor] in {database}")
        ops.append({"op": "add_to_role", "status": "success"})

    cursor.close()
    conn.close()
    return ops


def main(req: func.HttpRequest) -> func.HttpResponse:
    logger.info("Azure Function triggered for Azure SQL DB VA configuration")
    start_time = datetime.now()

    try:
        credentials = get_credentials()

        access_token = get_sql_access_token(
            credentials['tenant_id'],
            credentials['admin_client_id'],
            credentials['admin_client_secret']
        )

        server = credentials['endpoint']
        app_reg_name = credentials['monitor_app_registration_name']

        results = []

        # Configure master DB (user only — no role in master)
        try:
            ops = setup_master_db(server, access_token, app_reg_name)
            results.append({"database": "master", "status": "success", "operations": ops})
        except Exception as e:
            logger.error(f"Error processing master: {e}")
            results.append({"database": "master", "status": "error", "error": str(e)})

        # Configure each user database
        databases = get_user_databases(server, access_token)
        for db in databases:
            try:
                ops = setup_user_db(server, db, access_token, app_reg_name)
                results.append({"database": db, "status": "success", "operations": ops})
            except Exception as e:
                logger.error(f"Error processing {db}: {e}")
                results.append({"database": db, "status": "error", "error": str(e)})

        duration = (datetime.now() - start_time).total_seconds()
        success_count = sum(1 for r in results if r["status"] == "success")
        error_count = sum(1 for r in results if r["status"] == "error")

        response = {
            "success": error_count == 0,
            "message": (
                f"VA configuration completed. "
                f"{success_count}/{len(results)} databases configured successfully."
            ),
            "timestamp": datetime.now().isoformat(),
            "duration_seconds": duration,
            "server": server,
            "monitor_app_registration": app_reg_name,
            "databases_processed": len(results),
            "results": results,
        }

        return func.HttpResponse(
            json.dumps(response, default=str),
            status_code=200 if error_count == 0 else 207,
            mimetype="application/json",
        )

    except Exception as e:
        logger.error(f"Function execution failed: {e}")
        return func.HttpResponse(
            json.dumps({
                "success": False,
                "message": f"Function execution failed: {str(e)}",
                "timestamp": datetime.now().isoformat(),
            }),
            status_code=500,
            mimetype="application/json",
        )

# Made with Bob
