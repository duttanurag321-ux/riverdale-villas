import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDateTime } from "@/lib/format";
import { Badge, Card, Empty, Flash, PageHeader, btnGhostCls } from "@/components/ui";
import { SubmitButton } from "@/components/SubmitButton";
import { markAllRead } from "./actions";

export default async function Notifications({ searchParams }: { searchParams: { ok?: string } }) {
  const me = await requireMe();
  const { data } = await createClient().from("notifications").select("id, kind, title, body, link, created_at, read_at").eq("user_id", me.id).order("created_at", { ascending: false }).limit(50);
  const list = (data ?? []) as any[]; const unread = list.filter((n) => !n.read_at).length;
  return (
    <>
      <PageHeader title="Notifications" subtitle={unread ? `${unread} unread` : "You're all caught up"} action={unread ? <form action={markAllRead}><SubmitButton className={btnGhostCls} pendingText="Saving…">Mark all read</SubmitButton></form> : undefined} />
      <Flash ok={searchParams.ok} />
      {list.length === 0 ? <Empty>No notifications yet. Alerts about approvals, payments and follow-ups will appear here.</Empty> : (
        <div className="space-y-2">{list.map((n) => (
          <Card key={n.id} className={n.read_at ? "opacity-70" : "border-l-4 border-l-brand"}>
            <div className="flex flex-wrap items-center gap-2">{!n.read_at && <Badge tone="blue">New</Badge>}<span className="font-medium">{n.title}</span><span className="ml-auto text-xs text-slate-500">{fmtDateTime(n.created_at)}</span></div>
            {n.body && <p className="mt-1 whitespace-pre-line text-sm text-slate-700">{n.body}</p>}
            {n.link && <Link href={n.link} className="mt-2 inline-block text-sm text-brand underline">Open</Link>}
          </Card>))}</div>)}
      <p className="mt-4 text-xs text-slate-500">Showing the latest 50. Older notifications are removed automatically after the retention period to keep storage small.</p>
    </>
  );
}
