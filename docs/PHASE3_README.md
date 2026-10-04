# Phase 3 — Construction updates, photos, approvals, stage settings

## New in this phase
- Site Manager phone flow: Construction -> Update construction -> villa, stage, status (In progress / Delayed / Completed), photos, remarks, issue flag, Submit. Photos are shrunk on the phone before upload.
- Rules: "Completed" needs at least one photo; "Delayed" needs a reason; max 6 photos.
- Director: Construction -> Approvals (see photos, Approve or Reject with a reason). Approving can make a payment milestone payable (if the booking's schedule links that stage) and creates the Salesperson's follow-up task. A rejected update is kept; a corrected one can be submitted.
- Director: Stages page — rename, reorder, approval on/off, target days, disable, mark which stage means Handover.
- Villa history page: full timeline with private photos (links expire after an hour).
- Villa status follows work automatically: first update -> Under construction; approved Handover stage -> Handed over.

## Install (existing project)
1. Upload this ZIP's contents to GitHub (Add file -> Upload files, replace when asked). Vercel redeploys by itself.
2. Supabase -> SQL Editor -> New query -> paste `supabase/migrations/005_construction_storage.sql` -> Run (once only).
3. Check: Supabase -> Storage should show a private bucket `construction-photos`.

## Try it (fictional data)
- The update picker lists villas that are Booked / Under construction and assigned to that Site Manager. So: add a villa with the Site Manager assigned, create and CONFIRM a booking for it, then log in as the Site Manager.
- There is no villa edit screen yet. If a villa has no Site Manager assigned, add a new villa (Phase 2 form) instead.

## Tested vs not tested
- Executed: 90 database checks pass on PostgreSQL 16 (Phase 1 + new storage rules, approval/reject/resubmit, handover, stage settings, other site managers blocked). Storage was imitated by a small test shim, not real Supabase Storage.
- Executed: TypeScript type-check and production build.
- NOT executed: real photo upload from a phone, and the screens against live Supabase. Please test with 1-2 photos on your phone.

## Limits
- Bucket allows JPEG/PNG/WebP up to 5 MB each. Free Supabase storage is about 1 GB total; compression keeps photos around a few hundred KB each.
- Photos cannot be deleted by anyone through the app (by design, to protect history).
- Delay and issue alerts are recorded as events now; in-app/WhatsApp notifications come in Phase 5.
- Not yet: villa edit screen, "target date" reminders from stage target days (Phase 5).
