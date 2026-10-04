"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, str } from "@/lib/forms";

function parse(fd: FormData) {
  const name = str(fd, "name"); const seq = Number(str(fd, "sequence")); const td = str(fd, "target_days");
  if (!name) back("/stages", "error", "Stage name is required.");
  if (!Number.isInteger(seq) || seq < 1) back("/stages", "error", "Order must be a whole number from 1.");
  if (td && !(Number.isInteger(Number(td)) && Number(td) >= 0)) back("/stages", "error", "Target days must be a whole number.");
  return { name, sequence: seq, target_days: td ? Number(td) : null, requires_approval: fd.get("requires_approval") === "on", is_active: fd.get("is_active") === "on", is_handover: fd.get("is_handover") === "on" };
}
export async function addStage(fd: FormData) {
  await requireMe(["director"]);
  const { error } = await createClient().from("construction_stages").insert(parse(fd));
  if (error) back("/stages", "error", error.code === "23505" ? "A stage with that name already exists." : friendly(error));
  back("/stages", "ok", "Stage added.");
}
export async function saveStage(fd: FormData) {
  await requireMe(["director"]);
  const { error } = await createClient().from("construction_stages").update(parse(fd)).eq("id", str(fd, "id"));
  if (error) back("/stages", "error", error.code === "23505" ? "A stage with that name already exists." : friendly(error));
  back("/stages", "ok", "Stage saved. Changes apply to new updates; history is not rewritten.");
}
