import { notFound } from "next/navigation";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { titleCase } from "@/lib/format";
import { Card, Field, Flash, PageHeader, btnCls, inputCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { updateVilla } from "../../actions";

export default async function EditVilla({ params, searchParams }: { params: { id: string }; searchParams: { error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const [{ data: v }, { data: pr }, { data: staff }] = await Promise.all([sb.from("villas").select("*").eq("id", params.id).maybeSingle(), sb.from("villa_pricing").select("list_price_paise").eq("villa_id", params.id).maybeSingle(), sb.from("profiles").select("id, full_name, role").eq("is_active", true).order("full_name")]);
  if (!v) notFound();
  const sm = (staff ?? []).filter((s: any) => s.role === "site_manager"), sp = (staff ?? []).filter((s: any) => s.role === "salesperson");
  const editableStatus = ["available", "reserved", "inactive"].includes(v.status);
  return (
    <>
      <PageHeader title={`Edit villa ${v.villa_number}`} subtitle={`Status: ${titleCase(v.status)}${editableStatus ? "" : " (changes automatically with bookings and construction)"}`} />
      <Flash error={searchParams.error} />
      <Card><form action={updateVilla} className="grid gap-4 sm:grid-cols-2"><input type="hidden" name="id" value={v.id} />
        <Field label="Configuration"><input name="configuration" defaultValue={v.configuration ?? ""} className={inputCls} /></Field>
        <Field label="List price (₹)"><input name="price" required defaultValue={pr ? String(Number(pr.list_price_paise) / 100) : ""} inputMode="decimal" className={inputCls} /></Field>
        <Field label="Land area"><input name="land_area" defaultValue={v.land_area ?? ""} inputMode="decimal" className={inputCls} /></Field>
        <Field label="Land unit"><input name="land_unit" defaultValue={v.land_unit} className={inputCls} /></Field>
        <Field label="Plot details"><input name="plot_details" defaultValue={v.plot_details ?? ""} className={inputCls} /></Field>
        <Field label="Expected completion"><input name="expected_completion" type="date" defaultValue={v.expected_completion ?? ""} className={inputCls} /></Field>
        <Field label="Site Manager"><select name="site_manager_id" defaultValue={v.site_manager_id ?? ""} className={inputCls}><option value="">— none —</option>{sm.map((s: any) => <option key={s.id} value={s.id}>{s.full_name}</option>)}</select></Field>
        <Field label="Salesperson"><select name="salesperson_id" defaultValue={v.salesperson_id ?? ""} className={inputCls}><option value="">— none —</option>{sp.map((s: any) => <option key={s.id} value={s.id}>{s.full_name}</option>)}</select></Field>
        {editableStatus && <Field label="Status"><select name="status" defaultValue={v.status} className={inputCls}><option value="available">Available</option><option value="reserved">Reserved</option><option value="inactive">Inactive</option></select></Field>}
        <div className="sm:col-span-2"><Field label="Internal remarks"><textarea name="remarks" rows={2} defaultValue={v.remarks ?? ""} className={inputCls} /></Field></div>
        <div className="sm:col-span-2"><SubmitButton className={btnCls} pendingText="Saving…">Save changes</SubmitButton></div>
      </form></Card>
    </>
  );
}
