import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type Role = "site_manager" | "salesperson" | "director";
export interface Me { id: string; full_name: string; role: Role }

/** Role comes from the profiles table (trusted), never from the browser.
 *  cache() = looked up ONCE per page request even though layout and page both ask for it (this was doubling the wait). */
export const getMe = cache(async (): Promise<Me | null> => {
  const sb = createClient();
  const { data: claims } = await sb.auth.getClaims();   // verifies the login token locally when possible: no extra network trip
  const uid = claims?.claims?.sub;
  if (!uid) return null;
  const { data } = await sb.from("profiles").select("id, full_name, role, is_active").eq("id", uid).maybeSingle();
  if (!data || !data.is_active) return null;
  return { id: data.id, full_name: data.full_name, role: data.role as Role };
});

export async function requireMe(roles?: Role[]): Promise<Me> {
  const me = await getMe();
  if (!me) redirect("/auth/signout?reason=inactive");
  if (roles && !roles.includes(me.role)) redirect("/dashboard");
  return me;
}
