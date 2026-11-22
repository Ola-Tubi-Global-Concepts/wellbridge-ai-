# WellBridge AI — Administrative Verification Interface Security Design

**Status:** validation-stage design and migration 003 committed; not production approved.  
**Identity decision:** Microsoft Entra workforce administrator authentication, subject to tenant capability and security configuration checks.  
**Database scope:** temporary Neon project `wellbridge-pathway-validation` only.  
**Out of scope:** patient records, check-ins, symptoms, conversations, clinical decision support, public directory and emergency dispatch.

## 1. Architecture boundary

The administrative interface is a private workforce tool. The browser authenticates through Entra. A server-side application validates the Entra token, maps the immutable identity pair (`iss` + `sub`) to `admin_identities`, checks active database role assignments, and only then accesses PostgreSQL.

- Entra authenticates administrators; WellBridge role assignments authorise application actions.
- Email address is a display/contact attribute, never the identity key.
- Do not store passwords, bearer tokens, refresh tokens, client secrets or full identity tokens in PostgreSQL.
- Never expose database credentials or direct database access to browser code.
- The public WellBridge application has no route or database role for administrative data.
- Do not connect this validation database to Azure App Service or a production workload.

## 2. Canonical roles

These identifiers are shared by `lib/admin-permissions.ts`, Entra app-role claims and the database `admin_role_assignments.role_name` constraint. Do not introduce aliases or shortened variants.

| Canonical role | Intended permissions |
|---|---|
| `platform_owner` | Govern platform, manage administrator access and role assignments, and perform all pathway and audit functions |
| `pathway_administrator` | Maintain pathway records and assign verification work |
| `pathway_verifier` | Collect sources, record direct confirmations and submit reviews |
| `pathway_approver` | Independently approve, reject or return submitted reviews |
| `audit_reviewer` | Read permitted records and audit history; no edits |

The database decision trigger accepts only `pathway_approver` or `platform_owner` for approval. A verifier must not approve their own review. High-risk records (emergency contacts, crisis lines and urgent referral routes) require independent approval and an agreed operational verification protocol.

The first platform-owner account must be bootstrapped through a separately controlled, documented administrative procedure. Do not create a publicly callable self-service owner-registration path. Record the bootstrap action in the audit trail.

## 3. Migration 003

File: `db/migrations/003_admin_verification_security.sql`

Adds administrator identity and role mapping, verification work, evidence metadata, decision history and append-only audit metadata. The migration enables RLS but intentionally creates no application policies or grants. Non-owner database roles therefore have no usable access until a separate, reviewed policy and privilege migration is designed. The Neon project owner can still administer the validation schema; do not use owner credentials in the application.

## 4. Audit identity context

Migration 005 replaces trust in a bare `app.actor_admin_id` setting with a signed HMAC actor assertion. The trusted server resolves the exact Entra issuer + immutable subject pair, signs `key_id|admin_uuid|issued_at_epoch_seconds|nonce_uuid`, and calls `wellbridge_set_actor_context` inside one transaction. PostgreSQL verifies the signature against a key stored in the private `wellbridge_private` schema and binds the nonce to the current transaction. Role helpers, review/evidence RLS and audit attribution re-verify the assertion. An unsigned or modified GUC is not an authenticated actor.

The key must be provisioned out-of-band by an authorised DBA and held in server-side secret storage. Never expose the key or database credentials to the browser. The transaction adapter is documented in `docs/migration-005-signed-actor-context.md`. This design reduces GUC spoofing risk but does not protect against compromise of the trusted server, signing key, migration owner or database superuser. Forward security logs to a separately controlled log platform and retain identity-provider sign-in logs under an approved retention policy.

## 5. Evidence file handling

- Store files only in private object storage, never public buckets or public URLs.
- Store only an opaque object key in PostgreSQL.
- Allow-list file types and enforce the 20 MiB database metadata limit in the migration; enforce size limits at upload time too.
- Scan uploads before they can be attached to a submitted review.
- Verify SHA-256 after upload and on retrieval.
- Use short-lived, authorised download links generated server-side.
- Do not upload unrelated email threads, patient data, identity documents or unnecessary personal contact details.
- Define retention, legal hold, deletion and backup expiry before production.

## 6. Entra and application controls still required

The SQL migration does not configure Entra or the web application. Before enabling administrator sign-in:

1. Configure an administrator-only Entra application and exact redirect/logout URIs.
2. Validate token signature, issuer, audience, expiry, nonce/state and authorised client/application claims server-side.
3. Use the immutable issuer + subject pair for identity mapping.
4. Require MFA for all administrators; use stronger Conditional Access for platform owners and approvers where supported.
5. Keep role authorisation in the server-side WellBridge database, not in user-editable browser state.
6. Use secure, HttpOnly, SameSite cookies; protect state-changing requests against CSRF.
7. Enforce session expiry, revocation and re-authentication for role changes and sensitive decisions.
8. Rate-limit authentication and administrative endpoints; log failed access attempts.
9. Keep Entra secrets and database credentials in managed server-side secret storage.
10. Do not expose administrative endpoints to unauthenticated users or the public application.

## 7. Database access-policy and signed-context stages

Migrations 004 and 005 implement the validation-stage grants, RLS, role governance, signed actor assertions and assignment-aware review/evidence access. Their CI coverage is not production certification. Provision a separate least-privilege login role as a member of the NOLOGIN `wellbridge_app` group; keep the migration owner separate. Every protected data route/action must use the transaction adapter and current database roles. Do not use the Neon owner connection string in application code.

## 8. Validation checklist

After applying migration 003 to the disposable Neon validation database, verify:

- All seven administrative tables exist.
- RLS is enabled on all new administrative tables and pathway tables listed in the migration.
- No application policies or grants were accidentally created.
- The decision trigger rejects self-approval.
- The decision trigger rejects users without an active `pathway_approver` or `platform_owner` role.
- A review cannot be submitted without an assignee and linked evidence source.
- A review with a pending, failed or quarantined attachment cannot be submitted.
- An approved/rejected decision updates the review state.
- Insert/update/delete operations on audited tables create audit rows.
- Direct UPDATE/DELETE against `audit_log` fails.
- No patient, symptom, check-in, conversation or crisis-event table is created.

The migration's audit actor is null when run manually in the Neon SQL Editor without application context; that is expected for schema validation.

## 9. Production gates

This validation migration is not a production security certification. Before production: complete NDPA/NDPC privacy assessment and DPIA; approve data classification, retention and deletion; establish clinical/pathway governance; appoint accountable owners; configure private evidence storage; complete threat modelling and penetration testing; verify backup/restore and incident response; review Entra tenant configuration; and independently test every RLS policy and role boundary.

No pathway becomes user-facing solely because an administrative record says `verified_active`. Separate clinical, operational and publication approval remains mandatory.
