# Azure deployment preparation

## Status
No Azure subscription resources have been provisioned. This document is a preparation plan only; no cloud resources, database, identity tenant, AI model or production endpoint have been created.

## Target architecture
- Azure App Service for Linux (Node.js 20 runtime) for the Next.js standalone application.
- Azure Database for PostgreSQL Flexible Server, private network access, private DNS and backups.
- Microsoft Entra External ID for end-user identity; demo authentication is not production authentication.
- System-assigned managed identity for App Service; Key Vault RBAC for secrets.
- Application Insights / Azure Monitor for telemetry and alerting.
- Azure OpenAI as a separately gated capability; disabled until clinical governance, privacy review and safety evaluation are signed off.
- GitHub Actions using OIDC federation; no publish profile or long-lived Azure credential in repository secrets.

## Country and region strategy
Nigeria is the initial service country. The application keeps country configuration separate so other African countries can be onboarded without treating a directory listing as an active referral service. Ghana, Kenya and South Africa remain inactive placeholders until country-specific legal, clinical, emergency-pathway, provider-licensing, language and data-residency reviews are complete.

Select the Azure deployment region only after checking current regional availability for every required service (App Service, PostgreSQL Flexible Server, Key Vault, Monitor and any later AI service), service quotas, latency, disaster-recovery options and Nigerian data-protection obligations. Do not assume that a region's presence means every Azure service is available there. Record the approved region and data-flow map before provisioning.

## Pre-provisioning gates
1. Confirm the Azure subscription, billing owner, tenant and authorized deployment administrator.
2. Select and approve a region and resource-group naming convention.
3. Complete Nigeria privacy/legal review, DPIA and data-residency decision.
4. Confirm PostgreSQL network mode, VNet CIDRs, private DNS design, backup retention and restore objectives.
5. Review and validate `infra/main.bicep` with the Azure CLI/Bicep compiler against the target subscription. The current Bicep is a starter template, not production-approved.
6. Create a dedicated deployment identity and GitHub OIDC federated credential scoped to this repository and the `main` branch. Assign least privilege at the resource-group scope.
7. Configure repository Actions secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_WEBAPP_NAME`. These are identifiers, not passwords. Never put client secrets, database passwords, API keys or connection strings in source control.
8. Create resources first in a non-production resource group. Run build, smoke tests, network checks, database migration review and rollback test before production.
9. Configure Entra External ID, authorization, retention, audit, alerting, backups and incident response before any real user data is collected.
10. Keep `LIVE_REFERRALS_ENABLED=false`; keep the AI companion disabled until clinical safety and privacy approval.

## GitHub Actions deployment
The workflow at `.github/workflows/azure-deploy.yml` builds the Next.js standalone output, runs TypeScript type-checking and uses `azure/login@v2` with GitHub OIDC before deploying to App Service. It will not deploy successfully until the Azure resources, federated credential and repository secrets exist.

## Important infrastructure review items
- Confirm the PostgreSQL private DNS zone suffix and subnet delegation against current Flexible Server requirements; ensure the database delegated subnet is dedicated and the App Service integration subnet is distinct.
- Confirm App Service VNet integration is supported by the selected plan SKU and region.
- Confirm Key Vault name uniqueness, soft-delete/purge-protection policy, RBAC role scope and managed-identity role assignment.
- The app currently needs a production database connection/authentication design; do not add a raw database password to app settings or GitHub secrets. Prefer managed identity where supported or Key Vault references.
- Validate the App Service startup command and standalone artifact layout in a staging deployment.
- Configure health checks, diagnostic settings, TLS, custom domain, backup/restore, alert thresholds and deployment rollback.
- Review Content Security Policy and any future external AI endpoints before enabling them.

## Deployment acceptance checklist
- [ ] Subscription and billing owner confirmed
- [ ] Region and data residency approved
- [ ] Bicep build and what-if pass
- [ ] Private networking and DNS verified
- [ ] OIDC federation and least-privilege role verified
- [ ] App Service health endpoint passes
- [ ] PostgreSQL connection and migration verified
- [ ] Entra External ID sign-in and authorization tested
- [ ] Key Vault access via managed identity tested
- [ ] App Insights alerts and audit logs configured
- [ ] Backup restore and rollback tested
- [ ] DPIA, clinical safety case and operational owner signed
- [ ] Live referrals and AI remain disabled until separate approval
