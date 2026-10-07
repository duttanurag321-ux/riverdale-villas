"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, str } from "@/lib/forms";

export async function handleMessage(fd: FormData) {
  await requireMe(["salesperson", "director"]);
  const { error } = await createClient().rpc("handle_message", { p_id: str(fd, "id"), p_action: str(fd, "action") });
  if (error) back("/messages", "error", friendly(error));
  back("/messages", "ok", str(fd, "action") === "sent" ? "Marked as sent." : "Skipped.");
}
