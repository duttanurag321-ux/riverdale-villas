"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, opt, str } from "@/lib/forms";
import { rupeesToPaise } from "@/lib/format";

export async function createBooking(fd: FormData) {
  await requireMe(["director"]);
  const sb = createClient(); const P = "/bookings/new";
  const villa = str(fd, "villa_id"), customer = str(fd, "customer_id"), template = str(fd, "template_id");
  if (!villa || !customer) back(P, "error", "Choose a villa and a customer.");
  const price = rupeesToPaise(str(fd, "price")); if (!price) back(P, "error", "Enter a valid package price in rupees.");
  const extraRaw = str(fd, "extra"); let extra = 0;
  if (extraRaw && extraRaw !== "0") { const e = rupeesToPaise(extraRaw); if (!e) back(P, "error", "Extra charges are not valid."); extra = e!; }

  const { data: b, error } = await sb.from("bookings").insert({
    villa_id: villa, customer_id: customer, salesperson_id: opt(fd, "salesperson_id"), package_price_paise: price, extra_charges_paise: extra,
    booking_date: str(fd, "booking_date") || undefined, expected_start: opt(fd, "expected_start"), expected_handover: opt(fd, "expected_handover"), notes: opt(fd, "notes"),
  }).select("id").single();
  if (error) back(P, "error", error.code === "23505" ? "This villa already has a live booking." : friendly(error));
  if (template) {
    const { error: e2 } = await sb.rpc("create_booking_schedule", { p_booking: b!.id, p_template: template });
    if (e2) back(`/bookings/${b!.id}`, "error", "Booking saved as a draft, but the payment schedule failed: " + friendly(e2));
  }
  const tokenRaw = str(fd, "token_amount");
  if (tokenRaw) {
    const t = rupeesToPaise(tokenRaw);
    if (!t) back(`/bookings/${b!.id}`, "error", "Booking saved, but the token amount was not a valid number. Record it from Money, Report payment.");
    const { error: e3 } = await sb.rpc("report_payment", { p_booking: b!.id, p_amount_paise: t, p_method: str(fd, "token_method") || "upi", p_reference: opt(fd, "token_reference"), p_received_on: str(fd, "token_date") || new Date().toISOString().slice(0, 10), p_notes: "Token", p_request_id: null });
    if (e3) back(`/bookings/${b!.id}`, "error", "Booking saved, but the token could not be recorded: " + friendly(e3));
    back(`/bookings/${b!.id}`, "ok", "Booking started and the token is recorded. Check it under Money, then confirm the booking when the customer is ready.");
  }
  back(`/bookings/${b!.id}`, "ok", "Draft booking created. Review the payment schedule, then confirm.");
}

export async function applyTemplate(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "booking_id"); const P = `/bookings/${id}`;
  const t = str(fd, "template_id"); if (!t) back(P, "error", "Choose a payment plan template.");
  const { error } = await createClient().rpc("create_booking_schedule", { p_booking: id, p_template: t });
  if (error) back(P, "error", friendly(error)); back(P, "ok", "Payment schedule created from the template.");
}

export async function confirmBooking(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "booking_id"); const P = `/bookings/${id}`;
  const { error } = await createClient().rpc("confirm_booking", { p_booking: id });
  if (error) back(P, "error", friendly(error)); back(P, "ok", "Booking confirmed. The booking-time payment milestone is now active.");
}

export async function cancelBooking(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "booking_id"); const P = `/bookings/${id}`;
  const { error } = await createClient().rpc("cancel_booking", { p_booking: id, p_reason: str(fd, "reason") });
  if (error) back(P, "error", friendly(error)); back(P, "ok", "Booking cancelled. Its history has been kept.");
}

export async function amendSchedule(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "booking_id"); const P = `/bookings/${id}`;
  const changes: { milestone_id: string; amount_paise: number; due_days?: number }[] = [];
  for (const [k, v] of fd.entries()) {
    if (!k.startsWith("amt_")) continue;
    const mid = k.slice(4); const paise = rupeesToPaise(String(v));
    if (!paise) back(P, "error", "Every amount must be a valid number of rupees.");
    const due = str(fd, "due_" + mid);
    changes.push({ milestone_id: mid, amount_paise: paise!, ...(due !== "" ? { due_days: Number(due) } : {}) });
  }
  if (!changes.length) back(P, "error", "There are no future milestones to amend.");
  const { error } = await createClient().rpc("amend_booking_schedule", { p_booking: id, p_changes: changes, p_reason: str(fd, "reason") });
  if (error) back(P, "error", friendly(error));
  back(P, "ok", "Schedule amended. The previous schedule has been saved in the history.");
}

export async function setHold(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "booking_id"); const hold = str(fd, "hold") === "true";
  const { error } = await createClient().rpc("set_milestone_hold", { p_milestone: str(fd, "milestone_id"), p_hold: hold, p_reason: opt(fd, "reason") });
  if (error) back(`/bookings/${id}`, "error", friendly(error));
  back(`/bookings/${id}`, "ok", hold ? "Milestone put on hold." : "Hold removed.");
}

/** "12.5" -> 1250 basis points of the price, without floating point. */
function pctToBp(s: string): number | null {
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const [i, f = ""] = s.split("."); const bp = Number(i) * 100 + Number(f.padEnd(2, "0"));
  return bp >= 1 && bp <= 10000 ? bp : null;
}

export async function raiseDemand(fd: FormData) {
  await requireMe(["director"]);
  const sb = createClient(); const id = str(fd, "booking_id"); const P = `/bookings/${id}/demand`;
  const { data: b } = await sb.from("bookings").select("contract_value_paise, villas(villa_number), customers(full_name)").eq("id", id).maybeSingle();
  const { data: sg } = await sb.rpc("suggest_demand", { p_booking: id });
  if (!b || !sg) back(`/bookings/${id}`, "error", "Could not load this booking.");
  const contract = Number((b as any).contract_value_paise); const pool = Number((sg as any).pool_paise); const suggested = Number((sg as any).suggested_paise);
  const choice = str(fd, "choice"); let amount = 0;
  if (choice === "suggested") amount = suggested;
  else if (choice === "p5") amount = Math.floor((contract * 500) / 10000);
  else if (choice === "p10") amount = Math.floor((contract * 1000) / 10000);
  else if (choice === "all") amount = pool;
  else if (choice === "custom") {
    const raw = str(fd, "custom_amount").replace(/[,\s₹]/g, "");
    if (str(fd, "custom_unit") === "pct") { const bp = pctToBp(raw); if (!bp) back(P, "error", "Type a percentage like 10 or 12.5."); amount = Math.floor((contract * bp!) / 10000); }
    else { const p = rupeesToPaise(raw); if (!p) back(P, "error", "Type the amount in rupees, like 500000."); amount = p!; }
  }
  if (!(amount > 0)) back(P, "error", "Choose how much to ask for.");
  const title = str(fd, "title"); if (!title) back(P, "error", "Write what this payment is for.");
  const upd = str(fd, "update_id") || null;
  const { error } = await sb.rpc("raise_demand", { p_booking: id, p_amount_paise: amount, p_title: title, p_due_days: Number(str(fd, "due_days") || 7), p_update: upd, p_note: opt(fd, "note"), p_suggested_paise: suggested || null, p_request_id: opt(fd, "request_id") });
  if (error) back(P, "error", friendly(error));
  back(`/bookings/${id}`, "ok", "Done. The payment is now requested. Your salesperson has a call task, and a WhatsApp message for the customer is ready under Messages.");
}

export async function saveFunding(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "booking_id"); const P = `/bookings/${id}`;
  const type = str(fd, "funding_type") === "loan" ? "loan" : "self";
  let sanctioned: number | null = null;
  if (type === "loan" && str(fd, "loan_sanctioned")) { sanctioned = rupeesToPaise(str(fd, "loan_sanctioned")); if (!sanctioned) back(P, "error", "Loan amount must be a number of rupees."); }
  const { error } = await createClient().from("bookings").update({ funding_type: type, loan_bank: type === "loan" ? opt(fd, "loan_bank") : null, loan_sanctioned_paise: type === "loan" ? sanctioned : null }).eq("id", id);
  if (error) back(P, "error", friendly(error));
  back(P, "ok", "Payment route saved.");
}

export async function releaseConstruction(fd: FormData) {
  await requireMe(["director"]); const id = str(fd, "booking_id"); const release = str(fd, "release") === "true";
  const { error } = await createClient().rpc("release_construction", { p_booking: id, p_release: release });
  if (error) back(`/bookings/${id}`, "error", friendly(error));
  back(`/bookings/${id}`, "ok", release ? "Construction is allowed to start." : "Construction is locked again until the payment condition is met.");
}
