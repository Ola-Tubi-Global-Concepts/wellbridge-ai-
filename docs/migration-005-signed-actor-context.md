# Migration 005 — signed administrator actor context

**Status:** feature-branch implementation; CI validation pending. Not approved for Neon, production or Azure.

## Threat addressed

PostgreSQL custom GUCs such as `app.actor_admin_id` are mutable by a session. They are therefore not proof of identity. Migration 005 no longer authorises a database actor merely because an administrator UUID appears in a GUC.

## Assertion protocol

The trusted Next.js server first receives an Auth.js session created by the Microsoft Entra provider. The provider is configured for one tenant and the expected v2 issuer. The server uses the validated issuer and immutable subject pair to call `wellbridge_resolve_admin_identity`; email is not an identity key.

The server signs this exact UTF-8 payload with HMAC-SHA256:

```text
key_id|admin_uuid|issued_at_epoch_seconds|nonce_uuid
```

It then calls `wellbridge_set_actor_context` inside an open database transaction. PostgreSQL verifies the HMAC using a key in the private `wellbridge_private.actor_assertion_keys` table. The assertion must be within 60 seconds of database time. Its nonce is recorded with the current transaction ID. The same assertion may be checked repeatedly inside that transaction, but a later transaction cannot reuse the nonce.

A direct `SET app.actor_admin_id` without a matching signature does not authenticate. Role helpers and review/evidence RLS call the signed-assertion verifier; audit attribution obtains the actor from the same verified helper.

## Key provisioning

Generate at least 32 random bytes using an approved secret-generation facility, for example `openssl rand -hex 32`. Do not put the result in source control, an issue, a chat transcript or a client bundle.

An authorised DBA provisions the key using a protected SQL session:

```sql
INSERT INTO wellbridge_private.actor_assertion_keys (key_id, secret)
VALUES ('wellbridge-hmac-2026-01', decode('<64-or-more-hex-characters>', 'hex'));
```

Configure the exact same values in the trusted server secret store:

- `WELLBRIDGE_ACTOR_ASSERTION_KEY_ID`
- `WELLBRIDGE_ACTOR_ASSERTION_SECRET_HEX`

Do not place the key in a public build variable. Rotate by adding a new key ID, deploying the server with the new key, then deactivating the old key after all old sessions/transactions have expired. The application role cannot read or alter the key table.

## Transaction integration

Use `withAdminDatabaseContext` (or `withRequiredAdminDatabasePermission`) with a dedicated checked-out PostgreSQL client. It begins a transaction, switches to `wellbridge_app`, resolves the Entra identity, sets the signed context, checks active database roles, invokes the protected callback and commits. Any error rolls back.

All protected SQL for one request must execute through the callback on that same transaction/client. Never take an administrator ID, issuer or subject from request JSON, query parameters or client-side state. The caller must release/discard the database client using the pool's normal lifecycle after the helper returns.

The database login role must be a separate least-privilege login that is granted membership in the NOLOGIN `wellbridge_app` group role. The login must not own protected objects or have independent broad grants. Schema migrations must use a separate migration-owner credential. Do not use the Neon owner credential for application traffic.

## RLS model

- A verifier can read and link evidence only for reviews assigned to that verifier.
- A pathway administrator and platform owner can manage the operational review queue.
- An approver can read reviews in the submitted/decision lifecycle for independent approval.
- An audit reviewer can read permitted review and audit metadata, without mutation rights.
- Review evidence and attachment reads inherit the parent review visibility.
- Evidence insertion requires the actor to be authorised to read the parent review.

## Validation coverage

The disposable PostgreSQL CI suite applies migrations 001–005 and exercises the existing role-governance tests plus:
- unsigned actor-GUC spoofing rejection;
- expired signed assertion rejection;
- replay of a nonce bound to another transaction is rejected;
- verifier visibility limited to assigned reviews;
- assignment changes reject suspended identities and accounts without an active verifier role;
- the final active platform-owner role cannot be revoked;
- approval by a distinct approver;
- role grant/revocation restrictions and audit immutability.

Nonce records are intentionally retained beyond the 60-second assertion window to prevent replay. A DBA maintenance task may purge records older than an approved retention interval (at least 24 hours). Do not grant nonce-table DELETE to the application role.

The latest feature-branch CI run also validates the non-login application-role ownership checks, including protected schema, table and function ownership.

## Remaining production gates

This implementation does not itself provision a database connection pool, database login role, signing secret or Entra application configuration. It provides a server-only transaction adapter that must be used by every protected administrative data route/action. Existing session-role UI checks alone are insufficient.

Before production:
1. provision and test the dedicated login/group-role membership using separate credentials;
2. configure and rotate the HMAC key in managed secret storage;
3. integrate every protected route/action with the database transaction wrapper;
4. add session revocation/re-authentication controls and MFA/Conditional Access;
5. implement private evidence object storage, malware scanning, retention and deletion;
6. run independent penetration testing and a privacy/security review;
7. obtain explicit approval before applying migrations to a real database.

No production data or public healthcare pathway is enabled by this migration.
