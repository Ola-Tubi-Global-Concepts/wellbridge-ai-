import NextAuth from "next-auth";
import MicrosoftEntraID from "next-auth/providers/microsoft-entra-id";

const tenantId = process.env.AUTH_MICROSOFT_ENTRA_ID_TENANT_ID;

if (!tenantId) {
  throw new Error("AUTH_MICROSOFT_ENTRA_ID_TENANT_ID is required.");
}

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [
    MicrosoftEntraID({
      clientId: process.env.AUTH_MICROSOFT_ENTRA_ID_ID,
      clientSecret: process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET,
      issuer: `https://login.microsoftonline.com/${tenantId}/v2.0`,
    }),
  ],
  session: { strategy: "jwt" },
  callbacks: {
    async jwt({ token, profile }) {
      if (profile) {
        const entraProfile = profile as typeof profile & {
          tid?: string;
          roles?: string[];
        };

        // Reject identities issued by a different Entra directory.
        if (entraProfile.tid !== tenantId) {
          throw new Error("Sign-in rejected: Microsoft Entra tenant mismatch.");
        }

        token.tenantId = entraProfile.tid;
        token.roles = Array.isArray(entraProfile.roles) ? entraProfile.roles : [];
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.roles = Array.isArray(token.roles) ? token.roles : [];
        session.user.tenantId = typeof token.tenantId === "string" ? token.tenantId : undefined;
      }
      return session;
    },
  },
  pages: {
    signIn: "/admin/sign-in",
  },
});
