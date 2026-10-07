"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, str } from "@/lib/forms";

export async function saveTemplate(fd: FormData) {
  await requireMe(["director"]);
  const body = str(fd, "body"); if (!body) back("/settings", "error", "The message cannot be empty.");
  const { error } = await createClient().from("message_templates").update({ body, updated_at: new Date().toISOString() }).eq("kind", str(fd, "kind"));
  if (error) back("/settings", "error", friendly(error));
  back("/settings", "ok", "Message wording saved. It applies to new messages only.");
}

export async function saveSettings(fd: FormData) {
  await requireMe(["director"]);
  const days = str(fd, "reminder_days").split(",").map((x) => x.trim()).filter(Boolean).map(Number);
  if (days.length === 0 || days.length > 5 || days.some((d) => !Number.isInteger(d) || d < 1 || d > 60)) back("/settings", "error", "Reminder days: up to 5 whole numbers between 1 and 60, like 7, 2.");
  const ints = ["overdue_reminder_every_days", "overdue_reminder_max", "escalate_after_overdue_days", "retention_days"].map((k) => [k, Number(str(fd, k))] as const);
  if (ints.some(([, v]) => !Number.isInteger(v) || v < 1 || v > 365)) back("/settings", "error", "Numbers must be whole numbers between 1 and 365.");
  const rows = [{ key: "reminder_days_before", value: days }, ...ints.map(([key, value]) => ({ key, value })), { key: "customer_drafts_enabled", value: fd.get("customer_drafts_enabled") === "on" }]
    .map((r) => ({ ...r, updated_at: new Date().toISOString() }));
  const { error } = await createClient().from("system_settings").upsert(rows);
  if (error) back("/settings", "error", friendly(error));
  back("/settings", "ok", "Settings saved.");
}

export async function runChecksNow() {
  await requireMe(["director"]);
  const { data, error } = await createClient().rpc("run_daily_jobs");
  if (error) back("/settings", "error", friendly(error));
  back("/settings", "ok", `Checks finished: ${(data as any)?.notifications_created ?? 0} notification(s) and ${(data as any)?.drafts_created ?? 0} message draft(s) created.`);
}
