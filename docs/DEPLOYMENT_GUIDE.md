# Deployment reference (Vercel + GitHub)

- **Host**: Vercel free (Hobby) plan, connected to your private GitHub repository. Framework preset: Next.js (automatic). Build command and output folder: leave defaults.
- **Region**: `vercel.json` pins functions to Singapore (`sin1`) to sit next to Supabase. Why it matters: every page makes several database calls.
- **Environment variables** (Vercel, **Settings**, **Environment Variables**):
  | Name | Where from | Public? |
  |---|---|---|
  | NEXT_PUBLIC_SUPABASE_URL | Supabase, Project Settings, API | yes |
  | NEXT_PUBLIC_SUPABASE_ANON_KEY | same (anon / publishable) | yes |
  | SUPABASE_SERVICE_ROLE_KEY | same (service_role / secret) | NO (mark Sensitive) |
  | APP_BASE_URL | your Vercel address, no trailing slash | no |
  After changing a variable, **Redeploy**.
- **First deploy**: import repository, add variables, **Deploy**. Address shown on success.
- **Update**: upload files to GitHub; Vercel redeploys by itself.
- **Logs**: Vercel, your project, **Deployments**, click one, **Build Logs** (build problems) or **Logs** (runtime).
- **Troubleshoot a failed build**: copy the red lines from Build Logs; common causes are a missing file upload (check the repo has `src`, `package.json`, `package-lock.json`) or an old Next.js version (this project uses a patched version).
- **Custom domain (optional)**: Vercel, **Settings**, **Domains**; buying a domain costs money. Afterwards update `APP_BASE_URL` and the Supabase URL Configuration.
- **Limits**: Vercel's free Hobby plan is, as far as I know, for personal non-commercial use only, with usage caps. Running a business on it may require a paid plan or another host: check Vercel's current terms before going live with real customers. Cold starts can make the first request after a quiet period take a couple of seconds.
- **Not used**: GitHub Pages (cannot run this app), Edge Functions, Realtime, paid add-ons.
