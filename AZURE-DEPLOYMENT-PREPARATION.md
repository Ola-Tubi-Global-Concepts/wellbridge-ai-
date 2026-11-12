# Azure deployment preparation

OIDC authentication has been verified separately. That does not mean the app is ready to deploy.

## Current intended resource direction
- Azure App Service (Linux Node.js) for Next.js.
- Azure Database for PostgreSQL Flexible Server only when persistence is approved.
- Key Vault and Managed Identity for secrets.
- Application Insights / Azure Monitor for operational telemetry.
- Microsoft Entra External ID for customer authentication after configuration and testing.

## Before provisioning
1. Confirm monthly development budget and spending alert thresholds.
2. Confirm target subscription, resource group and region availability/pricing.
3. Review network topology, PostgreSQL private access, backups and recovery objectives.
4. Validate Bicep in a non-production environment.
5. Confirm identity, least-privilege RBAC, secrets, logs and data retention.
6. Complete privacy, clinical safety and country-pathway governance reviews.

## GitHub Actions secrets
The existing OIDC test uses `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`. The deployment workflow also requires `AZURE_WEBAPP_NAME` after an App Service has been intentionally provisioned. Never create a client secret for the OIDC flow.

Do not add production credentials to `.env.example` or commit secrets.
