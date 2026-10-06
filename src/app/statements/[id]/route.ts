import { getMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Pdf, pdfDate, pdfMoney, pdfResponse } from "@/lib/pdf";

// Customer payment statement for one booking: schedule + full ledger. Pending items are clearly marked as not receipts.
export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const me = await getMe();
  if (!me || me.role === "site_manager") return new Response("Not found", { status: 404 });
  const sb = createClient();
  const { data: b } = await sb.from("bookings").select("id, status, booking_date, contract_value_paise, villas(villa_number), customers(full_name)").eq("id", params.id).maybeSingle();
  if (!b) return new Response("Not found", { status: 404 });
  const [{ data: ms }, { data: pays }, { data: bal }] = await Promise.all([
    sb.from("v_milestone_balances").select("seq, name, amount_paise, paid_paise, outstanding_paise, due_date, derived_status, activated_at").eq("booking_id", b.id).order("seq"),
    sb.from("payments").select("kind, amount_paise, received_on, method, verification, receipt_number").eq("booking_id", b.id).order("created_at"),
    sb.from("v_booking_balances").select("net_receipts_paise, outstanding_paise, pending_verification_paise, overdue_paise").eq("booking_id", b.id).maybeSingle(),
  ]);
  const d = await Pdf.create();
  d.text("Riverdale Villas", { size: 20, bold: true }); d.text("PAYMENT STATEMENT", { size: 14, bold: true, gap: 8 }); d.rule();
  d.row([{ t: "Customer", x: 50, bold: true }, { t: (b as any).customers?.full_name ?? "-", x: 150 }]);
  d.row([{ t: "Villa", x: 50, bold: true }, { t: (b as any).villas?.villa_number ?? "-", x: 150 }]);
  d.row([{ t: "Booking date", x: 50, bold: true }, { t: pdfDate(b.booking_date), x: 150 }]);
  d.row([{ t: "Statement date", x: 50, bold: true }, { t: pdfDate(new Date().toISOString()), x: 150 }]);
  d.row([{ t: "Contract value", x: 50, bold: true }, { t: pdfMoney(Number(b.contract_value_paise)), x: 150 }]);
  d.row([{ t: "Confirmed receipts", x: 50, bold: true }, { t: pdfMoney(Number(bal?.net_receipts_paise ?? 0)), x: 150 }]);
  d.row([{ t: "Outstanding", x: 50, bold: true }, { t: pdfMoney(Number(bal?.outstanding_paise ?? b.contract_value_paise)), x: 150, bold: true }], 11);
  d.space(8); d.text("Payment schedule", { bold: true, size: 11 });
  d.row([{ t: "#", x: 50, bold: true }, { t: "Milestone", x: 70, bold: true }, { t: "Amount", x: 230, bold: true }, { t: "Paid", x: 320, bold: true }, { t: "Due on", x: 410, bold: true }, { t: "Status", x: 480, bold: true }]);
  (ms ?? []).forEach((m: any) => d.row([{ t: String(m.seq), x: 50 }, { t: m.name, x: 70 }, { t: pdfMoney(Number(m.amount_paise)), x: 230 }, { t: pdfMoney(Number(m.paid_paise)), x: 320 }, { t: m.due_date ? pdfDate(m.due_date) : "-", x: 410 }, { t: m.derived_status.replace("_", " "), x: 480 }]));
  d.space(8); d.text("Payment ledger", { bold: true, size: 11 });
  d.row([{ t: "Date", x: 50, bold: true }, { t: "Type", x: 130, bold: true }, { t: "Amount", x: 200, bold: true }, { t: "Status", x: 300, bold: true }, { t: "Receipt no.", x: 420, bold: true }]);
  if (!pays?.length) d.text("No payments recorded.");
  (pays ?? []).forEach((p: any) => d.row([{ t: pdfDate(p.received_on), x: 50 }, { t: p.kind === "reversal" ? "Reversal" : "Payment", x: 130 }, { t: pdfMoney(Number(p.amount_paise)), x: 200 },
    { t: p.verification === "pending" ? "PENDING - not a receipt" : p.verification, x: 300 }, { t: p.receipt_number ?? "-", x: 420 }]));
  d.space(12); d.text("Only verified payments reduce the outstanding balance. Computer-generated statement.", { size: 8 });
  return pdfResponse(await d.bytes(), `statement-villa-${(b as any).villas?.villa_number ?? "x"}.pdf`);
}
