# Phase 4 — Payments, plans, follow-ups, receipts + speed

## Speed and "is it working?" fixes
- **Biggest cause of slowness: distance.** Vercel runs your app in one region; every page makes several calls to Supabase. If they are on different continents each call costs 0.2-0.3 s. `vercel.json` now pins the app to Singapore (`sin1`), matching the Supabase project. If you ever move Supabase, change the region in `vercel.json` (Mumbai is `bom1`). (Supabase: Project Settings -> Infrastructure shows the region.)
- Login check is done once per page (it used to be done 3+ times), and no longer needs an extra network trip.
- Back/forward and revisits reuse recent pages for a short time (30 s) instead of reloading.
- Database indexes added for the lists opened most (migration 006).
- **Loading feedback:** a blue bar at the top the moment you tap a link or search; skeleton screens while a page loads; every Save/Submit button shows a spinner, locks itself, and dims the screen with "Working…" so repeat taps do nothing.

## New screens
- **Payments** (Director, Salesperson): report a payment (stays Pending), Director verifies (auto-applies to the oldest due milestone, or pick one), rejects, or reverses. Receipt PDF only for verified payments; re-downloading never makes a new payment.
- **Payment plans** (Director): create templates, edit milestones (percent or fixed, trigger, stage, due days, grace). Shows a live "totals 100%" check.
- **Follow-ups** (Salesperson, Director): open tasks with one-tap Call and WhatsApp (opens WhatsApp chat; it does NOT send automatic messages yet), call outcomes, promised dates (reschedules the same task), history, mark done.
- **Booking page**: payment ledger, Statement PDF, hold/release a milestone, amend future milestones (old schedule saved to history).

## Install (existing project)
1. GitHub -> Add file -> Upload files: drag in the contents of the ZIP (replace when asked) and commit. **Check `vercel.json` region first** (see above).
2. Supabase -> SQL Editor -> New query -> paste `supabase/migrations/006_followups_amendments.sql` -> Run (once only). 005 must already have been run.
3. Wait for Vercel to finish deploying.

## Try it (fictional data)
1. Plans -> create plan, add milestones totalling 100% (or run `supabase/dev/sample_payment_plan.sql` from Phase 2).
2. Create a booking with that plan and Confirm. Follow-ups now shows a task for the booking-time payment.
3. As Salesperson: Report payment -> as Director: Payments -> Verify -> open the receipt PDF.
4. Booking page: check Outstanding dropped; try Statement (PDF).

## Tested vs not tested
- Executed: 119 database checks pass on PostgreSQL 16 (all phases; includes follow-ups, amendments, holds, ledger protection). TypeScript type-check and production build pass. PDF generator smoke-tested (valid PDF, many rows, special characters).
- NOT executed: the screens against live Supabase, and the real speed gain on Vercel. Please tell me how fast it feels after the region fix.

## Limits
- PDFs use standard fonts: "Rs." instead of the rupee sign; non-English letters in names show as "?". Embedding a Unicode font is a later improvement.
- Reversal is whole-payment only (no partial refunds yet).
- Verify can apply a payment to one chosen milestone or automatically; splitting one payment across several chosen milestones by hand is not in the screen yet (the database supports it).
- No automatic WhatsApp or in-app notifications, reminders or daily reports yet (Phase 5). Missed promised dates are not flagged until then.
- Statement is for the booking's customer; no Director "all customers" report yet (Phase 5/6).
