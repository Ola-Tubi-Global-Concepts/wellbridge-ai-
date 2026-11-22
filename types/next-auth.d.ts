import "next-auth";
import type { DefaultSession } from "next-auth";

declare module "next-auth" {
  interface Session {
    user: Omit<DefaultSession["user"], "id"> & {
      id?: string;
      roles: string[];
      tenantId?: string;
    };
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    roles?: string[];
    tenantId?: string;
  }
}
