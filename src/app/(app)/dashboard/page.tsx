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

export default async function Dashboard() {
  const me = await requireMe();
  const sb = createClient();
  let body: React.ReactNode;

  if (me.role === "director") {
    const [villas, customers, draft, confirmed, pendingPay, pendingUpd] = await Promise.all([
      count("villas"), count("customers"), count("bookings", (q) => q.eq("status", "draft")),
      count("bookings", (q) => q.eq("status", "confirmed")), count("payments", (q) => q.eq("verification", "pending")),
      count("construction_updates", (q) => q.eq("approval", "pending")),
    ]);
    const { data: live } = await sb.from("bookings").select("id").eq("status", "confirmed");
    const ids = (live ?? []).map((b: any) => b.id);
    const { data: bal } = ids.length ? await sb.from("v_booking_balances").select("contract_value_paise, net_receipts_paise, outstanding_paise, overdue_paise").in("booking_id", ids) : { data: [] as any[] };
    const sum = (k: string) => (bal ?? []).reduce((a: number, r: any) => a + Number(r[k]), 0);
    body = (<>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Villas" value={villas} /><Stat label="Customers" value={customers} />
        <Stat label="Confirmed bookings" value={confirmed} /><Stat label="Draft bookings" value={draft} tone={draft ? "warn" : undefined} />
      </div>
      <h2 className="mb-2 mt-6 font-medium">Money (confirmed bookings)</h2>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Contract value" value={inr(sum("contract_value_paise"))} /><Stat label="Confirmed collections" value={inr(sum("net_receipts_paise"))} tone="good" />
        <Stat label="Outstanding" value={inr(sum("outstanding_paise"))} /><Stat label="Overdue" value={inr(sum("overdue_paise"))} tone={sum("overdue_paise") ? "warn" : undefined} />
      </div>
      <div className="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-4"><Stat label="Payments awaiting verification" value={pendingPay} tone={pendingPay ? "warn" : undefined} />
        <Link href="/construction/approvals"><Stat label="Construction updates to approve" value={pendingUpd} tone={pendingUpd ? "warn" : undefined} /></Link></div>
      <p className="mt-6 text-sm text-slate-500">Payment verification and follow-ups arrive in the next phases.</p>
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
      <PageHeader title={`Welcome, ${me.full_name.split(" ")[0]}`} action={me.role === "director" ? <Link href="/bookings/new" className={btnCls}>New booking</Link> : undefined} />
      {body}
    </>
  );
}
