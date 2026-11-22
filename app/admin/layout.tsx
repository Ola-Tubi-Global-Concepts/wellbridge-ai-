import { auth } from "@/auth";
import { hasAdminAccess } from "@/lib/admin-permissions";
import { redirect } from "next/navigation";

export default async function AdminLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const session = await auth();

  if (!session?.user) {
    redirect("/admin-sign-in");
  }

  if (!hasAdminAccess(session.user.roles)) {
    return (
      <div className="container">
        <section className="notice">
          <h1>Administrator access required</h1>
          <p>
            Your account is signed in, but it does not have an enabled WellBridge AI
            administrator role.
          </p>
          <p>
            Access is denied by default. Contact the Platform Owner if you believe
            this is an error.
          </p>
        </section>
      </div>
    );
  }

  return <>{children}</>;
}
