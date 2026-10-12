import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, fmtDateTime, inr, titleCase } from "@/lib/format";
import { Badge, Card, Empty, Flash, PageHeader, Table, btnCls, btnDangerCls, btnGhostCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { rejectPayment, reversePayment, verifyMany, verifyPayment } from "./actions";

export default async function Payments({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe(["director", "salesperson"]);
  const sb = createClient(); const isDir = me.role === "director";
  const sel = "id, booking_id, kind, amount_paise, received_on, method, reference, verification, receipt_number, created_at, reverses_payment_id, purpose, paid_by, entered_by, customers(full_name), bookings(villas(villa_number))";
  const [{ data: pend }, { data: recent }] = await Promise.all([
    sb.from("payments").select(sel).eq("verification", "pending").order("created_at"),
    sb.from("payments").select(sel).eq("verification", "verified").order("created_at", { ascending: false }).limit(30),
  ]);
  const pending = (pend ?? []) as any[]; const done = (recent ?? []) as any[];
  const reversed = new Set(done.filter((p) => p.kind === "reversal").map((p) => p.reverses_payment_id));
  const open = new Map<string, any[]>();
  if (isDir && pending.length) {
    const { data: ms } = await sb.from("v_milestone_balances").select("id, booking_id, name, outstanding_paise, due_date").in("booking_id", pending.map((p) => p.booking_id)).not("activated_at", "is", null).gt("outstanding_paise", 0).eq("on_hold", false).order("due_date");
    (ms ?? []).forEach((m: any) => open.set(m.booking_id, [...(open.get(m.booking_id) ?? []), m]));
  }
  return (
    <>
      <PageHeader title="Payments" subtitle="Reported payments count only after the Director verifies them." action={<div className="flex gap-2">
        {isDir && <Link href="/plans" className={btnGhostCls}>Payment plans</Link>}<Link href="/payments/new" className={btnCls}>Report payment</Link></div>} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {isDir && pending.length > 0 && (
        <Card className="mb-6 border-l-4 border-l-brand">
          <form action={verifyMany}>
            <div className="font-medium">Confirm what arrived</div>
            <p className="text-sm text-slate-500">Look in your bank or UPI app for each line. Untick any you cannot find, then confirm.</p>
            <div className="mt-3 divide-y divide-slate-100">{pending.map((p) => (
              <label key={p.id} className="flex items-start gap-3 py-2"><input type="checkbox" name="ids" value={p.id} defaultChecked className="mt-1 h-5 w-5" />
                <span className="flex-1"><b>{p.customers?.full_name}</b> <span className="text-slate-500">· Villa {p.bookings?.villas?.villa_number}</span><br />
                  <span className="text-sm text-slate-500">{titleCase(p.method)}{p.reference ? ` · ref ${p.reference}` : " · no reference"} · {fmtDate(p.received_on)}{p.purpose === "token" ? " · token" : ""}{p.paid_by === "bank" ? " · from bank" : ""}</span></span>
                <span className="font-semibold">{inr(Number(p.amount_paise))}</span></label>))}</div>
            <SubmitButton className={`${btnCls} mt-3 px-6 py-3 text-base`} pendingText="Confirming…">Confirm selected payments</SubmitButton>
          </form></Card>)}
      <h2 className="mb-2 font-medium">{isDir ? "Awaiting verification" : "My reports awaiting verification"} ({pending.length})</h2>
      {pending.length === 0 ? <Empty>Nothing is waiting.</Empty> : (
        <details open={!isDir}><summary className={isDir ? "mb-2 cursor-pointer text-sm text-brand underline" : "hidden"}>Reject a payment, or choose which milestone it pays</summary><div className="space-y-3">{pending.map((p) => (
          <Card key={p.id}>
            <div className="flex flex-wrap items-center gap-2"><span className="font-medium">Villa {p.bookings?.villas?.villa_number} — {p.customers?.full_name}</span>
              <span className="text-lg font-semibold">{inr(Number(p.amount_paise))}</span><Badge tone="amber">Pending</Badge>{p.purpose === "token" && <Badge tone="blue">Token</Badge>}{p.paid_by === "bank" && <Badge tone="blue">From bank</Badge>}
              <span className="ml-auto text-xs text-slate-500">{titleCase(p.method)}{p.reference ? ` · ${p.reference}` : ""} · received {fmtDate(p.received_on)}</span></div>
            {isDir && (
              <div className="mt-3 flex flex-wrap items-end gap-3 border-t border-slate-100 pt-3">
                <form action={verifyPayment} className="flex flex-wrap items-end gap-2"><input type="hidden" name="id" value={p.id} />
                  <label className="text-xs">Apply to<select name="milestone_id" className={`${inputCls} mt-1 min-w-[14rem]`} defaultValue=""><option value="">Oldest due milestone first (automatic)</option>
                    {(open.get(p.booking_id) ?? []).map((m) => <option key={m.id} value={m.id}>{m.name} — {inr(Number(m.outstanding_paise))} outstanding</option>)}</select></label>
                  <SubmitButton className={btnCls} pendingText="Verifying…">Verify payment</SubmitButton></form>
                <form action={rejectPayment} className="flex flex-1 flex-wrap items-end gap-2"><input type="hidden" name="id" value={p.id} />
                  <input name="reason" required placeholder="Reason if not received" className={`${inputCls} min-w-[10rem] flex-1`} /><SubmitButton className={btnDangerCls}>Reject</SubmitButton></form>
              </div>)}
          </Card>))}</div></details>)}
      <h2 className="mb-2 mt-8 font-medium">Recent verified payments</h2>
      {done.length === 0 ? <Empty>No verified payments yet.</Empty> : (
        <Table head={["Verified", "Villa", "Customer", "Amount", "Receipt", ""]}>
          {done.map((p) => (<tr key={p.id}><td className="px-3 py-2">{fmtDateTime(p.created_at)}</td><td className="px-3 py-2">{p.bookings?.villas?.villa_number}</td><td className="px-3 py-2">{p.customers?.full_name}</td>
            <td className="px-3 py-2">{p.kind === "reversal" ? <span className="text-red-700">− {inr(Number(p.amount_paise))}</span> : inr(Number(p.amount_paise))}</td>
            <td className="px-3 py-2">{p.kind === "reversal" ? <Badge tone="red">Reversal</Badge> : reversed.has(p.id) ? <Badge tone="red">Reversed</Badge> : <a className="text-brand underline" target="_blank" href={`/receipts/${p.id}`}>{p.receipt_number}</a>}</td>
            <td className="px-3 py-2 text-right">{isDir && p.kind === "receipt" && !reversed.has(p.id) && (
              <form action={reversePayment} className="flex gap-1"><input type="hidden" name="id" value={p.id} /><input name="reason" required placeholder="Reason" className={`${inputCls} w-28`} /><SubmitButton className={btnDangerCls} pendingText="Reversing…">Reverse</SubmitButton></form>)}</td></tr>))}
        </Table>)}
    </>
  );
}
