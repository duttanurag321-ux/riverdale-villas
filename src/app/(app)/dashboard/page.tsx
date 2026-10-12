import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDateTime, inr } from "@/lib/format";
import { PageHeader, Stat, Card, btnCls } from "@/components/ui";

async function count(table: string, filter?: (q: any) => any) {
  let q: any = createClient().from(table).select("*", { count: "exact", head: true });
  if (filter) q = filter(q);
  const { count: n } = await q;
  return n ?? 0;
}

function Todo({ title, detail, href, button, soft }: { title: string; detail?: string; href: string; button: string; soft?: boolean }) {
  return (
    <Card className={`flex flex-wrap items-center justify-between gap-3 border-l-4 ${soft ? "border-l-slate-300" : "border-l-amber-500"}`}>
      <div><div className="font-medium">{title}</div>{detail && <div className="text-sm text-slate-500">{detail}</div>}</div>
      <Link href={href} className={btnCls}>{button}</Link>
    </Card>
  );
}

const TONE = { green: "border-green-300 bg-green-50 text-green-900", amber: "border-amber-300 bg-amber-50 text-amber-900", red: "border-red-300 bg-red-50 text-red-900" } as const;
const DOT = { ask: "bg-blue-500", money: "bg-green-600", report: "bg-amber-500", build: "bg-slate-500", booking: "bg-purple-500", message: "bg-teal-500" } as Record<string, string>;

function Tile({ label, value, sub }: { label: string; value: number; sub: string }) {
  return (<div className="flex-1 rounded-lg border border-slate-200 bg-white p-3 text-center"><div className="text-2xl font-semibold">{value}</div><div className="text-sm font-medium">{label}</div><div className="text-xs text-slate-500">{sub}</div></div>);
}

export default async function Dashboard() {
  const me = await requireMe();
  const sb = createClient();
  const first = me.full_name.split(" ")[0];
  let body: React.ReactNode;

  if (me.role === "director") {
    const [{ data: fo }, { data: feed }] = await Promise.all([sb.rpc("flow_overview"), sb.rpc("activity_feed", { p_limit: 12 })]);
    const f: any = fo ?? {}; const st = (f.status ?? "amber") as keyof typeof TONE;
    const needs = (f.pending_confirm > 0 ? 1 : 0) + (f.ready_to_confirm?.length ?? 0) + (f.big_asks?.length ?? 0);
    body = (<>
      <div className={`mb-6 rounded-xl border p-4 ${TONE[st]}`}>
        <div className="flex items-center gap-3"><span className={`inline-block h-3 w-3 rounded-full ${st === "green" ? "bg-green-600" : st === "amber" ? "bg-amber-500" : "bg-red-600"}`} /><div className="text-lg font-semibold">{f.headline ?? "Loading…"}</div></div>
        <div className="mt-1 text-xs opacity-80">Last automatic check: {f.last_run_at ? fmtDateTime(f.last_run_at) : "not yet"}</div>
        {(f.stuck ?? []).length > 0 && <ul className="mt-3 space-y-1 text-sm">{(f.stuck as any[]).map((s, i) => <li key={i}><b>{s.who}</b> ({s.role}): {s.text}</li>)}</ul>}
        {st === "green" && <div className="mt-1 text-sm">Site managers and salespeople are on track. Payments are being asked for and collected automatically.</div>}
      </div>

      <h2 className="mb-2 font-medium">Needs you</h2>
      <div className="space-y-3">
        {f.pending_confirm > 0 && <Todo title={`${f.pending_confirm} payment${f.pending_confirm > 1 ? "s" : ""} to confirm (${inr(Number(f.pending_confirm_paise))})`} detail="Check your bank, then confirm in one tap." href="/payments" button="Confirm payments" />}
        {(f.ready_to_confirm ?? []).map((b: any) => <Todo key={b.booking_id} title={`New booking ready: Villa ${b.villa} — ${b.customer}`} detail="Your salesperson prepared it. Open it and press Confirm." href={`/bookings/${b.booking_id}`} button="Open & confirm" />)}
        {(f.big_asks ?? []).map((b: any) => <Todo key={b.booking_id} title={`OK to ask ${b.customer} for ${inr(Number(b.suggested_paise))}?`} detail={`Villa ${b.villa}. More than the automatic limit.`} href={`/bookings/${b.booking_id}/demand`} button="Review & ask" />)}
        {needs === 0 && <Card className="text-sm text-slate-600">Nothing needs you right now. ✓</Card>}
        {f.pending_key_approvals > 0 && <Todo soft title={`${f.pending_key_approvals} key construction step${f.pending_key_approvals > 1 ? "s" : ""} waiting`} detail="They will be approved automatically if you do nothing. Look only if you want to." href="/construction/approvals" button="Take a look" />}
      </div>

      <h2 className="mb-2 mt-6 font-medium">Where every villa is</h2>
      <div className="flex items-stretch gap-2">
        <Tile label="Token / new" value={f.draft_bookings ?? 0} sub="not confirmed yet" /><div className="self-center text-slate-400">›</div>
        <Tile label="Collecting" value={f.collecting ?? 0} sub="before construction" /><div className="self-center text-slate-400">›</div>
        <Tile label="Building" value={f.building ?? 0} sub="payments as it progresses" /><div className="self-center text-slate-400">›</div>
        <Tile label="Handed over" value={f.handed_over ?? 0} sub="done" />
      </div>

      <h2 className="mb-2 mt-6 font-medium">Money this week</h2>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Stat label="Received in the last 7 days" value={inr(Number(f.received_7d ?? 0))} tone="good" /><Stat label="Asked for, waiting to be paid" value={inr(Number(f.asked_open_paise ?? 0))} />
        <Stat label="Late right now" value={inr(Number(f.overdue_paise ?? 0))} tone={Number(f.overdue_paise) ? "warn" : undefined} />
      </div>
      <p className="mt-2 text-sm text-slate-600">The system asked customers for money <b>{f.auto_asks_7d ?? 0}</b> time(s) this week ({inr(Number(f.auto_asks_amount_7d ?? 0))}) and approved <b>{f.auto_approved_7d ?? 0}</b> construction step(s) by itself.</p>

      <h2 className="mb-2 mt-6 font-medium">What just happened</h2>
      <Card>{(feed ?? []).length === 0 ? <div className="text-sm text-slate-500">Nothing yet. As your team works, you will see it here.</div> : (
        <ul className="divide-y divide-slate-100">{(feed as any[]).map((r, i) => (
          <li key={i} className="flex items-start gap-3 py-2 text-sm"><span className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${DOT[r.kind] ?? "bg-slate-400"}`} /><span className="flex-1">{r.line}</span><span className="shrink-0 text-xs text-slate-400">{fmtDateTime(r.at)}</span></li>))}</ul>)}</Card>
    </>);
  } else if (me.role === "salesperson") {
    const [customers, bookings, tasks] = await Promise.all([count("customers"), count("bookings", (q) => q.eq("status", "confirmed")), count("follow_up_tasks", (q) => q.eq("status", "open"))]);
    body = (<>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4"><Stat label="My customers" value={customers} /><Stat label="My confirmed bookings" value={bookings} /><Stat label="Open follow-ups" value={tasks} tone={tasks ? "warn" : undefined} /></div>
      <div className="mt-4 flex flex-wrap gap-2"><Link href="/followups" className={btnCls}>Today&apos;s calls</Link><Link href="/messages" className={btnCls}>Messages to send</Link><Link href="/bookings/new" className={btnCls}>Prepare a booking</Link></div>
    </>);
  } else {
    const [villas, pending] = await Promise.all([count("villas"), count("construction_updates", (q) => q.eq("approval", "pending"))]);
    body = (<>
      <div className="grid grid-cols-2 gap-3"><Stat label="Villas assigned to me" value={villas} /><Stat label="Updates awaiting approval" value={pending} /></div>
      <Link href="/construction/update" className={`${btnCls} mt-4 w-full py-4 text-base sm:w-auto`}>Update Construction</Link>
    </>);
  }
  return (
    <>
      <PageHeader title={`Welcome, ${first}`} action={me.role === "director" ? <Link href="/bookings/new" className={btnCls}>New booking</Link> : undefined} />
      {body}
    </>
  );
}
