# WhatsApp: how it works in this system (free)

## What is built
No WhatsApp subscription or Meta account is needed. The system prepares messages and staff send them from their own WhatsApp:
1. Something happens (stage approved, payment due, payment verified, reminder, booking confirmed, handover).
2. If the customer has WhatsApp consent ticked, a **draft** appears under **Messages** for the assigned Salesperson (Directors see all).
3. The Salesperson taps **Send on WhatsApp**: WhatsApp opens with the text typed in. They press send, return, tap **Mark as sent** (or **Skip**).
Wording is editable by the Director in **Settings, Customer message wording**. Variables like `{{customer_name}}` are filled automatically. No PAN or documents are ever put in messages.

## Consent and good practice
Tick the consent box only when the customer has agreed to receive WhatsApp messages about their booking. Payment reminders also follow your payment schedule: demands are only prepared for milestones that have become payable.

## What it cannot do
No automatic sending, no delivery/read status, no webhooks, no sending while nobody is logged in. "Sent" means a staff member confirmed it.

## Upgrading later (optional, costs money)
The official WhatsApp Business Platform (Cloud API) needs a Meta business account, a verified business, a phone number, and approved message templates, and Meta charges per template message (prices change; check Meta's current India rates). Adding it later means a new server function that reads the same drafts and sends them, plus a webhook for delivery status. It is not part of this version, so no WhatsApp keys exist in the app.
