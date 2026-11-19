import { auth, signOut } from "@/auth";

export default async function AdminHomePage() {
  const session = await auth();

  return (
    <div className="container">
      <section className="hero">
        <p className="eyebrow">RESTRICTED ADMINISTRATION</p>
        <h1>WellBridge AI verification workspace</h1>
        <p className="lead">Administrator authentication is active. No live healthcare pathway is enabled by this workspace.</p>
        <div className="notice">
          <strong>Signed-in administrator</strong>
          <p>{session?.user?.name ?? session?.user?.email ?? "Microsoft account"}</p>
          <strong>Assigned application roles</strong>
          <p>{session?.user?.roles.join(", ") || "No application roles received"}</p>
          <strong>Tenant</strong>
          <p>{session?.user?.tenantId ?? "Not available"}</p>
        </div>
        <form
          action={async () => {
            "use server";
            await signOut({ redirectTo: "/admin/sign-in" });
          }}
        >
          <button className="button secondary" type="submit">Sign out</button>
        </form>
      </section>
      <section className="cards">
        <article className="card"><h2>Pathway verification</h2><p>Review and verify evidence before any pathway can be approved.</p><p>Status: Not yet connected to persistence.</p></article>
        <article className="card"><h2>Approval controls</h2><p>Separate verifier and approver responsibilities will be enforced before production.</p><p>Status: Under development.</p></article>
        <article className="card"><h2>Audit trail</h2><p>Administrative actions must be recorded in a protected audit log.</p><p>Status: Database integration pending.</p></article>
      </section>
    </div>
  );
}
