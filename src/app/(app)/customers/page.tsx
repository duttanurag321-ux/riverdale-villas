import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { maskPan } from "@/lib/format";
import { Badge, Empty, Flash, PageHeader, Table, btnCls, btnGhostCls, inputCls } from "@/components/ui";

const PAGE = 20;
export default async function Customers({ searchParams }: { searchParams: { q?: string; page?: string; ok?: string; error?: string } }) {
  const me = await requireMe(["director", "salesperson"]);
  const sb = createClient();
  const page = Math.max(1, Number(searchParams.page) || 1);
  let q = sb.from("customers").select("id, full_name, phone, email, whatsapp_opt_in, is_archived", { count: "exact" }).eq("is_archived", false).order("full_name").range((page - 1) * PAGE, page * PAGE - 1);
  if (searchParams.q) { const s = searchParams.q.replace(/[%,()]/g, ""); q = q.or(`full_name.ilike.%${s}%,phone.ilike.%${s}%`); }
  const { data, count } = await q;
  const rows = (data ?? []) as any[];
  const pans = new Map<string, string>();
  if (me.role === "director" && rows.length) {
    const { data: s } = await sb.from("customer_sensitive").select("customer_id, pan").in("customer_id", rows.map((r) => r.id));
    (s ?? []).forEach((r: any) => r.pan && pans.set(r.customer_id, r.pan));
  }
  const pages = Math.max(1, Math.ceil((count ?? 0) / PAGE));
  const link = (p: number) => `/customers?page=${p}${searchParams.q ? `&q=${encodeURIComponent(searchParams.q)}` : ""}`;
  return (
    <>
      <PageHeader title="Customers" subtitle={`${count ?? 0} customer(s)`} action={me.role === "director" ? <Link href="/customers/new" className={btnCls}>Add customer</Link> : undefined} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <form className="mb-4 flex gap-2"><input name="q" defaultValue={searchParams.q} placeholder="Search name or phone" className={`${inputCls} max-w-xs`} /><button className={btnGhostCls}>Search</button></form>
      {rows.length === 0 ? <Empty>No customers found.</Empty> : (
        <Table head={["Name", "Phone", "Email", "WhatsApp opt-in", ...(me.role === "director" ? ["PAN (masked)", ""] : [])]}>
          {rows.map((c) => (
            <tr key={c.id}><td className="px-3 py-2 font-medium">{c.full_name}</td>
              <td className="px-3 py-2"><a className="text-brand underline" href={`tel:${c.phone}`}>{c.phone}</a></td><td className="px-3 py-2">{c.email ?? "—"}</td>
              <td className="px-3 py-2"><Badge tone={c.whatsapp_opt_in ? "green" : "slate"}>{c.whatsapp_opt_in ? "Opted in" : "No"}</Badge></td>
              {me.role === "director" && <><td className="px-3 py-2 font-mono text-xs">{maskPan(pans.get(c.id))}</td><td className="px-3 py-2 text-right"><Link className="text-brand underline" href={`/customers/${c.id}/edit`}>Edit</Link></td></>}</tr>))}
        </Table>)}
      {pages > 1 && <div className="mt-4 flex items-center justify-between text-sm">
        {page > 1 ? <Link className={btnGhostCls} href={link(page - 1)}>Previous</Link> : <span />}<span>Page {page} of {pages}</span>
        {page < pages ? <Link className={btnGhostCls} href={link(page + 1)}>Next</Link> : <span />}</div>}
    </>
  );
}
