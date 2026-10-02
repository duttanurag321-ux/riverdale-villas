import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, inr, titleCase } from "@/lib/format";
import { Badge, Empty, Flash, PageHeader, Table, btnCls } from "@/components/ui";

export default async function Bookings({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe(["director", "salesperson"]);
  const { data } = await createClient().from("bookings").select("id, status, booking_date, contract_value_paise, villas(villa_number), customers(full_name)").order("created_at", { ascending: false }).limit(100);
  const rows = (data ?? []) as any[];
  const tone = (s: string) => (s === "confirmed" ? "green" : s === "cancelled" ? "red" : "amber");
  return (
    <>
      <PageHeader title="Bookings" action={me.role === "director" ? <Link href="/bookings/new" className={btnCls}>New booking</Link> : undefined} />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      {rows.length === 0 ? <Empty>No bookings yet.</Empty> : (
        <Table head={["Villa", "Customer", "Booked on", "Contract value", "Status", ""]}>
          {rows.map((b) => (
            <tr key={b.id}><td className="px-3 py-2 font-medium">{b.villas?.villa_number}</td><td className="px-3 py-2">{b.customers?.full_name}</td>
              <td className="px-3 py-2">{fmtDate(b.booking_date)}</td><td className="px-3 py-2">{inr(b.contract_value_paise)}</td>
              <td className="px-3 py-2"><Badge tone={tone(b.status) as any}>{titleCase(b.status)}</Badge></td>
              <td className="px-3 py-2 text-right"><Link className="text-brand underline" href={`/bookings/${b.id}`}>Open</Link></td></tr>))}
        </Table>)}
    </>
  );
}
