"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, opt, str } from "@/lib/forms";
import { rupeesToPaise } from "@/lib/format";

/** "12.5" -> 1250 basis points, no floating point. */
function percentToBp(s: string): number | null {
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const [i, f = ""] = s.split("."); const bp = Number(i) * 100 + Number(f.padEnd(2, "0"));
  return bp >= 1 && bp <= 10000 ? bp : null;
}

export async function createTemplate(fd: FormData) {
  await requireMe(["director"]);
  const name = str(fd, "name"); if (!name) back("/plans", "error", "Give the plan a name.");
  const { data, error } = await createClient().from("payment_plan_templates").insert({ name, villa_configuration: opt(fd, "villa_configuration") }).select("id").single();
  if (error) back("/plans", "error", error.code === "23505" ? "A plan with that name already exists." : friendly(error));
  back(`/plans/${data!.id}`, "ok", "Plan created. Add its milestones below.");
}

export async function saveMilestone(fd: FormData) {
  await requireMe(["director"]);
  const tpl = str(fd, "template_id"); const P = `/plans/${tpl}`; const id = str(fd, "id");
  const kind = str(fd, "kind"); const trigger = str(fd, "trigger"); const seq = Number(str(fd, "seq"));
  if (!Number.isInteger(seq) || seq < 1) back(P, "error", "Order must be a whole number from 1.");
  if (!str(fd, "name")) back(P, "error", "Milestone name is required.");
  const row: Record<string, unknown> = { template_id: tpl, seq, name: str(fd, "name"), kind, trigger, stage_id: opt(fd, "stage_id"),
    due_days: Number(str(fd, "due_days") || 0), grace_days: Number(str(fd, "grace_days") || 0), notify_customer: fd.get("notify_customer") === "on", is_mandatory: fd.get("is_mandatory") === "on",
    percent_bp: null, fixed_paise: null };
  if (kind === "percent") { const bp = percentToBp(str(fd, "value")); if (!bp) back(P, "error", "Enter a percentage like 10 or 12.5."); row.percent_bp = bp; }
  else { const p = rupeesToPaise(str(fd, "value")); if (!p) back(P, "error", "Enter a fixed amount in rupees."); row.fixed_paise = p; }
  if (trigger === "stage_approved" && !row.stage_id) back(P, "error", "Choose the construction stage that triggers this payment.");
  const sb = createClient();
  const { error } = id ? await sb.from("payment_plan_template_milestones").update(row).eq("id", id) : await sb.from("payment_plan_template_milestones").insert(row);
  if (error) back(P, "error", error.code === "23505" ? "Another milestone already uses that order number." : friendly(error));
  back(P, "ok", "Milestone saved.");
}

export async function deleteMilestone(fd: FormData) {
  await requireMe(["director"]); const tpl = str(fd, "template_id");
  const { error } = await createClient().from("payment_plan_template_milestones").delete().eq("id", str(fd, "id"));
  if (error) back(`/plans/${tpl}`, "error", friendly(error));
  back(`/plans/${tpl}`, "ok", "Milestone removed from the template. Existing bookings are not affected.");
}

export async function toggleTemplate(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "id");
  const { error } = await createClient().from("payment_plan_templates").update({ is_active: str(fd, "active") === "true" }).eq("id", id);
  if (error) back(`/plans/${id}`, "error", friendly(error));
  back(`/plans/${id}`, "ok", "Plan updated.");
}
