"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, opt, str } from "@/lib/forms";

export async function logOutcome(fd: FormData) {
  await requireMe(["salesperson", "director"]);
  const { error } = await createClient().rpc("record_follow_up_outcome", { p_task: str(fd, "task_id"), p_outcome: str(fd, "outcome"), p_note: opt(fd, "note"), p_promised: opt(fd, "promised") });
  if (error) back("/followups", "error", friendly(error));
  back("/followups", "ok", "Call outcome saved.");
}
export async function completeTask(fd: FormData) {
  await requireMe(["salesperson", "director"]);
  const { error } = await createClient().rpc("complete_follow_up", { p_task: str(fd, "task_id"), p_note: opt(fd, "note") });
  if (error) back("/followups", "error", friendly(error));
  back("/followups", "ok", "Follow-up marked done.");
}
