import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { inr } from "@/lib/format";
import { Card, PageHeader, Stat, btnGhostCls } from "@/components/ui";

export default async function Reports() {
  await requireMe(["director"]);
  const sb = createClient(); const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  const week = new Date(Date.now() - 7 * 864e5).toISOString();
  const [{ data: live }, { data: pays }, { data: ms }, { count: tasksLate }, { count: pendUpd }, { count: villasLate }, { count: pendPay }] = await Promise.all([
    sb.from("bookings").select("id").eq("status", "confirmed"),
    sb.from("payments").select("kind, amount_paise").eq("verification", "verified").gte("verified_at", week),
    sb.from("v_milestone_balances").select("amount_paise, outstanding_paise, due_date, derived_status, booking_id").not("activated_at", "is", null).in("derived_status", ["due", "upcoming", "partially_paid", "overdue"]),
    sb.from("follow_up_tasks").select("*", { count: "exact", head: true }).eq("status", "open").lt("due_date", today),
    sb.from("construction_updates").select("*", { count: "exact", head: true }).eq("approval", "pending"),
    sb.from("villas").select("*", { count: "exact", head: true }).lt("expected_completion", today).in("status", ["booked", "under_construction"]),
    sb.from("payments").select("*", { count: "exact", head: true }).eq("verification", "pending"),
  ]);
  const ids = (live ?? []).map((b: any) => b.id);
  const { data: bal } = ids.length ? await sb.from("v_booking_balances").select("contract_value_paise, net_receipts_paise, outstanding_paise, overdue_paise").in("booking_id", ids) : { data: [] as any[] };
  const sum = (rows: any[] | null, k: string) => (rows ?? []).reduce((a, r) => a + Number(r[k]), 0);
  const collected = (pays ?? []).reduce((a: number, p: any) => a + (p.kind === "receipt" ? Number(p.amount_paise) : -Number(p.amount_paise)), 0);
  const in30 = (ms ?? []).filter((m: any) => m.derived_status !== "overdue" && m.due_date <= new Date(Date.now() + 30 * 864e5).toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" }));
  return (
    <>
      <PageHeader title="Reports" subtitle="Live figures from the database (confirmed bookings only)." action={<div className="flex gap-2"><a className={btnGhostCls} href="/exports/payments">Payments (CSV)</a><a className={btnGhostCls} href="/exports/outstanding">Outstanding (CSV)</a></div>} />
      <h2 className="mb-2 font-medium">Money</h2>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Contract value" value={inr(sum(bal, "contract_value_paise"))} /><Stat label="Confirmed collections (all time)" value={inr(sum(bal, "net_receipts_paise"))} tone="good" />
        <Stat label="Outstanding on contracts" value={inr(sum(bal, "outstanding_paise"))} /><Stat label="Overdue" value={inr(sum(bal, "overdue_paise"))} tone={sum(bal, "overdue_paise") ? "warn" : undefined} />
        <Stat label="Collected in last 7 days" value={inr(collected)} tone="good" /><Stat label="Falling due in next 30 days" value={inr(sum(in30, "outstanding_paise"))} />
        <Stat label="Reported, awaiting verification" value={pendPay ?? 0} tone={pendPay ? "warn" : undefined} />
      </div>
      <h2 className="mb-2 mt-6 font-medium">Work in progress</h2>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4"><Stat label="Construction updates to approve" value={pendUpd ?? 0} tone={pendUpd ? "warn" : undefined} /><Stat label="Follow-ups overdue" value={tasksLate ?? 0} tone={tasksLate ? "warn" : undefined} /><Stat label="Villas past expected completion" value={villasLate ?? 0} tone={villasLate ? "warn" : undefined} /></div>
      <Card className="mt-6 text-xs text-slate-500">&ldquo;Scheduled&rdquo; amounts come from each booking&apos;s payment schedule; &ldquo;collected&rdquo; counts only payments you verified. A weekly summary also arrives in your notifications every Monday.</Card>
    </>
  );
}
