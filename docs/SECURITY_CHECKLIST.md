# Security checklist

## Built in (what the system does)
- No public sign-up; only the Director creates accounts; the first Director is bootstrapped once by SQL.
- Roles are read from the database on the server for every page; the browser cannot claim a role. Users cannot edit their own role (RLS), and the last Director cannot be removed.
- Row Level Security on every table. Site Managers cannot read prices, customers, bookings or payments; Salespeople only their own customers/bookings; PAN only the Director, in a separate table, shown masked.
- Payments: salespeople can only report; only the Director verifies; ledger, allocations, audit log, call log and schedule history are append-only; money is integer paise.
- Photos in a private bucket; viewed through links that expire in an hour; nobody can edit or delete them via the app.
- Service-role key only in one server file, used after a Director check; never in the browser.
- Customer data in CSV exports and imports is Director-only; spreadsheet formula injection is neutralised in exports.
- Server actions have built-in same-origin protection (Next.js); forms validate input on the server; errors hide database internals.
- WhatsApp messages never contain PAN or documents. No WhatsApp or other third-party credentials are stored.

## Your tasks before real data
- [ ] Strong, unique passwords for Supabase, GitHub, Vercel (use a password manager and turn on two-factor sign-in on all three).
- [ ] Repository is **Private**; no `.env` file or keys ever uploaded.
- [ ] Service-role key marked **Sensitive** in Vercel; rotate it if ever exposed (SUPABASE_SETUP.md).
- [ ] Employees use their own accounts; deactivate leavers the same day.
- [ ] Monthly backup downloaded and stored privately (BACKUP_AND_RECOVERY.md).
- [ ] Review **Users** monthly. Check the audit log in Supabase (`select * from audit_logs order by at desc limit 50;`) after unusual events.
- [ ] Only collect PAN if legally needed; do not store Aadhaar.
- [ ] Get advice on India's data-protection rules (DPDP Act) and RERA obligations for your business; this software does not make you compliant by itself.

## Known limits
No rate limiting on login beyond Supabase's defaults; no automatic idle logout; no in-app audit-log viewer (use the Supabase dashboard); sensitive-document uploads and a full-PAN reveal are not built (so there is no screen that can leak them).
