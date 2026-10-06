"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { Spinner } from "./Spinner";

export default function NavLinks({ items, variant }: { items: { href: string; label: string }[]; variant: "side" | "bottom" }) {
  const pathname = usePathname();
  const [pending, setPending] = useState<string | null>(null);
  useEffect(() => { setPending(null); }, [pathname]);
  return (
    <>
      {items.map((i) => {
        const active = pathname === i.href || pathname.startsWith(i.href + "/");
        const isPending = pending === i.href;
        const cls = variant === "side"
          ? `flex items-center justify-between rounded-md px-3 py-2 text-sm ${active ? "bg-navy-700 font-medium" : "hover:bg-navy-700"} ${isPending ? "opacity-70" : ""}`
          : `flex min-w-[5.5rem] flex-1 items-center justify-center gap-1 px-2 py-3 text-xs font-medium ${active ? "border-t-2 border-brand text-brand" : "text-navy-900"} ${isPending ? "opacity-60" : ""}`;
        return (<Link key={i.href} href={i.href} onClick={() => { if (!active) setPending(i.href); }} className={cls} aria-current={active ? "page" : undefined}>{i.label}{isPending && <Spinner className="h-3 w-3" />}</Link>);
      })}
    </>
  );
}
