"use client";
import { useFormStatus } from "react-dom";
import { Spinner } from "./Spinner";

/** Submit button for server-action forms: shows a spinner, blocks repeat clicks, and dims the screen with "Working…" until the server answers. */
export function SubmitButton({ children, className, pendingText = "Working…", disabled }: { children: React.ReactNode; className?: string; pendingText?: string; disabled?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <>
      <button type="submit" disabled={pending || disabled} aria-busy={pending} className={className}>
        {pending ? <span className="inline-flex items-center gap-2"><Spinner />{pendingText}</span> : children}
      </button>
      {pending && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-white/70" role="status" aria-live="polite">
          <div className="flex items-center gap-3 rounded-lg bg-white px-5 py-3 text-brand shadow-lg ring-1 ring-slate-200"><Spinner className="h-5 w-5" /><span className="text-sm font-medium text-navy-900">{pendingText}</span></div>
        </div>
      )}
    </>
  );
}
