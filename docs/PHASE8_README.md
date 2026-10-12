# Phase 8 — Autopilot: the Director only handles exceptions

## Goal
Keep the Director free. Site Managers and Salespeople keep the work moving; the system asks for payments, reminds, and reports by itself; the Director confirms money, confirms new bookings, and says "OK" to unusual requests. Home proves it: one green banner when everything is running.

## What the system now does by itself
- **Construction steps:** ordinary steps count the moment the Site Manager submits them (no waiting). Only four key steps (Foundation, First slab, Final inspection, Handover) wait for the Director, and even those are **approved automatically after 24 hours** if the Director does nothing (hours are a setting; 0 = never).
- **Payment requests:** when a step is completed, the system asks the customer for the suggested amount automatically (record kept, call task and WhatsApp draft created). Limits: nothing above 10% of the price at a time (setting) and nothing below Rs 25,000 (setting). A bigger request appears on Home as one tap: "OK to ask Mr Das for Rs X?".
- **Before construction:** once the earlier request (for example the 10% booking amount) is paid, the system asks for the money needed to reach the start percentage (40% by default). Turn it off in Settings if you prefer to do this one yourself.
- **Bookings:** the Salesperson prepares a booking (their own villa and customer, price from the villa list, token if any). The Director only presses Confirm.
- **Money checking, once a day:** Money screen shows one list: tick what you see in your bank, press **Confirm selected payments**. A reminder arrives at about 6 pm if payments are waiting.
- **Staff watching:** the system notices a Site Manager with no update for 7 days, a Salesperson with calls more than 3 days late, customer messages not sent for 2 days, and tells the Director only then.

## What the Director sees (Home)
1. A banner: **Everything is running automatically** (green) / **A few things need a nudge** (amber, with names) / **The automatic system needs attention** (red).
2. **Needs you**: payments to confirm, new bookings to confirm, big requests to OK.
3. **Where every villa is**: Token/new → Collecting → Building → Handed over.
4. **Money this week**: received, asked and waiting, late; how many requests and approvals the system made.
5. **What just happened**: plain-language activity (for example "The system asked Mr Das for Rs 5,40,000 (Foundation completed payment) - Villa A1").

## Install
1. Upload the ZIP contents to GitHub (replace files); Vercel redeploys.
2. Supabase SQL Editor: run `supabase/migrations/011_autopilot.sql` once (after 001-010).
   - It sets most construction steps to "no approval needed" and only the four key steps to "needs approval". It also fixes a bug where a booking with no "balance asked later" line could show a suggestion.
   - If pg_cron is already switched on it schedules two jobs (autopilot every 15 minutes, payment reminder at 6 pm India). If not, switch on pg_cron (Database, Extensions) and run the file again is NOT needed: instead run `select cron.schedule('riverdale-autopilot','*/15 * * * *','select public.autopilot_tick()'); select cron.schedule('riverdale-confirm-reminder','30 12 * * *','select public.remind_pending_payments()');`
   - Without the scheduler, use **More, Settings, Run autopilot now**; Home will show a warning that automatic checks are not running.
3. More, Settings: look at the new **Autopilot** card and adjust the limits to your comfort.

## Tested vs not
Executed: 318 database checks on PostgreSQL 16 (all earlier checks plus 51 new: automatic approval timing, automatic requests and their limits, no double requests, Director OK for big ones, switches, salesperson booking rules, overview colours, activity feed, daily reminder). Type-check and build pass.
Not executed: the screens on live Supabase; the real scheduler; how it feels to the Director. Please run with fictional data and watch what the system does by itself for a week before using real customers.

## Honest limits
- Money must still be confirmed by the Director, because the system cannot see the bank. This is a deliberate safety. It takes about one minute a day.
- The automatic suggestion counts all construction steps equally and assumes a full villa. Foundation-only or tin-shed jobs will under-ask; the Director can ask manually, or you can switch autopilot off for now.
- An automatically approved step cannot be un-approved later (it can be corrected by a new update).
- Auto-asks use the percent limit of the price; set the limit lower while you build trust.
