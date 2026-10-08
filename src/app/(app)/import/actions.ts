"use server";
import { createClient } from "@/lib/supabase/server";
import { requireMe } from "@/lib/auth";

export type ImportResult = { ok: true; inserted: number; duplicates: { row: number; reason: string }[] } | { ok: false; errors: { row?: number; problems?: string[] }[] | string };

export async function runImport(kind: "villas" | "customers", rows: Record<string, string>[]): Promise<ImportResult> {
  await requireMe(["director"]);
  if (!Array.isArray(rows) || rows.length === 0 || rows.length > 500) return { ok: false, errors: "A file must contain between 1 and 500 rows." };
  const clean = rows.map((r) => Object.fromEntries(Object.entries(r).slice(0, 20).map(([k, v]) => [String(k).slice(0, 40), String(v ?? "").slice(0, 500)])));
  const { data, error } = await createClient().rpc(kind === "villas" ? "import_villas" : "import_customers", { p_rows: clean });
  if (error) return { ok: false, errors: /not authorized/i.test(error.message) ? "You do not have permission to import." : error.message.replace(/violates.*/i, "could not be saved") };
  return data as ImportResult;
}
