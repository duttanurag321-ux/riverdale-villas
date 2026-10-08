import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, inr, titleCase } from "@/lib/format";
import { Badge, Empty, Flash, PageHeader, Table, btnCls, btnGhostCls, inputCls } from "@/components/ui";

const PAGE = 20;
export default async function Villas({ searchParams }: { searchParams: { q?: string; status?: string; page?: string; ok?: string; error?: string } }) {
  const me = await requireMe();
  const sb = createClient();
  const page = Math.max(1, Number(searchParams.page) || 1);
  let q = sb.from("villas").select("id, villa_number, configuration, status, expected_completion, land_area, land_unit, projects(name), construction_stages(name)", { count: "exact" })
    .order("villa_number").range((page - 1) * PAGE, page * PAGE - 1);
  if (searchParams.q) q = q.ilike("villa_number", `%${searchParams.q.replace(/[%,]/g, "")}%`);
  if (searchParams.status) q = q.eq("status", searchParams.status);
  const { data, count } = await q;
  const rows = (data ?? []) as any[];
  const showPrice = me.role !== "site_manager";
  const prices = new Map<string, number>();
  if (showPrice && rows.length) {
    const { data: p } = await sb.from("villa_pricing").select("villa_id, list_price_paise").in("villa_id", rows.map((r) => r.id));
    (p ?? []).forEach((r: any) => prices.set(r.villa_id, Number(r.list_price_paise)));
  }
  const tone = (s: string) => (s === "available" ? "green" : s === "inactive" ? "red" : "blue");
  const pages = Math.max(1, Math.ceil((count ?? 0) / PAGE));
  const link = (p: number) => `/villas?page=${p}${searchParams.q ? `&q=${encodeURIComponent(searchParams.q)}` : ""}${searchParams.status ? `&status=${searchParams.status}` : ""}`;

  return (
    <>
      <PageHeader title="Villas" subtitle={`${count ?? 0} villa(s)`} action={me.role === "director" ? <Link href="/villas/new" className={btnCls}>Add villa</Link> : undefined} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <form className="mb-4 flex flex-wrap gap-2">
        <input name="q" defaultValue={searchParams.q} placeholder="Search villa number" className={`${inputCls} max-w-xs`} />
        <select name="status" defaultValue={searchParams.status ?? ""} className={`${inputCls} max-w-[11rem]`}>
          <option value="">All statuses</option>
          {["available", "reserved", "booked", "under_construction", "completed", "handed_over", "inactive"].map((s) => <option key={s} value={s}>{titleCase(s)}</option>)}
        </select>
        <button className={btnGhostCls}>Filter</button>
      </form>
      {rows.length === 0 ? <Empty>{me.role === "director" ? "No villas yet. Add your first villa." : "No villas are assigned to you yet."}</Empty> : (
        <Table head={["Villa", "Project", "Configuration", "Status", "Current stage", ...(showPrice ? ["List price"] : []), "Expected completion", ...(me.role === "director" ? [""] : [])]}>
          {rows.map((v) => (
            <tr key={v.id}>
              <td className="px-3 py-2 font-medium"><Link className="text-brand underline" href={`/construction/villa/${v.id}`}>{v.villa_number}</Link></td><td className="px-3 py-2">{v.projects?.name}</td>
              <td className="px-3 py-2">{v.configuration ?? "—"}{v.land_area ? ` · ${v.land_area} ${v.land_unit}` : ""}</td>
              <td className="px-3 py-2"><Badge tone={tone(v.status) as any}>{titleCase(v.status)}</Badge></td>
              <td className="px-3 py-2">{v.construction_stages?.name ?? "Not started"}</td>
              {showPrice && <td className="px-3 py-2">{inr(prices.get(v.id))}</td>}
              <td className="px-3 py-2">{fmtDate(v.expected_completion)}</td>{me.role === "director" && <td className="px-3 py-2 text-right"><Link className="text-brand underline" href={`/villas/${v.id}/edit`}>Edit</Link></td>}
            </tr>))}
        </Table>)}
      {pages > 1 && <div className="mt-4 flex items-center justify-between text-sm">
        {page > 1 ? <Link className={btnGhostCls} href={link(page - 1)}>Previous</Link> : <span />}<span>Page {page} of {pages}</span>
        {page < pages ? <Link className={btnGhostCls} href={link(page + 1)}>Next</Link> : <span />}</div>}
    </>
  );
}
