import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";

/** Standard PDF fonts only cover basic Latin, so amounts use "Rs." and other characters become "?". */
const clean = (t: string) => t.replace(/[\u2013\u2014]/g, "-").replace(/[\u2018\u2019]/g, "'").replace(/[\u201c\u201d]/g, '"').replace(/[^\x20-\x7E]/g, "?");
export const pdfMoney = (paise: number) => "Rs. " + new Intl.NumberFormat("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(paise / 100);
export const pdfDate = (d: string | null | undefined) => (d ? new Date(d).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric", timeZone: "Asia/Kolkata" }) : "-");
const NAVY = rgb(0.06, 0.12, 0.24);

export class Pdf {
  page!: PDFPage; y = 800;
  private constructor(private doc: PDFDocument, private font: PDFFont, private bold: PDFFont) {}
  static async create() {
    const doc = await PDFDocument.create();
    const p = new Pdf(doc, await doc.embedFont(StandardFonts.Helvetica), await doc.embedFont(StandardFonts.HelveticaBold));
    p.newPage(); return p;
  }
  newPage() { this.page = this.doc.addPage([595, 842]); this.y = 800; }
  text(t: string, o: { size?: number; bold?: boolean; x?: number; gap?: number } = {}) {
    const size = o.size ?? 10; if (this.y < 60) this.newPage();
    this.page.drawText(clean(t).slice(0, 110), { x: o.x ?? 50, y: this.y, size, font: o.bold ? this.bold : this.font, color: NAVY });
    this.y -= size + (o.gap ?? 5);
  }
  row(cells: { t: string; x: number; bold?: boolean }[], size = 9) {
    if (this.y < 60) this.newPage();
    cells.forEach((c) => this.page.drawText(clean(c.t).slice(0, 34), { x: c.x, y: this.y, size, font: c.bold ? this.bold : this.font, color: NAVY }));
    this.y -= size + 6;
  }
  rule() { this.page.drawLine({ start: { x: 50, y: this.y + 4 }, end: { x: 545, y: this.y + 4 }, thickness: 0.6, color: rgb(0.8, 0.83, 0.88) }); this.y -= 8; }
  space(n: number) { this.y -= n; }
  async bytes() { return this.doc.save(); }
}

export const pdfResponse = (bytes: Uint8Array, filename: string) =>
  new Response(Buffer.from(bytes), { headers: { "Content-Type": "application/pdf", "Content-Disposition": `inline; filename="${filename}"`, "Cache-Control": "private, no-store" } });
