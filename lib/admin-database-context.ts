import "server-only";

import { createHmac, randomUUID } from "node:crypto";
import {
  hasPermission,
  type AdminPermission,
  type AdminRole,
} from "@/lib/admin-permissions";

/**
 * Minimal pg-compatible transaction interface. The caller supplies a dedicated
 * checked-out database client; this module deliberately does not create pools
 * or expose connection strings.
 */
export interface WellBridgeQueryResult<Row> {
  rows: Row[];
}

export interface WellBridgeDatabaseClient {
  query<Row = Record<string, unknown>>(
    sql: string,
    values?: readonly unknown[],
  ): Promise<WellBridgeQueryResult<Row>>;
}

export interface ResolvedDatabaseActor {
  adminId: string;
  roles: AdminRole[];
}

const ROLE_NAMES: readonly AdminRole[] = [
  "platform_owner",
  "pathway_administrator",
  "pathway_verifier",
  "pathway_approver",
  "audit_reviewer",
];

function createSignedAssertion(adminId: string) {
  const keyId = process.env.WELLBRIDGE_ACTOR_ASSERTION_KEY_ID;
  const secretHex = process.env.WELLBRIDGE_ACTOR_ASSERTION_SECRET_HEX;

  if (!keyId || !/^[a-zA-Z0-9_-]{1,40}$/.test(keyId)) {
    throw new Error("WellBridge actor assertion key ID is not configured.");
  }
  if (!secretHex || !/^(?:[a-fA-F0-9]{2}){32,}$/.test(secretHex)) {
    throw new Error("WellBridge actor assertion secret must be at least 32 bytes of hex.");
  }

  const issuedAtEpoch = Math.floor(Date.now() / 1000);
  const nonce = randomUUID();
  const payload = `${keyId}|${adminId}|${issuedAtEpoch}|${nonce}`;
  const signatureHex = createHmac("sha256", Buffer.from(secretHex, "hex"))
    .update(payload, "utf8")
    .digest("hex");

  return { keyId, issuedAtEpoch, nonce, signatureHex };
}

/**
 * Establishes an authenticated administrator context inside one transaction.
 *
 * The caller must pass a server-validated Entra issuer and immutable subject
 * from the Auth.js session. The database resolves that pair, then verifies a
 * short-lived HMAC assertion. The callback must perform all protected queries
 * on this same client/transaction. Never accept issuer, subject or admin ID
 * from browser request parameters.
 */
export async function withAdminDatabaseContext<T>(
  client: WellBridgeDatabaseClient,
  identity: { issuer: string; subject: string },
  permission: AdminPermission,
  work: (
    transaction: WellBridgeDatabaseClient,
    actor: ResolvedDatabaseActor,
  ) => Promise<T>,
): Promise<T> {
  if (!identity.issuer || !identity.subject) {
    throw new Error("A validated Entra issuer and subject are required.");
  }

  await client.query("BEGIN");
  try {
    // The login role must be a member of this NOLOGIN, non-owner group role.
    await client.query("SET LOCAL ROLE wellbridge_app");

    const identityResult = await client.query<{ admin_id: string | null }>(
      "SELECT public.wellbridge_resolve_admin_identity($1, $2) AS admin_id",
      [identity.issuer, identity.subject],
    );
    const adminId = identityResult.rows[0]?.admin_id;
    if (!adminId) {
      throw new Error("Administrator identity is inactive or not provisioned.");
    }

    const assertion = createSignedAssertion(adminId);
    await client.query(
      "SELECT public.wellbridge_set_actor_context($1, $2, $3, $4, $5)",
      [
        adminId,
        assertion.keyId,
        assertion.issuedAtEpoch,
        assertion.nonce,
        assertion.signatureHex,
      ],
    );

    const roleResult = await client.query<Record<AdminRole, boolean>>(
      `SELECT
        public.wellbridge_has_role('platform_owner') AS platform_owner,
        public.wellbridge_has_role('pathway_administrator') AS pathway_administrator,
        public.wellbridge_has_role('pathway_verifier') AS pathway_verifier,
        public.wellbridge_has_role('pathway_approver') AS pathway_approver,
        public.wellbridge_has_role('audit_reviewer') AS audit_reviewer`,
    );
    const roleRow = roleResult.rows[0];
    const roles = ROLE_NAMES.filter((role) => roleRow?.[role] === true);

    if (!hasPermission(roles, permission)) {
      throw new Error("Forbidden: insufficient active WellBridge database role.");
    }

    const result = await work(client, { adminId, roles });
    await client.query("COMMIT");
    return result;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // Preserve the original failure; the caller should discard a broken client.
    }
    throw error;
  }
}
