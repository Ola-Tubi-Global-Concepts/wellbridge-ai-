# WellBridge AI administrator authentication setup

## Scope and safety

This is an isolated development implementation on `feature/admin-verification-system`. Do not merge it into `main` or deploy it until the authentication and authorization tests have been reviewed.

The administrator sign-in uses the dedicated Microsoft Entra workforce tenant and the `WellBridge-AI-Admin` app registration. Do not use the WellBridge AI Customers External ID directory for administrator authentication.

No public registration is provided. Access is denied unless Microsoft Entra issues the expected tenant identity and the required application role.

## Required environment variables

Set these only in a trusted local environment or an approved secret store. Never commit actual values.

- `AUTH_SECRET`: a cryptographically random secret of at least 32 characters.
- `AUTH_TRUST_HOST=true`: required when running behind a trusted reverse proxy.
- `AUTH_MICROSOFT_ENTRA_ID_ID`: Application (client) ID from WellBridge-AI-Admin.
- `AUTH_MICROSOFT_ENTRA_ID_SECRET`: client-secret VALUE (not the secret ID).
- `AUTH_MICROSOFT_ENTRA_ID_TENANT_ID`: Directory (tenant) ID of the workforce directory containing WellBridge-AI-Admin.

The Microsoft Entra app registration must include this local Web redirect URI:

`http://localhost:3000/api/auth/callback/microsoft-entra-id`

For a later approved deployment, add the exact production callback URI to the app registration before configuring production secrets. Do not enable production sign-in merely by copying local settings.

## Install and run locally

Install dependencies with the package manager used by the repository, then configure the environment variables in an untracked `.env.local` file based on `.env.example`.

Run:

```bash
npm install
npm run typecheck
npm run dev
```

Open `http://localhost:3000/admin`. An unauthenticated visitor should be redirected to `/admin/sign-in`. Sign in with the account assigned the `WellBridge AI Platform Owner` app role. A successful session should display the `platform_owner` role and the expected workforce tenant ID.

## Security test cases

1. Unauthenticated request to `/admin` redirects to administrator sign-in.
2. A user from a different Entra tenant is rejected.
3. A signed-in user without `platform_owner` sees an access-denied message.
4. The assigned Platform Owner receives the `platform_owner` role claim and can open the admin workspace.
5. Sign-out ends the session.
6. No secret is present in Git, browser-visible code, or client-side environment variables.

## Current limitations

This is the first authentication checkpoint, not the complete administrative verification system. The dashboard is a protected shell only. Evidence upload, reviewer/approver separation, persistent role management, database-backed workflow, immutable audit events, and operational security tests remain to be implemented. The temporary Neon validation database is not connected. No live healthcare pathways are enabled.
