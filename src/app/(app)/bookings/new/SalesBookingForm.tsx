import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Card, Empty, Field, Flash, PageHeader, btnCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { inr } from "@/lib/format";
import { startBooking } from "../actions";

export default async function SalesBookingForm({ error }: { error?: string }) {
  const sb = createClient();
  const [{ data: villas }, { data: live }, { data: customers }] = await Promise.all([
    sb.from("villas").select("id, villa_number, configuration, projects(name)").in("status", ["available", "reserved"]).order("villa_number"),
    sb.from("bookings").select("villa_id").in("status", ["draft", "confirmed", "completed"]),
    sb.from("customers").select("id, full_name, phone").eq("is_archived", false).order("full_name"),
  ]);
  const taken = new Set((live ?? []).map((b: any) => b.villa_id));
  const free = ((villas ?? []) as any[]).filter((v) => !taken.has(v.id));
  const { data: pr } = free.length ? await sb.from("villa_pricing").select("villa_id, list_price_paise").in("villa_id", free.map((v) => v.id)) : { data: [] as any[] };
  const price = new Map((pr ?? []).map((p: any) => [p.villa_id, Number(p.list_price_paise)]));
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  if (!free.length || !(customers ?? []).length) return (<><PageHeader title="Prepare a booking" /><Empty>You need one of your villas that is still free, and one of your customers. <Link className="text-brand underline" href="/customers/new">Add a customer</Link></Empty></>);
  return (
    <>
      <PageHeader title="Prepare a booking" subtitle="The price comes from the villa list. The Director only has to confirm it." />
      <Flash error={error} />
      <Card><form action={startBooking} className="grid gap-4 sm:grid-cols-2"><input type="hidden" name="request_id" value={crypto.randomUUID()} />
        <Field label="Villa"><select name="villa_id" required defaultValue="" className={inputCls}><option value="" disabled>— select —</option>{free.map((v) => <option key={v.id} value={v.id}>{v.villa_number} · {v.projects?.name}{price.get(v.id) ? ` · ${inr(price.get(v.id))}` : " · no price yet"}</option>)}</select></Field>
        <Field label="Customer"><select name="customer_id" required defaultValue="" className={inputCls}><option value="" disabled>— select —</option>{(customers ?? []).map((c: any) => <option key={c.id} value={c.id}>{c.full_name} · {c.phone}</option>)}</select></Field>
        <div className="rounded-md bg-slate-50 p-3 text-sm sm:col-span-2"><b>Token received?</b> (optional) The Director confirms it after checking the bank.</div>
        <Field label="Token amount (₹)"><input name="token_amount" inputMode="decimal" className={inputCls} placeholder="100000" /></Field>
        <Field label="Paid by"><select name="token_method" defaultValue="upi" className={inputCls}><option value="upi">UPI</option><option value="bank_transfer">Bank transfer</option><option value="cheque">Cheque</option><option value="cash">Cash</option></select></Field>
        <Field label="UPI / bank reference"><input name="token_reference" className={inputCls} /></Field>
        <Field label="Date received"><input name="token_date" type="date" defaultValue={today} max={today} className={inputCls} /></Field>
        <div className="sm:col-span-2"><SubmitButton className={btnCls} pendingText="Preparing…">Prepare booking</SubmitButton></div>
      </form></Card>
    </>
  );
}
