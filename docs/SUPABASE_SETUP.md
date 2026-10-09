# Supabase setup reference

- **Project**: free plan, Singapore region (change `vercel.json` if you pick another; Mumbai = `bom1`).
- **SQL files**: `supabase/migrations/001`…`010`, run in order, each once (see BEGINNER_SETUP_GUIDE Part 2).
- **First Director**: Authentication, Users, create user, then `select public.bootstrap_first_director('UID','Name');` (works once).
- **Employees**: created inside the app (**Users**, **Add employee**). Do not create them in the Supabase dashboard: they would have a login but no role.
- **Storage**: bucket `construction-photos` (private, JPEG/PNG/WebP, 5 MB each) is created by `005`. Policies limit upload/view to the right people; nobody can edit or delete photos through the app. Check it exists under **Storage**.
- **Scheduler**: pg_cron on, then `008`. Verify with `select jobname, schedule from cron.job;`.
- **Time zone**: `007` sets the database clock to India time.
- **URL Configuration**: Site URL + `/auth/callback` redirect (Part 8).
- **Keys**: anon/publishable key is public by design; service_role must stay server-side (Vercel, Sensitive).
- **Rotating a key**: Project Settings, API Keys, generate a new key, paste it into Vercel (Settings, Environment Variables), Redeploy. Do this immediately if a key is ever posted or emailed.
- **Testing the schema without real data**: the SQL tests in `supabase/tests` run on a throwaway PostgreSQL (see TESTING_GUIDE). Never run them on your real project.
- **Monitoring**: Supabase **Settings, Usage**, and the app's **Settings** page (usage meters).
