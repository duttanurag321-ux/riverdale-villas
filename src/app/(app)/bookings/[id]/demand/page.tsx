import Link from "next/link";
import { notFound } from "next/navigation";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, inr } from "@/lib/format";
import { Card, Field, Flash, PageHeader, btnGhostCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { btnCls } from "@/components/ui";
import { raiseDemand } from "../../actions";

export default async function DemandPage({ params, searchParams }: { params: { id: string }; searchParams: { error?: string; update?: string; approved?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const { data: b } = await sb.from("bookings").select("id, status, contract_value_paise, villas(villa_number, id), customers(full_name)").eq("id", params.id).maybeSingle();
  if (!b || b.status !== "confirmed") notFound();
  const [{ data: sg }, { data: ups }, { data: st }] = await Promise.all([
    sb.rpc("suggest_demand", { p_booking: b.id }),
    sb.from("construction_updates").select("id, submitted_at, construction_stages(name)").eq("villa_id", (b as any).villas?.id).eq("new_status", "completed").in("approval", ["approved", "not_required"]).order("submitted_at", { ascending: false }).limit(6),
    sb.from("system_settings").select("value").eq("key", "default_demand_due_days").maybeSingle(),
  ]);
  const s: any = sg ?? {}; const contract = Number(b.contract_value_paise); const pool = Number(s.pool_paise ?? 0); const sugg = Number(s.suggested_paise ?? 0);
  const p5 = Math.floor((contract * 500) / 10000), p10 = Math.floor((contract * 1000) / 10000);
  const target = Number(s.target_paise ?? 0); const prog = Math.round(Number(s.progress_bp ?? 0) / 100); const targetPct = contract ? Math.round((target / contract) * 100) : 0;
  const updates = (ups ?? []) as any[]; const preUpdate = updates.find((u) => u.id === searchParams.update) ?? null;
  const defaultTitle = preUpdate ? `${preUpdate.construction_stages?.name} payment` : prog === 0 ? "Payment before construction starts" : "Construction payment";
  const dueDefault = Number(st?.value ?? 7); const name = (b as any).customers?.full_name;
  return (
    <>
      <PageHeader title={`Ask ${name} for a payment`} subtitle={`Villa ${(b as any).villas?.villa_number}`} />
      {searchParams.approved && <div role="status" className="mb-4 rounded-md border border-green-200 bg-green-50 px-3 py-2 text-sm text-green-800">Stage approved. Do you want to ask the customer for a payment now?</div>}
      <Flash error={searchParams.error} />
      {pool <= 0 ? <Card>There is no balance left to ask for on this booking. To change the plan, open the booking and use &ldquo;Change plan&rdquo;.</Card> : (<>
        <Card className="mb-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">Our suggestion</div>
          {sugg > 0 ? <div className="mt-1 text-lg">Ask for <b>{inr(sugg)}</b></div> : <div className="mt-1 text-lg">Nothing more is suggested right now</div>}
          <p className="mt-2 text-sm text-slate-600">{prog === 0 ? "Construction work has not been marked complete yet. " : `About ${prog}% of the construction steps are complete. `}
            By now about {targetPct}% of the price ({inr(target)}) should be received. You have received {inr(Number(s.collected_paise ?? 0))}{Number(s.open_demand_paise) > 0 ? ` and are still waiting for ${inr(Number(s.open_demand_paise))} you already asked for` : ""}.
            {sugg === 0 ? " You can still type your own amount below." : ""}</p>
          <p className="mt-1 text-xs text-slate-500">This is only a guide. You decide the amount. Balance of the price not asked for yet: {inr(pool)}.</p>
        </Card>
        <form action={raiseDemand} className="space-y-4"><input type="hidden" name="booking_id" value={b.id} /><input type="hidden" name="request_id" value={crypto.randomUUID()} />
          <Card><fieldset className="space-y-2"><legend className="mb-1 font-medium">How much?</legend>
            {sugg > 0 && <label className="flex items-center gap-2"><input type="radio" name="choice" value="suggested" defaultChecked /> Suggested: <b>{inr(sugg)}</b></label>}
            {p5 <= pool && <label className="flex items-center gap-2"><input type="radio" name="choice" value="p5" defaultChecked={sugg === 0} /> 5% of the price: {inr(p5)}</label>}
            {p10 <= pool && <label className="flex items-center gap-2"><input type="radio" name="choice" value="p10" /> 10% of the price: {inr(p10)}</label>}
            <label className="flex items-center gap-2"><input type="radio" name="choice" value="all" /> Everything that is left: {inr(pool)}</label>
            <label className="flex flex-wrap items-center gap-2"><input type="radio" name="choice" value="custom" /> My own amount:
              <input name="custom_amount" inputMode="decimal" placeholder="e.g. 500000" className={`${inputCls} w-40`} />
              <select name="custom_unit" className={`${inputCls} w-36`} defaultValue="inr"><option value="inr">rupees (₹)</option><option value="pct">% of the price</option></select></label>
          </fieldset></Card>
          <Card className="grid gap-4 sm:grid-cols-2">
            <Field label="What is this payment for?" hint="The customer will see this."><input name="title" required defaultValue={defaultTitle} className={inputCls} /></Field>
            <Field label="Pay within"><select name="due_days" defaultValue={String(dueDefault)} className={inputCls}>{[3, 7, 14, 30].map((d) => <option key={d} value={d}>{d} days</option>)}</select></Field>
            <Field label="Tell the customer about this construction update (optional)"><select name="update_id" defaultValue={preUpdate?.id ?? ""} className={inputCls}><option value="">— none —</option>
              {updates.map((u) => <option key={u.id} value={u.id}>{u.construction_stages?.name} — {fmtDate(u.submitted_at)}</option>)}</select></Field>
            <Field label="Note for your team (optional)"><input name="note" className={inputCls} /></Field>
          </Card>
          <div className="flex flex-wrap items-center gap-3"><SubmitButton className={`${btnCls} px-6 py-3 text-base`} pendingText="Sending request…">Ask for payment</SubmitButton>
            <Link href={`/bookings/${b.id}`} className={btnGhostCls}>Not now</Link></div>
        </form></>)}
    </>
  );
}
