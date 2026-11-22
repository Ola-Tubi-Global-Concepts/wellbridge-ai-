import NextAuth from "next-auth";
import MicrosoftEntraID from "next-auth/providers/microsoft-entra-id";

const tenantId = process.env.AUTH_MICROSOFT_ENTRA_ID_TENANT_ID;
const expectedIssuer = tenantId
  ? `https://login.microsoftonline.com/${tenantId}/v2.0`
  : undefined;

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [
    MicrosoftEntraID({
      clientId: process.env.AUTH_MICROSOFT_ENTRA_ID_ID,
      clientSecret: process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET,
      issuer: expectedIssuer,
    }),
  ],
  session: { strategy: "jwt" },
  callbacks: {
    async jwt({ token, profile }) {
      if (profile) {
        const entraProfile = profile as typeof profile & {
          tid?: string;
          roles?: string[];
          iss?: string;
        };

        // Fail closed if the workforce tenant is not configured or does not match.
        if (!tenantId || entraProfile.tid !== tenantId) {
          throw new Error("Sign-in rejected: Microsoft Entra tenant mismatch or missing tenant configuration.");
        }

        if (entraProfile.iss && entraProfile.iss !== expectedIssuer) {
          throw new Error("Sign-in rejected: Microsoft Entra issuer mismatch.");
        }

        token.tenantId = entraProfile.tid;
        token.issuer = expectedIssuer;
        token.roles = Array.isArray(entraProfile.roles) ? entraProfile.roles : [];
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        if (typeof token.sub === "string") {
          session.user.id = token.sub;
        }
        session.user.roles = Array.isArray(token.roles) ? token.roles : [];
        session.user.issuer = typeof token.issuer === "string" ? token.issuer : undefined;
        session.user.tenantId = typeof token.tenantId === "string" ? token.tenantId : undefined;
      }
      return session;
    },
  },
  pages: {
    signIn: "/admin-sign-in",
  },
});
