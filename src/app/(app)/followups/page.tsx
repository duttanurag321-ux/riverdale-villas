import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, fmtDateTime, inr } from "@/lib/format";
import { Badge, Card, Empty, Flash, PageHeader, btnCls, btnGhostCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { completeTask, logOutcome } from "./actions";

const OUTCOMES: [string, string][] = [["contacted_will_pay", "Contacted — will pay on a date"], ["contacted_more_time", "Contacted — wants more time"], ["contacted_already_paid", "Contacted — says already paid"],
  ["no_answer", "Did not answer"], ["wrong_number", "Wrong / unavailable number"], ["dispute", "Customer dispute"], ["needs_director", "Needs Director"], ["other", "Other (note required)"]];
const label = Object.fromEntries(OUTCOMES);

export default async function FollowUps({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe(["salesperson", "director"]);
  const sb = createClient();
  const { data } = await sb.from("follow_up_tasks").select("id, booking_id, milestone_id, priority, due_date, promised_date, bookings(villas(villa_number), customers(full_name, phone))").eq("status", "open").order("due_date").limit(100);
  const tasks = (data ?? []) as any[];
  const [{ data: ms }, { data: logs }] = tasks.length ? await Promise.all([
    sb.from("v_milestone_balances").select("id, name, outstanding_paise, due_date, derived_status").in("id", tasks.map((t) => t.milestone_id)),
    sb.from("follow_up_activity_logs").select("task_id, outcome, note, promised_date, created_at").in("task_id", tasks.map((t) => t.id)).order("created_at", { ascending: false }),
  ]) : [{ data: [] as any[] }, { data: [] as any[] }];
  const mm = new Map<string, any>((ms ?? []).map((m: any) => [m.id, m]));
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  return (
    <>
      <PageHeader title="Follow-ups" subtitle={`${tasks.length} open${me.role === "director" ? " (all salespeople)" : ""}`} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {tasks.length === 0 ? <Empty>No open follow-ups. They appear automatically when a payment milestone becomes payable.</Empty> : (
        <div className="space-y-3">{tasks.map((t) => {
          const m = mm.get(t.milestone_id); const c = t.bookings?.customers; const hist = (logs ?? []).filter((l: any) => l.task_id === t.id).slice(0, 3);
          const late = t.due_date < today; const wa = (c?.phone ?? "").replace(/\D/g, "");
          return (
            <Card key={t.id}>
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium">{c?.full_name}</span><span className="text-sm text-slate-500">Villa {t.bookings?.villas?.villa_number}</span>
                {t.priority === "high" && <Badge tone="red">High priority</Badge>}{late && <Badge tone="red">Follow-up overdue</Badge>}{m?.derived_status === "overdue" && <Badge tone="red">Payment overdue</Badge>}
                <span className="ml-auto text-xs text-slate-500">Follow up by {fmtDate(t.due_date)}</span></div>
              <div className="mt-2 text-sm">{m?.name}: <b>{inr(Number(m?.outstanding_paise ?? 0))}</b> remaining · payment due {fmtDate(m?.due_date)}</div>
              <div className="mt-3 flex flex-wrap gap-2">
                {c?.phone && <a className={btnCls} href={`tel:${c.phone}`}>Call</a>}
                {wa && <a className={btnGhostCls} target="_blank" rel="noreferrer" href={`https://wa.me/${wa}`}>WhatsApp</a>}
                <Link className={btnGhostCls} href={`/payments/new?booking=${t.booking_id}`}>Report payment</Link></div>
              {hist.length > 0 && <ul className="mt-3 space-y-1 text-xs text-slate-600">{hist.map((l: any, i: number) => <li key={i}>{fmtDateTime(l.created_at)} — {label[l.outcome] ?? "Marked done"}{l.promised_date ? ` (promised ${fmtDate(l.promised_date)})` : ""}{l.note ? `: ${l.note}` : ""}</li>)}</ul>}
              <form action={logOutcome} className="mt-3 grid gap-2 border-t border-slate-100 pt-3 sm:grid-cols-[1fr_9rem_1fr_auto]"><input type="hidden" name="task_id" value={t.id} />
                <select name="outcome" required defaultValue="" className={inputCls} aria-label="Call outcome"><option value="" disabled>Call outcome…</option>{OUTCOMES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
                <input name="promised" type="date" min={today} className={inputCls} aria-label="Promised payment date" title="Promised payment date" />
                <input name="note" placeholder="Note" className={inputCls} /><SubmitButton className={btnCls} pendingText="Saving…">Save</SubmitButton></form>
              <form action={completeTask} className="mt-2"><input type="hidden" name="task_id" value={t.id} /><SubmitButton className="text-xs text-slate-500 underline" pendingText="Saving…">Mark follow-up done</SubmitButton></form>
            </Card>); })}</div>)}
    </>
  );
}
