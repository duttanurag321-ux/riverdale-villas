import { notFound } from "next/navigation";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, inr, titleCase } from "@/lib/format";
import { Badge, Card, Field, Flash, PageHeader, Stat, Table, btnCls, btnDangerCls, btnGhostCls, inputCls } from "@/components/ui";
import { applyTemplate, cancelBooking, confirmBooking } from "../actions";

export default async function BookingDetail({ params, searchParams }: { params: { id: string }; searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe(["director", "salesperson"]);
  const sb = createClient();
  const { data: b } = await sb.from("bookings").select("*, villas(villa_number), customers(full_name, phone)").eq("id", params.id).maybeSingle();
  if (!b) notFound();
  const [{ data: ms }, { data: bal }, { data: templates }] = await Promise.all([
    sb.from("v_milestone_balances").select("*").eq("booking_id", b.id).order("seq"),
    sb.from("v_booking_balances").select("*").eq("booking_id", b.id).maybeSingle(),
    me.role === "director" && b.status === "draft" ? sb.from("payment_plan_templates").select("id, name").eq("is_active", true) : Promise.resolve({ data: [] as any[] }),
  ]);
  const rows = (ms ?? []) as any[];
  const isDir = me.role === "director";
  const tone = (s: string) => ({ paid: "green", overdue: "red", due: "amber", partially_paid: "amber", upcoming: "blue" } as Record<string, any>)[s] ?? "slate";
  return (
    <>
      <PageHeader title={`Villa ${b.villas?.villa_number} — ${b.customers?.full_name}`} subtitle={`Booked ${fmtDate(b.booking_date)} · ${b.customers?.phone}`} action={<Badge tone={b.status === "confirmed" ? "green" : b.status === "cancelled" ? "red" : "amber"}>{titleCase(b.status)}</Badge>} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Contract value" value={inr(b.contract_value_paise)} /><Stat label="Confirmed receipts" value={inr(bal?.net_receipts_paise)} tone="good" />
        <Stat label="Outstanding" value={inr(bal?.outstanding_paise)} /><Stat label="Overdue" value={inr(bal?.overdue_paise)} tone={bal?.overdue_paise ? "warn" : undefined} />
      </div>
      <h2 className="mb-2 mt-6 font-medium">Payment schedule {b.status !== "draft" && <span className="text-xs font-normal text-slate-500">(frozen for this booking)</span>}</h2>
      {rows.length === 0 ? <Card className="text-sm text-slate-600">No schedule yet.</Card> : (
        <Table head={["#", "Milestone", "Amount", "Paid", "Outstanding", "Due", "Status"]}>
          {rows.map((m) => (<tr key={m.id}><td className="px-3 py-2">{m.seq}</td><td className="px-3 py-2 font-medium">{m.name}</td><td className="px-3 py-2">{inr(m.amount_paise)}</td>
            <td className="px-3 py-2">{inr(m.paid_paise)}</td><td className="px-3 py-2">{m.activated_at ? inr(m.outstanding_paise) : "—"}</td><td className="px-3 py-2">{fmtDate(m.due_date)}</td>
            <td className="px-3 py-2"><Badge tone={tone(m.derived_status)}>{titleCase(m.derived_status)}</Badge></td></tr>))}
        </Table>)}
      {isDir && b.status === "draft" && (
        <Card className="mt-6 space-y-4">
          <form action={applyTemplate} className="flex flex-wrap items-end gap-2"><input type="hidden" name="booking_id" value={b.id} />
            <Field label={rows.length ? "Replace schedule from template" : "Create schedule from template"}><select name="template_id" className={inputCls} defaultValue=""><option value="">— select —</option>{(templates ?? []).map((t: any) => <option key={t.id} value={t.id}>{t.name}</option>)}</select></Field>
            <button className={btnGhostCls}>Apply</button></form>
          <form action={confirmBooking}><input type="hidden" name="booking_id" value={b.id} /><button className={btnCls} disabled={!rows.length}>Confirm booking</button>
            <p className="mt-1 text-xs text-slate-500">Confirming freezes the schedule and activates any payment due at booking.</p></form>
        </Card>)}
      {isDir && b.status !== "cancelled" && b.status !== "completed" && (
        <Card className="mt-4"><form action={cancelBooking} className="flex flex-wrap items-end gap-2"><input type="hidden" name="booking_id" value={b.id} />
          <Field label="Cancel this booking"><input name="reason" required placeholder="Reason (required)" className={inputCls} /></Field><button className={btnDangerCls}>Cancel booking</button></form></Card>)}
    </>
  );
}
