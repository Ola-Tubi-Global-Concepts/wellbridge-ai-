import NextAuth from "next-auth";
import MicrosoftEntraID from "next-auth/providers/microsoft-entra-id";

const tenantId = process.env.AUTH_MICROSOFT_ENTRA_ID_TENANT_ID;

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [
    MicrosoftEntraID({
      clientId: process.env.AUTH_MICROSOFT_ENTRA_ID_ID,
      clientSecret: process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET,
      issuer: tenantId
        ? `https://login.microsoftonline.com/${tenantId}/v2.0`
        : undefined,
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

        // Fail closed if the workforce tenant is not configured or does not match.
        if (!tenantId || entraProfile.tid !== tenantId) {
          throw new Error("Sign-in rejected: Microsoft Entra tenant mismatch or missing tenant configuration.");
        }

        token.tenantId = entraProfile.tid;
        token.roles = Array.isArray(entraProfile.roles) ? entraProfile.roles : [];
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.id = typeof token.sub === "string" ? token.sub : undefined;
        session.user.roles = Array.isArray(token.roles) ? token.roles : [];
        session.user.tenantId = typeof token.tenantId === "string" ? token.tenantId : undefined;
      }
      return session;
    },
  },
  pages: {
    signIn: "/admin-sign-in",
  },
});
