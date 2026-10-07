# Phase 5 — Free notifications, reminders, reports

## What changed from the original plan (and why)
You asked for no WhatsApp subscription and nothing that can exceed Supabase's free limits. So this phase uses **no paid services, no Edge Functions and no Realtime**.
- **Official WhatsApp Business API is NOT used.** Meta charges per message and needs business verification; it cannot be free. Instead the system **prepares each customer message** (right wording, amounts, dates, receipt number) and the Salesperson taps **Send on WhatsApp**: it opens their own WhatsApp with the text already typed. They press send, then mark it sent. Nothing goes out automatically, so there is also no delivery/read tracking: "sent" means a staff member confirmed it.
- Messages are prepared only for customers who ticked WhatsApp consent.
- **Staff alerts** appear in the bell icon (top right) and the Notifications page. There are no push or SMS alerts; staff see them when they open the app.
- **Automation runs inside the database** (free): alerts are created the moment something happens; reminders, overdue checks and summaries run every morning (~9:00 India) with Supabase's built-in scheduler (pg_cron).

## What you get
- Alerts: update needs approval, update rejected (with reason), stage approved, delay, payment reported, payment verified, payment reversed, booking confirmed, milestone now payable, handover, escalations.
- Daily checks: reminders 7 and 2 days before due (days are editable), due-today, overdue (after grace days), repeated overdue reminders (every 7 days, max 4, editable), Director alert after N overdue days, overdue follow-ups, missed promised dates, one short daily summary per person (only if something needs attention), Monday weekly report for the Director.
- Failures never undo business actions. If preparing an alert fails, the payment/approval stays saved; the system retries (every 15 min, max 5 times) and tells the Director if it gives up.
- Director pages: **Settings** (edit all message wording, reminder numbers, usage meter, "Run checks now"), **Reports** (live figures, CSV exports of payments and outstanding balances).
- Messages page for Salesperson/Director. Everyone has Notifications.

## Staying inside the free limits
- Database 500 MB: this phase adds small text rows only (a handful per event). Old notifications and handled messages are deleted automatically after 90 days (editable). Rough estimate: 100 bookings generating ~3,000 notifications and ~1,500 drafts a month is a few MB a month.
- Photos use the separate 1 GB storage (compressed to ~300 KB each, so roughly 3,000 photos). The Settings page shows both meters in colour; at 60% it warns you.
- No Edge Functions (limit never touched), no Realtime. The bell does ONE tiny count request per page visit; there is no polling.
- Free Supabase projects pause after about a week of no activity: daily jobs do not wake a paused project. Open the app weekly, or Restore in the dashboard.
- I cannot see your live usage. Check Supabase -> Settings -> Usage monthly, and confirm the limits there; they may change.

## Install (existing project)
1. Upload this ZIP's contents to GitHub (replace when asked); Vercel redeploys.
2. Supabase -> SQL Editor -> New query -> paste `supabase/migrations/007_notifications_free.sql` -> Run (once). It also sets the database clock to India time.
3. Turn on the scheduler: Supabase -> Database -> Extensions -> search **pg_cron** -> switch on.
4. New query -> paste `supabase/migrations/008_schedule_jobs.sql` -> Run.
5. Check: SQL Editor -> run `select jobname, schedule from cron.job;` -> two rows. If step 3/4 fails, the app still works; use **Settings -> Run checks now** each morning.

## Try it (fictional data)
1. Confirm a booking for a customer who has WhatsApp consent ticked. Log in as the Salesperson: the bell shows alerts and **Messages** has a booking-confirmed message and a payment-due message.
2. Tap Send on WhatsApp, see the text opens in WhatsApp, come back, Mark as sent.
3. Report a payment as Salesperson; the Director's bell shows "Payment to verify". Verify it; the Salesperson gets "Payment verified" and an acknowledgement message with the receipt number.
4. Director: Settings -> Run checks now.

## Tested vs not tested
- Executed: 179 database checks pass on PostgreSQL 16, including: alerts reach only the right people, no duplicates when events or daily checks repeat, reminder/overdue/escalation timing, failure isolation and retry limit, permissions, retention clean-up, Indian rupee formatting. Type-check and production build pass.
- NOT executed: pg_cron scheduling on real Supabase, opening WhatsApp from a phone, and the new screens against live Supabase. The Monday weekly report logic ran without error only in code review, not on a Monday.
- Upper bound of free limits is from my knowledge; verify in your dashboard.

## Not built (decided or deferred)
- Official WhatsApp API, delivery/read status, webhook, templates approved by Meta (cost). Web push / SMS / email alerts (not free or not simple). Realtime live updates.
- Unicode PDF fonts, partial refunds, villa edit screen, CSV import (Phase 6).
