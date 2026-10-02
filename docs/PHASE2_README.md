# Phase 2 — App shell, login, users, villas, customers, bookings

## What works
- Login / logout / forgot-password / reset-password (Supabase Auth). No public sign-up.
- Role-based navigation (desktop sidebar, phone bottom bar):
  Director: Dashboard, Villas, Customers, Bookings, Users. Salesperson: Dashboard, Customers, Bookings, Villas. Site Manager: Dashboard, Villas.
- Director: create employees (the server creates the login and profile), deactivate/reactivate, add projects/villas/customers/bookings, apply a payment-plan template, confirm or cancel a booking.
- Salesperson: sees only own customers, bookings and assigned villas. Site Manager: sees only assigned villas — no prices, customers or money.
- Dashboards show real database numbers (no placeholders).
- Security: roles are read from the `profiles` table on the server; every page re-checks it; the database (RLS from Phase 1) is the final guard. The service-role key is used in exactly one server file (`src/lib/supabase/admin.ts`) and only after a Director check.

## Run it on your computer (optional)
1. Copy `.env.example` to `.env.local`, fill in your Supabase URL, anon/publishable key, service-role key.
2. `npm install` then `npm run dev` -> http://localhost:3000
(Hosting on Vercel from GitHub's website is covered in the final deployment guide in Phase 6.)

## Try it with fictional data
1. Run Phase 1 migrations, create your Director (see Phase 1 guide). Optionally run `supabase/dev/sample_payment_plan.sql`.
2. Log in -> Users -> add a Site Manager and a Salesperson.
3. Villas -> Add villa (creates the project too) -> Customers -> Add customer -> New booking -> pick the sample plan -> Confirm.

## Tested vs not tested
- Executed: TypeScript strict type-check and a full `next build` both succeeded.
- NOT executed: any click-through against a live Supabase project, and no automated UI tests. Please try the flow above on a test project.

## Known gaps (planned)
- Not built yet: customer/villa detail pages and editing, PAN reveal, payment-plan editor (Phase 4), construction updates and photos (Phase 3), payments UI (Phase 4), notifications (Phase 5), CSV import and PDFs (Phase 6).
- App icons for "Add to home screen" are not included; a manifest is.
- Uses plain Tailwind components rather than shadcn/ui, because shadcn needs a command-line installer.
- Temporary employee passwords are chosen by the Director and shared privately; there is no invite email yet.
