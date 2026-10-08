"use client";
import { useState } from "react";
import { runImport, type ImportResult } from "./actions";

const REQUIRED = { villas: ["project", "villa_number", "list_price_inr"], customers: ["full_name", "phone"] } as const;
const inputCls = "block w-full text-sm";
const btn = "inline-flex items-center rounded-md bg-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-50";

/** Small CSV reader: handles quotes, commas and line breaks inside quotes. */
function parseCsv(text: string): string[][] {
  const rows: string[][] = []; let row: string[] = [], cell = "", q = false;
  const t = text.replace(/^\uFEFF/, "");
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"') { if (t[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c; }
    else if (c === '"') q = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && t[i + 1] === "\n") i++; row.push(cell); cell = ""; if (row.some((x) => x.trim() !== "")) rows.push(row); row = []; }
    else cell += c;
  }
  row.push(cell); if (row.some((x) => x.trim() !== "")) rows.push(row);
  return rows;
}

export default function ImportForm() {
  const [kind, setKind] = useState<"villas" | "customers">("villas");
  const [rows, setRows] = useState<Record<string, string>[]>([]);
  const [headers, setHeaders] = useState<string[]>([]);
  const [msg, setMsg] = useState<string | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [busy, setBusy] = useState(false);

  const missing = REQUIRED[kind].filter((h) => !headers.includes(h));

  async function onFile(f: File | undefined) {
    setResult(null); setMsg(null); setRows([]); setHeaders([]);
    if (!f) return;
    if (f.size > 1_000_000) return setMsg("That file is larger than 1 MB.");
    const parsed = parseCsv(await f.text());
    if (parsed.length < 2) return setMsg("The file needs a header row and at least one data row.");
    const h = parsed[0].map((x) => x.trim().toLowerCase());
    const data = parsed.slice(1).map((r) => Object.fromEntries(h.map((k, i) => [k, (r[i] ?? "").trim()])));
    if (data.length > 500) return setMsg("A file can have at most 500 rows. Split it into smaller files.");
    setHeaders(h); setRows(data);
  }
  async function go() {
    setBusy(true); setResult(null);
    try { setResult(await runImport(kind, rows)); } catch { setResult({ ok: false, errors: "Something went wrong. Nothing was saved." }); }
    setBusy(false);
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-4 text-sm">
        <label><input type="radio" checked={kind === "villas"} onChange={() => { setKind("villas"); setRows([]); setResult(null); }} /> Villas</label>
        <label><input type="radio" checked={kind === "customers"} onChange={() => { setKind("customers"); setRows([]); setResult(null); }} /> Customers</label>
        <a className="text-brand underline" href={`/exports/template-${kind}`}>Download the {kind} template</a>
      </div>
      <input type="file" accept=".csv,text/csv" className={inputCls} key={kind} onChange={(e) => onFile(e.target.files?.[0])} />
      {msg && <div role="alert" className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">{msg}</div>}
      {rows.length > 0 && missing.length > 0 && <div role="alert" className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">This file is missing required column(s): {missing.join(", ")}. Use the template.</div>}
      {rows.length > 0 && missing.length === 0 && !result && (
        <div className="space-y-3">
          <div className="text-sm"><b>{rows.length}</b> row(s) found. Preview of the first 5:</div>
          <div className="overflow-x-auto rounded border border-slate-200 bg-white"><table className="min-w-full text-xs"><thead className="bg-slate-50 text-left"><tr>{headers.map((h) => <th key={h} className="px-2 py-1">{h}</th>)}</tr></thead>
            <tbody>{rows.slice(0, 5).map((r, i) => <tr key={i} className="border-t">{headers.map((h) => <td key={h} className="px-2 py-1">{h === "pan" && r[h] ? "XXXXX" + r[h].slice(5) : r[h]}</td>)}</tr>)}</tbody></table></div>
          <p className="text-xs text-slate-500">Existing {kind === "villas" ? "villas (same project and number)" : "customers (same phone)"} are skipped, never changed. If any row has a problem, nothing is saved and every problem is listed.</p>
          {kind === "customers" && <p className="text-xs text-amber-700">Only put &ldquo;yes&rdquo; in whatsapp_consent for customers who have actually agreed to receive WhatsApp messages.</p>}
          <button onClick={go} disabled={busy} className={btn}>{busy ? "Importing… please wait" : `Import ${rows.length} row(s)`}</button>
        </div>)}
      {result?.ok === true && (<div role="status" className="rounded-md border border-green-200 bg-green-50 px-3 py-2 text-sm text-green-800">Imported {result.inserted} {kind}. {result.duplicates.length > 0 && <>Skipped {result.duplicates.length} that already exist: {result.duplicates.map((d) => `row ${d.row}`).join(", ")}.</>}</div>)}
      {result?.ok === false && (<div role="alert" className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800"><b>Nothing was saved.</b>
        {typeof result.errors === "string" ? <> {result.errors}</> : <ul className="mt-1 list-disc pl-5">{result.errors.map((e, i) => <li key={i}>Row {e.row}: {(e.problems ?? []).join("; ")}</li>)}</ul>}
        <p className="mt-1">Fix the file and choose it again.</p></div>)}
    </div>
  );
}
