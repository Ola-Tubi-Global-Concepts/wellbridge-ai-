export const ADMIN_ROLES = [
  "platform_owner",
  "pathway_administrator",
  "pathway_verifier",
  "pathway_approver",
  "audit_reviewer",
] as const;

export type AdminRole = (typeof ADMIN_ROLES)[number];

export type AdminPermission =
  | "platform:govern"
  | "roles:manage"
  | "pathways:manage"
  | "pathways:verify"
  | "pathways:approve"
  | "audit:read";

const ROLE_PERMISSIONS: Record<AdminRole, readonly AdminPermission[]> = {
  platform_owner: [
    "platform:govern",
    "roles:manage",
    "pathways:manage",
    "pathways:verify",
    "pathways:approve",
    "audit:read",
  ],
  pathway_administrator: ["pathways:manage"],
  pathway_verifier: ["pathways:verify"],
  pathway_approver: ["pathways:approve"],
  audit_reviewer: ["audit:read"],
};

export function isAdminRole(value: string): value is AdminRole {
  return ADMIN_ROLES.some((role) => role === value);
}

export function getAdminRoles(roles: readonly string[] | undefined): AdminRole[] {
  return (roles ?? []).filter(isAdminRole);
}

export function hasAdminAccess(roles: readonly string[] | undefined): boolean {
  return getAdminRoles(roles).length > 0;
}

export function hasPermission(
  roles: readonly string[] | undefined,
  permission: AdminPermission,
): boolean {
  return getAdminRoles(roles).some((role) =>
    ROLE_PERMISSIONS[role].includes(permission),
  );
}

/**
 * Separation-of-duties guard for approval actions.
 * Call this from the server-side approval handler with trusted IDs loaded
 * from the database. Never trust actor or verifier IDs supplied by a client.
 */
export function canApproveVerifiedPathway(input: {
  roles: readonly string[] | undefined;
  actorId: string;
  verifiedByUserId: string | null;
}): boolean {
  return (
    hasPermission(input.roles, "pathways:approve") &&
    Boolean(input.actorId) &&
    Boolean(input.verifiedByUserId) &&
    input.actorId !== input.verifiedByUserId
  );
}
