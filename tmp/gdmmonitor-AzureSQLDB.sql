--***********************************************************************************************--
--                                                                                               --
-- IBM Confidential                                                                              --
-- OCO Source Materials                                                                          --
-- © Copyright IBM Corp. 2002, 2026                                                              --
-- The source code for this program is not published or otherwise divested of its trade secrets, --
-- irrespective of what has been deposited with the U.S. Copyright Office.                       --
--                                                                                               --
--***********************************************************************************************--

-- ============================================================================
-- Guardium Data Protection - Azure SQL Database Connection Setup for Entra ID
-- ============================================================================
-- Purpose: Document steps for connecting Guardium to Azure SQL DB using
--          Active Directory Service Principal (App Registration with Client Secret)
-- ============================================================================

-- ============================================================================
-- PREREQUISITES
-- ============================================================================
-- 1. Azure SQL Database instance created and accessible
--    (i.e., networking firewall rule for client IP address to enable access)
-- 2. Azure Active Directory App Registration with Client Secret
-- 3. Guardium Data Protection 12.x installed
-- 4. CLI access to Guardium appliance
-- 5. Internet connectivity to download certificates

-- ============================================================================
-- PART 1: AZURE ACTIVE DIRECTORY SETUP
-- ============================================================================

-- Step 1: Create App Registration in Azure Portal
-- Navigate to: Azure Portal > Azure Services > App registrations > New registration
-- 
-- Required Information:
--   - Name: app-reg-sqlguard (or your preferred name)
--   - Supported account types: Single tenant
--   - Redirect URI: Not required for this scenario
--
-- After creation, note the following value:
--   - Application (client) ID: <your-client-id>

-- Step 2: Create Client Secret
-- Navigate to: App registration > Certificates & secrets > New client secret
--
-- Required Information:
--   - Description: Guardium SQL DB Access
--   - Expires: Choose appropriate expiration (e.g., 12 months, 24 months)
--
-- IMPORTANT: Copy the secret VALUE immediately - it won't be shown again
--   - Client Secret Value: <your-client-secret-value>

-- Step 3: Create Database User for App Registration (in each database including master)
-- Connect to your Azure SQL Database using Azure Data Studio or SSMS
-- Run the following SQL command to create a user for the App Registration:

-- Create user for the App Registration (replace with your App Registration name)
-- CREATE USER [app-reg-sqlguard] FROM EXTERNAL PROVIDER;

-- ============================================================================
-- PART 2: CERTIFICATE SETUP
-- ============================================================================

-- Import two DigiCert certificates into Guardium's keystore to prevent connection error:
-- javax.net.ssl.SSLHandshakeException: PKIX path building failed

-- ----------------------------------------------------------------------------
-- Step 1: Backup Existing Keystore
-- ----------------------------------------------------------------------------
-- Execute on Guardium Appliance:

-- Create timestamped backup
-- cp -p /opt/IBM/Guardium/tomcat/.keystore /opt/IBM/Guardium/tomcat/.keystore.backup.$(date +%Y%m%d)

-- Verify backup was created
-- ls -lh /opt/IBM/Guardium/tomcat/.keystore*

-- ----------------------------------------------------------------------------
-- Step 2: Check Existing Certificates
-- ----------------------------------------------------------------------------
-- Execute on Guardium CLI:

-- show certificate keystore all

-- Look for these certificates (may already exist):
--   - digicertglobalrootg2 (DigiCert Global Root G2)
--   - digicertglobalroot (DigiCert Global Root CA G1) - This is also required
--   - digicertsha2secureserverca (DigiCert SHA2 Secure Server CA) - This is also required
--   - microsoftrsarootcertificateauthority2017 (Microsoft RSA Root CA 2017)

-- NOTE: If digicertglobalroot and digicertsha2secureserverca already exist,
--       skip to PART 3. Otherwise, continue with certificate import.

-- ----------------------------------------------------------------------------
-- Step 3: Download Required Certificates
-- ----------------------------------------------------------------------------
-- Execute on Guardium Appliance (or download to /tmp directory):

-- Download DigiCert Global Root CA (G1 - NOT G2!)
-- curl -o /tmp/DigiCertGlobalRootCA.crt https://cacerts.digicert.com/DigiCertGlobalRootCA.crt

-- Download DigiCert SHA2 Secure Server CA (2020 version)
-- curl -o /tmp/DigiCertSHA2SecureServerCA.crt https://cacerts.digicert.com/DigiCertSHA2SecureServerCA-2.crt

-- Convert certificates from DER to PEM format (required for import)
-- openssl x509 -inform DER -in /tmp/DigiCertGlobalRootCA.crt -out /tmp/DigiCertGlobalRootCA.pem -outform PEM
-- openssl x509 -inform DER -in /tmp/DigiCertSHA2SecureServerCA.crt -out /tmp/DigiCertSHA2SecureServerCA.pem -outform PEM

-- View certificate content (for console import)
-- cat /tmp/DigiCertGlobalRootCA.pem
-- cat /tmp/DigiCertSHA2SecureServerCA.pem

-- ----------------------------------------------------------------------------
-- Step 4: Import Certificates into Guardium Keystore
-- ----------------------------------------------------------------------------
-- Execute on Guardium CLI:

-- Console Import (Recommended - Paste certificate content)
-- 
-- Import DigiCert Global Root CA:
-- store certificate keystore trusted console
-- When prompted for alias, enter: digicertglobalroot
-- Paste the entire certificate content from /tmp/DigiCertGlobalRootCA.pem
-- (Include -----BEGIN CERTIFICATE----- and -----END CERTIFICATE----- lines)
--
-- Import DigiCert SHA2 Secure Server CA:
-- store certificate keystore trusted console
-- When prompted for alias, enter: digicertsha2secureserverca
-- Paste the entire certificate content from /tmp/DigiCertSHA2SecureServerCA.pem

-- ----------------------------------------------------------------------------
-- Step 5: Verify Certificate Import
-- ----------------------------------------------------------------------------
-- Execute on Guardium CLI:

-- show certificate keystore all

-- Expected output should include:
--
-- Alias name: digicertglobalroot
-- Entry type: trustedCertEntry
-- Owner: CN=DigiCert Global Root CA, OU=www.digicert.com, O=DigiCert Inc, C=US
-- Valid from: Nov 10, 2006 until: Nov 10, 2031
--
-- Alias name: digicertsha2secureserverca
-- Entry type: trustedCertEntry
-- Owner: CN=DigiCert SHA2 Secure Server CA, O=DigiCert Inc, C=US
-- Valid from: Sep 22, 2020 until: Sep 22, 2030

-- ----------------------------------------------------------------------------
-- Step 6: Restart Guardium
-- (required if not completed by CLI upon successful certificate import)
-- ----------------------------------------------------------------------------
-- Execute on Guardium CLI:

-- restart gui

-- Wait for Guardium to fully restart (typically 5-10 minutes)
-- Monitor restart progress with: show status

-- ============================================================================
-- PART 3: AZURE SQL DATABASE DATASOURCE CONFIGURATION
-- ============================================================================

-- Navigate to: Guardium GUI > Harden > Vulnerability Assessment > Datasource Definitions

-- ----------------------------------------------------------------------------
-- Datasource Configuration Parameters:
-- ----------------------------------------------------------------------------

-- Basic Information:
--   Application Type: Security Assessment
--   Database Type: SQL DB Azure

-- Authentication:
--   Credential type: Assign credentials
--   User name: <your-client-id> (from App Registration)
--   Password: <your-client-secret-VALUE> (copied when Client Secret created for App Registration)

-- Location:
--   Host name/IP: <your-server>.database.windows.net
--   Port: 1433
--   Database: master

-- Connection Properties:
--   authentication=ActiveDirectoryServicePrincipal;
--   hostNameInCertificate=*.database.windows.net;
--   loginTimeout=60;

-- ============================================================================
-- PART 4: OPTIONAL CERTIFICATES
-- ============================================================================

-- In rare cases, you may need to import additional certificates:

-- Microsoft Azure RSA TLS Issuing CA 04 (Intermediate Certificate)
-- Only needed if your Azure SQL DB instance uses this specific chain
-- 
-- Download and import if connection still fails after importing the two
-- required DigiCert certificates:
--
-- This certificate is typically not needed because the two DigiCert
-- certificates (Global Root CA and SHA2 Secure Server CA) cover most
-- Azure SQL DB instances.

-- ============================================================================
-- REFERENCES
-- ============================================================================

-- Microsoft Azure Certificate Authority Details:
-- https://learn.microsoft.com/en-us/azure/security/fundamentals/azure-certificate-authority-details
--
-- DigiCert Trusted Root Certificates:
-- https://www.digicert.com/kb/digicert-root-certificates.htm
--
-- IBM Guardium Certificate CLI Commands:
-- https://www.ibm.com/docs/en/gdp/12.x?topic=commands-certificate-cli
--
-- Azure SQL Database Authentication Methods:
-- https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-service-principal
--

-- ============================================================================
-- SUMMARY CHECKLIST
-- ============================================================================

-- Azure Active Directory Setup:
-- [ ] Azure App Registration created with Client Secret
-- [ ] Application (client) ID recorded
-- [ ] Client Secret value recorded (saved securely)
-- [ ] App Registration user created in Azure SQL DB

-- Certificate Setup:
-- [ ] Guardium keystore backed up
-- [ ] DigiCert Global Root CA certificate downloaded
-- [ ] DigiCert SHA2 Secure Server CA certificate downloaded
-- [ ] Certificates converted from DER to PEM format
-- [ ] DigiCert Global Root CA imported (alias: digicertglobalroot)
-- [ ] DigiCert SHA2 Secure Server CA imported (alias: digicertsha2secureserverca)
-- [ ] Certificates verified in keystore
-- [ ] Guardium restarted after certificate import

-- Datasource Configuration:
-- [ ] Database definition created for SQL DB Azure in Guardium GUI
-- [ ] User [Client ID], Password [Client Secret Value] configured
-- [ ] Server address configured: <server>.database.windows.net
-- [ ] Port set to 1433
-- [ ] Database set to master
-- [ ] Connection properties include: hostNameInCertificate=*.database.windows.net;
-- [ ] Authentication method: authentication=ActiveDirectoryServicePrincipal;
-- [ ] Connection tested successfully

-- ============================================================================
-- CERTIFICATE DETAILS REFERENCE
-- ============================================================================

-- Certificate 1: DigiCert Global Root CA
-- Alias: digicertglobalroot
-- Owner: CN=DigiCert Global Root CA, OU=www.digicert.com, O=DigiCert Inc, C=US
-- Issuer: CN=DigiCert Global Root CA, OU=www.digicert.com, O=DigiCert Inc, C=US
-- Valid: November 10, 2006 to November 10, 2031
-- SHA256 Fingerprint: 43:48:A0:E9:44:4C:78:CB:26:5E:05:8D:5E:89:44:B4:D8:4F:96:62:BD:26:DB:25:7F:89:34:A4:43:C7:01:61
-- Purpose: Root certificate for Azure SQL DB SSL chain

-- Certificate 2: DigiCert SHA2 Secure Server CA
-- Alias: digicertsha2secureserverca
-- Owner: CN=DigiCert SHA2 Secure Server CA, O=DigiCert Inc, C=US
-- Issuer: CN=DigiCert Global Root CA, OU=www.digicert.com, O=DigiCert Inc, C=US
-- Valid: September 22, 2020 to September 22, 2030
-- SHA256 Fingerprint: C1:AD:77:78:79:6D:20:BC:A6:5C:88:9A:26:55:02:11:56:52:8B:B6:2F:F5:FA:43:E1:B8:E5:A8:3E:3D:2E:AA
-- Purpose: Intermediate certificate for Azure SQL DB SSL chain

-- ============================================================================

-- Made with Bob
