-- Riverdale Villas — Phase 5 / 008: schedule the free in-database jobs.
-- BEFORE running: Supabase Dashboard -> Database -> Extensions -> search "pg_cron" -> switch it ON.
-- Times are UTC (pg_cron default). 03:30 UTC = 09:00 India. Safe to run once; re-running just replaces the schedules.
select cron.schedule('riverdale-daily-jobs', '30 3 * * *', $$select public.run_daily_jobs()$$);
select cron.schedule('riverdale-retry-events', '*/15 * * * *', $$select public.process_pending_events()$$);
