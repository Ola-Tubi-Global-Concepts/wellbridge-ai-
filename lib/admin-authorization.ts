import "server-only";

import { auth } from "@/auth";
import {
  hasPermission,
  type AdminPermission,
} from "@/lib/admin-permissions";
import { redirect } from "next/navigation";
import {
  withAdminDatabaseContext,
  type WellBridgeDatabaseClient,
  type ResolvedDatabaseActor,
} from "@/lib/admin-database-context";

/**
 * Legacy Entra-claim gate for UI/session presentation only.
 * @deprecated Do not use this function to authorise protected database reads or writes.
 * Use withRequiredAdminDatabasePermission so current database roles and a signed
 * actor assertion are checked inside the same transaction as the protected work.
 */
export async function requireAdminPermission(permission: AdminPermission) {
  const session = await auth();

  if (!session?.user) {
    redirect("/admin-sign-in");
  }

  if (!session.user.tenantId || !session.user.roles?.length) {
    throw new Error("Forbidden: no validated administrator role is present.");
  }

  if (!hasPermission(session.user.roles, permission)) {
    throw new Error("Forbidden: insufficient administrator permission.");
  }

  return {
    userId: session.user.id,
    roles: session.user.roles,
    tenantId: session.user.tenantId,
  };
}

/**
 * Legacy session-claim separation-of-duties check for UI presentation only.
 * @deprecated Approval writes must use withRequiredAdminDatabasePermission and
 * the database decision trigger; this helper alone is not an approval control.
 */
export async function requireIndependentPathwayApproval(
  verifiedByUserId: string | null | undefined,
) {
  const actor = await requireAdminPermission("pathways:approve");

  if (!actor.userId || !verifiedByUserId) {
    throw new Error("Forbidden: pathway verification identity is incomplete.");
  }

  if (actor.userId === verifiedByUserId) {
    throw new Error("Forbidden: a verifier cannot approve their own verification.");
  }

  return actor;
}


/**
 * Database-authoritative gate for protected administrative data operations.
 * The caller must pass a checked-out server-side client and perform all work
 * inside the supplied callback. The helper opens/commits the transaction,
 * switches to wellbridge_app, resolves the immutable Entra identity, verifies
 * the signed actor assertion, and checks current database roles.
 */
export async function withRequiredAdminDatabasePermission<T>(
  client: WellBridgeDatabaseClient,
  permission: AdminPermission,
  work: (transaction: WellBridgeDatabaseClient, actor: ResolvedDatabaseActor) => Promise<T>,
): Promise<T> {
  const session = await auth();

  if (!session?.user) {
    redirect("/admin-sign-in");
  }

  if (!session.user.issuer || !session.user.id) {
    throw new Error("Forbidden: validated Entra issuer and subject are required.");
  }

  return withAdminDatabaseContext(
    client,
    { issuer: session.user.issuer, subject: session.user.id },
    permission,
    work,
  );
}
