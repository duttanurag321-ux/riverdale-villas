import { getMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

// Director-only CSV exports and import templates. Values are escaped and prefixed so spreadsheet programs cannot run them as formulas.
const esc = (v: unknown) => { let s = v == null ? "" : String(v); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
const rup = (p: unknown) => (p == null ? "" : (Number(p) / 100).toFixed(2));
const LIMIT = 5000;

const TEMPLATES: Record<string, string[][]> = {
  "template-villas": [["project", "villa_number", "configuration", "plot_details", "land_area", "land_unit", "list_price_inr", "expected_completion"],
    ["Sample Project (FICTIONAL)", "S1", "2 BHK", "Plot 12", "3", "katha", "6000000", "2027-12-31"], ["Sample Project (FICTIONAL)", "S2", "2 BHK", "Plot 13", "3", "katha", "60,00,000", "2027-12-31"]],
  "template-customers": [["full_name", "phone", "alt_phone", "email", "address", "notes", "whatsapp_consent", "pan"],
    ["Sample Customer One (FICTIONAL)", "9000000001", "", "one@example.test", "Siliguri", "", "no", ""], ["Sample Customer Two (FICTIONAL)", "+91 90000 00002", "", "", "", "Prefers evening calls", "yes", ""]],
};

export async function GET(_req: Request, { params }: { params: { kind: string } }) {
  const me = await getMe();
  if (!me || me.role !== "director") return new Response("Not found", { status: 404 });
  const sb = createClient(); const k = params.kind; let rows: unknown[][] | null = TEMPLATES[k] ?? null;
  if (!rows) {
    if (k === "payments") {
      const { data } = await sb.from("payments").select("received_on, kind, amount_paise, method, reference, verification, receipt_number, customers(full_name), bookings(villas(villa_number))").order("created_at", { ascending: false }).limit(LIMIT);
      rows = [["Received on", "Villa", "Customer", "Type", "Amount (INR)", "Method", "Reference", "Status", "Receipt no."], ...(data ?? []).map((p: any) => [p.received_on, p.bookings?.villas?.villa_number, p.customers?.full_name, p.kind, rup(p.amount_paise), p.method, p.reference, p.verification, p.receipt_number])];
    } else if (k === "outstanding") {
      const { data } = await sb.from("bookings").select("id, villas(villa_number), customers(full_name, phone), contract_value_paise").eq("status", "confirmed").limit(LIMIT);
      const { data: bal } = await sb.from("v_booking_balances").select("booking_id, net_receipts_paise, outstanding_paise, overdue_paise, pending_verification_paise").in("booking_id", (data ?? []).map((b: any) => b.id));
      const m = new Map((bal ?? []).map((b: any) => [b.booking_id, b]));
      rows = [["Villa", "Customer", "Phone", "Contract value", "Confirmed receipts", "Outstanding", "Overdue", "Pending verification"], ...(data ?? []).map((b: any) => { const x: any = m.get(b.id) ?? {}; return [b.villas?.villa_number, b.customers?.full_name, b.customers?.phone, rup(b.contract_value_paise), rup(x.net_receipts_paise), rup(x.outstanding_paise), rup(x.overdue_paise), rup(x.pending_verification_paise)]; })];
    } else if (k === "villas") {
      const { data } = await sb.from("villas").select("villa_number, configuration, plot_details, land_area, land_unit, status, expected_completion, actual_completion, projects(name)").order("villa_number").limit(LIMIT);
      rows = [["Project", "Villa", "Configuration", "Plot", "Land area", "Unit", "Status", "Expected completion", "Actual completion"], ...(data ?? []).map((v: any) => [v.projects?.name, v.villa_number, v.configuration, v.plot_details, v.land_area, v.land_unit, v.status, v.expected_completion, v.actual_completion])];
    } else if (k === "customers") {
      const { data } = await sb.from("customers").select("full_name, phone, alt_phone, email, address, whatsapp_opt_in, whatsapp_opt_in_at, notes, is_archived").order("full_name").limit(LIMIT);
      rows = [["Name", "Phone", "Alt phone", "Email", "Address", "WhatsApp consent", "Consent given at", "Notes", "Archived"], ...(data ?? []).map((c: any) => [c.full_name, c.phone, c.alt_phone, c.email, c.address, c.whatsapp_opt_in, c.whatsapp_opt_in_at, c.notes, c.is_archived])];
    } else if (k === "bookings") {
      const { data } = await sb.from("bookings").select("status, booking_date, package_price_paise, extra_charges_paise, contract_value_paise, expected_handover, cancelled_at, cancel_reason, villas(villa_number), customers(full_name)").order("created_at", { ascending: false }).limit(LIMIT);
      rows = [["Villa", "Customer", "Status", "Booking date", "Package price", "Extra charges", "Contract value", "Expected handover", "Cancelled at", "Cancel reason"], ...(data ?? []).map((b: any) => [b.villas?.villa_number, b.customers?.full_name, b.status, b.booking_date, rup(b.package_price_paise), rup(b.extra_charges_paise), rup(b.contract_value_paise), b.expected_handover, b.cancelled_at, b.cancel_reason])];
    } else if (k === "milestones") {
      const { data } = await sb.from("v_milestone_balances").select("seq, name, amount_paise, paid_paise, outstanding_paise, due_date, derived_status, bookings(villas(villa_number))").order("booking_id").order("seq").limit(LIMIT);
      rows = [["Villa", "#", "Milestone", "Amount", "Paid", "Outstanding", "Due date", "Status"], ...(data ?? []).map((m: any) => [m.bookings?.villas?.villa_number, m.seq, m.name, rup(m.amount_paise), rup(m.paid_paise), rup(m.outstanding_paise), m.due_date, m.derived_status])];
    } else if (k === "allocations") {
      const { data } = await sb.from("payment_allocations").select("amount_paise, created_at, payments(receipt_number, kind), booking_payment_milestones(name)").order("created_at", { ascending: false }).limit(LIMIT);
      rows = [["Created", "Receipt no.", "Type", "Milestone", "Amount (INR)"], ...(data ?? []).map((a: any) => [a.created_at, a.payments?.receipt_number, a.payments?.kind, a.booking_payment_milestones?.name, rup(a.amount_paise)])];
    }
  }
  if (!rows) return new Response("Not found", { status: 404 });
  const csv = "\uFEFF" + rows.map((r) => r.map(esc).join(",")).join("\r\n");
  return new Response(csv, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${k}-${new Date().toISOString().slice(0, 10)}.csv"`, "Cache-Control": "private, no-store" } });
}
