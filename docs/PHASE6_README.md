# Phase 6 — Import, edit screens, backups, documentation

## New
- **Villa edit** and **Customer edit** screens (Director): details, assignments, price, WhatsApp consent, PAN replace/remove (never shown in full), archive.
- **Import CSV** (Settings, Import CSV): villas and customers. Download template, upload, preview, import. All-or-nothing; existing records skipped and never overwritten; max 500 rows per file. Bookings/payments are deliberately not importable.
- **Backups** page: CSV downloads of villas, customers (no PAN), bookings, schedules, ledger, allocations, outstanding balances.
- **Documentation:** 16 guides in `docs/` (see README), a generated database schema, a file inventory, and an optional GitHub build check (`.github/workflows/ci.yml`).

## Install (existing project)
1. Upload the ZIP contents to GitHub, replacing files; Vercel redeploys.
2. Supabase SQL Editor: run `supabase/migrations/009_csv_import.sql` once (008 only if you have not already set up the scheduler).
3. Try Settings, Import CSV with the fictional templates; then Backups.

## Tested vs not
Executed: 209 database checks pass on PostgreSQL 16 (adds 15 import checks: phone/amount parsing, atomic all-or-nothing, duplicates not overwritten, permissions, 500-row cap, audit). Type-check and build pass; browser CSV reader smoke-tested.
Not executed: the screens against live Supabase; real phone use; the optional GitHub workflow.
