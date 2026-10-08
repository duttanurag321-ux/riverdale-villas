import { requireMe } from "@/lib/auth";
import { Card, PageHeader, btnGhostCls } from "@/components/ui";

const FILES = [["villas", "Villas"], ["customers", "Customers (PAN is not included)"], ["bookings", "Bookings"], ["milestones", "Payment schedules"], ["payments", "Payment ledger"], ["allocations", "Payment allocations"], ["outstanding", "Outstanding balances"]];

export default async function Backup() {
  await requireMe(["director"]);
  return (
    <>
      <PageHeader title="Backups" subtitle="Download your data as spreadsheets. Do this at least once a month and store the files somewhere safe." />
      <Card><div className="grid gap-2 sm:grid-cols-2">{FILES.map(([k, l]) => <a key={k} href={`/exports/${k}`} className={btnGhostCls}>{l} (CSV)</a>)}</div></Card>
      <Card className="mt-4 space-y-2 text-sm text-slate-600">
        <p>Each file holds up to the latest 5,000 rows. These spreadsheets contain customer names and phone numbers: keep them private and delete old copies.</p>
        <p>PAN numbers, construction photos and the audit log are not in these files. Photos can be downloaded from the Supabase dashboard (Storage). Free Supabase projects do not include automatic backups, so these downloads are your safety net. See docs/BACKUP_AND_RECOVERY.md.</p></Card>
    </>
  );
}
