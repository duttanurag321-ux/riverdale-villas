import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Card, Empty, PageHeader } from "@/components/ui";
import UpdateForm from "./UpdateForm";

export default async function UpdatePage({ searchParams }: { searchParams: { villa?: string } }) {
  await requireMe(["site_manager", "director"]);
  const sb = createClient();
  const [{ data: gates }, { data: villas }, { data: stages }] = await Promise.all([
    sb.rpc("construction_gates"),
    sb.from("villas").select("id, villa_number, projects(name)").not("status", "in", "(inactive,available)").order("villa_number"),
    sb.from("construction_stages").select("id, name, sequence").eq("is_active", true).order("sequence").order("name"),
  ]);
  const v = ((villas ?? []) as any[]).map((x) => ({ id: x.id, label: `${x.villa_number} · ${x.projects?.name ?? ""}` }));
  const s = ((stages ?? []) as any[]).map((x) => ({ id: x.id, label: x.name }));
  return (
    <>
      <PageHeader title="Update construction" />
      {v.length === 0 ? <Empty>No villas are assigned to you yet. Ask the Director to assign you to a villa.</Empty> : <Card><UpdateForm locked={((gates ?? []) as any[]).filter((g) => !g.gate_open).map((g) => g.villa_id)} villas={v} stages={s} initialVilla={v.some((x) => x.id === searchParams.villa) ? searchParams.villa : undefined} /></Card>}
    </>
  );
}
