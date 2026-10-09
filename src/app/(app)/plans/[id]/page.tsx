import Link from "next/link";
import { notFound } from "next/navigation";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Badge, Card, Flash, PageHeader, btnCls, btnDangerCls, btnGhostCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { deleteMilestone, saveMilestone, toggleTemplate } from "../actions";

function Row({ tpl, stages, m, nextSeq }: { tpl: string; stages: any[]; m?: any; nextSeq?: number }) {
  const val = m ? (m.kind === "percent" ? String(m.percent_bp / 100) : String(m.fixed_paise / 100)) : "";
  return (
    <form action={saveMilestone} className="grid items-end gap-2 border-b border-slate-100 py-3 sm:grid-cols-6">
      <input type="hidden" name="template_id" value={tpl} />{m && <input type="hidden" name="id" value={m.id} />}
      <label className="text-xs">Order<input name="seq" type="number" min={1} required defaultValue={m?.seq ?? nextSeq} className={`${inputCls} mt-1`} /></label>
      <label className="text-xs sm:col-span-2">Milestone name<input name="name" required defaultValue={m?.name} className={`${inputCls} mt-1`} placeholder="Foundation completed" /></label>
      <label className="text-xs">Type<select name="kind" defaultValue={m?.kind ?? "percent"} className={`${inputCls} mt-1`}><option value="percent">Percent</option><option value="fixed">Fixed ₹</option></select></label>
      <label className="text-xs">Value (% or ₹)<input name="value" required defaultValue={val} className={`${inputCls} mt-1`} inputMode="decimal" /></label>
      <label className="text-xs">Becomes payable on<select name="trigger" defaultValue={m?.trigger ?? "stage_approved"} className={`${inputCls} mt-1`}><option value="booking_confirmed">Booking confirmed</option><option value="stage_approved">Stage approved</option><option value="manual">Manual only</option></select></label>
      <label className="text-xs sm:col-span-2">Construction stage<select name="stage_id" defaultValue={m?.stage_id ?? ""} className={`${inputCls} mt-1`}><option value="">— none —</option>{stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
      <label className="text-xs">Due after (days)<input name="due_days" type="number" min={0} defaultValue={m?.due_days ?? 7} className={`${inputCls} mt-1`} /></label>
      <label className="text-xs">Grace (days)<input name="grace_days" type="number" min={0} defaultValue={m?.grace_days ?? 0} className={`${inputCls} mt-1`} /></label>
      <div className="flex flex-wrap items-center gap-3 text-xs"><label className="flex items-center gap-1"><input type="checkbox" name="notify_customer" defaultChecked={m ? m.notify_customer : true} />Notify customer</label>
        <label className="flex items-center gap-1"><input type="checkbox" name="is_mandatory" defaultChecked={m ? m.is_mandatory : true} />Mandatory</label>
        <label className="flex items-center gap-1"><input type="checkbox" name="is_pool" defaultChecked={m?.is_pool} />Balance asked for later, as needed</label></div>
      <div className="flex gap-2"><SubmitButton className={m ? btnGhostCls : btnCls} pendingText="Saving…">{m ? "Save" : "Add milestone"}</SubmitButton></div>
    </form>
  );
}

export default async function PlanDetail({ params, searchParams }: { params: { id: string }; searchParams: { ok?: string; error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const { data: t } = await sb.from("payment_plan_templates").select("*").eq("id", params.id).maybeSingle();
  if (!t) notFound();
  const [{ data: ms }, { data: st }] = await Promise.all([
    sb.from("payment_plan_template_milestones").select("*").eq("template_id", t.id).order("seq"),
    sb.from("construction_stages").select("id, name").eq("is_active", true).order("sequence")]);
  const rows = (ms ?? []) as any[]; const pct = rows.filter((r) => r.kind === "percent"); const fixed = rows.filter((r) => r.kind === "fixed");
  const bp = pct.reduce((a, r) => a + r.percent_bp, 0);
  const msg = rows.length === 0 ? "No milestones yet." : pct.length && fixed.length ? "Mixed percent and fixed milestones: use one type only." : pct.length && bp !== 10000 ? `Percentages total ${(bp / 100).toFixed(2)}% — must be exactly 100% before this plan can be used.` : "Plan is valid.";
  const ok = msg === "Plan is valid.";
  return (
    <>
      <PageHeader title={t.name} subtitle={t.villa_configuration ?? undefined} action={<div className="flex gap-2"><Link href="/plans" className={btnGhostCls}>All plans</Link>
        <form action={toggleTemplate}><input type="hidden" name="id" value={t.id} /><input type="hidden" name="active" value={String(!t.is_active)} /><SubmitButton className={btnGhostCls}>{t.is_active ? "Deactivate" : "Activate"}</SubmitButton></form></div>} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <Card className="mb-4"><Badge tone={ok ? "green" : "red"}>{ok ? "Valid" : "Needs attention"}</Badge> <span className="ml-2 text-sm">{msg}</span>
        <p className="mt-1 text-xs text-slate-500">Percentage amounts are rounded down to the paisa; any leftover paise go to the last milestone so the total is exact. Fixed-amount plans are checked against the contract value when applied to a booking.</p></Card>
      <Card>{rows.map((m) => (<div key={m.id}><Row tpl={t.id} stages={st ?? []} m={m} />
        <form action={deleteMilestone} className="-mt-2 mb-2"><input type="hidden" name="template_id" value={t.id} /><input type="hidden" name="id" value={m.id} /><SubmitButton className={`${btnDangerCls} !py-1 text-xs`} pendingText="Removing…">Remove milestone</SubmitButton></form></div>))}
        <h2 className="mb-1 mt-4 text-sm font-medium">Add milestone</h2><Row tpl={t.id} stages={st ?? []} nextSeq={rows.length + 1} /></Card>
    </>
  );
}
