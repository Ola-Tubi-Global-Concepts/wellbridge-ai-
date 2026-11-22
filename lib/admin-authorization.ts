import "server-only";

import { auth } from "@/auth";
import {
  hasPermission,
  type AdminPermission,
} from "@/lib/admin-permissions";
import { redirect } from "next/navigation";

/**
 * Server-side permission gate for Route Handlers and Server Actions.
 * Do not rely on conditional rendering in the admin UI as an access control.
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
 * Approval gate. The caller MUST load verifiedByUserId from the persisted
 * pathway record on the server before calling this function. Never pass an
 * actor ID or verifier ID supplied by a browser request.
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
