# WellBridge AI — Migration 004 access-control design and validation

**Status:** implemented on `feature/admin-verification-system`; awaiting disposable PostgreSQL CI execution. Not production approved.

## Scope

Migration 004 follows migrations 001–003. It adds explicit row-level security policies and grants for a dedicated non-owner `wellbridge_app` role, active-role helper functions, platform-owner-only role grant/revocation functions, and a guard against changing a review to an approval outcome without a corresponding decision row.

No patient, symptom, check-in, conversation or crisis-event data is introduced. No Azure deployment or production database is changed.

## Database role boundary

Before applying migration 004, create `wellbridge_app` as a non-owner, non-superuser role without `BYPASSRLS`. The CI workflow does this in an ephemeral PostgreSQL 16 service. The migration intentionally fails closed if the role is missing or privileged.

The application role receives:
- SELECT on administrator and pathway records, subject to RLS.
- INSERT/UPDATE only on workflow and pathway tables required by the current validation design.
- No direct INSERT/UPDATE/DELETE on administrator identity mappings, role assignments or audit records.
- No direct UPDATE/DELETE on audit history.
- Execute access to the narrowly scoped identity/role helper and role-grant/revocation functions.

A platform owner is required to grant or revoke administrator roles. The functions retain revoked/expired assignment history. Active duplicate grants are checked while locking the target identity row.

## RLS policy summary

| Role | Intended database access |
|---|---|
| `platform_owner` | Administrator governance, pathway maintenance, reviews, approvals and audit history |
| `pathway_administrator` | Maintain pathway records and create/assign reviews; no role governance |
| `pathway_verifier` | Read assigned workflow and pathway material, link evidence and submit verification work; cannot approve |
| `pathway_approver` | Read review material and insert independent decisions; cannot directly edit pathway records |
| `audit_reviewer` | Read audit history and permitted review context; no mutations |

The SQL test suite checks verifier visibility and denial, independent approval, pathway-administrator write access, role-grant restrictions, owner grant/revocation and auditor read-only access.

## Decision enforcement

A decision row must be inserted by the current administrator identity and that identity must hold an active `pathway_approver` or `platform_owner` role. The decision trigger rejects self-approval and requires a submitted or returned review. A scoped SECURITY DEFINER trigger updates the review status after the decision row is recorded. The decision-validation trigger also runs as SECURITY DEFINER with a fixed search path so its integrity check can lock and inspect the target review even when the approver's RLS policy does not expose that review directly. The function remains narrowly scoped to validation; it does not grant the application role general review-table access. A second trigger rejects direct transitions to `approved`, `rejected` or `changes_requested` without a matching decision record.

## Important trust-boundary limitation

The RLS helper reads the transaction-local PostgreSQL setting `app.actor_admin_id`. The trusted server must set it only after validating the Entra token (signature, issuer, audience, expiry, tenant and subject) and resolving an active `admin_identities` record. This custom setting is application-asserted context, not cryptographic proof. A party holding the application database credential with arbitrary SQL execution could attempt to set the value. The credential must remain server-side, arbitrary SQL execution must never be exposed, and a signed-context or equivalent hardened trust boundary must be designed and independently reviewed before production.

The migration deliberately does not claim protection against a database owner/superuser, a compromised trusted application process, or arbitrary SQL execution using the application credential.

## Validation

CI runs:
1. Dependency audit.
2. TypeScript, ESLint and production build checks.
3. PostgreSQL 16 service startup.
4. Creation of the restricted application role.
5. Sequential application of migrations 001, 002, 003 and 004.
6. `tests/db/migration-004-security-tests.sql`, which uses synthetic records and rolls back its transaction.

A green workflow proves the migration and listed regression cases execute in the CI disposable database. It does not certify the complete application, Entra configuration, production deployment, clinical governance or legal compliance.

## Not yet implemented

- Database-backed administrator identity resolution in the NextAuth server flow.
- Signed or otherwise hardened database actor context.
- Complete field-level workflow transition controls and application handlers.
- Private object-storage integration, malware scanning and retention enforcement.
- Independent external security review, penetration testing and production approval.
