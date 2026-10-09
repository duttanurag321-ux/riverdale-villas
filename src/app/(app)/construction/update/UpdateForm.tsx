"use client";
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createBrowserSupabase } from "@/lib/supabase/client";
import { submitUpdate } from "../actions";

interface Opt { id: string; label: string }
const inputCls = "w-full rounded-md border border-slate-300 bg-white px-3 py-3 text-base focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand";

// Shrinks phone photos (often 4-8 MB) to about 1600 px JPEG before upload: faster on mobile data, fits free storage longer.
async function compress(file: File): Promise<Blob> {
  const bmp = await createImageBitmap(file);
  const scale = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
  const c = document.createElement("canvas");
  c.width = Math.round(bmp.width * scale); c.height = Math.round(bmp.height * scale);
  c.getContext("2d")!.drawImage(bmp, 0, 0, c.width, c.height);
  return new Promise((res, rej) => c.toBlob((b) => (b ? res(b) : rej(new Error("Could not read that photo"))), "image/jpeg", 0.8));
}

export default function UpdateForm({ villas, stages, initialVilla, locked = [] }: { villas: Opt[]; stages: Opt[]; initialVilla?: string; locked?: string[] }) {
  const router = useRouter();
  const requestId = useRef(crypto.randomUUID());   // same id on retry => no duplicate update
  const [villa, setVilla] = useState(initialVilla ?? "");
  const [stage, setStage] = useState("");
  const [status, setStatus] = useState("in_progress");
  const [remarks, setRemarks] = useState("");
  const [isIssue, setIsIssue] = useState(false);
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault(); setMsg(null);
    if (!villa || !stage) return setMsg("Choose a villa and a stage.");
    if (locked.includes(villa)) return setMsg("Construction cannot start on this villa yet. The Director will release it once the customer's payment is confirmed.");
    if (status === "completed" && files.length === 0) return setMsg("Add at least one photo to mark a stage completed.");
    if (status === "delayed" && !remarks.trim()) return setMsg("Please say why the work is delayed.");
    setBusy(true);
    try {
      const sb = createBrowserSupabase();
      const paths: string[] = [];
      for (let i = 0; i < files.length; i++) {
        const blob = await compress(files[i]);
        const path = `${villa}/${requestId.current}/${i}.jpg`;
        const { error } = await sb.storage.from("construction-photos").upload(path, blob, { contentType: "image/jpeg" });
        if (error && !/already exists|duplicate/i.test(error.message)) throw new Error("Photo upload failed. Check your connection and try again.");
        paths.push(path);
      }
      const res = await submitUpdate({ villaId: villa, stageId: stage, status, remarks, isIssue, requestId: requestId.current, paths });
      if (!res.ok) { setMsg(res.error); setBusy(false); return; }
      router.push(`/construction/villa/${villa}?ok=${encodeURIComponent("Update submitted.")}`);
    } catch (err) { setMsg(err instanceof Error ? err.message : "Something went wrong. Please try again."); setBusy(false); }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5">
      {busy && <div className="fixed inset-0 z-50 flex items-center justify-center bg-white/80" role="status"><div className="rounded-lg bg-white px-5 py-4 text-center shadow-lg ring-1 ring-slate-200"><div className="mx-auto mb-2 h-6 w-6 animate-spin rounded-full border-4 border-brand/25 border-t-brand" /><p className="text-sm font-medium">Uploading photos and saving…</p><p className="text-xs text-slate-500">Please keep this screen open.</p></div></div>}
      {msg && <div role="alert" className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">{msg}</div>}
      <label className="block"><span className="mb-1 block text-sm font-medium">1. Villa</span>
        <select className={inputCls} value={villa} onChange={(e) => setVilla(e.target.value)} required><option value="">Select villa…</option>{villas.map((v) => <option key={v.id} value={v.id} disabled={locked.includes(v.id)}>{v.label}{locked.includes(v.id) ? " — waiting for payment" : ""}</option>)}</select></label>
      <label className="block"><span className="mb-1 block text-sm font-medium">2. Construction stage</span>
        <select className={inputCls} value={stage} onChange={(e) => setStage(e.target.value)} required><option value="">Select stage…</option>{stages.map((s) => <option key={s.id} value={s.id}>{s.label}</option>)}</select></label>
      <fieldset><legend className="mb-1 text-sm font-medium">3. What is the status?</legend>
        <div className="grid grid-cols-3 gap-2">{[["in_progress", "In progress"], ["delayed", "Delayed"], ["completed", "Completed"]].map(([v, l]) => (
          <button type="button" key={v} onClick={() => setStatus(v)} aria-pressed={status === v}
            className={`rounded-md border px-2 py-3 text-sm font-medium ${status === v ? "border-brand bg-brand text-white" : "border-slate-300 bg-white"}`}>{l}</button>))}</div></fieldset>
      <label className="block"><span className="mb-1 block text-sm font-medium">4. Photos {status === "completed" ? "(required)" : "(optional)"} — up to 6</span>
        <input type="file" accept="image/*" multiple onChange={(e) => setFiles(Array.from(e.target.files ?? []).slice(0, 6))} className="block w-full text-sm" />
        {files.length > 0 && <span className="mt-1 block text-xs text-slate-500">{files.length} photo(s) selected</span>}</label>
      <label className="block"><span className="mb-1 block text-sm font-medium">5. Remarks {status === "delayed" ? "(reason required)" : "(optional)"}</span>
        <textarea rows={3} className={inputCls} value={remarks} onChange={(e) => setRemarks(e.target.value)} maxLength={1000} /></label>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isIssue} onChange={(e) => setIsIssue(e.target.checked)} className="h-5 w-5" /> There is an issue the Director should know about</label>
      {locked.includes(villa) && <div role="alert" className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900">This villa is waiting for the customer's payment. The Director will tell you when construction can start.</div>}
      <button disabled={busy || locked.includes(villa)} className="w-full rounded-md bg-brand px-4 py-4 text-base font-semibold text-white disabled:opacity-50">{busy ? "Uploading… please wait" : "Submit update"}</button>
    </form>
  );
}
