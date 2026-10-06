import { SubmitButton } from "@/components/SubmitButton";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Card, Flash, PageHeader, btnCls, btnGhostCls, inputCls } from "@/components/ui";
import { addStage, saveStage } from "./actions";

function Row({ s }: { s?: any }) {
  return (
    <form action={s ? saveStage : addStage} className="grid items-center gap-2 border-b border-slate-100 py-2 sm:grid-cols-[4rem_1fr_6rem_auto_auto_auto_auto]">
      {s && <input type="hidden" name="id" value={s.id} />}
      <input name="sequence" type="number" min={1} defaultValue={s?.sequence} required aria-label="Order" className={inputCls} />
      <input name="name" defaultValue={s?.name} required placeholder="Stage name" aria-label="Stage name" className={inputCls} />
      <input name="target_days" type="number" min={0} defaultValue={s?.target_days ?? ""} placeholder="Target days" aria-label="Target days" className={inputCls} />
      <label className="flex items-center gap-1 text-xs"><input type="checkbox" name="requires_approval" defaultChecked={s ? s.requires_approval : true} /> Needs approval</label>
      <label className="flex items-center gap-1 text-xs"><input type="checkbox" name="is_handover" defaultChecked={s?.is_handover} /> Handover</label>
      <label className="flex items-center gap-1 text-xs"><input type="checkbox" name="is_active" defaultChecked={s ? s.is_active : true} /> Active</label>
      <SubmitButton className={s ? btnGhostCls : btnCls}>{s ? "Save" : "Add"}</SubmitButton>
    </form>
  );
}

export default async function Stages({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  await requireMe(["director"]);
  const { data } = await createClient().from("construction_stages").select("*").order("sequence").order("name");
  return (
    <>
      <PageHeader title="Construction stages" subtitle="Order, wording, approval rule and target days. Which stage triggers which payment is set in each payment plan (Phase 4)." />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <Card>
        <div className="hidden gap-2 pb-1 text-xs uppercase text-slate-500 sm:grid sm:grid-cols-[4rem_1fr_6rem_auto_auto_auto_auto]"><span>Order</span><span>Name</span><span>Target days</span><span className="col-span-4">Rules</span></div>
        {(data ?? []).map((s: any) => <Row key={s.id} s={s} />)}
        <h2 className="mb-1 mt-6 text-sm font-medium">Add a stage</h2><Row />
      </Card>
      <p className="mt-3 text-xs text-slate-500">Disabling a stage hides it from new updates but keeps all history. &ldquo;Handover&rdquo; marks the stage whose approval makes the villa Handed over.</p>
    </>
  );
}
