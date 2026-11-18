# WellBridge AI — Healthcare Pathway Verification Database

**Status:** design and migration starter only  
**Scope:** internal pathway and evidence administration; Nigeria/Lagos first, multi-country capable  
**Production status:** not approved; no database is connected and no public directory is enabled.

## Purpose

Create a traceable register of the organisations, facilities, services, practitioners' credential checks, referral relationships and evidence needed to assess whether a care pathway can eventually be presented accurately.

This is an administrative verification system. It is not a clinical record system, patient-management system, emergency dispatch system or clinical decision-support system.

## Data model

| Record | Purpose |
|---|---|
| Country | ISO country identity and research scope |
| Administrative area | State/region, LGA/LCDA, district and parent-child geography |
| Organisation | Government authority, facility operator, helpline operator or regulator |
| Facility | Physical facility or non-physical helpline/service point |
| Service | A defined support or clinical service, with scope and eligibility |
| Facility-service | Evidence that a particular facility actually offers a particular service, including hours and access |
| Referral relationship | Explicit, verified relationship between a referring and receiving facility |
| Professional credential | Role-specific regulator and registration checks; not a substitute for regulator confirmation |
| Evidence source | Public source, official correspondence, letter, or other evidence |
| Verification event | Who checked what, how, when, outcome, limitations and next review |

## Verification states

- `research_only`: desk-research lead only; not suitable for a user-facing recommendation.
- `officially_published`: information appears in an official public source; operational status remains unconfirmed.
- `direct_confirmation_pending`: confirmation has been requested but not received.
- `verified_active`: required details have been directly confirmed and evidence recorded; still requires separate approval before user-facing use.
- `temporarily_unavailable`: confirmed temporary outage or closure.
- `expired`: verification is past its review date or cannot be relied on.
- `rejected`: evidence contradicts the claim or the entry is unsuitable.

A public-source review must never be treated as direct confirmation. A verified facility does not automatically mean every service at that facility is verified. A verified service does not automatically verify a referral relationship.

## Nigeria/Lagos seed approach

Do not seed guessed operational facts. Start with candidate records from the current desk-research register and label them `officially_published` or `direct_confirmation_pending` as appropriate.

Initial candidate set:
- Onilekere PHC — Ikeja LGA.
- Oregun PHC — Onigbongbo LCDA.
- Ojodu PHC — Ojodu LCDA.
- Five programme-published general-hospital referral hubs: Alimosho, Gbagada, Lagos Island, Ikorodu and Epe General Hospitals.
- LASUTH as a separately identified tertiary facility.
- Federal Neuro-Psychiatric Hospital Yaba as a specialist-facility candidate.
- Lagos Lifeline channels as operator-published support contacts, pending direct operator confirmation.
- 112 and Lagos 767/112 as published emergency-number candidates, with local operation and dispatch limitations recorded.

Do not create a PHC-to-hospital assignment based on geographic proximity. The published MeHPriC hub-and-spoke model does not by itself establish the assignment for an individual PHC.

## Evidence and audit requirements

Every verification event should preserve:
1. Entity type and identifier.
2. Source URL or evidence reference.
3. Verification method and date.
4. Confirming organisation and representative's role (not unnecessary personal details).
5. Exact claim supported and limitations.
6. Reviewer and next review date.

Store dated official replies and source snapshots in a controlled evidence repository. Do not store patient information, sensitive personal data or full email threads containing unrelated personal information in this register.

## Review cadence

Use a risk-based schedule. Emergency contacts, crisis lines and urgent referral routes require frequent checks and an agreed operational test protocol. Routine facility details can have a longer interval, but must have an owner and expiry date. An overdue record should become non-publishable automatically in any future directory.

## Security and governance gates before applying this migration

- Select and provision an approved PostgreSQL service and region.
- Complete the Nigeria NDPA/NDPC privacy assessment and DPIA.
- Approve data classification, retention, deletion, backup and incident-response policies.
- Configure workforce authentication and least-privilege roles; do not expose the register through public endpoints.
- Add database audit logging and tested backup/restore.
- Validate the migration in a disposable development database and run schema tests.
- Appoint a pathway-verification owner and clinical governance approver.
- Keep all public directory and crisis escalation features disabled until separately approved.

## Current project decision

The repository currently has no database driver or live database configuration. The migration is intentionally not wired into the application and must not be run against a production resource. This avoids silently introducing a new paid service or persisting sensitive data before the required approvals.
