const inrFmt = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 });
export const inr = (paise: number | null | undefined) => (paise == null ? "—" : inrFmt.format(paise / 100));

export const fmtDate = (d: string | null | undefined) =>
  d ? new Date(d).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric", timeZone: "Asia/Kolkata" }) : "—";

/** "60,00,000" or "6000000.50" -> integer paise, with no floating-point arithmetic. Returns null if invalid. */
export function rupeesToPaise(input: string): number | null {
  const s = input.replace(/[,\s₹]/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const [r, p = ""] = s.split(".");
  const paise = Number(r) * 100 + Number(p.padEnd(2, "0"));
  return Number.isSafeInteger(paise) && paise > 0 ? paise : null;
}

/** 10-digit Indian mobile -> +91XXXXXXXXXX; otherwise accept a +country number; else null. */
export function normalizePhone(input: string): string | null {
  const d = input.replace(/[\s-]/g, "");
  if (/^[6-9]\d{9}$/.test(d)) return "+91" + d;
  if (/^(91|0)[6-9]\d{9}$/.test(d.replace(/^\+/, ""))) return "+91" + d.replace(/^\+?(91|0)/, "");
  if (/^\+[1-9]\d{7,14}$/.test(d)) return d;
  return null;
}

export const maskPan = (pan: string | null | undefined) => (pan ? "XXXXX" + pan.slice(5) : "—");
export const titleCase = (s: string) => s.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());
