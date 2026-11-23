# WellBridge AI pathway register — database setup notes

**Current state:** SQL files committed; database not provisioned or connected; no migration has been applied.

## Files and execution order

1. `migrations/001_healthcare_pathway_verification.sql` — core register tables.
2. `migrations/002_contact_channels_and_area_authorities.sql` — multiple service contact channels and separate administrative oversight records.
3. `migrations/003_admin_verification_security.sql` — private administrator identities, role assignments, verification workflow, evidence metadata, decisions, audit triggers and RLS enablement.
4. `migrations/004_admin_access_policies_and_role_governance.sql` — restricted `wellbridge_app` grants, explicit RLS policies, controlled role governance and workflow enforcement (validation only). 
5. `migrations/005_signed_actor_context_and_review_isolation.sql` — HMAC-signed transaction-bound actor assertions, immutable Entra identity lookup, stricter review/evidence RLS, verified audit attribution and non-login application-role checks (validation only).
6. `seeds/001_nigeria_lagos_candidates.sql` — cautious Nigeria/Lagos desk-research candidates.
7. `seeds/002_candidate_evidence_links.sql` — attaches public-source review events to the candidate organisations, facilities and services.
8. `seeds/003_additional_official_sources.sql` — adds Lagos State agency-directory and emergency-contact evidence.

Apply only to a disposable PostgreSQL development database after reviewing the SQL. Do not run against production.

## Expected initial candidate contents

The seed script is designed to create, if absent:
- 1 country: Nigeria.
- 6 administrative areas: Lagos State, Ikeja, Onigbongbo, Ojodu, PHC Board District 6 and Lagos State Health District VI.
- 6 organisations: LSPHCB, Health District VI, Lagos MiND, NCC, LASEMA and Federal Neuro-Psychiatric Hospital Yaba.
- 10 facility candidates: three PHCs, five general-hospital hubs, LASUTH and Federal Neuro-Psychiatric Hospital Yaba.
- 4 service records: national 112, Lagos LASEMA emergency lines, Lagos Lifeline and MeHPriC.
- 7 contact channels: 112, 767, Lagos Lifeline's two voice numbers, WhatsApp and email (the emergency service rows include both national and Lagos 112 as separate records).
- Public evidence-source records for the relevant government, programme and facility pages.
- Public-source review events linked to the relevant candidate entities; these are not direct confirmations.

The script is intended to be repeatable and checks for existing records before inserting. Review it against the actual database state before execution.

## Initial quality checks

After applying migrations 001 and 002, then seed scripts 001, 002 and 003, use read-only checks:

```sql
SELECT iso2, name FROM countries WHERE iso2 = 'NG';

SELECT official_name, facility_type, address, verification_status, operating_status
FROM facilities
ORDER BY facility_type, official_name;

SELECT service_name, service_category, verification_status
FROM services
ORDER BY service_category, service_name;

SELECT s.service_name, c.channel_type, c.channel_value, c.verification_status
FROM service_contact_channels c
JOIN services s ON s.id = c.service_id
ORDER BY s.service_name, c.channel_type, c.channel_value;

SELECT a.name AS area, o.name AS authority, x.responsibility_type, x.verification_status
FROM administrative_area_authorities x
JOIN administrative_areas a ON a.id = x.administrative_area_id
JOIN organisations o ON o.id = x.organisation_id
ORDER BY a.name, o.name;

SELECT count(*) AS referral_relationships FROM referral_relationships;
SELECT count(*) AS facility_service_links FROM facility_services;
SELECT entity_type, outcome, count(*)
FROM verification_events
GROUP BY entity_type, outcome
ORDER BY entity_type, outcome;
```

The last two counts should be zero in this initial seed. That is intentional: the current evidence does not establish facility-level mental-health service availability or formal PHC-to-hospital cluster assignments.

## Safety and deployment boundary

- No patient, user, symptom, check-in, conversation or crisis-event data is stored.
- No pathway is seeded as `verified_active`.
- Publicly published contact details are not represented as live-tested.
- No referral relationship is inferred from geographic proximity.
- No API, user-facing directory, AI decision-making or crisis escalation is connected to these tables.
- Do not provision a paid database or connect the app until budget, privacy, security, identity/access, backup, retention, clinical governance and operational ownership are approved.

## Administrative verification interface — validation only

Migration 003 is designed for the disposable `wellbridge-pathway-validation` Neon database only. Apply it after migrations 001 and 002. It does not configure Entra, create application grants/RLS policies, or connect the database to Azure. The companion design is `docs/admin-verification-interface-security-design.md`. The new RLS-enabled tables intentionally have no application policies; non-owner roles remain denied until a separately reviewed access-policy migration is implemented. Never use the Neon owner connection string in application code.


## Migration 004 security validation

Migrations 004 and 005 require a pre-created PostgreSQL role named `wellbridge_app`. It must be a NOLOGIN, non-owner, non-superuser role without `BYPASSRLS`, CREATEDB, CREATEROLE or replication privileges, and it must not be a member of another role. The CI workflow creates this role in a disposable PostgreSQL 16 service, applies migrations 001–005, then runs `tests/db/migration-004-security-tests.sql`. The test script rolls back its synthetic fixtures.

The application role receives no direct write access to administrator identities, role assignments or audit records. Role grants and revocations go through narrowly scoped database functions and require an active `platform_owner`. The verifier, approver and auditor test cases exercise row visibility and separation of duties. An audit-only reviewer can inspect review/audit metadata but cannot read source-evidence rows or evidence attachments.

**Signed actor context (migration 005):** the application must resolve the authenticated Entra issuer + immutable subject using `wellbridge_resolve_admin_identity`, then sign the canonical payload `key_id|admin_uuid|issued_at_epoch_seconds|nonce_uuid` with HMAC-SHA256. It calls `wellbridge_set_actor_context` inside a transaction; PostgreSQL verifies the signature against a key in the private `wellbridge_private.actor_assertion_keys` table and binds the nonce to the current transaction. Reuse is accepted only within that transaction; a different transaction, invalid signature, inactive key or assertion older than 60 seconds is rejected. The app role cannot read the key or nonce tables. The trusted server key must be configured as `WELLBRIDGE_ACTOR_ASSERTION_SECRET_HEX` and `WELLBRIDGE_ACTOR_ASSERTION_KEY_ID`; the same secret must be provisioned into the database by an authorised DBA through a secure channel. Never commit or paste the secret into source control or chat.

The application login must be a member of the NOLOGIN `wellbridge_app` role and must not have independent access to protected tables or elevated roles. Use a separate migration-owner credential for schema changes. `withAdminDatabaseContext` provides the transaction adapter; all protected queries must run inside its callback on the same checked-out client. Existing UI/session permission checks are not a substitute for this database gate.

The SQL regression test creates a disposable test key and temporary signing helper, tests expired and forged assertions and cross-assignment review isolation, then rolls back. This is validation evidence, not a production security certification. Key rotation, nonce cleanup, DB login role provisioning, session revocation, MFA/Conditional Access, private evidence storage and independent penetration testing remain operational requirements.

Do not apply migration 005 to Azure or production. Do not use the Neon owner connection string in application code.