import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

export const str = (fd: FormData, k: string) => String(fd.get(k) ?? "").trim();
export const opt = (fd: FormData, k: string) => str(fd, k) || null;

export function back(path: string, kind: "error" | "ok", msg: string): never {
  if (kind === "ok") revalidatePath("/", "layout");   // after a change, drop cached pages so lists are never stale
  redirect(`${path}${path.includes("?") ? "&" : "?"}${kind}=${encodeURIComponent(msg)}`);
}

/** Show our own business-rule messages, hide raw database internals. */
export function friendly(err: { message?: string; code?: string } | null | undefined): string {
  const m = err?.message ?? "";
  if (err?.code === "42501" || /not authorized|permission denied|row-level security/i.test(m)) return "You do not have permission to do that.";
  if (err?.code === "23505") return "That already exists.";
  if (/violates|constraint|syntax|relation|column/i.test(m)) return "Could not save. Please check the values and try again.";
  return m || "Something went wrong. Please try again.";
}
