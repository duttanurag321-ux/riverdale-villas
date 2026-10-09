import Link from "next/link";
import { notFound } from "next/navigation";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, fmtDateTime, inr, titleCase } from "@/lib/format";
import { Badge, Card, Field, Flash, PageHeader, Stat, Table, btnCls, btnDangerCls, btnGhostCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { amendSchedule, applyTemplate, cancelBooking, confirmBooking, releaseConstruction, saveFunding, setHold } from "../actions";

export default async function BookingDetail({ params, searchParams }: { params: { id: string }; searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe(["director", "salesperson"]);
  const sb = createClient(); const isDir = me.role === "director";
  const { data: b } = await sb.from("bookings").select("*, villas(villa_number), customers(full_name, phone)").eq("id", params.id).maybeSingle();
  if (!b) notFound();
  const [{ data: ms }, { data: bal }, { data: templates }, { data: pays }, { data: vers }] = await Promise.all([
    sb.from("v_milestone_balances").select("*").eq("booking_id", b.id).order("seq"),
    sb.from("v_booking_balances").select("*").eq("booking_id", b.id).maybeSingle(),
    isDir && b.status === "draft" ? sb.from("payment_plan_templates").select("id, name").eq("is_active", true) : Promise.resolve({ data: [] as any[] }),
    sb.from("payments").select("id, kind, amount_paise, received_on, method, verification, receipt_number, created_at, purpose, paid_by").eq("booking_id", b.id).order("created_at", { ascending: false }),
    isDir ? sb.from("booking_schedule_versions").select("version, reason, changed_at").eq("booking_id", b.id).order("version", { ascending: false }) : Promise.resolve({ data: [] as any[] }),
  ]);
  const sgRes = isDir && b.status === "confirmed" ? await sb.rpc("suggest_demand", { p_booking: b.id }) : { data: null as any };
  const sg: any = sgRes.data; const rows = ((ms ?? []) as any[]).sort((x, y) => Number(x.is_pool) - Number(y.is_pool) || x.seq - y.seq); const future = rows.filter((m) => !m.activated_at && !m.cancelled);
  const tone = (s: string) => ({ paid: "green", overdue: "red", due: "amber", partially_paid: "amber", upcoming: "blue", on_hold: "red" } as Record<string, any>)[s] ?? "slate";
  return (
    <>
      <PageHeader title={`Villa ${b.villas?.villa_number} — ${b.customers?.full_name}`} subtitle={`Booked ${fmtDate(b.booking_date)} · ${b.customers?.phone}`}
        action={<div className="flex flex-wrap items-center gap-2"><Badge tone={b.status === "confirmed" ? "green" : b.status === "cancelled" ? "red" : "amber"}>{titleCase(b.status)}</Badge>
          {b.status !== "draft" && <a className={btnGhostCls} target="_blank" href={`/statements/${b.id}`}>Statement (PDF)</a>}
          {b.status === "confirmed" && <Link className={btnCls} href={`/payments/new?booking=${b.id}`}>Report payment</Link>}</div>} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {isDir && b.status === "draft" && <Card className="mb-4 border-l-4 border-l-brand text-sm"><b>Next step:</b> {rows.length === 0 ? "choose a payment plan below." : "when the customer is ready, press Confirm booking. Any token already received is counted towards the booking amount."}</Card>}
      {isDir && b.status === "confirmed" && sg && (
        <Card className="mb-4 flex flex-wrap items-center justify-between gap-3 border-l-4 border-l-brand">
          <div><div className="font-medium">{!sg.gate_open ? "Construction is waiting for payment" : "Construction can go on"}</div>
            <div className="text-sm text-slate-600">{!sg.gate_open ? `Construction starts after about ${Math.round(Number(sg.start_bp) / 100)}% is received (${inr(Math.floor((Number(sg.contract_value_paise) * Number(sg.start_bp)) / 10000))}). Received so far: ${inr(Number(sg.collected_paise))}.` : "Ask for a payment whenever the company needs funds."}
              {Number(sg.suggested_paise) > 0 ? ` Suggestion: ask for ${inr(Number(sg.suggested_paise))}.` : ""}</div></div>
          <Link className={btnCls} href={`/bookings/${b.id}/demand`}>Ask for payment</Link></Card>)}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Contract value" value={inr(b.contract_value_paise)} /><Stat label="Confirmed receipts" value={inr(bal?.net_receipts_paise)} tone="good" />
        <Stat label="Outstanding" value={inr(bal?.outstanding_paise)} /><Stat label="Overdue" value={inr(bal?.overdue_paise)} tone={bal?.overdue_paise ? "warn" : undefined} />
      </div>
      {Number(bal?.pending_verification_paise) > 0 && <p className="mt-2 text-sm text-amber-700">{inr(bal?.pending_verification_paise)} reported but not yet verified (not counted above).</p>}
      <h2 className="mb-2 mt-6 font-medium">Payment schedule {b.status !== "draft" && <span className="text-xs font-normal text-slate-500">(this booking&apos;s own copy)</span>}</h2>
      {rows.length === 0 ? <Card className="text-sm text-slate-600">No schedule yet.</Card> : (
        <Table head={["#", "Milestone", "Amount", "Paid", "Outstanding", "Due", "Status", ...(isDir && b.status === "confirmed" ? [""] : [])]}>
          {rows.map((m) => (<tr key={m.id}><td className="px-3 py-2">{m.seq}</td><td className="px-3 py-2 font-medium">{m.name}{m.is_pool && <div className="text-xs font-normal text-slate-500">Not asked yet. Use &ldquo;Ask for payment&rdquo; when needed.</div>}</td><td className="px-3 py-2">{inr(m.amount_paise)}</td>
            <td className="px-3 py-2">{inr(m.paid_paise)}</td><td className="px-3 py-2">{m.activated_at ? inr(m.outstanding_paise) : "—"}</td><td className="px-3 py-2">{fmtDate(m.due_date)}</td>
            <td className="px-3 py-2"><Badge tone={tone(m.derived_status)}>{titleCase(m.derived_status)}</Badge>{m.on_hold_reason && <div className="text-xs text-slate-500">{m.on_hold_reason}</div>}</td>
            {isDir && b.status === "confirmed" && <td className="px-3 py-2">{m.activated_at && !m.cancelled && (
              <form action={setHold} className="flex gap-1"><input type="hidden" name="booking_id" value={b.id} /><input type="hidden" name="milestone_id" value={m.id} /><input type="hidden" name="hold" value={String(!m.on_hold)} />
                {!m.on_hold && <input name="reason" required placeholder="Hold reason" className={`${inputCls} w-32`} />}<SubmitButton className={btnGhostCls} pendingText="Saving…">{m.on_hold ? "Release" : "Hold"}</SubmitButton></form>)}</td>}</tr>))}
        </Table>)}
      {isDir && b.status === "draft" && (
        <Card className="mt-6 space-y-4">
          <form action={applyTemplate} className="flex flex-wrap items-end gap-2"><input type="hidden" name="booking_id" value={b.id} />
            <Field label={rows.length ? "Replace schedule from template" : "Create schedule from template"}><select name="template_id" className={inputCls} defaultValue=""><option value="">— select —</option>{(templates ?? []).map((t: any) => <option key={t.id} value={t.id}>{t.name}</option>)}</select></Field>
            <SubmitButton className={btnGhostCls} pendingText="Applying…">Apply</SubmitButton></form>
          <form action={confirmBooking}><input type="hidden" name="booking_id" value={b.id} /><SubmitButton className={btnCls} disabled={!rows.length} pendingText="Confirming…">Confirm booking</SubmitButton>
            <p className="mt-1 text-xs text-slate-500">Confirming freezes the schedule and activates any payment due at booking.</p></form>
        </Card>)}
      {isDir && b.status === "confirmed" && future.length > 0 && (
        <Card className="mt-6"><h2 className="mb-1 font-medium">Amend future milestones</h2>
          <p className="mb-3 text-xs text-slate-500">Only milestones that have not become payable can change. The total must still equal the contract value. The old schedule is saved in the history.</p>
          <form action={amendSchedule} className="space-y-2"><input type="hidden" name="booking_id" value={b.id} />
            {future.map((m) => (<div key={m.id} className="grid items-end gap-2 sm:grid-cols-[1fr_10rem_8rem]"><div className="text-sm font-medium">{m.seq}. {m.name}</div>
              <label className="text-xs">Amount (₹)<input name={`amt_${m.id}`} defaultValue={String(m.amount_paise / 100)} className={`${inputCls} mt-1`} inputMode="decimal" /></label>
              <label className="text-xs">Due after (days)<input name={`due_${m.id}`} type="number" min={0} defaultValue={m.due_days} className={`${inputCls} mt-1`} /></label></div>))}
            <Field label="Reason for amendment (required)"><input name="reason" required className={inputCls} /></Field>
            <SubmitButton className={btnCls} pendingText="Amending…">Save amendment</SubmitButton></form>
          {(vers ?? []).length > 0 && <ul className="mt-3 space-y-1 text-xs text-slate-600">{(vers ?? []).map((v: any) => <li key={v.version}>Version {v.version} saved {fmtDateTime(v.changed_at)} — {v.reason}</li>)}</ul>}</Card>)}
      {isDir && b.status === "confirmed" && (
        <Card className="mt-6 space-y-4">
          <form action={releaseConstruction} className="flex flex-wrap items-center gap-3"><input type="hidden" name="booking_id" value={b.id} /><input type="hidden" name="release" value={String(!b.construction_released)} />
            <div className="text-sm"><b>Construction start:</b> {b.construction_released ? "You have allowed it to start." : sg?.gate_open ? "Open (enough payment received)." : "Locked until enough payment is received."}</div>
            <SubmitButton className={btnGhostCls} pendingText="Saving…">{b.construction_released ? "Lock again" : "Allow construction to start now"}</SubmitButton></form></Card>)}
      {(isDir || b.funding_type === "loan") && b.status !== "cancelled" && (
        <Card className="mt-4">
          {isDir ? (
            <form action={saveFunding} className="grid items-end gap-3 sm:grid-cols-4"><input type="hidden" name="booking_id" value={b.id} />
              <Field label="How will the customer pay?"><select name="funding_type" defaultValue={b.funding_type} className={inputCls}><option value="self">Own money</option><option value="loan">Bank loan</option></select></Field>
              <Field label="Bank (if loan)"><input name="loan_bank" defaultValue={b.loan_bank ?? ""} className={inputCls} /></Field>
              <Field label="Loan sanctioned (₹)"><input name="loan_sanctioned" defaultValue={b.loan_sanctioned_paise ? String(Number(b.loan_sanctioned_paise) / 100) : ""} inputMode="decimal" className={inputCls} /></Field>
              <SubmitButton className={btnGhostCls} pendingText="Saving…">Save</SubmitButton></form>
          ) : <div className="text-sm">Bank loan: {b.loan_bank ?? "—"}</div>}
          {b.funding_type === "loan" && <p className="mt-2 text-xs text-slate-500">Received from the bank so far: {inr((pays ?? []).filter((p: any) => p.paid_by === "bank" && p.verification === "verified" && p.kind === "receipt").reduce((a: number, p: any) => a + Number(p.amount_paise), 0))}. Record each loan instalment under Money, Report payment, choosing &ldquo;Bank (loan instalment)&rdquo;.</p>}
        </Card>)}
      <h2 className="mb-2 mt-6 font-medium">Payment ledger</h2>
      {(pays ?? []).length === 0 ? <Card className="text-sm text-slate-600">No payments recorded yet.</Card> : (
        <Table head={["Received", "Type", "Amount", "Method", "Status", "Receipt"]}>
          {(pays ?? []).map((p: any) => (<tr key={p.id}><td className="px-3 py-2">{fmtDate(p.received_on)}</td><td className="px-3 py-2">{p.kind === "reversal" ? "Reversal" : p.purpose === "token" ? "Token" : "Payment"}{p.paid_by === "bank" && <div className="text-xs text-slate-500">from bank loan</div>}</td>
            <td className="px-3 py-2">{inr(Number(p.amount_paise))}</td><td className="px-3 py-2">{titleCase(p.method)}</td>
            <td className="px-3 py-2"><Badge tone={p.verification === "verified" ? "green" : p.verification === "rejected" ? "red" : "amber"}>{p.verification === "pending" ? "Pending verification" : titleCase(p.verification)}</Badge></td>
            <td className="px-3 py-2">{p.kind === "receipt" && p.receipt_number ? <a className="text-brand underline" target="_blank" href={`/receipts/${p.id}`}>{p.receipt_number}</a> : "—"}</td></tr>))}
        </Table>)}
      {isDir && b.status !== "cancelled" && b.status !== "completed" && (
        <Card className="mt-6"><form action={cancelBooking} className="flex flex-wrap items-end gap-2"><input type="hidden" name="booking_id" value={b.id} />
          <Field label="Cancel this booking"><input name="reason" required placeholder="Reason (required)" className={inputCls} /></Field><SubmitButton className={btnDangerCls} pendingText="Cancelling…">Cancel booking</SubmitButton></form></Card>)}
    </>
  );
}
