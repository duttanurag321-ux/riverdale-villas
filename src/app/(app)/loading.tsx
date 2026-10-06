import { Spinner } from "@/components/Spinner";

export default function Loading() {
  return (
    <div aria-busy="true" role="status">
      <div className="mb-6 flex items-center gap-3 text-brand"><Spinner className="h-6 w-6" /><span className="text-sm font-medium text-slate-600">Loading…</span></div>
      <div className="mb-4 h-7 w-48 animate-pulse rounded bg-slate-200" />
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">{[0, 1, 2, 3].map((i) => <div key={i} className="h-20 animate-pulse rounded-lg bg-slate-200" />)}</div>
      <div className="mt-6 h-48 animate-pulse rounded-lg bg-slate-200" />
    </div>
  );
}
