import { signIn } from "@/auth";

export default function AdminSignInPage() {
  return (
    <div className="container">
      <section className="hero">
        <p className="eyebrow">WELLBRIDGE AI ADMINISTRATION</p>
        <h1>Administrator sign-in</h1>
        <p className="lead">Sign in using the Microsoft account assigned a WellBridge AI administrator role.</p>
        <form
          action={async () => {
            "use server";
            await signIn("microsoft-entra-id", { redirectTo: "/admin" });
          }}
        >
          <button className="button" type="submit">Continue with Microsoft</button>
        </form>
        <p className="muted">This area is restricted to authorised administrators. Public users cannot create administrator accounts.</p>
      </section>
    </div>
  );
}
