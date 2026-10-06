import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Badge, Card, Empty, Field, Flash, PageHeader, btnCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { createTemplate } from "./actions";

export default async function Plans({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const [{ data: t }, { data: m }] = await Promise.all([sb.from("payment_plan_templates").select("id, name, villa_configuration, is_active").order("name"), sb.from("payment_plan_template_milestones").select("template_id, kind, percent_bp")]);
  const sums = new Map<string, { n: number; bp: number; pct: boolean }>();
  (m ?? []).forEach((r: any) => { const s = sums.get(r.template_id) ?? { n: 0, bp: 0, pct: false }; s.n++; s.bp += r.percent_bp ?? 0; s.pct = s.pct || r.kind === "percent"; sums.set(r.template_id, s); });
  return (
    <>
      <PageHeader title="Payment plans" subtitle="Reusable templates. A booking gets its own frozen copy when you apply one, so editing a template never changes existing customers." />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {(t ?? []).length === 0 ? <Empty>No plans yet. Create one below.</Empty> : (
        <div className="space-y-2">{(t ?? []).map((p: any) => { const s = sums.get(p.id); const ok = s && (!s.pct || s.bp === 10000); return (
          <Card key={p.id} className="flex flex-wrap items-center gap-3"><Link className="font-medium text-brand underline" href={`/plans/${p.id}`}>{p.name}</Link>
            <span className="text-sm text-slate-500">{p.villa_configuration ?? "Any configuration"} · {s?.n ?? 0} milestones{s?.pct ? ` · ${(s.bp / 100).toFixed(2)}%` : ""}</span>
            {!p.is_active && <Badge>Inactive</Badge>}{s ? (ok ? <Badge tone="green">Valid</Badge> : <Badge tone="red">Does not total 100%</Badge>) : <Badge tone="amber">Empty</Badge>}</Card>); })}</div>)}
      <h2 className="mb-2 mt-8 font-medium">Create a plan</h2>
      <Card><form action={createTemplate} className="grid gap-4 sm:grid-cols-3">
        <Field label="Plan name"><input name="name" required className={inputCls} placeholder="2 BHK standard" /></Field>
        <Field label="Villa configuration"><input name="villa_configuration" className={inputCls} placeholder="2 BHK" /></Field>
        <div className="flex items-end"><SubmitButton className={btnCls} pendingText="Creating…">Create plan</SubmitButton></div></form></Card>
    </>
  );
}
