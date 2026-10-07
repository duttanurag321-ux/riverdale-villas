import { getMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

// Director-only CSV exports. The values are escaped and prefixed so spreadsheet programs cannot run them as formulas.
const esc = (v: unknown) => { let s = v == null ? "" : String(v); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
const rup = (p: unknown) => (Number(p) / 100).toFixed(2);

export async function GET(_req: Request, { params }: { params: { kind: string } }) {
  const me = await getMe();
  if (!me || me.role !== "director") return new Response("Not found", { status: 404 });
  const sb = createClient(); let rows: unknown[][] = [];
  if (params.kind === "payments") {
    const { data } = await sb.from("payments").select("received_on, kind, amount_paise, method, reference, verification, receipt_number, customers(full_name), bookings(villas(villa_number))").order("created_at", { ascending: false }).limit(5000);
    rows = [["Received on", "Villa", "Customer", "Type", "Amount (INR)", "Method", "Reference", "Status", "Receipt no."], ...(data ?? []).map((p: any) => [p.received_on, p.bookings?.villas?.villa_number, p.customers?.full_name, p.kind, rup(p.amount_paise), p.method, p.reference, p.verification, p.receipt_number])];
  } else if (params.kind === "outstanding") {
    const { data } = await sb.from("bookings").select("id, villas(villa_number), customers(full_name, phone), contract_value_paise").eq("status", "confirmed").limit(5000);
    const { data: bal } = await sb.from("v_booking_balances").select("booking_id, net_receipts_paise, outstanding_paise, overdue_paise, pending_verification_paise").in("booking_id", (data ?? []).map((b: any) => b.id));
    const m = new Map((bal ?? []).map((b: any) => [b.booking_id, b]));
    rows = [["Villa", "Customer", "Phone", "Contract value", "Confirmed receipts", "Outstanding", "Overdue", "Pending verification"], ...(data ?? []).map((b: any) => { const x: any = m.get(b.id) ?? {}; return [b.villas?.villa_number, b.customers?.full_name, b.customers?.phone, rup(b.contract_value_paise), rup(x.net_receipts_paise), rup(x.outstanding_paise), rup(x.overdue_paise), rup(x.pending_verification_paise)]; })];
  } else return new Response("Not found", { status: 404 });
  const csv = "\uFEFF" + rows.map((r) => r.map(esc).join(",")).join("\r\n");
  return new Response(csv, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${params.kind}-${new Date().toISOString().slice(0, 10)}.csv"`, "Cache-Control": "private, no-store" } });
}
