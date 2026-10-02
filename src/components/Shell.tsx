import Link from "next/link";
import type { Me, Role } from "@/lib/auth";
import { titleCase } from "@/lib/format";

const NAV: Record<Role, { href: string; label: string }[]> = {
  director: [{ href: "/dashboard", label: "Dashboard" }, { href: "/villas", label: "Villas" }, { href: "/customers", label: "Customers" }, { href: "/bookings", label: "Bookings" }, { href: "/users", label: "Users" }],
  salesperson: [{ href: "/dashboard", label: "Dashboard" }, { href: "/customers", label: "Customers" }, { href: "/bookings", label: "Bookings" }, { href: "/villas", label: "Villas" }],
  site_manager: [{ href: "/dashboard", label: "Dashboard" }, { href: "/villas", label: "Villas" }],
};

export default function Shell({ me, children }: { me: Me; children: React.ReactNode }) {
  const items = NAV[me.role];
  return (
    <div className="min-h-screen md:flex">
      <aside className="hidden w-60 shrink-0 flex-col bg-navy-900 p-4 text-white md:flex">
        <div className="mb-8"><div className="text-lg font-semibold">Riverdale Villas</div><div className="text-xs text-slate-300">Construction &amp; Payments</div></div>
        <nav className="flex-1 space-y-1">{items.map((i) => <Link key={i.href} href={i.href} className="block rounded-md px-3 py-2 text-sm hover:bg-navy-700">{i.label}</Link>)}</nav>
        <div className="border-t border-navy-700 pt-3 text-sm"><div className="font-medium">{me.full_name}</div><div className="text-xs text-slate-300">{titleCase(me.role)}</div>
          <a href="/auth/signout" className="mt-2 inline-block text-xs text-slate-300 underline">Log out</a></div>
      </aside>
      <div className="flex-1 pb-16 md:pb-0">
        <header className="flex items-center justify-between bg-navy-900 px-4 py-3 text-white md:hidden">
          <span className="font-semibold">Riverdale Villas</span><a href="/auth/signout" className="text-xs underline">Log out</a>
        </header>
        <main className="mx-auto max-w-6xl p-4 sm:p-6">{children}</main>
      </div>
      <nav className="fixed inset-x-0 bottom-0 z-10 flex border-t border-slate-200 bg-white md:hidden" aria-label="Main">
        {items.map((i) => <Link key={i.href} href={i.href} className="flex-1 px-1 py-3 text-center text-xs font-medium text-navy-900">{i.label}</Link>)}
      </nav>
    </div>
  );
}
