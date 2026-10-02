import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type Role = "site_manager" | "salesperson" | "director";
export interface Me { id: string; full_name: string; role: Role }

/** Role comes from the profiles table (trusted), never from the browser. */
export async function getMe(): Promise<Me | null> {
  const sb = createClient();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return null;
  const { data } = await sb.from("profiles").select("id, full_name, role, is_active").eq("id", user.id).maybeSingle();
  if (!data || !data.is_active) return null;
  return { id: data.id, full_name: data.full_name, role: data.role as Role };
}

export async function requireMe(roles?: Role[]): Promise<Me> {
  const me = await getMe();
  if (!me) redirect("/auth/signout?reason=inactive");
  if (roles && !roles.includes(me.role)) redirect("/dashboard");
  return me;
}
