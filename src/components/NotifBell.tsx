"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { createBrowserSupabase } from "@/lib/supabase/client";

/** One tiny count request per page visit. No polling and no Realtime, so it uses almost nothing of the free quota. */
export default function NotifBell({ dark = false }: { dark?: boolean }) {
  const pathname = usePathname();
  const [n, setN] = useState(0);
  useEffect(() => {
    let live = true;
    createBrowserSupabase().from("notifications").select("id", { count: "exact", head: true }).is("read_at", null)
      .then(({ count }) => { if (live) setN(count ?? 0); });
    return () => { live = false; };
  }, [pathname]);
  return (
    <Link href="/notifications" aria-label={`Notifications${n ? `, ${n} unread` : ""}`} className={`relative inline-flex h-9 w-9 items-center justify-center rounded-full ${dark ? "hover:bg-navy-700" : "hover:bg-slate-100"}`}>
      <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9" /><path d="M13.7 21a2 2 0 0 1-3.4 0" /></svg>
      {n > 0 && <span className="absolute -right-0.5 -top-0.5 min-w-[1.1rem] rounded-full bg-red-600 px-1 text-center text-[10px] font-semibold leading-4 text-white">{n > 99 ? "99+" : n}</span>}
    </Link>
  );
}
