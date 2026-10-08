# Director manual

Menu: Dashboard, Villas, Customers, Bookings, Payments, Follow-ups, Construction, Messages, Reports, Settings, Users. The bell (top right) shows alerts.

**Daily routine (5 minutes):** Dashboard numbers → bell alerts → Payments (verify) → Construction, Approvals → Follow-ups (escalations).

## Set up
- **Users → Add employee**: name, email, role, temporary password (10+ characters). Share it privately. They can choose their own with "Forgot password". **Deactivate** stops access at once (history stays). You cannot deactivate yourself or the last Director.
- **Villas → Add villa**: creates the project too. Assign a Site Manager and Salesperson. **Edit** changes details, prices, assignments. Status changes by itself with bookings and construction.
- **Customers → Add customer**: tick WhatsApp consent only if the customer agreed. PAN is optional, stored apart, shown masked.
- **Import CSV** (Settings, Import CSV): download the template, fill it, upload, check the preview, import. Existing villas/customers are skipped, never changed; one bad row means nothing is saved.
- **Construction → Stages**: order, wording, "needs approval", target days, which stage is Handover.
- **Payments → Payment plans**: create a plan, add milestones (percent or fixed), trigger (booking / stage approved), due days, grace days. Percentages must total 100%. Editing a plan never changes existing bookings.

## Booking
**Bookings → New booking** (draft) → choose the plan → check the schedule → **Confirm booking**. Confirming freezes the schedule and makes the booking-time payment payable. **Cancel** needs a reason; history is kept and the villa can be sold again.
**Amend a schedule** (booking page): change amount or due days of milestones that are not yet payable; the total must still equal the contract value; give a reason; the old schedule is saved.
**Hold** a milestone (e.g. dispute) on the booking page; held milestones are skipped when payments are auto-applied.

## Construction approvals
**Construction → Approvals**: look at the photos, **Approve** or **Reject** (reason required). Approving can make a payment payable and creates the Salesperson's follow-up.

## Payments
**Payments → Awaiting verification**: check the UPI/bank reference against your bank record, then **Verify payment** (applies to the oldest due milestone, or pick one). A receipt number is issued and the receipt PDF can be opened. **Reject** if the money was not received. **Reverse** (bounced cheque, mistake) adds a reversal; the original is kept. The system does not check your bank; you do.

## Reports, backups, settings
- **Reports**: live figures; CSV of payments and outstanding balances. A weekly summary arrives in the bell on Mondays.
- **Settings**: usage meters (database/photos), reminder days, overdue repeat and escalation, retention, message wording, **Run checks now**.
- **Backups** (Settings): download CSVs monthly.
- Failed notifications: Settings shows the count; **Run checks now** retries; if still failing, check message wording.
