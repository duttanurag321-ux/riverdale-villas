import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDateTime, titleCase } from "@/lib/format";
import { Badge, Card, Empty, Flash, PageHeader, btnCls, btnDangerCls, inputCls } from "@/components/ui";
import { approveUpdate, rejectUpdate } from "../actions";

export default async function Approvals({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const { data } = await sb.from("construction_updates").select("id, villa_id, new_status, remarks, is_issue, submitted_at, villas(villa_number), construction_stages(name)").eq("approval", "pending").order("submitted_at");
  const list = (data ?? []) as any[];
  const { data: photos } = list.length ? await sb.from("construction_update_photos").select("update_id, storage_path").in("update_id", list.map((u) => u.id)) : { data: [] as any[] };
  const signed = new Map<string, string>();
  const paths = (photos ?? []).map((p: any) => p.storage_path);
  if (paths.length) { const { data: s } = await sb.storage.from("construction-photos").createSignedUrls(paths, 3600); (s ?? []).forEach((x: any) => x.signedUrl && signed.set(x.path, x.signedUrl)); }
  return (
    <>
      <PageHeader title="Construction approvals" subtitle="Approving a stage can make a payment milestone payable, so check the photos first." />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {list.length === 0 ? <Empty>Nothing is waiting for approval.</Empty> : (
        <div className="space-y-4">{list.map((u) => (
          <Card key={u.id}>
            <div className="flex flex-wrap items-center gap-2"><span className="font-medium">Villa {u.villas?.villa_number} — {u.construction_stages?.name}</span><Badge tone="blue">{titleCase(u.new_status)}</Badge>{u.is_issue && <Badge tone="red">Issue flagged</Badge>}<span className="ml-auto text-xs text-slate-500">{fmtDateTime(u.submitted_at)}</span></div>
            {u.remarks && <p className="mt-2 text-sm">{u.remarks}</p>}
            <div className="mt-3 flex flex-wrap gap-2">{(photos ?? []).filter((p: any) => p.update_id === u.id).map((p: any) => signed.get(p.storage_path) && (
              <a key={p.storage_path} href={signed.get(p.storage_path)} target="_blank" rel="noreferrer"><img src={signed.get(p.storage_path)} alt="Construction photo" className="h-28 w-28 rounded object-cover" /></a>))}</div>
            <div className="mt-4 flex flex-wrap items-end gap-3 border-t border-slate-100 pt-3">
              <form action={approveUpdate}><input type="hidden" name="id" value={u.id} /><button className={btnCls}>Approve</button></form>
              <form action={rejectUpdate} className="flex flex-1 flex-wrap gap-2"><input type="hidden" name="id" value={u.id} /><input name="reason" required placeholder="Reason for rejection" className={`${inputCls} min-w-[12rem] flex-1`} /><button className={btnDangerCls}>Reject</button></form>
            </div>
          </Card>))}</div>)}
    </>
  );
}
