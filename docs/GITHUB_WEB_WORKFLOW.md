# Using GitHub in the browser only

No command line is needed.

## Upload or replace files
1. Open your repository, **Add file**, **Upload files**.
2. Drag files from inside the unzipped folder (select everything inside it, not the folder). Same-named files are replaced. Drag folders too: GitHub keeps their structure.
3. Scroll down, **Commit changes**. Vercel then redeploys automatically (watch Vercel **Deployments**: **Ready** = done).

## Create or edit one file
Open the file, click the pencil icon, edit, **Commit changes**. New file: **Add file**, **Create new file**, type the path (for example `src/middleware.ts`) and content.

## Delete a file
Open it, **⋯** (top right), **Delete file**, **Commit changes**.

## Update the app to a newer ZIP
1. Extract the new ZIP. 2. Upload everything (replaces changed files). 3. Delete files that the notes say were removed (rare). 4. If the notes mention a new SQL file, run it in Supabase SQL Editor once.

## Good habits
- Keep the repository **Private**. Never upload a file named `.env` or any text containing keys.
- If a deployment fails, the previous working version stays live. Fix and upload again.
- Optional: the folder `.github/workflows` runs a free build check on every upload and shows a green tick or red cross next to your commit. If GitHub rejects uploading that folder, skip it; the app does not need it.

## Why no Edge Functions or Supabase CLI
This system runs its automation inside the database (SQL files you paste), so there is nothing to deploy with the command line.
