# Testing guide

## What was tested and how
- **Database tests** (`supabase/tests`): 267 checks, executed on PostgreSQL 16 using a small imitation of Supabase's login and storage. Covers: payment rules (partial payments, allocation limits, reversals, no self-service verification), duplicate prevention (activations, events, reminders, imports), role access (what each role can and cannot read or change), construction approval/reject/resubmit/handover, follow-ups, amendments and holds, notifications, retries, retention, CSV imports, tokens, the construction start gate, payment demands and the suggestion (including loan instalments and credit being applied to a new demand).
- **App**: TypeScript strict type-check and production build passed; the browser CSV reader and PDF generator were smoke-tested.
- **Not tested**: the screens clicked through against a live Supabase project, phone photo uploads, pg_cron on Supabase, real speed on Vercel, automated browser tests, mobile layout tests. Please do the manual test below.

## Manual test (use fictional data)
Follow BEGINNER_SETUP_GUIDE Part 9, then also check: a Site Manager cannot open /payments or /customers by typing the address (they are sent to the dashboard); a Salesperson cannot verify a payment (no button, and the database refuses); importing a bad CSV saves nothing; double-clicking Submit creates one record.

## Re-running the database tests (optional, advanced)
On a computer with PostgreSQL: `su postgres -c "bash supabase/tests/run_tests.sh"`. It builds a throwaway database `riverdale_test`. Never point it at your real project.

## Before going live
Run the full manual test on a separate test Supabase project, then repeat setup on the real one.
