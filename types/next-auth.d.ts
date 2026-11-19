import "next-auth";

declare module "next-auth" {
  interface Session {
    user: {
      roles: string[];
      tenantId?: string;
    } & NonNullable<Session["user"]>;
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    roles?: string[];
    tenantId?: string;
  }
}
