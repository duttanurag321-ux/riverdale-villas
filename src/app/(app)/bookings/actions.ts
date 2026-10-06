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
