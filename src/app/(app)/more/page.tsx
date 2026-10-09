import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { Card, PageHeader } from "@/components/ui";

const ITEMS = [
  ["/customers", "Customers", "Add or change customer details"], ["/villas", "Villas", "Add villas, prices and who looks after them"],
  ["/followups", "Follow-ups", "Calls your team needs to make"], ["/reports", "Reports", "Totals and downloadable lists"],
  ["/plans", "Payment plans", "How much is due at booking and later"], ["/stages", "Building steps", "The list of construction steps"],
  ["/users", "Staff", "Add or remove people who can log in"], ["/settings", "Settings", "Reminders, message wording, storage space"],
  ["/import", "Import from spreadsheet", "Add many villas or customers at once"], ["/backup", "Backups", "Download your data (do this monthly)"],
  ["/notifications", "Alerts", "Everything the system told you"],
];

export default async function More() {
  await requireMe(["director"]);
  return (
    <>
      <PageHeader title="More" subtitle="Everything else, in plain words." />
      <div className="grid gap-3 sm:grid-cols-2">{ITEMS.map(([href, t, d]) => (
        <Link key={href} href={href}><Card className="h-full hover:border-brand"><div className="font-medium">{t}</div><div className="mt-1 text-sm text-slate-500">{d}</div></Card></Link>))}</div>
    </>
  );
}
