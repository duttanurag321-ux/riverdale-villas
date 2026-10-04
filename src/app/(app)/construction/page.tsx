import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDateTime, titleCase } from "@/lib/format";
import { Badge, Empty, Flash, PageHeader, Table, btnCls, btnGhostCls } from "@/components/ui";

export default async function Construction({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe();
  const sb = createClient();
  const [{ data: villas }, { data: ups }] = await Promise.all([
    sb.from("villas").select("id, villa_number, status, projects(name), construction_stages(name)").order("villa_number"),
    sb.from("construction_updates").select("villa_id, approval, new_status, submitted_at").order("submitted_at", { ascending: false }).limit(500),
  ]);
  const latest = new Map<string, any>(); const pending = new Map<string, number>();
  (ups ?? []).forEach((u: any) => { if (!latest.has(u.villa_id)) latest.set(u.villa_id, u); if (u.approval === "pending") pending.set(u.villa_id, (pending.get(u.villa_id) ?? 0) + 1); });
  const canUpdate = me.role !== "salesperson";
  const rows = (villas ?? []) as any[];
  return (
    <>
      <PageHeader title="Construction" subtitle="Progress by villa" action={<div className="flex gap-2">
        {me.role === "director" && <><Link href="/construction/approvals" className={btnGhostCls}>Approvals</Link><Link href="/stages" className={btnGhostCls}>Stages</Link></>}
        {canUpdate && <Link href="/construction/update" className={btnCls}>Update construction</Link>}</div>} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {rows.length === 0 ? <Empty>No villas to show yet.</Empty> : (
        <Table head={["Villa", "Current stage", "Last update", "Awaiting approval", ""]}>
          {rows.map((v) => { const l = latest.get(v.id); return (
            <tr key={v.id}><td className="px-3 py-2 font-medium">{v.villa_number}<div className="text-xs font-normal text-slate-500">{v.projects?.name}</div></td>
              <td className="px-3 py-2">{v.construction_stages?.name ?? "Not started"}</td>
              <td className="px-3 py-2">{l ? <>{titleCase(l.new_status)}<div className="text-xs text-slate-500">{fmtDateTime(l.submitted_at)}</div></> : "—"}</td>
              <td className="px-3 py-2">{pending.get(v.id) ? <Badge tone="amber">{pending.get(v.id)} pending</Badge> : "—"}</td>
              <td className="px-3 py-2 text-right whitespace-nowrap">
                {canUpdate && <Link className="mr-3 text-brand underline" href={`/construction/update?villa=${v.id}`}>Update</Link>}
                <Link className="text-brand underline" href={`/construction/villa/${v.id}`}>History</Link></td></tr>); })}
        </Table>)}
    </>
  );
}
