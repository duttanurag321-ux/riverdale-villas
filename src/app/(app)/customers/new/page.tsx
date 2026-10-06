import { SubmitButton } from "@/components/SubmitButton";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Card, Field, Flash, PageHeader, btnCls, inputCls } from "@/components/ui";
import { createCustomer } from "../actions";

export default async function NewCustomer({ searchParams }: { searchParams: { error?: string } }) {
  await requireMe(["director"]);
  const { data: sp } = await createClient().from("profiles").select("id, full_name").eq("role", "salesperson").eq("is_active", true).order("full_name");
  return (
    <>
      <PageHeader title="Add customer" />
      <Flash error={searchParams.error} />
      <Card><form action={createCustomer} className="grid gap-4 sm:grid-cols-2">
        <Field label="Full name"><input name="full_name" required className={inputCls} /></Field>
        <Field label="Mobile number" hint="10 digits; +91 is added automatically."><input name="phone" required inputMode="tel" className={inputCls} /></Field>
        <Field label="Alternate number"><input name="alt_phone" inputMode="tel" className={inputCls} /></Field>
        <Field label="Email"><input name="email" type="email" className={inputCls} /></Field>
        <Field label="Assigned salesperson"><select name="salesperson_id" className={inputCls} defaultValue=""><option value="">— none —</option>{(sp ?? []).map((s: any) => <option key={s.id} value={s.id}>{s.full_name}</option>)}</select></Field>
        <Field label="PAN (optional)" hint="Only if legally needed. Stored separately; visible to the Director only."><input name="pan" maxLength={10} className={`${inputCls} uppercase`} autoComplete="off" /></Field>
        <div className="sm:col-span-2"><Field label="Correspondence address"><textarea name="address" rows={2} className={inputCls} /></Field></div>
        <div className="sm:col-span-2"><Field label="Internal notes"><textarea name="notes" rows={2} className={inputCls} /></Field></div>
        <label className="flex items-start gap-2 text-sm sm:col-span-2"><input type="checkbox" name="whatsapp_opt_in" className="mt-1" />
          <span>Customer has agreed to receive WhatsApp messages about their booking. Tick only if you have their consent.</span></label>
        <div className="sm:col-span-2"><SubmitButton className={btnCls}>Save customer</SubmitButton></div>
      </form></Card>
    </>
  );
}
