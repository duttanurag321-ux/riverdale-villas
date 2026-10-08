# Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Your account is not active" after login | Login exists but has no role (created in Supabase dashboard) or user deactivated | Delete the user in Supabase, Authentication, Users; create again in the app (**Users**). Or reactivate |
| "Could not create the login" when adding employee | Wrong/missing `SUPABASE_SERVICE_ROLE_KEY` in Vercel | Re-enter the key, Redeploy |
| Vercel build fails | Files missing from GitHub, or old Next.js | Open Build Logs, copy red lines; check repo has `src`, `package.json`, `package-lock.json` |
| App is slow | Region mismatch or cold start | `vercel.json` region must match Supabase (Singapore = `sin1`); first tap after quiet time can take 2 s |
| Password reset link says invalid | URL Configuration not set | Part 8 of the setup guide; links also expire |
| SQL error "already exists" | File run twice | Harmless: it already worked |
| SQL error "does not exist" | A file was skipped | Run files in numeric order 001 to 009 |
| Photos won't upload | `005` not run, or photo over 5 MB / not an image, or you are not assigned to that villa | Check Storage bucket; assign the villa; retry |
| Update list has no villa | Villa is Available (no confirmed booking) or not assigned to you | Confirm a booking; assign the Site Manager |
| Can't confirm booking | Schedule missing or does not total the contract value | Apply a plan; fix amounts |
| "Percentages total x%" | Plan not 100% | Fix on the plan page |
| Receipt PDF shows "?" | PDF fonts are basic Latin | Known limit |
| No daily reminders | pg_cron off or `008` not run, or project paused | Part 3; use **Run checks now**; open the app weekly |
| Bell count stale | Only refreshes per page visit | Open any page |
| Import says "Nothing was saved" | Some row has a problem | Read the row list, fix the file, retry |
| Customer message not prepared | Customer has no WhatsApp consent or drafts are switched off | Edit customer / Settings |
| Event failed 5 times | Message wording broken (a template emptied) | Fix wording in Settings, **Run checks now** |
If stuck: note the exact message and the page, take a screenshot, and ask for help. Do not paste keys or passwords.
