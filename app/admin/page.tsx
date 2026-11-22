import { auth, signOut } from "@/auth";
import { hasPermission } from "@/lib/admin-permissions";

export default async function AdminHomePage() {
  const session = await auth();
  const roles = session?.user?.roles ?? [];

  const canManagePathways = hasPermission(roles, "pathways:manage");
  const canVerifyPathways = hasPermission(roles, "pathways:verify");
  const canApprovePathways = hasPermission(roles, "pathways:approve");
  const canReviewAudit = hasPermission(roles, "audit:read");
  const canManageRoles = hasPermission(roles, "roles:manage");

  return (
    <div className="container">
      <section className="hero">
        <p className="eyebrow">RESTRICTED ADMINISTRATION</p>
        <h1>WellBridge AI verification workspace</h1>
        <p className="lead">
          Administrator authentication is active. No live healthcare pathway is
          enabled by this workspace.
        </p>
        <div className="notice">
          <strong>Signed-in administrator</strong>
          <p>{session?.user?.name ?? session?.user?.email ?? "Microsoft account"}</p>
          <strong>Entra sign-in role claims (display only)</strong>
          <p>{roles.join(", ") || "No application roles received"}</p>
          <p>Database-backed WellBridge roles will be authoritative for protected records and actions when the database connection is provisioned.</p>
          <strong>Tenant</strong>
          <p>{session?.user?.tenantId ?? "Not available"}</p>
        </div>
        <form
          action={async () => {
            "use server";
            await signOut({ redirectTo: "/admin-sign-in" });
          }}
        >
          <button className="button secondary" type="submit">Sign out</button>
        </form>
      </section>

      <section className="cards">
        {canManagePathways && (
          <article className="card">
            <h2>Pathway administration</h2>
            <p>Create and maintain candidate healthcare pathway records and supporting evidence.</p>
            <p>Status: Not yet connected to persistence.</p>
          </article>
        )}
        {canVerifyPathways && (
          <article className="card">
            <h2>Pathway verification</h2>
            <p>Examine source evidence and record a verification assessment.</p>
            <p>Status: Verification workflow under development.</p>
          </article>
        )}
        {canApprovePathways && (
          <article className="card">
            <h2>Approval controls</h2>
            <p>Approve or reject eligible pathways only after independent verification.</p>
            <p>Status: Approval workflow under development.</p>
          </article>
        )}
        {canReviewAudit && (
          <article className="card">
            <h2>Audit review</h2>
            <p>Review protected records of administrative actions. This role is read-only.</p>
            <p>Status: Audit database integration pending.</p>
          </article>
        )}
        {canManageRoles && (
          <article className="card">
            <h2>Role and governance management</h2>
            <p>Manage administrator access and platform governance controls.</p>
            <p>Status: Role-management workflow under development.</p>
          </article>
        )}
      </section>
    </div>
  );
}
