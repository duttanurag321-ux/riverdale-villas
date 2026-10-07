"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back } from "@/lib/forms";

export async function markAllRead() {
  const me = await requireMe();
  await createClient().from("notifications").update({ read_at: new Date().toISOString() }).eq("user_id", me.id).is("read_at", null);
  back("/notifications", "ok", "All marked as read.");
}
