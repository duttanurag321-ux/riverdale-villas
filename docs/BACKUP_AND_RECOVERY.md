# Backup and recovery

## The honest picture
On the free Supabase plan there are, as far as I know, **no automatic backups you can restore from** (paid plans add daily backups). Verify in Supabase, **Database**, **Backups**. Your safety net is your own regular downloads.

## Monthly routine (10 minutes)
1. Log in as Director, **Settings**, **Backups**.
2. Download all the CSV files (villas, customers, bookings, payment schedules, payment ledger, allocations, outstanding balances).
3. Save them in a private folder with the date (for example `2026-11-01`), plus a copy in a second place (another drive or private cloud folder). Keep at least 6 months.
4. Photos: Supabase, **Storage**, `construction-photos`; download important folders if needed.
5. These files hold customer names and phone numbers. Keep them private; delete old copies you no longer need. PAN numbers are intentionally not exported.
Also export before any CSV import and before any big change.

## What recovery looks like
- **Project paused** (free plan inactivity): Supabase dashboard, **Restore project**. Data is kept.
- **Wrong data entered**: payments are never edited; use **Reverse**. Schedules: use **Amend**. Everything is in the audit log.
- **Everything lost**: create a new Supabase project, run the 9 SQL files, create the Director, then re-enter data from your CSVs (the villas/customers CSV can be re-imported with the Import tool; bookings and payments must be re-entered, which is why monthly backups and the ledger CSV matter).
- **Upgrade option**: Supabase Pro adds daily backups; worth it once real money is flowing.

## Limits
Each export contains up to the latest 5,000 rows. The system is not a disaster-recovery product; treat the CSVs as your record of truth if the database is lost.
