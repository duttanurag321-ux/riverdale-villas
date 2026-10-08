# Beginner setup guide — from nothing to a working system

You do not need to know programming. You will use three websites in your browser: **Supabase** (the database), **GitHub** (stores the code) and **Vercel** (runs the app). Use fictional test data until the end. Words in **bold** are exactly what you click.

## Checklist (tick as you go)
1. [ ] Unzip the project on your computer
2. [ ] Create the Supabase project (Part 1)
3. [ ] Run the 9 SQL files in order (Part 2)
4. [ ] Turn on the daily scheduler (Part 3)
5. [ ] Create the Director login (Part 4)
6. [ ] Copy 3 keys from Supabase (Part 5)
7. [ ] Put the files on GitHub (Part 6)
8. [ ] Deploy on Vercel (Part 7)
9. [ ] Connect Supabase to your web address (Part 8)
10. [ ] Create employees and test (Part 9)
11. [ ] Read the Security checklist and Backup guide before real data (docs/SECURITY_CHECKLIST.md, docs/BACKUP_AND_RECOVERY.md)

## Part 0 — Unzip
Download the latest project ZIP. Windows: right-click it, **Extract All**. Open the folder `riverdale`. You should see `src`, `supabase`, `docs`, `package.json`. Never open or run anything inside `supabase/tests`.

## Part 1 — Create the database (Supabase)
1. Go to **supabase.com**, **Start your project**, sign up.
2. **New project**. Name `riverdale`. Set a database password and save it in a password manager. Pick the region closest to you (this project was set up for **Singapore**). Plan: **Free**. Click **Create new project** and wait ~2 minutes.
3. Done when you see the project dashboard with a left menu.

## Part 2 — Create the tables (SQL files)
These files build the tables and rules. Run them **in this order, each once**:
`001_schema`, `002_functions_and_triggers`, `003_rls_and_grants`, `004_seed_reference_data`, `005_construction_storage`, `006_followups_amendments`, `007_notifications_free`, then (after Part 3) `008_schedule_jobs`, then `009_csv_import`.
For each file:
1. Left menu **SQL Editor**, **New query**.
2. Open the file from `supabase/migrations` in Notepad, **Ctrl+A**, **Ctrl+C**.
3. Paste into Supabase, click **Run**. Expect **Success. No rows returned**. If a warning mentions "destructive operations", click **Run this query**.
4. Check at the end: **Table Editor** lists tables such as `villas`, `bookings`, `payments`; **Storage** shows a private bucket `construction-photos`.
If a file errors: do not run the next one. Copy the exact error and see docs/TROUBLESHOOTING.md. Running a file twice gives "already exists": that means it already worked.

## Part 3 — Turn on the daily scheduler
1. **Database**, **Extensions**, search `pg_cron`, switch **on**.
2. Run `008_schedule_jobs.sql` as in Part 2.
3. Check: new query `select jobname, schedule from cron.job;` shows 2 rows.
If this part fails, everything else still works; use **Settings, Run checks now** each morning.

## Part 4 — Create the Director login
1. **Authentication**, **Users**, **Add user**, **Create new user**. Enter your email and a strong password; tick **Auto Confirm User**; **Create user**.
2. Click the new user and copy its **UID** (long code with dashes).
3. **SQL Editor**, new query, paste this with your UID and name, **Run**:
   `select public.bootstrap_first_director('PASTE-UID-HERE', 'Your Name');`
4. Check: **Table Editor**, `profiles` shows one row with role `director`. This works only once, and cannot be called from the app.

## Part 5 — Copy 3 keys
**Project Settings** (gear icon), **API** (or **API Keys**). Copy into a private note:
- **Project URL** (looks like https://abcd.supabase.co)
- **anon / publishable key** (safe to expose in the app)
- **service_role / secret key** — DANGEROUS. Never post it, never put it in GitHub.

## Part 6 — Put the code on GitHub
1. **github.com**, sign up, **+** (top right), **New repository**, name `riverdale-villas`, **Private**, **Create repository**.
2. Click **uploading an existing file**. In your unzipped `riverdale` folder press **Ctrl+A** and drag everything **inside** it onto the page (not the folder itself). Wait for uploads to finish, then **Commit changes**.
3. Check: the repository front page lists `src`, `supabase`, `docs`, `package.json`, `vercel.json`. Open `src`: you should see `middleware.ts`.
To update later: **Add file**, **Upload files**, drag the new files, **Commit changes** (see docs/GITHUB_WEB_WORKFLOW.md).

## Part 7 — Deploy (Vercel)
1. **vercel.com**, **Sign Up with GitHub**.
2. **Add New**, **Project**, **Import** `riverdale-villas`. Leave build settings alone (it says Next.js).
3. **Environment Variables**, add (name, value, **Add**):
   - `NEXT_PUBLIC_SUPABASE_URL` = Project URL
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` = anon/publishable key
   - `SUPABASE_SERVICE_ROLE_KEY` = service_role key — turn **Sensitive** ON
   - `APP_BASE_URL` = `https://temporary.example` for now
4. **Deploy**. When it says Congratulations, copy your address (like https://riverdale-villas-xyz.vercel.app).
5. **Settings**, **Environment Variables**: edit `APP_BASE_URL` to that address (no slash at the end). **Deployments**, **⋯** on the latest, **Redeploy**.

## Part 8 — Tell Supabase your address
**Authentication**, **URL Configuration**: **Site URL** = your Vercel address; under **Redirect URLs** add `https://YOUR-ADDRESS/auth/callback`. Save. (This makes password reset emails work.)

## Part 9 — First test (fictional data only)
1. Open your address, log in as the Director.
2. **Users**: add a Site Manager and a Salesperson (throwaway emails you control, temporary password 10+ characters).
3. **Villas**, **Add villa** (project "Riverdale Villas (TEST)", villa A1, assign the Site Manager and Salesperson). **Customers**, **Add customer** (tick WhatsApp consent only for testing).
4. **Payments**, **Payment plans**, create a plan with milestones totalling 100% (or run `supabase/dev/sample_payment_plan.sql`).
5. **Bookings**, **New booking**, choose the plan, **Create draft**, **Confirm booking**.
6. Log in (private window) as the Site Manager on a phone: **Construction**, **Update construction**, submit a "Foundation completed" update with a photo. As Director approve it. As Salesperson check **Follow-ups**, **Messages** and the bell icon.
7. Report a payment as Salesperson, verify as Director, open the receipt PDF.
Every step above is described per role in the manuals.

## Glossary
- **Repository (repo)**: the folder of code on GitHub. **Commit**: saving a change there.
- **Deploy**: Vercel builds the code and puts the app online.
- **Migration / SQL file**: a script that builds database tables.
- **RLS (Row Level Security)**: database rules that decide who may see which rows.
- **Environment variable**: a setting or key given to the app, kept out of the code.
- **Service role key**: a master key; keep it secret.
- **Paise**: 1/100 of a rupee; the system stores money as whole paise to avoid rounding errors.
- **Ledger**: the permanent list of payments; mistakes are fixed by adding a reversal, never by editing.
- **pg_cron**: Supabase's built-in scheduler (runs the morning checks).
