import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDateTime, titleCase } from "@/lib/format";
import { Badge, Card, Empty, Flash, PageHeader, btnCls, btnGhostCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { handleMessage } from "./actions";

export default async function Messages({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  await requireMe(["salesperson", "director"]);
  const { data } = await createClient().from("customer_message_drafts").select("id, kind, phone, body, status, created_at, customers(full_name), bookings(villas(villa_number))").order("created_at", { ascending: false }).limit(60);
  const list = (data ?? []) as any[]; const pending = list.filter((m) => m.status === "pending"); const done = list.filter((m) => m.status !== "pending");
  const link = (m: any) => `https://wa.me/${m.phone.replace(/\D/g, "")}?text=${encodeURIComponent(m.body)}`;
  return (
    <>
      <PageHeader title="Customer messages" subtitle="Ready-to-send WhatsApp messages. Tap Send, check the message in WhatsApp, press send there, then come back and mark it sent." />
      <Flash error={searchParams.error} ok={searchParams.ok} />
      <h2 className="mb-2 font-medium">Ready to send ({pending.length})</h2>
      {pending.length === 0 ? <Empty>No messages waiting. They appear automatically after approvals, payments and reminders, only for customers who agreed to WhatsApp messages.</Empty> : (
        <div className="space-y-3">{pending.map((m) => (
          <Card key={m.id}>
            <div className="flex flex-wrap items-center gap-2"><span className="font-medium">{m.customers?.full_name}</span><span className="text-sm text-slate-500">Villa {m.bookings?.villas?.villa_number}</span><Badge tone="blue">{titleCase(m.kind)}</Badge><span className="ml-auto text-xs text-slate-500">{fmtDateTime(m.created_at)}</span></div>
            <pre className="mt-2 whitespace-pre-wrap rounded bg-slate-50 p-3 font-sans text-sm">{m.body}</pre>
            <div className="mt-3 flex flex-wrap gap-2">
              <a className={btnCls} target="_blank" rel="noreferrer" href={link(m)}>Send on WhatsApp</a>
              <form action={handleMessage}><input type="hidden" name="id" value={m.id} /><input type="hidden" name="action" value="sent" /><SubmitButton className={btnGhostCls} pendingText="Saving…">Mark as sent</SubmitButton></form>
              <form action={handleMessage}><input type="hidden" name="id" value={m.id} /><input type="hidden" name="action" value="skipped" /><SubmitButton className="px-2 text-sm text-slate-500 underline" pendingText="Saving…">Skip</SubmitButton></form>
            </div></Card>))}</div>)}
      {done.length > 0 && <><h2 className="mb-2 mt-8 font-medium">Handled recently</h2><div className="space-y-1 text-sm text-slate-600">{done.slice(0, 20).map((m) => <div key={m.id}>{m.customers?.full_name} — {titleCase(m.kind)} — {titleCase(m.status)}</div>)}</div></>}
    </>
  );
}
