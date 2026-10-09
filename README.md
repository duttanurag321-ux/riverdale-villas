# Riverdale Villas — Construction & Payment Management System

A web app for a villa developer: villas, customers, bookings, construction updates with photos, approvals, payment plans, a verified payment ledger, receipts, follow-ups, alerts, reports and CSV import. Three roles only: Site Manager, Salesperson, Director.

**Stack:** Next.js (App Router, TypeScript, Tailwind) · Supabase (Postgres, Auth, Storage, Row Level Security) · Vercel (free) · GitHub. No paid services, no Edge Functions, no automatic WhatsApp.

## Start here
New to this? Read **docs/BEGINNER_SETUP_GUIDE.md** (browser-only steps). Then the manual for your role: docs/DIRECTOR_MANUAL.md, SALESPERSON_MANUAL.md, SITE_MANAGER_MANUAL.md.

## Documents
DIRECTOR_QUICK_GUIDE · BEGINNER_SETUP_GUIDE · GITHUB_WEB_WORKFLOW · SUPABASE_SETUP · DEPLOYMENT_GUIDE · WHATSAPP_SETUP · DATABASE_SCHEMA · DAILY_USER_MANUAL · DIRECTOR/SITE_MANAGER/SALESPERSON manuals · BACKUP_AND_RECOVERY · TROUBLESHOOTING · SECURITY_CHECKLIST · TESTING_GUIDE · COSTS_AND_LIMITS · FILE_INVENTORY · PHASE1…PHASE7 notes (history of what each build added).

## Layout
`supabase/migrations` (SQL 001-010, run in order) · `supabase/tests` (database tests) · `supabase/dev` (optional sample plan) · `src` (app) · `docs` · `.env.example` (variable names only) · `vercel.json` (Singapore region).

## Decisions worth knowing
- Money is stored as integer paise; payments are an append-only ledger; balances are always calculated.
- Booking schedules are frozen copies; changes go through an audited amendment.
- Reported payments count only after the Director verifies them.
- Customer WhatsApp messages are prepared as drafts that staff send from their own WhatsApp (free).

## Honest status
Database logic: 267 automated checks passed on PostgreSQL 16. App: type-check and build pass. **Not yet tested by a human on a live Supabase/Vercel set-up for every screen.** Test with fictional data first (docs/TESTING_GUIDE.md). Not built: official WhatsApp API, partial refunds, Unicode PDFs, booking/payment CSV import, in-app audit-log viewer, document uploads.
