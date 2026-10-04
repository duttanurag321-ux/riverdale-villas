import Link from "next/link";
import { notFound } from "next/navigation";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDateTime, titleCase } from "@/lib/format";
import { Badge, Card, Empty, Flash, PageHeader, btnCls } from "@/components/ui";

export default async function VillaTimeline({ params, searchParams }: { params: { id: string }; searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe();
  const sb = createClient();
  const { data: v } = await sb.from("villas").select("id, villa_number, status, expected_completion, projects(name), construction_stages(name)").eq("id", params.id).maybeSingle();
  if (!v) notFound();
  const { data: ups } = await sb.from("construction_updates").select("id, new_status, remarks, is_issue, submitted_at, approval, rejection_reason, construction_stages(name)").eq("villa_id", v.id).order("submitted_at", { ascending: false });
  const list = (ups ?? []) as any[];
  const { data: photos } = list.length ? await sb.from("construction_update_photos").select("update_id, storage_path").in("update_id", list.map((u) => u.id)) : { data: [] as any[] };
  const paths = (photos ?? []).map((p: any) => p.storage_path);
  const signed = new Map<string, string>();
  if (paths.length) { const { data: s } = await sb.storage.from("construction-photos").createSignedUrls(paths, 3600); (s ?? []).forEach((x: any) => x.signedUrl && signed.set(x.path, x.signedUrl)); }
  const tone = (a: string) => (a === "approved" ? "green" : a === "rejected" ? "red" : a === "pending" ? "amber" : "slate");
  return (
    <>
      <PageHeader title={`Villa ${v.villa_number}`} subtitle={`${(v as any).projects?.name} · ${titleCase(v.status)} · Current stage: ${(v as any).construction_stages?.name ?? "Not started"}`}
        action={me.role !== "salesperson" ? <Link href={`/construction/update?villa=${v.id}`} className={btnCls}>Add update</Link> : undefined} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {list.length === 0 ? <Empty>No construction updates yet.</Empty> : (
        <div className="space-y-3">{list.map((u) => (
          <Card key={u.id}>
            <div className="flex flex-wrap items-center gap-2"><span className="font-medium">{u.construction_stages?.name}</span>
              <Badge tone="blue">{titleCase(u.new_status)}</Badge>
              <Badge tone={tone(u.approval) as any}>{u.approval === "not_required" ? "No approval needed" : titleCase(u.approval)}</Badge>
              {u.is_issue && <Badge tone="red">Issue flagged</Badge>}
              <span className="ml-auto text-xs text-slate-500">{fmtDateTime(u.submitted_at)}</span></div>
            {u.remarks && <p className="mt-2 text-sm">{u.remarks}</p>}
            {u.rejection_reason && <p className="mt-2 rounded bg-red-50 p-2 text-sm text-red-800">Rejected: {u.rejection_reason}</p>}
            <div className="mt-3 flex flex-wrap gap-2">{(photos ?? []).filter((p: any) => p.update_id === u.id).map((p: any) => signed.get(p.storage_path) && (
              <a key={p.storage_path} href={signed.get(p.storage_path)} target="_blank" rel="noreferrer"><img src={signed.get(p.storage_path)} alt="Construction photo" className="h-24 w-24 rounded object-cover" /></a>))}</div>
          </Card>))}</div>)}
    </>
  );
}
