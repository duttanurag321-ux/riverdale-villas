import { getMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Pdf, pdfDate, pdfMoney, pdfResponse } from "@/lib/pdf";

// Regenerated on demand from the ledger, so downloading again never creates a second payment.
// Only VERIFIED receipts get a PDF; access is enforced by the database (RLS) for the logged-in user.
export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const me = await getMe();
  if (!me || me.role === "site_manager") return new Response("Not found", { status: 404 });
  const sb = createClient();
  const { data: p } = await sb.from("payments").select("id, amount_paise, received_on, method, reference, receipt_number, verified_at, kind, verification, booking_id, customers(full_name), bookings(villas(villa_number))").eq("id", params.id).maybeSingle();
  if (!p || p.kind !== "receipt" || p.verification !== "verified" || !p.receipt_number) return new Response("No verified receipt exists for this payment.", { status: 404 });
  const [{ data: al }, { data: bal }, { data: rev }] = await Promise.all([
    sb.from("payment_allocations").select("amount_paise, booking_payment_milestones(name)").eq("payment_id", p.id),
    sb.from("v_booking_balances").select("contract_value_paise, net_receipts_paise, outstanding_paise").eq("booking_id", p.booking_id).maybeSingle(),
    sb.from("payments").select("id").eq("reverses_payment_id", p.id).maybeSingle(),
  ]);
  const d = await Pdf.create();
  d.text("Riverdale Villas", { size: 20, bold: true }); d.text("Siliguri, West Bengal", { gap: 14 });
  d.text("PAYMENT RECEIPT", { size: 14, bold: true, gap: 8 });
  if (rev) d.text("*** THIS PAYMENT HAS BEEN REVERSED - NOT VALID ***", { bold: true });
  d.rule();
  d.row([{ t: "Receipt no.", x: 50, bold: true }, { t: p.receipt_number, x: 170 }]);
  d.row([{ t: "Verified on", x: 50, bold: true }, { t: pdfDate(p.verified_at), x: 170 }]);
  d.row([{ t: "Received from", x: 50, bold: true }, { t: (p as any).customers?.full_name ?? "-", x: 170 }]);
  d.row([{ t: "Villa", x: 50, bold: true }, { t: (p as any).bookings?.villas?.villa_number ?? "-", x: 170 }]);
  d.row([{ t: "Date received", x: 50, bold: true }, { t: pdfDate(p.received_on), x: 170 }]);
  d.row([{ t: "Method", x: 50, bold: true }, { t: p.method.replace("_", " ") + (p.reference ? ` (ref ${p.reference})` : ""), x: 170 }]);
  d.row([{ t: "Amount received", x: 50, bold: true }, { t: pdfMoney(Number(p.amount_paise)), x: 170, bold: true }], 12);
  d.rule();
  d.text("Applied against", { bold: true });
  if (!al?.length) d.text("Not yet applied to a milestone (held as customer credit).");
  (al ?? []).forEach((a: any) => d.row([{ t: a.booking_payment_milestones?.name ?? "-", x: 60 }, { t: pdfMoney(Number(a.amount_paise)), x: 330 }]));
  d.space(6); d.rule();
  if (bal) {
    d.row([{ t: "Contract value", x: 50 }, { t: pdfMoney(Number(bal.contract_value_paise)), x: 330 }]);
    d.row([{ t: "Total confirmed receipts to date", x: 50 }, { t: pdfMoney(Number(bal.net_receipts_paise)), x: 330 }]);
    d.row([{ t: "Balance outstanding on contract", x: 50, bold: true }, { t: pdfMoney(Number(bal.outstanding_paise)), x: 330, bold: true }]);
  }
  d.space(18);
  d.text("Issued after verification of the payment by the Director. This is a computer-generated receipt.", { size: 8 });
  return pdfResponse(await d.bytes(), `receipt-${p.receipt_number.replace(/\//g, "-")}.pdf`);
}
