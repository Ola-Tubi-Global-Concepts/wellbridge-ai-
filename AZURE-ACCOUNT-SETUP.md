# Azure account and identity setup — WellBridge AI

This is an operator checklist. No Azure resources are provisioned by this repository.

## 1. Create the Azure subscription

1. Open https://azure.microsoft.com/free/ or https://azure.microsoft.com/pricing/purchase-options/azure-account/.
2. Sign in with the Microsoft account that will own the WellBridge AI cloud environment.
3. Complete Microsoft's identity, phone and payment verification using the real account holder and billing details. Never use false country, billing or identity information.
4. Choose Pay-As-You-Go for a continuing pilot, or use the free-account offer only for short-lived evaluation. The free account offer includes $200 credit for 30 days; after the credit period, free monthly allowances are limited and non-free resources can incur charges.
5. In the Azure portal, open Subscriptions and confirm the subscription is Active. Record the Subscription ID privately.
6. Set up a Cost Management budget and alerts before creating resources. A budget is an alerting control, not a hard spending cap.
7. Keep the initial subscription dedicated to WellBridge AI where practical. Do not share owner credentials.

## 2. Workforce tenant and administrator security

The Azure subscription is associated with a Microsoft Entra workforce directory. Use the tenant created/associated during Azure sign-up as the workforce directory for cloud administrators and deployment identities. Avoid creating extra workforce directories unnecessarily.
- Enable MFA for every administrator.
- Keep at least two appropriately secured emergency-access accounts, stored and monitored according to Microsoft's guidance.
- Use least-privilege Azure RBAC. Do not use Global Administrator for routine resource deployment.
- Record tenant ID and primary domain privately.

## 3. Create the customer identity tenant

WellBridge AI is a customer-facing service. Use Microsoft Entra External ID (external tenant configuration) for patient/member/customer sign-in, separate from the workforce tenant used by cloud administrators.

After the Azure subscription exists:
1. Open https://entra.microsoft.com/.
2. Go to Entra ID > Overview > Manage tenants > Create.
3. Choose External, then Continue.
4. Choose the Azure subscription path (or trial only for isolated testing).
5. Proposed tenant display name: WellBridge AI Customers.
6. Proposed initial domain: choose an available, brand-consistent domain such as wellbridgeai; verify availability in the portal.
7. Select the tenant country/region only after reviewing the External ID data location and privacy implications. The location cannot be changed later. Do not assume the App Service region automatically sets the External ID data location.
8. Associate the tenant with the WellBridge AI subscription/resource group as prompted, review and create.
9. Record the External tenant ID, domain and issuer privately. Do not publish these identifiers as secrets; do not share passwords or client secrets in chat.

Do not use the old Azure AD B2C product for a new customer identity implementation. Use Microsoft Entra External ID.

## 4. Region and deployment decision

Proposed Azure resource region: South Africa North (Johannesburg), subject to final service availability, quotas, pricing and legal approval. The application service country remains Nigeria. Hosting in South Africa does not establish compliance with Nigerian privacy or health-data rules.

Before provisioning, verify each selected SKU in the Azure portal and the official Products available by region catalogue. PostgreSQL Flexible Server lists South Africa North among supported regions; confirm the required compute generation/SKU and capacity in the subscription before deployment.

## 5. Before the first resource is created

- Approve a resource group name, e.g. rg-wellbridge-dev-southafricanorth.
- Approve app/database naming and a unique Key Vault name.
- Choose non-production environment and cost budget.
- Validate Bicep with the current Azure CLI/Bicep compiler and run az deployment group what-if.
- Review PostgreSQL private networking and DNS; confirm distinct delegated database subnet and App Service integration subnet.
- Confirm the chosen App Service plan supports VNet integration.
- Configure GitHub Actions OIDC with a dedicated Entra application/service principal and least-privilege RBAC scoped to the deployment resource group.
- Add only the OIDC identifiers to GitHub Actions secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID and AZURE_WEBAPP_NAME. Do not store passwords or connection strings in GitHub.
- Keep production user registration, health data collection, AI and live referrals disabled until privacy, clinical safety and operational sign-off.

## 6. Values to return to the implementation team

Once the account setup is complete, provide only these non-secret identifiers in the project conversation:
- Azure subscription display name (or a masked label) and confirmation that it is Active.
- Azure subscription ID (share only if comfortable; it is an identifier, not a password).
- Workforce tenant ID.
- External ID tenant ID and initial domain, if already created.
- Confirmation that the subscription region picker offers South Africa North for the required services.

Never send account passwords, MFA codes, client secrets, certificates, database passwords, access tokens or API keys in chat.
