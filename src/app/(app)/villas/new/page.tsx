import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Card, Field, Flash, PageHeader, btnCls, inputCls } from "@/components/ui";
import { createVilla } from "../actions";

export default async function NewVilla({ searchParams }: { searchParams: { error?: string } }) {
  await requireMe(["director"]);
  const sb = createClient();
  const [{ data: projects }, { data: staff }] = await Promise.all([
    sb.from("projects").select("id, name").order("name"), sb.from("profiles").select("id, full_name, role").eq("is_active", true).order("full_name"),
  ]);
  const sm = (staff ?? []).filter((s: any) => s.role === "site_manager"); const sp = (staff ?? []).filter((s: any) => s.role === "salesperson");
  return (
    <>
      <PageHeader title="Add villa" />
      <Flash error={searchParams.error} />
      <Card><form action={createVilla} className="grid gap-4 sm:grid-cols-2">
        <Field label="Project"><select name="project_id" className={inputCls} defaultValue=""><option value="">— select —</option>{(projects ?? []).map((p: any) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></Field>
        <Field label="…or create a new project" hint="Leave blank if you chose a project."><input name="new_project" className={inputCls} placeholder="Riverdale Villas" /></Field>
        <Field label="Villa number"><input name="villa_number" required className={inputCls} placeholder="A1" /></Field>
        <Field label="Configuration"><input name="configuration" className={inputCls} placeholder="2 BHK" /></Field>
        <Field label="Land area"><input name="land_area" inputMode="decimal" className={inputCls} placeholder="3" /></Field>
        <Field label="Land unit"><input name="land_unit" defaultValue="katha" className={inputCls} /></Field>
        <Field label="List price (₹)" hint="Total package, e.g. 60,00,000"><input name="price" required inputMode="decimal" className={inputCls} /></Field>
        <Field label="Plot details"><input name="plot_details" className={inputCls} /></Field>
        <Field label="Site Manager"><select name="site_manager_id" className={inputCls} defaultValue=""><option value="">— none —</option>{sm.map((s: any) => <option key={s.id} value={s.id}>{s.full_name}</option>)}</select></Field>
        <Field label="Salesperson"><select name="salesperson_id" className={inputCls} defaultValue=""><option value="">— none —</option>{sp.map((s: any) => <option key={s.id} value={s.id}>{s.full_name}</option>)}</select></Field>
        <Field label="Expected completion"><input name="expected_completion" type="date" className={inputCls} /></Field>
        <div className="sm:col-span-2"><button className={btnCls}>Create villa</button></div>
      </form></Card>
    </>
  );
}
