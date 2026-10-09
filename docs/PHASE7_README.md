# Phase 7 — The real Riverdale flow, and a simple Director experience

## Your business flow, now in the system
Token → 10% booking → 40-50% before construction (own money or loan) → payment requests whenever the company needs funds, each with a construction update.

## What changed
- **Token**: record a token when creating a booking (before it is confirmed). The villa becomes Reserved. On confirmation the token is subtracted from the booking amount automatically. Any early or extra payment waits as "credit" and is applied to the next request automatically.
- **Funding route**: Own money or Bank loan (bank, sanctioned amount). Loan instalments are recorded as "paid by the bank"; the Director verifies them like any payment.
- **Construction start rule**: construction is locked until about 40% of the price is verified (the percentage is a setting) or the Director presses "Allow construction to start now". The Site Manager only sees "waiting for payment", never amounts.
- **Ask for payment**: one screen on each booking. Shows a plain-words suggestion (collections follow construction: start % first, then rising as steps are completed and approved), plus 5%, 10%, everything left, or the Director's own amount in rupees or percent. It records what was suggested and what was chosen, tells the Salesperson to call, and prepares the WhatsApp message with the update and amount.
- **Stage approval no longer triggers payments by itself** (that was the old fixed-plan behaviour). After approving, the app offers "Ask for payment?".
- **Starter plan** "Riverdale standard": 10% booking + 90% "balance asked later". Editable under More → Payment plans (tick "Balance asked for later" on one line).
- **Simple Director screens**: Home shows only what needs action (payments to check, updates to approve, late payments, customers to ask for money, three money numbers). Navigation reduced to six plain items; everything else is under More.

## Install (existing project)
1. Upload the ZIP contents to GitHub (replace files); Vercel redeploys.
2. Supabase SQL Editor: run `supabase/migrations/010_real_flow.sql` once (after 001-009).
3. Existing bookings keep working. Confirmed bookings that were made from older plans have no "balance asked later" line, so "Ask for payment" says there is none; use "Change plan" or create new bookings from the starter plan.
4. If you want a different start percentage: More → Settings → "Construction may start after this % …".

## Tested vs not tested
- Executed: 267 database checks pass on PostgreSQL 16 (all earlier checks still pass, plus 58 new: token adjustment, gate open/locked and permissions, suggestion numbers, demands, double-click safety, loan instalments opening the gate, credit applied automatically, schedule always totals the contract value).
- Executed: type-check and production build.
- NOT executed: the new screens on live Supabase/Vercel and with the Director. Please test with fictional data and tell me what feels confusing.

## Known limits
- Scopes (foundation only / tin shed / full villa) are not separate yet: all construction steps count equally in the suggestion, so for partial scopes type your own amount. Step weights exist in the database but have no screen.
- The suggestion rounds down to ₹10,000 steps (a setting in the database, no screen).
- A booking that already had a fixed plan keeps it; there is no automatic conversion.
