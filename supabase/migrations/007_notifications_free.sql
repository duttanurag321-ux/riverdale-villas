-- Riverdale Villas — Phase 5 / 007: zero-cost notifications, reminders and reports.
-- Design: NO paid services, NO Edge Functions, NO Realtime. Everything runs inside the database (free) and is tiny:
--   * staff get in-app notifications (bell icon);
--   * customer WhatsApp messages are prepared as ready-to-send drafts; a staff member taps "Send on WhatsApp"
--     (opens their own WhatsApp with the text filled in) and marks it sent. Nothing is sent automatically.
-- Run once in the Supabase SQL Editor AFTER 001-006.

-- Keep "today" consistent with India (affects due dates and reminders).
do $$ begin execute format('alter database %I set timezone to %L', current_database(), 'Asia/Kolkata'); end $$;
set timezone to 'Asia/Kolkata';

-- ---------- settings & templates ----------
create table system_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
insert into system_settings(key, value) values
  ('reminder_days_before', '[7,2]'), ('overdue_reminder_every_days', '7'), ('overdue_reminder_max', '4'),
  ('escalate_after_overdue_days', '5'), ('customer_drafts_enabled', 'true'), ('retention_days', '90');

create table message_templates (kind text primary key, title text not null, body text not null check (length(trim(body)) > 0), updated_at timestamptz not null default now());
insert into message_templates(kind, title, body) values
('construction_update','Construction update',
$t$Hello {{customer_name}},

We have an update on your Riverdale Villas home.

Villa: {{villa_number}}
Construction milestone: {{milestone_name}}
Updated on: {{date}}

Our team has recorded the completion of this stage. Your sales representative will assist you with the next steps.

Regards,
Riverdale Villas Team$t$),
('payment_due','Payment due',
$t$Hello {{customer_name}},

As per your agreed payment schedule, the payment for your Riverdale Villas home is due.

Villa: {{villa_number}}
Milestone: {{milestone_name}}
Milestone amount: {{milestone_amount}}
Paid against this milestone: {{milestone_paid}}
Remaining amount: {{milestone_outstanding}}
Due date: {{due_date}}

Please contact your Riverdale Villas representative for payment assistance.

Regards,
Riverdale Villas Team$t$),
('payment_upcoming','Upcoming payment reminder',
$t$Hello {{customer_name}},

This is a reminder that a payment for your Riverdale Villas home is coming up.

Villa: {{villa_number}}
Milestone: {{milestone_name}}
Remaining amount: {{milestone_outstanding}}
Due date: {{due_date}}

Please contact your Riverdale Villas representative if you need any assistance.

Regards,
Riverdale Villas Team$t$),
('payment_overdue','Overdue payment reminder',
$t$Hello {{customer_name}},

Our records show that the following payment for your Riverdale Villas home is now overdue.

Villa: {{villa_number}}
Milestone: {{milestone_name}}
Remaining amount: {{milestone_outstanding}}
Due date: {{due_date}}

If you have already paid, please share the payment reference with your representative so we can update our records.

Regards,
Riverdale Villas Team$t$),
('payment_ack','Payment acknowledgement',
$t$Hello {{customer_name}},

We have confirmed receipt of {{verified_payment_amount}} against your Riverdale Villas booking.

Villa: {{villa_number}}
Payment reference: {{receipt_number}}
Remaining amount against this milestone: {{remaining_milestone_balance}}

Thank you,
Riverdale Villas Team$t$),
('booking_confirmed','Booking confirmed',
$t$Hello {{customer_name}},

Your booking for Villa {{villa_number}} at Riverdale Villas is confirmed. Contract value: {{contract_value}}.

Regards,
Riverdale Villas Team$t$),
('handover','Handover',
$t$Hello {{customer_name}},

Construction of Villa {{villa_number}} at Riverdale Villas is complete. Your sales representative will contact you about handover.

Regards,
Riverdale Villas Team$t$);

-- ---------- in-app notifications and WhatsApp drafts ----------
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  kind text not null,
  title text not null,
  body text,
  link text,
  dedupe_key text not null unique,        -- the same event can never notify the same person twice
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index on notifications(user_id, created_at desc);

create table customer_message_drafts (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  customer_id uuid not null references customers(id),
  assigned_to uuid references profiles(id),
  kind text not null,
  phone text not null,
  body text not null,
  status text not null default 'pending' check (status in ('pending','sent','skipped')),
  dedupe_key text not null unique,
  created_at timestamptz not null default now(),
  handled_at timestamptz, handled_by uuid references profiles(id)
);
create index on customer_message_drafts(assigned_to, status);

alter table domain_events add column attempts int not null default 0;
alter table domain_events add column last_error text;

alter table system_settings enable row level security;
alter table message_templates enable row level security;
alter table notifications enable row level security;
alter table customer_message_drafts enable row level security;
grant select on system_settings, message_templates, notifications, customer_message_drafts to authenticated;
grant update on system_settings, message_templates to authenticated;
grant update (read_at) on notifications to authenticated;
create policy settings_dir on system_settings for all to authenticated using (public.is_director()) with check (public.is_director());
create policy templates_dir on message_templates for all to authenticated using (public.is_director()) with check (public.is_director());
create policy notif_read on notifications for select to authenticated using (user_id = auth.uid());
create policy notif_mark on notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy drafts_read on customer_message_drafts for select to authenticated using (public.is_director() or assigned_to = auth.uid());

-- ---------- helpers ----------
create function public.fmt_inr(p bigint) returns text language plpgsql immutable as $$
declare r bigint := p / 100; f int := (p % 100); s text := r::text;
begin
  if length(s) > 3 then s := regexp_replace(left(s, length(s) - 3), '(\d)(?=(\d\d)+$)', '\1,', 'g') || ',' || right(s, 3); end if;
  return '₹' || s || case when f <> 0 then '.' || lpad(f::text, 2, '0') else '' end;
end $$;

create function public.setting_int(p_key text, p_default int) returns int language sql stable security definer set search_path = public
as $$ select coalesce((select (value #>> '{}')::int from system_settings where key = p_key), p_default) $$;

create function public.render_template(p_kind text, p_vars jsonb) returns text language plpgsql stable security definer set search_path = public as $$
declare b text; k text;
begin
  select body into b from message_templates where kind = p_kind;
  if b is null then return null; end if;
  for k in select jsonb_object_keys(p_vars) loop b := replace(b, '{{' || k || '}}', coalesce(p_vars ->> k, '')); end loop;
  return b;
end $$;

create function public.notify_user(p_user uuid, p_kind text, p_title text, p_body text, p_link text, p_key text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  insert into notifications(user_id, kind, title, body, link, dedupe_key) values (p_user, p_kind, p_title, p_body, p_link, p_key) on conflict (dedupe_key) do nothing;
end $$;

create function public.notify_directors(p_kind text, p_title text, p_body text, p_link text, p_key text) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  for u in select id from profiles where role = 'director' and is_active loop perform public.notify_user(u, p_kind, p_title, p_body, p_link, p_key || ':' || u); end loop;
end $$;

create function public.notify_booking_staff(p_booking uuid, p_villa uuid, p_kind text, p_title text, p_body text, p_link text, p_key text) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  perform public.notify_directors(p_kind, p_title, p_body, p_link, p_key);
  for u in select distinct x from (select salesperson_id x from bookings where id = p_booking union select salesperson_id from villas where id = p_villa) s where x is not null loop
    perform public.notify_user(u, p_kind, p_title, p_body, p_link, p_key || ':' || u);
  end loop;
end $$;

-- Customer message draft: only if drafts are enabled AND the customer has opted in to WhatsApp messages.
create function public.queue_customer_message(p_booking uuid, p_kind text, p_vars jsonb, p_key text) returns void
language plpgsql security definer set search_path = public as $$
declare b bookings; c customers; txt text;
begin
  if coalesce((select value from system_settings where key = 'customer_drafts_enabled'), 'true'::jsonb) <> 'true'::jsonb then return; end if;
  select * into b from bookings where id = p_booking; if b.id is null then return; end if;
  select * into c from customers where id = b.customer_id;
  if not c.whatsapp_opt_in then return; end if;
  txt := public.render_template(p_kind, jsonb_build_object('customer_name', c.full_name, 'villa_number', (select villa_number from villas where id = b.villa_id)) || p_vars);
  insert into customer_message_drafts(booking_id, customer_id, assigned_to, kind, phone, body, dedupe_key)
    values (b.id, c.id, coalesce(b.salesperson_id, c.salesperson_id), p_kind, c.phone, txt, p_key) on conflict (dedupe_key) do nothing;
end $$;

-- ---------- event -> notifications ----------
create function public.handle_event(p_event uuid) returns void language plpgsql security definer set search_path = public as $$
declare e domain_events; b bookings; vid uuid; vn text; cn text; sn text; mid uuid; mn text; ma bigint; mp bigint; mo bigint; md date; mnotify boolean;
        pid uuid; pamt bigint; rcpt text; sub uuid; rsn text; rem bigint;
begin
  select * into e from domain_events where id = p_event;
  if e.booking_id is not null then select * into b from bookings where id = e.booking_id; end if;
  vid := coalesce(b.villa_id, nullif(e.payload ->> 'villa_id', '')::uuid);
  select villa_number into vn from villas where id = vid;
  select full_name into cn from customers where id = b.customer_id;
  if e.payload ? 'stage_id' then select name into sn from construction_stages where id = (e.payload ->> 'stage_id')::uuid; end if;

  if e.event_type = 'payment_milestone_activated' then
    mid := (e.payload ->> 'milestone_id')::uuid;
    select name, amount_paise, paid_paise, outstanding_paise, due_date, notify_customer into mn, ma, mp, mo, md, mnotify from v_milestone_balances where id = mid;
    perform public.notify_booking_staff(b.id, vid, 'payment', 'Payment now payable: Villa ' || vn,
      cn || ' - ' || mn || ' ' || public.fmt_inr(ma) || ', due ' || to_char(md, 'DD Mon YYYY') || '. A follow-up task was created.', '/followups', 'act:' || e.id);
    if mnotify then
      perform public.queue_customer_message(b.id, 'payment_due', jsonb_build_object('milestone_name', mn, 'milestone_amount', public.fmt_inr(ma),
        'milestone_paid', public.fmt_inr(mp), 'milestone_outstanding', public.fmt_inr(mo), 'due_date', to_char(md, 'DD Mon YYYY')), 'due:' || mid);
    end if;
  elsif e.event_type = 'construction_update_submitted' then
    if e.payload ->> 'approval' = 'pending' then
      perform public.notify_directors('construction', 'Construction update needs approval', 'Villa ' || vn || ' - ' || sn, '/construction/approvals', 'sub:' || e.id);
    end if;
  elsif e.event_type = 'construction_delayed' then
    perform public.notify_booking_staff(b.id, vid, 'construction', 'Construction delayed: Villa ' || vn, 'Stage: ' || sn, '/construction/villa/' || vid, 'delay:' || e.id);
  elsif e.event_type = 'construction_update_approved' then
    perform public.notify_booking_staff(b.id, vid, 'construction', 'Stage approved: Villa ' || vn, sn, '/construction/villa/' || vid, 'appr:' || e.id);
    if b.id is not null then
      perform public.queue_customer_message(b.id, 'construction_update', jsonb_build_object('milestone_name', sn, 'date', to_char(now(), 'DD Mon YYYY')), 'cu:' || e.id);
    end if;
  elsif e.event_type = 'construction_update_rejected' then
    select submitted_by, rejection_reason into sub, rsn from construction_updates where id = (e.payload ->> 'update_id')::uuid;
    perform public.notify_user(sub, 'construction', 'Update rejected: Villa ' || vn, coalesce(rsn, ''), '/construction/villa/' || vid, 'rej:' || e.id);
  elsif e.event_type = 'payment_reported' then
    pamt := (e.payload ->> 'amount_paise')::bigint;
    perform public.notify_directors('payment', 'Payment to verify', cn || ' reported ' || public.fmt_inr(pamt) || ' for Villa ' || vn, '/payments', 'rep:' || e.id);
  elsif e.event_type = 'payment_verified' then
    pid := (e.payload ->> 'payment_id')::uuid; pamt := (e.payload ->> 'amount_paise')::bigint; rcpt := e.payload ->> 'receipt_number';
    select entered_by into sub from payments where id = pid;
    perform public.notify_user(sub, 'payment', 'Payment verified: Villa ' || vn, public.fmt_inr(pamt) || ' - receipt ' || rcpt, '/bookings/' || b.id, 'ver:' || e.id);
    select coalesce(sum(vb.outstanding_paise), 0) into rem from v_milestone_balances vb where vb.id in (select milestone_id from payment_allocations where payment_id = pid);
    perform public.queue_customer_message(b.id, 'payment_ack', jsonb_build_object('verified_payment_amount', public.fmt_inr(pamt), 'receipt_number', rcpt,
      'remaining_milestone_balance', public.fmt_inr(rem)), 'ack:' || pid);
  elsif e.event_type = 'payment_reversed' then
    perform public.notify_booking_staff(b.id, vid, 'payment', 'Payment reversed: Villa ' || vn, cn, '/bookings/' || b.id, 'revp:' || e.id);
  elsif e.event_type = 'booking_confirmed' then
    perform public.notify_booking_staff(b.id, vid, 'booking', 'Booking confirmed: Villa ' || vn, cn, '/bookings/' || b.id, 'bc:' || e.id);
    perform public.queue_customer_message(b.id, 'booking_confirmed', jsonb_build_object('contract_value', public.fmt_inr(b.contract_value_paise)), 'bc:' || b.id);
  elsif e.event_type = 'handover_completed' then
    perform public.notify_booking_staff(b.id, vid, 'construction', 'Handover completed: Villa ' || vn, 'The villa is ready for handover.', '/construction/villa/' || vid, 'ho:' || e.id);
    if b.id is not null then perform public.queue_customer_message(b.id, 'handover', '{}'::jsonb, 'ho:' || vid); end if;
  elsif e.event_type = 'follow_up_escalated' then
    perform public.notify_directors('followup', 'A follow-up needs your attention', 'Villa ' || vn || ' - ' || coalesce(cn, ''), '/followups', 'fesc:' || e.id);
  end if;
end $$;

-- Instant processing at the moment the event is saved. If it fails, the business action is NOT undone:
-- the event stays pending and is retried (max 5 times) by process_pending_events().
create function public.trg_event_dispatch() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public.handle_event(new.id);
    update domain_events set processed_at = now() where id = new.id;
  exception when others then
    update domain_events set attempts = 1, last_error = left(sqlerrm, 300) where id = new.id;
  end;
  return null;
end $$;
create trigger event_dispatch after insert on domain_events for each row execute function public.trg_event_dispatch();

create function public.process_pending_events() returns int language plpgsql security definer set search_path = public as $$
declare e record; n int := 0;
begin
  if auth.uid() is not null and not public.is_director() then raise exception 'Not authorized' using errcode = '42501'; end if;
  for e in select id from domain_events where processed_at is null and attempts < 5 order by created_at limit 200 loop
    begin
      perform public.handle_event(e.id);
      update domain_events set processed_at = now(), last_error = null where id = e.id; n := n + 1;
    exception when others then
      update domain_events set attempts = attempts + 1, last_error = left(sqlerrm, 300) where id = e.id;
      if (select attempts from domain_events where id = e.id) >= 5 then
        perform public.notify_directors('system', 'A notification could not be prepared', 'Event ' || e.id || ' failed 5 times. Details: ' || (select last_error from domain_events where id = e.id), '/settings', 'evfail:' || e.id);
      end if;
    end;
  end loop;
  return n;
end $$;

-- ---------- retention (keeps the free 500 MB database small) ----------
create function public.purge_old_data() returns void language plpgsql security definer set search_path = public as $$
declare keep int := public.setting_int('retention_days', 90);
begin
  delete from notifications where created_at < now() - make_interval(days => keep) and (read_at is not null or created_at < now() - make_interval(days => keep * 2));
  delete from customer_message_drafts where status <> 'pending' and handled_at < now() - make_interval(days => keep);
  delete from domain_events where processed_at is not null and processed_at < now() - make_interval(days => keep);
end $$;

-- ---------- daily jobs: reminders, escalations, summaries ----------
create function public.run_daily_jobs() returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; days int[]; esc int; every int; maxn int; d int; late int; n0 bigint; n1 bigint; d0 bigint; d1 bigint; lines text[]; c1 int; c2 int; c3 int; c4 int; c5 int;
        today date := current_date; wk date := date_trunc('week', current_date)::date;
begin
  if auth.uid() is not null and not public.is_director() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select count(*) into n0 from notifications; select count(*) into d0 from customer_message_drafts;
  days := array(select jsonb_array_elements_text(value)::int from system_settings where key = 'reminder_days_before');
  esc := public.setting_int('escalate_after_overdue_days', 5); every := greatest(public.setting_int('overdue_reminder_every_days', 7), 1); maxn := public.setting_int('overdue_reminder_max', 4);
  perform public.process_pending_events();

  for r in select m.id, m.booking_id, m.name, m.amount_paise, m.paid_paise, m.outstanding_paise, m.due_date, m.grace_days, m.derived_status,
                  b.salesperson_id sp, b.villa_id, (select villa_number from villas where id = b.villa_id) vn, (select full_name from customers where id = b.customer_id) cn
           from v_milestone_balances m join bookings b on b.id = m.booking_id
           where b.status = 'confirmed' and m.activated_at is not null and not m.on_hold and not m.cancelled and m.outstanding_paise > 0 loop
    d := r.due_date - today;
    if d = 0 or d = any(days) then
      perform public.notify_user(r.sp, 'payment', case when d = 0 then 'Payment due today' else 'Payment due in ' || d || ' days' end || ': Villa ' || r.vn,
        r.cn || ' - ' || r.name || ', ' || public.fmt_inr(r.outstanding_paise) || ' remaining', '/followups', 'rem:' || r.id || ':' || d);
      perform public.queue_customer_message(r.booking_id, case when d = 0 then 'payment_due' else 'payment_upcoming' end,
        jsonb_build_object('milestone_name', r.name, 'milestone_amount', public.fmt_inr(r.amount_paise), 'milestone_paid', public.fmt_inr(r.paid_paise),
          'milestone_outstanding', public.fmt_inr(r.outstanding_paise), 'due_date', to_char(r.due_date, 'DD Mon YYYY')), 'rem:' || r.id || ':' || d);
    elsif r.derived_status = 'overdue' then
      late := today - (r.due_date + r.grace_days);
      perform public.notify_user(r.sp, 'payment', 'Payment overdue: Villa ' || r.vn, r.cn || ' - ' || r.name || ', ' || public.fmt_inr(r.outstanding_paise) || ' unpaid', '/followups', 'overdue:' || r.id);
      if (late - 1) / every < maxn then
        perform public.queue_customer_message(r.booking_id, 'payment_overdue', jsonb_build_object('milestone_name', r.name,
          'milestone_outstanding', public.fmt_inr(r.outstanding_paise), 'due_date', to_char(r.due_date, 'DD Mon YYYY')), 'od:' || r.id || ':' || ((late - 1) / every));
      end if;
      if late >= esc then
        perform public.notify_directors('payment', 'Overdue ' || late || ' days: Villa ' || r.vn, r.cn || ' - ' || r.name || ', ' || public.fmt_inr(r.outstanding_paise), '/bookings/' || r.booking_id, 'overdue_esc:' || r.id);
      end if;
    end if;
  end loop;

  for r in select t.id, t.assigned_to, t.due_date, t.promised_date, (select villa_number from villas where id = (select villa_id from bookings where id = t.booking_id)) vn
           from follow_up_tasks t where t.status = 'open' loop
    if r.due_date < today then
      perform public.notify_user(r.assigned_to, 'followup', 'Follow-up overdue: Villa ' || r.vn, 'Was due ' || to_char(r.due_date, 'DD Mon YYYY'), '/followups', 'task_overdue:' || r.id);
      if today - r.due_date >= esc then perform public.notify_directors('followup', 'Follow-up overdue ' || (today - r.due_date) || ' days: Villa ' || r.vn, 'Still unresolved.', '/followups', 'task_esc:' || r.id); end if;
    end if;
    if r.promised_date is not null and r.promised_date < today then
      perform public.notify_user(r.assigned_to, 'followup', 'Promised payment date missed: Villa ' || r.vn, 'Promised ' || to_char(r.promised_date, 'DD Mon YYYY'), '/followups', 'promise_missed:' || r.id || ':' || r.promised_date);
    end if;
  end loop;

  -- one short summary per person per day, only when something needs attention
  for r in select id, role from profiles where is_active loop
    lines := '{}';
    if r.role = 'director' then
      select count(*) into c1 from payments where verification = 'pending';
      select count(*) into c2 from construction_updates where approval = 'pending';
      select coalesce(sum(vb.overdue_paise), 0) into c3 from v_booking_balances vb join bookings b on b.id = vb.booking_id where b.status = 'confirmed';
      select count(*) into c4 from follow_up_tasks where status = 'open' and due_date < today;
      select count(*) into c5 from domain_events where processed_at is null and attempts >= 5;
      if c1 > 0 then lines := lines || (c1 || ' payment(s) awaiting verification'); end if;
      if c2 > 0 then lines := lines || (c2 || ' construction update(s) awaiting approval'); end if;
      if c3 > 0 then lines := lines || ('Overdue amount: ' || public.fmt_inr(c3)); end if;
      if c4 > 0 then lines := lines || (c4 || ' follow-up(s) overdue'); end if;
      if c5 > 0 then lines := lines || (c5 || ' notification(s) failed - see Settings'); end if;
    elsif r.role = 'salesperson' then
      select count(*) into c1 from follow_up_tasks where status = 'open' and assigned_to = r.id and due_date <= today;
      select count(*) into c2 from follow_up_tasks where status = 'open' and assigned_to = r.id and promised_date = today;
      select count(*) into c3 from customer_message_drafts where status = 'pending' and assigned_to = r.id;
      if c1 > 0 then lines := lines || (c1 || ' follow-up(s) due or overdue'); end if;
      if c2 > 0 then lines := lines || (c2 || ' customer(s) promised to pay today'); end if;
      if c3 > 0 then lines := lines || (c3 || ' WhatsApp message(s) ready to send'); end if;
    else
      select count(*) into c1 from villas v where v.site_manager_id = r.id and v.status in ('booked','under_construction')
        and not exists (select 1 from construction_updates u where u.villa_id = v.id and u.submitted_at > now() - interval '7 days');
      select count(*) into c2 from construction_updates u where u.submitted_by = r.id and u.approval = 'rejected' and u.submitted_at > now() - interval '14 days'
        and not exists (select 1 from construction_updates u2 where u2.villa_id = u.villa_id and u2.stage_id = u.stage_id and u2.submitted_at > u.submitted_at);
      if c1 > 0 then lines := lines || (c1 || ' villa(s) with no update in 7 days'); end if;
      if c2 > 0 then lines := lines || (c2 || ' rejected update(s) to correct'); end if;
    end if;
    if array_length(lines, 1) > 0 then
      perform public.notify_user(r.id, 'summary', 'Daily summary', array_to_string(lines, E'\n'), '/dashboard', 'daily:' || r.id || ':' || today);
    end if;
  end loop;

  -- weekly Director report (Mondays)
  if extract(isodow from today) = 1 then
    select coalesce(sum(case kind when 'receipt' then amount_paise else -amount_paise end), 0) into c3 from payments where verification = 'verified' and verified_at >= now() - interval '7 days';
    select coalesce(sum(amount_paise), 0) into c4 from booking_payment_milestones where activated_at is not null and due_date between today - 7 and today - 1;
    select count(*) into c1 from villas where expected_completion < today and status in ('booked','under_construction');
    select coalesce(sum(vb.overdue_paise), 0) into c5 from v_booking_balances vb join bookings b on b.id = vb.booking_id where b.status = 'confirmed';
    select count(*) into c2 from follow_up_activity_logs where created_at >= now() - interval '7 days';
    perform public.notify_directors('summary', 'Weekly report', 'Collected this week: ' || public.fmt_inr(c3) || E'\nScheduled to fall due last week: ' || public.fmt_inr(c4)
      || E'\nOverdue now: ' || public.fmt_inr(c5) || E'\nVillas behind expected completion: ' || c1 || E'\nCall outcomes logged: ' || c2, '/reports', 'weekly:' || wk);
  end if;

  perform public.purge_old_data();
  select count(*) into n1 from notifications; select count(*) into d1 from customer_message_drafts;
  return jsonb_build_object('notifications_created', n1 - n0, 'drafts_created', d1 - d0);
end $$;

-- ---------- message drafts & usage meter ----------
create function public.handle_message(p_id uuid, p_action text) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid; m customer_message_drafts;
begin
  uid := public.require_role('salesperson', 'director');
  if p_action not in ('sent', 'skipped') then raise exception 'Unknown action'; end if;
  select * into m from customer_message_drafts where id = p_id for update;
  if m.id is null then raise exception 'Message not found'; end if;
  if public.app_role() = 'salesperson' and m.assigned_to is distinct from uid then raise exception 'This message is not assigned to you' using errcode = '42501'; end if;
  if m.status <> 'pending' then return; end if;
  update customer_message_drafts set status = p_action, handled_at = now(), handled_by = uid where id = p_id;
end $$;

create function public.usage_stats() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role('director');
  return jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'storage_bytes', coalesce((select sum((metadata ->> 'size')::bigint) from storage.objects), 0),
    'notifications', (select count(*) from notifications), 'drafts', (select count(*) from customer_message_drafts),
    'events', (select count(*) from domain_events), 'failed_events', (select count(*) from domain_events where processed_at is null and attempts >= 5),
    'audit_rows', (select count(*) from audit_logs), 'payments', (select count(*) from payments), 'users', (select count(*) from profiles));
end $$;

revoke execute on function public.handle_event(uuid), public.trg_event_dispatch(), public.notify_user(uuid,text,text,text,text,text), public.notify_directors(text,text,text,text,text),
  public.notify_booking_staff(uuid,uuid,text,text,text,text,text), public.queue_customer_message(uuid,text,jsonb,text), public.render_template(text,jsonb), public.purge_old_data(),
  public.setting_int(text,int), public.fmt_inr(bigint), public.process_pending_events(), public.run_daily_jobs(), public.handle_message(uuid,text), public.usage_stats() from public, anon;
grant execute on function public.process_pending_events(), public.run_daily_jobs(), public.handle_message(uuid,text), public.usage_stats() to authenticated;
