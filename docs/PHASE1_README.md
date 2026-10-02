# Riverdale Villas — Phase 1: Database Foundation

## What is in this phase
- `supabase/migrations/001_schema.sql` … `004_seed_reference_data.sql` — run in this order.
- `supabase/tests/` — automated tests (shim + 66 checks) that run on a plain PostgreSQL.

## Setting it up in Supabase (browser only)
1. Create a free project at supabase.com. Note the project is paused after about 7 days of inactivity on the free tier.
2. Left menu -> **SQL Editor** -> **New query**.
3. Open `001_schema.sql` on GitHub (or from the ZIP), copy ALL the text, paste, click **Run**. Expect "Success. No rows returned".
4. Repeat for `002`, then `003`, then `004`. Never run a file twice (the second run fails with "already exists"; that is harmless but means nothing changed).
5. Create the first Director: **Authentication -> Users -> Add user -> Create new user** (email + strong password, tick Auto Confirm). Copy that user's **UID**.
6. SQL Editor, new query (paste your UID and name):
   `select public.bootstrap_first_director('PASTE-UID-HERE', 'Your Name');`
   This only works while no Director exists and cannot be called from the app.
7. Check: `select * from profiles;` shows you as `director`.

Employees are added later by the Director (Phase 2 screen): create the Auth user, then a `profiles` row.

## Key design decisions
- Money = bigint paise. Percentages = basis points. Leftover paise from rounding go to the last milestone.
- Bookings, ledger and milestone status change ONLY through functions (confirm_booking, verify_payment, ...). Browser/API table writes cannot bypass them.
- Ledger (payments, payment_allocations, audit_logs) is append-only. Corrections = reversal rows.
- Balances are views (v_milestone_balances, v_booking_balances), never stored.
- Events go to `domain_events` with a unique key, so retries never duplicate activations. WhatsApp sending (Phase 5) reads this table, so a WhatsApp failure can never undo a business action.
- Overdue = due date + grace days passed and unpaid. Not related to construction progress.

## Known limits in Phase 1
- Only full reversal of a payment; partial refunds and payment-plan amendments come in Phase 4.
- A Director may report and verify their own payment (single-Director business). Salespeople can never verify.
- Notifications, follow-up outcomes, receipts PDF, storage buckets and the UI are later phases.

## Test status (honest)
Executed: 66 checks passed on PostgreSQL 16 using a small shim that imitates Supabase's `auth.uid()` and roles.
NOT executed: anything on a real Supabase project. Run the migrations on a fresh test project first, with fictional data only.
Re-run tests: `su postgres -c "bash supabase/tests/run_tests.sh"` on a machine with PostgreSQL.
