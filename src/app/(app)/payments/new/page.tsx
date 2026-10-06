import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Card, Empty, Field, Flash, PageHeader, btnCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { reportPayment } from "../actions";

export default async function NewPayment({ searchParams }: { searchParams: { error?: string; booking?: string } }) {
  await requireMe(["director", "salesperson"]);
  const { data } = await createClient().from("bookings").select("id, villas(villa_number), customers(full_name)").eq("status", "confirmed").order("created_at", { ascending: false });
  const list = (data ?? []) as any[];
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  return (
    <>
      <PageHeader title="Report a payment" subtitle="Record money the customer has paid. The Director then verifies it against the bank/UPI record." />
      <Flash error={searchParams.error} />
      {list.length === 0 ? <Empty>There are no confirmed bookings to record a payment against.</Empty> : (
        <Card><form action={reportPayment} className="grid gap-4 sm:grid-cols-2">
          <input type="hidden" name="request_id" value={crypto.randomUUID()} />
          <Field label="Booking"><select name="booking_id" required defaultValue={searchParams.booking ?? ""} className={inputCls}><option value="" disabled>— select —</option>{list.map((b) => <option key={b.id} value={b.id}>Villa {b.villas?.villa_number} — {b.customers?.full_name}</option>)}</select></Field>
          <Field label="Amount received (₹)"><input name="amount" required inputMode="decimal" className={inputCls} placeholder="200000" /></Field>
          <Field label="Date received"><input name="received_on" type="date" required defaultValue={today} max={today} className={inputCls} /></Field>
          <Field label="Method"><select name="method" className={inputCls} defaultValue="upi"><option value="upi">UPI</option><option value="bank_transfer">Bank transfer</option><option value="cheque">Cheque</option><option value="cash">Cash</option><option value="other">Other</option></select></Field>
          <Field label="UPI / bank reference" hint="Needed for the Director to check it."><input name="reference" className={inputCls} /></Field>
          <Field label="Notes"><input name="notes" className={inputCls} /></Field>
          <div className="sm:col-span-2"><SubmitButton className={btnCls} pendingText="Saving…">Report payment</SubmitButton></div>
        </form></Card>)}
    </>
  );
}
