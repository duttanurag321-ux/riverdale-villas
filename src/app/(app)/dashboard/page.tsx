import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { inr } from "@/lib/format";
import { PageHeader, Stat, Card, btnCls } from "@/components/ui";

async function count(table: string, filter?: (q: any) => any) {
  let q: any = createClient().from(table).select("*", { count: "exact", head: true });
  if (filter) q = filter(q);
  const { count: n } = await q;
  return n ?? 0;
}

function Todo({ title, detail, href, button }: { title: string; detail?: string; href: string; button: string }) {
  return (
    <Card className="flex flex-wrap items-center justify-between gap-3 border-l-4 border-l-amber-500">
      <div><div className="font-medium">{title}</div>{detail && <div className="text-sm text-slate-500">{detail}</div>}</div>
      <Link href={href} className={btnCls}>{button}</Link>
    </Card>
  );
}

export default async function Dashboard() {
  const me = await requireMe();
  const sb = createClient();
  const first = me.full_name.split(" ")[0];
  let body: React.ReactNode;

  if (me.role === "director") {
    const [pendPay, pendUpd, overdueN, { data: opp }, { data: live }] = await Promise.all([
      count("payments", (q) => q.eq("verification", "pending")),
      count("construction_updates", (q) => q.eq("approval", "pending")),
      count("v_milestone_balances", (q) => q.eq("derived_status", "overdue")),
      sb.rpc("demand_opportunities"),
      sb.from("bookings").select("id").eq("status", "confirmed"),
    ]);
    const ids = (live ?? []).map((b: any) => b.id);
    const { data: bal } = ids.length ? await sb.from("v_booking_balances").select("net_receipts_paise, outstanding_paise, overdue_paise").in("booking_id", ids) : { data: [] as any[] };
    const sum = (k: string) => (bal ?? []).reduce((a: number, r: any) => a + Number(r[k]), 0);
    const todo = (pendPay > 0 ? 1 : 0) + (pendUpd > 0 ? 1 : 0) + ((opp ?? []).length > 0 ? 1 : 0) + (overdueN > 0 ? 1 : 0);
    body = (<>
      <h2 className="mb-2 font-medium">What needs you today</h2>
      <div className="space-y-3">
        {pendPay > 0 && <Todo title={`${pendPay} payment${pendPay > 1 ? "s" : ""} to check`} detail="Money your team says the customer paid. Check it in your bank, then confirm." href="/payments" button="Check payments" />}
        {pendUpd > 0 && <Todo title={`${pendUpd} construction update${pendUpd > 1 ? "s" : ""} to approve`} detail="Your site manager sent photos and is waiting for your OK." href="/construction/approvals" button="Look at updates" />}
        {overdueN > 0 && <Todo title={`${overdueN} payment${overdueN > 1 ? "s are" : " is"} late`} detail="The customer has not paid by the due date." href="/followups" button="See who to call" />}
        {todo === 0 && <Card className="text-sm text-slate-600">Nothing is waiting for you right now. ✓</Card>}
      </div>
      {(opp ?? []).length > 0 && (<>
        <h2 className="mb-2 mt-6 font-medium">Good time to ask these customers for money</h2>
        <div className="space-y-2">{(opp as any[]).slice(0, 5).map((o) => (
          <Card key={o.booking_id} className="flex flex-wrap items-center justify-between gap-3">
            <div><div className="font-medium">{o.customer_name} <span className="text-sm font-normal text-slate-500">· Villa {o.villa_number}</span></div><div className="text-sm text-slate-500">Suggested: ask for {inr(Number(o.suggested_paise))}</div></div>
            <Link href={`/bookings/${o.booking_id}/demand`} className={btnCls}>Ask for payment</Link></Card>))}</div>
      </>)}
      <h2 className="mb-2 mt-6 font-medium">Money at a glance</h2>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Stat label="Received so far" value={inr(sum("net_receipts_paise"))} tone="good" /><Stat label="Still to receive" value={inr(sum("outstanding_paise"))} />
        <Stat label="Late right now" value={inr(sum("overdue_paise"))} tone={sum("overdue_paise") ? "warn" : undefined} />
      </div>
    </>);
  } else if (me.role === "salesperson") {
    const [customers, bookings, tasks] = await Promise.all([count("customers"), count("bookings", (q) => q.eq("status", "confirmed")), count("follow_up_tasks", (q) => q.eq("status", "open"))]);
    body = (<div className="grid grid-cols-2 gap-3 lg:grid-cols-4"><Stat label="My customers" value={customers} /><Stat label="My confirmed bookings" value={bookings} /><Stat label="Open follow-ups" value={tasks} tone={tasks ? "warn" : undefined} /></div>);
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
