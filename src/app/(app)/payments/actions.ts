"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";
import { back, friendly, opt, str } from "@/lib/forms";
import { rupeesToPaise } from "@/lib/format";

export async function reportPayment(fd: FormData) {
  await requireMe(["salesperson", "director"]);
  const P = "/payments/new";
  const booking = str(fd, "booking_id"); const amount = rupeesToPaise(str(fd, "amount"));
  if (!booking) back(P, "error", "Choose a booking.");
  if (!amount) back(P, "error", "Enter a valid amount in rupees.");
  if (!str(fd, "received_on")) back(P, "error", "Enter the date the money was received.");
  const { error } = await createClient().rpc("report_payment", { p_booking: booking, p_amount_paise: amount, p_method: str(fd, "method"),
    p_reference: opt(fd, "reference"), p_received_on: str(fd, "received_on"), p_notes: opt(fd, "notes"), p_request_id: opt(fd, "request_id"), p_paid_by: str(fd, "paid_by") === "bank" ? "bank" : "customer" });
  if (error) back(P, "error", friendly(error));
  back("/payments", "ok", "Payment reported. It stays Pending until the Director verifies it, and does not reduce the balance yet.");
}

export async function verifyPayment(fd: FormData) {
  await requireMe(["director"]);
  const sb = createClient(); const id = str(fd, "id"); const target = str(fd, "milestone_id");
  let allocations: { milestone_id: string; amount_paise: number }[] | null = null;
  if (target) {
    const [{ data: p }, { data: m }] = await Promise.all([sb.from("payments").select("amount_paise").eq("id", id).maybeSingle(), sb.from("v_milestone_balances").select("outstanding_paise").eq("id", target).maybeSingle()]);
    const amt = Math.min(Number(p?.amount_paise ?? 0), Number(m?.outstanding_paise ?? 0));
    if (amt <= 0) back("/payments", "error", "That milestone has nothing outstanding.");
    allocations = [{ milestone_id: target, amount_paise: amt }];
  }
  const { data, error } = await sb.rpc("verify_payment", { p_payment: id, p_allocations: allocations });
  if (error) back("/payments", "error", friendly(error));
  const left = Number((data as any)?.unallocated_paise ?? 0);
  back("/payments", "ok", `Payment verified. Receipt ${(data as any)?.receipt_number} issued.${left ? " Part of the amount is not applied to any milestone and is held as customer credit." : ""}`);
}

export async function rejectPayment(fd: FormData) {
  await requireMe(["director"]);
  const { error } = await createClient().rpc("reject_payment", { p_payment: str(fd, "id"), p_reason: str(fd, "reason") });
  if (error) back("/payments", "error", friendly(error));
  back("/payments", "ok", "Payment report rejected. It was kept on record.");
}

export async function reversePayment(fd: FormData) {
  await requireMe(["director"]);
  const { error } = await createClient().rpc("reverse_payment", { p_payment: str(fd, "id"), p_reason: str(fd, "reason") });
  if (error) back("/payments", "error", friendly(error));
  back("/payments", "ok", "Payment reversed. The original entry is kept and a reversal entry was added.");
}
