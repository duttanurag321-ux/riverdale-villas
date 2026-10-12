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
  const startPct = Number(str(fd, "start_threshold_percent")); const dueDays = Number(str(fd, "default_demand_due_days"));
  if (!Number.isInteger(startPct) || startPct < 0 || startPct > 100) back("/settings", "error", "Construction start percentage must be between 0 and 100.");
  if (!Number.isInteger(dueDays) || dueDays < 1 || dueDays > 60) back("/settings", "error", "Default days to pay must be between 1 and 60.");
  const rows = [{ key: "start_threshold_percent", value: startPct }, { key: "default_demand_due_days", value: dueDays }, { key: "start_gate_enabled", value: fd.get("start_gate_enabled") === "on" }, { key: "reminder_days_before", value: days }, ...ints.map(([key, value]) => ({ key, value })), { key: "customer_drafts_enabled", value: fd.get("customer_drafts_enabled") === "on" }]
    .map((r) => ({ ...r, updated_at: new Date().toISOString() }));
  const { error } = await createClient().from("system_settings").upsert(rows);
  if (error) back("/settings", "error", friendly(error));
  back("/settings", "ok", "Settings saved.");
}

export async function saveAutopilot(fd: FormData) {
  await requireMe(["director"]);
  const hrs = Number(str(fd, "auto_approve_hours")), pct = Number(str(fd, "auto_ask_max_percent")), minR = Number(str(fd, "auto_ask_min_rupees"));
  if (!Number.isInteger(hrs) || hrs < 0 || hrs > 168) back("/settings", "error", "Waiting time must be between 0 and 168 hours (0 = never approve by itself).");
  if (!Number.isInteger(pct) || pct < 1 || pct > 100) back("/settings", "error", "The automatic limit must be between 1 and 100 percent.");
  if (!Number.isInteger(minR) || minR < 0) back("/settings", "error", "Smallest amount must be a whole number of rupees.");
  const rows = [{ key: "autopilot_enabled", value: fd.get("autopilot_enabled") === "on" }, { key: "auto_approve_hours", value: hrs }, { key: "auto_ask_max_percent", value: pct },
    { key: "auto_ask_min_rupees", value: minR }, { key: "auto_ask_pre_construction", value: fd.get("auto_ask_pre_construction") === "on" }].map((r) => ({ ...r, updated_at: new Date().toISOString() }));
  const { error } = await createClient().from("system_settings").upsert(rows);
  if (error) back("/settings", "error", friendly(error));
  back("/settings", "ok", "Autopilot settings saved.");
}

export async function runAutopilotNow() {
  await requireMe(["director"]);
  const { data, error } = await createClient().rpc("autopilot_tick");
  if (error) back("/settings", "error", friendly(error));
  back("/settings", "ok", `Autopilot ran: ${(data as any)?.auto_approved ?? 0} step(s) approved, ${(data as any)?.auto_asked ?? 0} payment request(s) made, ${(data as any)?.needs_ok ?? 0} waiting for your OK.`);
}

export async function runChecksNow() {
  await requireMe(["director"]);
  const { data, error } = await createClient().rpc("run_daily_jobs");
  if (error) back("/settings", "error", friendly(error));
  back("/settings", "ok", `Checks finished: ${(data as any)?.notifications_created ?? 0} notification(s) and ${(data as any)?.drafts_created ?? 0} message draft(s) created.`);
}
