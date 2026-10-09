import { SubmitButton } from "@/components/SubmitButton";
import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Card, Empty, Field, Flash, PageHeader, btnCls, inputCls } from "@/components/ui";
import { createBooking } from "../actions";

export default async function NewBooking({ searchParams }: { searchParams: { error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const [{ data: villas }, { data: live }, { data: customers }, { data: sp }, { data: templates }] = await Promise.all([
    sb.from("villas").select("id, villa_number, configuration, projects(name)").in("status", ["available", "reserved"]).order("villa_number"),
    sb.from("bookings").select("villa_id").in("status", ["draft", "confirmed", "completed"]),
    sb.from("customers").select("id, full_name, phone").eq("is_archived", false).order("full_name"),
    sb.from("profiles").select("id, full_name").eq("role", "salesperson").eq("is_active", true).order("full_name"),
    sb.from("payment_plan_templates").select("id, name").eq("is_active", true).order("name"),
  ]);
  const taken = new Set((live ?? []).map((b: any) => b.villa_id));
  const free = ((villas ?? []) as any[]).filter((v) => !taken.has(v.id));
  const defTpl = ((templates ?? []) as any[]).find((t) => /^riverdale/i.test(t.name))?.id ?? "";
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  if (!free.length || !(customers ?? []).length) return (<><PageHeader title="New booking" /><Empty>You need at least one available villa and one customer first. <Link className="text-brand underline" href="/villas/new">Add a villa</Link> · <Link className="text-brand underline" href="/customers/new">Add a customer</Link></Empty></>);
  return (
    <>
      <PageHeader title="New booking" subtitle="Creates a draft. Nothing becomes payable until you confirm it." />
      <Flash error={searchParams.error} />
      <Card><form action={createBooking} className="grid gap-4 sm:grid-cols-2">
        <Field label="Villa"><select name="villa_id" required className={inputCls} defaultValue="">{<option value="" disabled>— select —</option>}{free.map((v) => <option key={v.id} value={v.id}>{v.villa_number} · {v.projects?.name}{v.configuration ? ` · ${v.configuration}` : ""}</option>)}</select></Field>
        <Field label="Customer"><select name="customer_id" required className={inputCls} defaultValue=""><option value="" disabled>— select —</option>{(customers ?? []).map((c: any) => <option key={c.id} value={c.id}>{c.full_name} · {c.phone}</option>)}</select></Field>
        <Field label="Package price (₹)"><input name="price" required inputMode="decimal" className={inputCls} /></Field>
        <Field label="Extra agreed charges (₹)" hint="Optional, e.g. registration. Included in the contract value."><input name="extra" inputMode="decimal" className={inputCls} /></Field>
        <Field label="Salesperson"><select name="salesperson_id" className={inputCls} defaultValue=""><option value="">— none —</option>{(sp ?? []).map((s: any) => <option key={s.id} value={s.id}>{s.full_name}</option>)}</select></Field>
        <Field label="Payment plan template" hint="Copied into this booking; later template edits never change it."><select name="template_id" className={inputCls} defaultValue={defTpl}><option value="">— choose later —</option>{(templates ?? []).map((t: any) => <option key={t.id} value={t.id}>{t.name}</option>)}</select></Field>
        <div className="rounded-md bg-slate-50 p-3 text-sm sm:col-span-2"><b>Token received?</b> (optional) Many customers pay a token first. It is counted towards the booking amount automatically.</div>
        <Field label="Token amount (₹)"><input name="token_amount" inputMode="decimal" className={inputCls} placeholder="100000" /></Field>
        <Field label="Token paid by"><select name="token_method" className={inputCls} defaultValue="upi"><option value="upi">UPI</option><option value="bank_transfer">Bank transfer</option><option value="cheque">Cheque</option><option value="cash">Cash</option></select></Field>
        <Field label="Token reference (UPI / bank)"><input name="token_reference" className={inputCls} /></Field>
        <Field label="Token date"><input name="token_date" type="date" defaultValue={today} max={today} className={inputCls} /></Field>
        <Field label="Booking date"><input name="booking_date" type="date" className={inputCls} /></Field>
        <Field label="Expected construction start"><input name="expected_start" type="date" className={inputCls} /></Field>
        <Field label="Expected handover"><input name="expected_handover" type="date" className={inputCls} /></Field>
        <Field label="Notes"><input name="notes" className={inputCls} /></Field>
        <div className="sm:col-span-2"><SubmitButton className={btnCls}>Create draft booking</SubmitButton></div>
      </form></Card>
    </>
  );
}
