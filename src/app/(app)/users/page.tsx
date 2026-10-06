import { SubmitButton } from "@/components/SubmitButton";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { titleCase } from "@/lib/format";
import { Badge, Card, Field, Flash, PageHeader, Table, btnCls, btnGhostCls, inputCls } from "@/components/ui";
import { createEmployee, setActive } from "./actions";

export default async function Users({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const me = await requireMe(["director"]);
  const { data } = await createClient().from("profiles").select("id, full_name, phone, role, is_active").order("full_name");
  return (
    <>
      <PageHeader title="Users" subtitle="Only the Director can create or deactivate accounts. There is no public sign-up." />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <Table head={["Name", "Role", "Phone", "Status", ""]}>
        {(data ?? []).map((u: any) => (
          <tr key={u.id}><td className="px-3 py-2 font-medium">{u.full_name}</td><td className="px-3 py-2">{titleCase(u.role)}</td><td className="px-3 py-2">{u.phone ?? "—"}</td>
            <td className="px-3 py-2"><Badge tone={u.is_active ? "green" : "red"}>{u.is_active ? "Active" : "Deactivated"}</Badge></td>
            <td className="px-3 py-2 text-right">{u.id !== me.id && <form action={setActive}><input type="hidden" name="id" value={u.id} /><input type="hidden" name="active" value={String(!u.is_active)} /><SubmitButton className={btnGhostCls}>{u.is_active ? "Deactivate" : "Reactivate"}</SubmitButton></form>}</td></tr>))}
      </Table>
      <h2 className="mb-2 mt-8 font-medium">Add employee</h2>
      <Card><form action={createEmployee} className="grid gap-4 sm:grid-cols-2">
        <Field label="Full name"><input name="full_name" required className={inputCls} /></Field>
        <Field label="Email (login)"><input name="email" type="email" required className={inputCls} /></Field>
        <Field label="Role"><select name="role" required className={inputCls} defaultValue="salesperson"><option value="site_manager">Site Manager</option><option value="salesperson">Salesperson</option><option value="director">Director</option></select></Field>
        <Field label="Phone"><input name="phone" className={inputCls} /></Field>
        <Field label="Temporary password" hint="At least 10 characters. Share it privately."><input name="password" type="text" required minLength={10} autoComplete="off" className={inputCls} /></Field>
        <div className="flex items-end"><SubmitButton className={btnCls}>Create account</SubmitButton></div>
      </form></Card>
    </>
  );
}
