# WellBridge AI

**Earlier Support. Trusted Care. Better Wellbeing.**

A Nigeria-first, multi-country mental-wellbeing support and care-navigation prototype built with Next.js, TypeScript and Azure-oriented deployment boundaries.

## Important safety status

This repository is a **prototype, not a live healthcare service**. It does not diagnose, prescribe, provide emergency dispatch, or confirm clinical referrals. Crisis escalation is simulated. Do not enter real patient records or sensitive health information.

Before any live service:
- Obtain clinical governance and safeguarding approval.
- Verify emergency contacts, provider credentials, referral pathways, availability, hours, eligibility and costs with authoritative sources and human owners.
- Complete a Nigeria NDPA/NDPC privacy review, DPIA, security testing, accessibility testing, incident response and disaster-recovery plans.
- Establish named human owners for crisis response and referral operations.
- Obtain country-specific legal, clinical and data-residency approval.

## Features in this prototype
- Wellbeing education and non-diagnostic check-in interface.
- Care-navigation explanation and directory with explicit verification status.
- Privacy and safety disclosures.
- Country configuration placeholders for Nigeria, Ghana, Kenya and South Africa.
- PostgreSQL starter schema and Azure deployment preparation notes.

No check-in responses are persisted. No real provider directory entries are seeded. AI integrations are disabled by default.

## Local development
Requirements: Node.js 20.9+ and npm.

```bash
npm install
cp .env.example .env.local
npm run dev
```

Open http://localhost:3000.

Validation:
```bash
npm run typecheck
npm run build
```

## Architecture direction
- Web: Next.js 15, React 19, TypeScript
- Hosting: Azure App Service (Linux Node.js), subject to validation
- Database: Azure Database for PostgreSQL Flexible Server, only after privacy/security approval
- Identity: Microsoft Entra External ID for customers; separate workforce Entra tenant for operators
- Secrets: Azure Key Vault + Managed Identity
- Monitoring: Azure Monitor + Application Insights
- AI: Azure OpenAI integration boundary disabled until clinical safety and privacy approval
- CI/CD: GitHub Actions with OIDC

## Directory approval lifecycle
`pending_confirmation -> source_verified -> provider_confirmed -> clinically_approved -> active`

Only `active` entries may be considered for live referral workflows. This prototype contains no active provider entries.

## Environment
See `.env.example`. Keep secrets out of Git. Never commit real credentials or patient information.

## Deployment
See `AZURE-DEPLOYMENT-PREPARATION.md` and `infra/README.md`. The Bicep file is a reviewable starter, not an approved production deployment. Do not provision paid resources until budget, region, network design, security and operating ownership are approved.
