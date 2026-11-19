# WellBridge AI — Administrative Verification Interface Security Design

**Status:** validation-stage design and migration 003 committed; not production approved.  
**Identity decision:** Microsoft Entra External ID, subject to tenant capability and security configuration checks.  
**Database scope:** temporary Neon project `wellbridge-pathway-validation` only.  
**Out of scope:** patient records, check-ins, symptoms, conversations, clinical decision support, public directory and emergency dispatch.

## 1. Architecture boundary

The administrative interface is a private workforce tool. The browser authenticates through Entra. A server-side application validates the Entra token, maps the immutable identity pair (`iss` + `sub`) to `admin_identities`, checks active database role assignments, and only then accesses PostgreSQL.

- Entra authenticates administrators; WellBridge role assignments authorise application actions.
- Email address is a display/contact attribute, never the identity key.
- Do not store passwords, bearer tokens, refresh tokens, client secrets or full identity tokens in PostgreSQL.
- Never expose database credentials or direct database access to browser code.
- The public WellBridge application has no route or database role for administrative data.
- Do not connect this validation database to Azure App Service or any production workload.

Before selecting the exact Entra application configuration, verify that the existing tenant and External ID configuration support the intended workforce-only administrator population, MFA and Conditional Access requirements. Do not assume External ID is already configured for this use merely because a tenant exists.

## 2. Roles

| Role | Intended permissions |
|---|---|
| `platform_owner` | Manage administrator access, role assignments and system configuration |
| `pathway_administrator` | Maintain pathway records and assign verification work |
| `verifier` | Collect sources, record direct confirmations and submit reviews |
| `approver` | Independently approve, reject or return submitted reviews |
| `auditor` | Read permitted records and audit history; no edits |

Use least privilege. A verifier must not approve their own review. High-risk records (emergency contacts, crisis lines and urgent referral routes) require independent approval and an agreed operational verification protocol.

The first platform-owner account must be bootstrapped through a separately controlled, documented administrative procedure. Do not create a publicly callable self-service owner-registration path. Record the bootstrap action in the audit trail.

## 3. Migration 003

File: `db/migrations/003_admin_verification_security.sql`

Adds:

- `admin_identities`: Entra issuer/subject mapping and account status.
- `admin_role_assignments`: time-bounded and revocable role assignments.
- `verification_reviews`: assigned review work, claim, priority and workflow state.
- `verification_review_evidence`: links reviews to existing evidence-source records.
- `evidence_attachments`: private object-storage metadata, hash, file type, size and malware-scan state. File bytes are not stored in PostgreSQL.
- `verification_decisions`: append-only decision history and rationale.
- `audit_log`: operation, actor context, target and changed column names; no before/after values.

Database checks enforce:
- Unique Entra issuer + subject identity mapping.
- Controlled role names and account states.
- A review must have an assignee and at least one linked evidence source before submission.
- Any attached file must pass malware scanning before submission.
- A decision can only be made on a submitted or returned review.
- The decision-maker must have an active `approver` or `platform_owner` role.
- A reviewer cannot approve their own assigned review.
- Decision records update the review workflow state.
- Audit rows cannot be updated or deleted through ordinary row operations.

The migration enables row-level security (RLS) on the new administrative tables and the pathway tables the interface will manage. It intentionally creates no application policies or grants. Non-owner database roles therefore have no usable access until a separate, reviewed policy and privilege migration is designed. The Neon project owner can still administer the validation schema; do not use owner credentials in the application.

## 4. Audit identity context

The audit trigger reads transaction-local settings `app.actor_admin_id`, `app.actor_source` and `app.request_id`. The trusted server must set these only after validating the Entra token and resolving the active administrator. It must set them transaction-locally and clear them automatically at transaction end.

The actor fields are application-asserted context, not cryptographic proof. Do not expose arbitrary SQL execution or database credentials to users. For production-grade non-repudiation, forward security logs to a separately controlled log platform and retain identity-provider sign-in logs under an approved retention policy.

The audit trigger records changed field names, not field values, to reduce the risk of copying sensitive content into audit metadata. Audit access itself must be restricted and monitored.

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

## 7. Next database stage — do not combine with migration 003

Before application use, design a separate migration for:
- explicit grants to a dedicated non-owner application database role;
- RLS policies that enforce role and record-level access;
- narrowly scoped server-side functions for sensitive workflow transitions;
- controls on role grants/revocations and the initial platform-owner bootstrap;
- a test matrix proving verifier, approver, auditor and owner isolation.

Do not solve RLS by granting broad access or using the Neon owner connection string in the application. The application role must not be able to bypass RLS, alter audit triggers, truncate audit records, or change its own privileges.

## 8. Validation checklist

After applying migration 003 to the disposable Neon validation database, verify:

- All seven administrative tables exist.
- RLS is enabled on all seven new tables and all pathway tables listed in the migration.
- No application policies or grants were accidentally created.
- The decision trigger rejects self-approval.
- The decision trigger rejects users without an active approver/platform-owner role.
- A review cannot be submitted without an assignee and linked evidence source.
- A review with a pending, failed or quarantined attachment cannot be submitted.
- An approved/rejected decision updates the review state.
- Insert/update/delete operations on audited tables create audit rows.
- Direct UPDATE/DELETE against `audit_log` fails.
- No patient, symptom, check-in, conversation or crisis-event table is created.

The migration's audit actor is null when run manually in the Neon SQL Editor without application context; that is expected for this schema-validation exercise.

## 9. Production gates

This validation migration is not a production security certification. Before production: complete NDPA/NDPC privacy assessment and DPIA; approve data classification, retention and deletion; establish clinical/pathway governance; appoint accountable owners; configure private evidence storage; complete threat modelling and penetration testing; verify backup/restore and incident response; review Entra tenant configuration; and independently test every RLS policy and role boundary.

No pathway becomes user-facing solely because an administrative record says `verified_active`. Separate clinical, operational and publication approval remains mandatory.
