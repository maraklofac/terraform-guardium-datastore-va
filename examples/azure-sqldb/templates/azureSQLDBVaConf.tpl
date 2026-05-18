{
  "name": "${datasource_name}",
  "type": "SQL DB Azure",
  "host": "${datasource_hostname}",
  "port": ${datasource_port},
  "database": "master",
  "application": "${application}",
  "description": "${datasource_description}",
  "severity": "${severity_level}",
  "shared": "Not Shared",
  "savePassword": 1,
  "user": "${monitor_client_id}",
  "password": "${monitor_client_secret}",
  "connectionProperties": "authentication=ActiveDirectoryServicePrincipal;hostNameInCertificate=*.database.windows.net;loginTimeout=60;"
}
