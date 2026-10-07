"use client";
import { useEffect, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";

/** Thin bar across the top the moment any internal link or search form is used, so a tap always looks "received". */
export default function TopProgress() {
  const pathname = usePathname(); const params = useSearchParams();
  const [busy, setBusy] = useState(false);
  useEffect(() => { setBusy(false); }, [pathname, params]);
  useEffect(() => {
    let t: ReturnType<typeof setTimeout> | undefined;
    const start = () => { setBusy(true); clearTimeout(t); t = setTimeout(() => setBusy(false), 20000); };
    const onClick = (e: MouseEvent) => {
      const a = (e.target as HTMLElement).closest?.("a");
      if (!a || a.target === "_blank" || a.hasAttribute("download") || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
      const u = new URL(a.href, location.href);
      if (u.origin !== location.origin || u.pathname + u.search === location.pathname + location.search) return;
      if (u.pathname.startsWith("/receipts") || u.pathname.startsWith("/statements") || u.pathname.startsWith("/exports")) return;   // file downloads
      start();
    };
    const onSubmit = (e: SubmitEvent) => {
      const f = e.target as HTMLFormElement;
      if ((f.getAttribute("method") ?? "get").toLowerCase() === "get" && !f.querySelector('input[name^="$ACTION"]')) start();
    };
    document.addEventListener("click", onClick); document.addEventListener("submit", onSubmit);
    return () => { document.removeEventListener("click", onClick); document.removeEventListener("submit", onSubmit); clearTimeout(t); };
  }, []);
  if (!busy) return null;
  return <div className="fixed inset-x-0 top-0 z-[60] h-1 overflow-hidden bg-brand/20" role="progressbar" aria-label="Loading"><div className="progress-bar h-full w-1/3 bg-brand" /></div>;
}
