import { notFound } from "next/navigation";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { maskPan } from "@/lib/format";
import { Card, Field, Flash, PageHeader, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { btnCls } from "@/components/ui";
import { updateCustomer } from "../../actions";

export default async function EditCustomer({ params, searchParams }: { params: { id: string }; searchParams: { error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const [{ data: c }, { data: s }, { data: sp }] = await Promise.all([sb.from("customers").select("*").eq("id", params.id).maybeSingle(), sb.from("customer_sensitive").select("pan").eq("customer_id", params.id).maybeSingle(), sb.from("profiles").select("id, full_name").eq("role", "salesperson").eq("is_active", true).order("full_name")]);
  if (!c) notFound();
  return (
    <>
      <PageHeader title={`Edit ${c.full_name}`} />
      <Flash error={searchParams.error} />
      <Card><form action={updateCustomer} className="grid gap-4 sm:grid-cols-2"><input type="hidden" name="id" value={c.id} />
        <Field label="Full name"><input name="full_name" required defaultValue={c.full_name} className={inputCls} /></Field>
        <Field label="Mobile number"><input name="phone" required defaultValue={c.phone} className={inputCls} /></Field>
        <Field label="Alternate number"><input name="alt_phone" defaultValue={c.alt_phone ?? ""} className={inputCls} /></Field>
        <Field label="Email"><input name="email" type="email" defaultValue={c.email ?? ""} className={inputCls} /></Field>
        <Field label="Assigned salesperson"><select name="salesperson_id" defaultValue={c.salesperson_id ?? ""} className={inputCls}><option value="">— none —</option>{(sp ?? []).map((x: any) => <option key={x.id} value={x.id}>{x.full_name}</option>)}</select></Field>
        <Field label={`PAN on file: ${maskPan(s?.pan)}`} hint="Type a new PAN only to replace it. The full number is never shown on screen."><input name="pan" maxLength={10} className={`${inputCls} uppercase`} autoComplete="off" /></Field>
        <div className="sm:col-span-2"><Field label="Correspondence address"><textarea name="address" rows={2} defaultValue={c.address ?? ""} className={inputCls} /></Field></div>
        <div className="sm:col-span-2"><Field label="Internal notes"><textarea name="notes" rows={2} defaultValue={c.notes ?? ""} className={inputCls} /></Field></div>
        <label className="flex items-start gap-2 text-sm sm:col-span-2"><input type="checkbox" name="whatsapp_opt_in" defaultChecked={c.whatsapp_opt_in} className="mt-1" /><span>Customer has agreed to receive WhatsApp messages about their booking.</span></label>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="remove_pan" />Remove the PAN on file</label>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="is_archived" defaultChecked={c.is_archived} />Archive this customer (hide from lists)</label>
        <div className="sm:col-span-2"><SubmitButton className={btnCls} pendingText="Saving…">Save changes</SubmitButton></div>
      </form></Card>
    </>
  );
}
