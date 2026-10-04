"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, str } from "@/lib/forms";

export interface SubmitInput { villaId: string; stageId: string; status: string; remarks: string; isIssue: boolean; requestId: string; paths: string[] }
export type SubmitResult = { ok: true; id: string } | { ok: false; error: string };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function submitUpdate(i: SubmitInput): Promise<SubmitResult> {
  await requireMe(["site_manager", "director"]);
  if (!UUID.test(i.villaId) || !UUID.test(i.stageId) || !UUID.test(i.requestId)) return { ok: false, error: "Invalid request." };
  if (!["in_progress", "delayed", "completed"].includes(i.status)) return { ok: false, error: "Choose a status." };
  if (i.paths.length > 6 || i.paths.some((p) => !p.startsWith(`${i.villaId}/${i.requestId}/`) || p.includes(".."))) return { ok: false, error: "Invalid photos." };
  if (i.status === "completed" && i.paths.length === 0) return { ok: false, error: "Add at least one photo to mark a stage completed." };
  if (i.status === "delayed" && !i.remarks.trim()) return { ok: false, error: "Please say why the work is delayed." };

  const sb = createClient();
  const { data: id, error } = await sb.rpc("submit_construction_update", {
    p_villa: i.villaId, p_stage: i.stageId, p_new_status: i.status, p_remarks: i.remarks.trim() || null, p_is_issue: i.isIssue, p_request_id: i.requestId,
  });
  if (error) return { ok: false, error: friendly(error) };
  const { count } = await sb.from("construction_update_photos").select("*", { count: "exact", head: true }).eq("update_id", id);
  if (!count && i.paths.length) {
    const { error: pErr } = await sb.from("construction_update_photos").insert(i.paths.map((storage_path) => ({ update_id: id, storage_path })));
    if (pErr) return { ok: false, error: "Update saved but photos could not be linked. Tap Submit again to retry." };
  }
  return { ok: true, id: id as string };
}

export async function approveUpdate(fd: FormData) {
  await requireMe(["director"]);
  const { error } = await createClient().rpc("approve_construction_update", { p_update: str(fd, "id"), p_approve: true });
  if (error) back("/construction/approvals", "error", friendly(error));
  back("/construction/approvals", "ok", "Approved. If this stage has a payment milestone in the booking's schedule, it is now active and the Salesperson has a follow-up task.");
}

export async function rejectUpdate(fd: FormData) {
  await requireMe(["director"]);
  const { error } = await createClient().rpc("approve_construction_update", { p_update: str(fd, "id"), p_approve: false, p_reason: str(fd, "reason") });
  if (error) back("/construction/approvals", "error", friendly(error));
  back("/construction/approvals", "ok", "Update rejected. The Site Manager can submit a corrected one.");
}
