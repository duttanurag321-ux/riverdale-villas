import Link from "next/link";
import { requireMe } from "@/lib/auth";
import { Card, PageHeader } from "@/components/ui";
import ImportForm from "./ImportForm";

export default async function ImportPage() {
  await requireMe(["director"]);
  return (
    <>
      <PageHeader title="Import data (CSV)" subtitle="Add many villas or customers at once. Try it with the fictional template first." />
      <Card><ImportForm /></Card>
      <Card className="mt-4 text-sm text-slate-600"><ul className="list-disc space-y-1 pl-5">
        <li>Bookings, schedules and payments cannot be imported. Money records are created one at a time so every rule is checked.</li>
        <li>Employee assignments (Site Manager, Salesperson) are set afterwards with Edit on each villa or customer.</li>
        <li>Save spreadsheets as &ldquo;CSV UTF-8&rdquo;. Amounts are in rupees, for example 6000000 or 60,00,000. Dates look like 2027-12-31.</li>
        <li>Practise with fictional data before importing real customers. <Link href="/backup" className="text-brand underline">Download a backup first</Link>.</li></ul></Card>
    </>
  );
}
