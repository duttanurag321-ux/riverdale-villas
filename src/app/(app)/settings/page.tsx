import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Card, Field, Flash, PageHeader, btnCls, btnGhostCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { runChecksNow, saveSettings, saveTemplate } from "./actions";

const FREE_DB = 500 * 1024 * 1024, FREE_STORAGE = 1024 * 1024 * 1024;
const mb = (b: number) => (b / 1048576).toFixed(1) + " MB";

function Meter({ label, used, limit }: { label: string; used: number; limit: number }) {
  const pct = Math.min(100, (used / limit) * 100);
  return (<div><div className="flex justify-between text-sm"><span>{label}</span><span>{mb(used)} of {mb(limit)} ({pct.toFixed(1)}%)</span></div>
    <div className="mt-1 h-2 overflow-hidden rounded bg-slate-200"><div className={`h-full ${pct > 80 ? "bg-red-600" : pct > 60 ? "bg-amber-500" : "bg-moss"}`} style={{ width: `${pct}%` }} /></div>
    {pct > 60 && <p className="mt-1 text-xs text-amber-700">Getting full. Consider lowering the retention days below or upgrading before it fills.</p>}</div>);
}

export default async function Settings({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const [{ data: st }, { data: tpl }, { data: usage }] = await Promise.all([sb.from("system_settings").select("key, value"), sb.from("message_templates").select("kind, title, body").order("title"), sb.rpc("usage_stats")]);
  const S: Record<string, any> = Object.fromEntries((st ?? []).map((r: any) => [r.key, r.value])); const u: any = usage ?? {};
  return (
    <>
      <PageHeader title="Settings" />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <h2 className="mb-2 font-medium">Free-plan usage</h2>
      <Card className="space-y-4">
        <Meter label="Database" used={Number(u.db_bytes ?? 0)} limit={FREE_DB} /><Meter label="Photo storage" used={Number(u.storage_bytes ?? 0)} limit={FREE_STORAGE} />
        <p className="text-xs text-slate-500">Rows: {u.notifications ?? 0} notifications · {u.drafts ?? 0} message drafts · {u.events ?? 0} events · {u.audit_rows ?? 0} audit entries · {u.payments ?? 0} payments. {Number(u.failed_events) > 0 && <b className="text-red-700">{u.failed_events} event(s) failed — press &ldquo;Run checks now&rdquo;; if they keep failing, check the message wording below.</b>}</p>
        <p className="text-xs text-slate-500">Limits shown are Supabase&apos;s free plan as I know it; confirm current limits in your Supabase dashboard (Settings, Usage). This system uses no Edge Functions, no Realtime and no paid services.</p>
      </Card>
      <h2 className="mb-2 mt-8 font-medium">Reminders and clean-up</h2>
      <Card><form action={saveSettings} className="grid gap-4 sm:grid-cols-2">
        <Field label="Remind before due date (days, comma separated)" hint="Example: 7, 2"><input name="reminder_days" defaultValue={(S.reminder_days_before ?? [7, 2]).join(", ")} className={inputCls} /></Field>
        <Field label="Repeat overdue reminder every (days)"><input name="overdue_reminder_every_days" type="number" min={1} defaultValue={S.overdue_reminder_every_days ?? 7} className={inputCls} /></Field>
        <Field label="Maximum overdue reminders per payment"><input name="overdue_reminder_max" type="number" min={1} defaultValue={S.overdue_reminder_max ?? 4} className={inputCls} /></Field>
        <Field label="Alert Director after payment overdue (days)"><input name="escalate_after_overdue_days" type="number" min={1} defaultValue={S.escalate_after_overdue_days ?? 5} className={inputCls} /></Field>
        <Field label="Delete handled messages and old alerts after (days)" hint="Keeps the free database small."><input name="retention_days" type="number" min={1} defaultValue={S.retention_days ?? 90} className={inputCls} /></Field>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="customer_drafts_enabled" defaultChecked={S.customer_drafts_enabled !== false} />Prepare customer WhatsApp messages</label>
        <div className="sm:col-span-2 flex flex-wrap gap-2"><SubmitButton className={btnCls} pendingText="Saving…">Save settings</SubmitButton></div></form>
        <form action={runChecksNow} className="mt-3 border-t border-slate-100 pt-3"><SubmitButton className={btnGhostCls} pendingText="Running…">Run checks now</SubmitButton>
          <span className="ml-2 text-xs text-slate-500">Reminders normally run by themselves every morning (about 9:00). Use this to test, or if automatic runs are not set up yet.</span></form></Card>
      <h2 className="mb-2 mt-8 font-medium">Customer message wording</h2>
      <p className="mb-2 text-xs text-slate-500">Words in double curly brackets, like {"{{customer_name}}"}, are filled in automatically. Keep them as they are.</p>
      <div className="space-y-3">{(tpl ?? []).map((t: any) => (
        <Card key={t.kind}><form action={saveTemplate} className="space-y-2"><input type="hidden" name="kind" value={t.kind} /><div className="text-sm font-medium">{t.title}</div>
          <textarea name="body" rows={8} defaultValue={t.body} className={`${inputCls} font-mono text-xs`} /><SubmitButton className={btnGhostCls} pendingText="Saving…">Save wording</SubmitButton></form></Card>))}</div>
    </>
  );
}
