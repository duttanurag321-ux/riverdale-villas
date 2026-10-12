-- Riverdale Villas — Phase 8 / 011: AUTOPILOT. The system does the routine work; the Director only handles exceptions.
--   * most construction steps count automatically; key steps are approved automatically after 24 h unless the Director says no
--   * payment requests are made automatically when construction progresses (within limits); big ones need one tap from the Director
--   * Salespeople can prepare bookings; the Director only confirms
--   * one daily list to confirm payments; a "flow" overview so the Director can see everything is running
-- Run once in the Supabase SQL Editor AFTER 001-010.

alter table construction_updates add column auto_approved boolean not null default false;
alter table payment_demands add column auto boolean not null default false;

create table autopilot_runs (id uuid primary key default gen_random_uuid(), ran_at timestamptz not null default now(), kind text not null,
  auto_approved int not null default 0, auto_asked int not null default 0, needs_ok int not null default 0, note text);
alter table autopilot_runs enable row level security;
grant select on autopilot_runs to authenticated;
create policy ar_read on autopilot_runs for select to authenticated using (public.is_director());

insert into system_settings(key, value) values
  ('autopilot_enabled', 'true'), ('auto_approve_hours', '24'), ('auto_ask_max_percent', '10'), ('auto_ask_min_rupees', '25000'),
  ('auto_ask_pre_construction', 'true'), ('stuck_site_days', '7'), ('stuck_follow_days', '3')
on conflict (key) do nothing;

-- Only the key steps wait for the Director (and even they pass automatically after the waiting time).
update construction_stages set requires_approval = (name in ('Foundation completed', 'First slab / ceiling completed', 'Final inspection', 'Handover completed'));

create function public.setting_bool(p_key text, p_default boolean) returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select (value #>> '{}')::boolean from system_settings where key = p_key), p_default) $$;

create function public.autopilot_log(p_kind text, p_note text) returns void language sql security definer set search_path = public
as $$ insert into autopilot_runs(kind, note) values (p_kind, p_note) $$;

-- customers: a Salesperson may add their own customers
create policy customers_sales_ins on customers for insert to authenticated with check (public.app_role() = 'salesperson' and salesperson_id = auth.uid());

-- ---------- role-free cores ----------
create function public.suggest_demand_calc(p_booking uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare b bookings; pool_amt bigint := 0; collected bigint; open_dem bigint; credit bigint; start_bp int; total_w int; done_w int; prog_bp int; target bigint; raw bigint; sugg bigint; step bigint;
begin
  select * into b from bookings where id = p_booking; if b.id is null then raise exception 'Booking not found'; end if;
  select amount_paise into pool_amt from booking_payment_milestones where booking_id = p_booking and is_pool and not cancelled;
  pool_amt := coalesce(pool_amt, 0);   -- a booking with no "balance asked later" line has nothing to ask for
  select net_receipts_paise, activated_outstanding_paise, credit_paise into collected, open_dem, credit from v_booking_balances where booking_id = p_booking;
  start_bp := coalesce(b.start_threshold_bp, public.setting_int('start_threshold_percent', 40) * 100);
  select coalesce(sum(weight), 0) into total_w from construction_stages where is_active;
  select coalesce(sum(s.weight), 0) into done_w from construction_stages s where s.is_active and exists
    (select 1 from construction_updates u where u.villa_id = b.villa_id and u.stage_id = s.id and u.new_status = 'completed' and u.approval in ('approved','not_required'));
  prog_bp := case when total_w = 0 then 0 else (done_w * 10000) / total_w end;
  target := (b.contract_value_paise * (start_bp + ((10000 - start_bp) * prog_bp) / 10000)) / 10000;
  raw := greatest(0, target - coalesce(collected, 0) - coalesce(open_dem, 0));
  raw := least(raw, pool_amt);
  step := public.setting_int('suggestion_round_rupees', 10000)::bigint * 100;
  sugg := case when raw >= step then (raw / step) * step else raw end;
  return jsonb_build_object('contract_value_paise', b.contract_value_paise, 'collected_paise', coalesce(collected, 0), 'open_demand_paise', coalesce(open_dem, 0),
    'pool_paise', pool_amt, 'start_bp', start_bp, 'progress_bp', prog_bp, 'target_paise', target, 'suggested_paise', sugg,
    'gate_open', public.gate_open(p_booking), 'funding_type', b.funding_type, 'loan_sanctioned_paise', b.loan_sanctioned_paise);
end $$;

create function public.raise_demand_core(p_booking uuid, p_amount_paise bigint, p_title text, p_due_days int default 7, p_update uuid default null,
  p_note text default null, p_suggested_paise bigint default null, p_request_id text default null, p_by uuid default null, p_auto boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid; b bookings; pool booking_payment_milestones; new_id uuid; nseq int; existing uuid;
begin
  uid := p_by;
  if p_request_id is not null then select milestone_id into existing from payment_demands where request_id = p_request_id; if existing is not null then return existing; end if; end if;
  if p_amount_paise is null or p_amount_paise <= 0 then raise exception 'Enter an amount above zero'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'Say what the payment is for'; end if;
  if p_due_days is null or p_due_days < 0 or p_due_days > 365 then raise exception 'Choose a due date within a year'; end if;
  select * into b from bookings where id = p_booking for update;
  if b.id is null or b.status <> 'confirmed' then raise exception 'You can only ask for a payment on a confirmed booking'; end if;
  select * into pool from booking_payment_milestones where booking_id = p_booking and is_pool and not cancelled for update;
  if pool.id is null then raise exception 'There is no balance left to ask for on this booking. Use "Change plan" to adjust it.'; end if;
  if p_amount_paise > pool.amount_paise then raise exception 'Only % is left to ask for on this booking', public.fmt_inr(pool.amount_paise); end if;
  if p_update is not null and not exists (select 1 from construction_updates where id = p_update and villa_id = b.villa_id) then raise exception 'That construction update belongs to a different villa'; end if;
  perform set_config('app.amending', 'on', true);
  if p_amount_paise = pool.amount_paise then
    update booking_payment_milestones set name = p_title, is_pool = false, due_days = p_due_days where id = pool.id; new_id := pool.id;
  else
    update booking_payment_milestones set amount_paise = amount_paise - p_amount_paise where id = pool.id;
    select coalesce(max(seq), 0) + 1 into nseq from booking_payment_milestones where booking_id = p_booking;
    insert into booking_payment_milestones(booking_id, seq, name, trigger, amount_paise, due_days, grace_days, notify_customer, is_mandatory)
      values (p_booking, nseq, p_title, 'manual', p_amount_paise, p_due_days, pool.grace_days, true, true) returning id into new_id;
  end if;
  perform set_config('app.amending', 'off', true);
  insert into payment_demands(booking_id, milestone_id, amount_paise, title, note, update_id, suggested_paise, request_id, created_by, auto)
    values (p_booking, new_id, p_amount_paise, p_title, p_note, p_update, p_suggested_paise, p_request_id, uid, p_auto);
  perform public.activate_milestone(new_id);
  perform public.write_audit('payment_demand_raised', 'bookings', p_booking::text, jsonb_build_object('amount_paise', p_amount_paise, 'title', p_title, 'suggested_paise', p_suggested_paise));
  return new_id;
end $$;

create or replace function public.create_booking_schedule_core(p_booking uuid, p_template uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b bookings; t record; running bigint := 0; last_seq int; amt bigint;
begin
  select * into b from bookings where id = p_booking for update;
  if b.status <> 'draft' then raise exception 'Schedule can only be created for a draft booking'; end if;
  perform public.check_template(p_template);
  delete from booking_payment_milestones where booking_id = p_booking;
  select max(seq) into last_seq from payment_plan_template_milestones where template_id = p_template;
  for t in select * from payment_plan_template_milestones where template_id = p_template order by seq loop
    if t.kind = 'percent' then
      amt := (b.contract_value_paise * t.percent_bp) / 10000;
      if t.seq = last_seq then amt := b.contract_value_paise - running; end if;
    else amt := t.fixed_paise; end if;
    running := running + amt;
    insert into booking_payment_milestones(booking_id, seq, name, trigger, stage_id, amount_paise, source_percent_bp,
      due_days, grace_days, notify_customer, is_mandatory, is_pool)
    values (p_booking, t.seq, t.name, t.trigger, t.stage_id, amt, t.percent_bp, t.due_days, t.grace_days, t.notify_customer, t.is_mandatory, t.is_pool);
  end loop;
  perform public.write_audit('booking_schedule_created', 'bookings', p_booking::text, jsonb_build_object('template_id', p_template));
end $$;

create or replace function public.trg_construction_villa_status() returns trigger language plpgsql security definer set search_path = public as $$
declare ho boolean;
begin
  update villas set status = 'under_construction' where id = new.villa_id and status = 'booked';
  if new.new_status = 'completed' and new.approval in ('approved','not_required')
     and (tg_op = 'INSERT' or old.approval is distinct from new.approval) then
    select is_handover into ho from construction_stages where id = new.stage_id;
    if ho then
      update villas set status = 'handed_over', actual_completion = coalesce(actual_completion, current_date) where id = new.villa_id;
      perform public.emit_event('handover_completed:' || new.villa_id, 'handover_completed', new.booking_id, jsonb_build_object('villa_id', new.villa_id));
    end if;
  end if;
  if new.booking_id is not null and new.new_status = 'completed' and new.approval in ('approved','not_required')
     and (tg_op = 'INSERT' or old.approval is distinct from new.approval) then
    begin perform public.autopilot_check_booking(new.booking_id, new.id);
    exception when others then perform public.autopilot_log('error', 'autopilot check failed: ' || left(sqlerrm, 200)); end;
  end if;
  return new;
end $$;

create or replace function public.suggest_demand(p_booking uuid) returns jsonb language plpgsql security definer set search_path = public as $$
begin perform public.require_role('director'); return public.suggest_demand_calc(p_booking); end $$;

create or replace function public.raise_demand(p_booking uuid, p_amount_paise bigint, p_title text, p_due_days int default 7, p_update uuid default null,
  p_note text default null, p_suggested_paise bigint default null, p_request_id text default null) returns uuid language plpgsql security definer set search_path = public as $$
begin return public.raise_demand_core(p_booking, p_amount_paise, p_title, p_due_days, p_update, p_note, p_suggested_paise, p_request_id, public.require_role('director'), false); end $$;

create or replace function public.create_booking_schedule(p_booking uuid, p_template uuid) returns void language plpgsql security definer set search_path = public as $$
begin perform public.require_role('director'); perform public.create_booking_schedule_core(p_booking, p_template); end $$;

-- ---------- automatic approval of waiting construction updates ----------
create function public.auto_approve_pending() returns int language plpgsql security definer set search_path = public as $$
declare hrs int := public.setting_int('auto_approve_hours', 24); u record; n int := 0;
begin
  if hrs <= 0 then return 0; end if;
  for u in select * from construction_updates where approval = 'pending' and submitted_at < now() - make_interval(hours => hrs) order by submitted_at for update skip locked loop
    update construction_updates set approval = 'approved', approved_by = null, approved_at = now(), auto_approved = true where id = u.id;
    update villas set current_stage_id = u.stage_id where id = u.villa_id;
    perform public.activate_milestone(m.id) from booking_payment_milestones m where m.booking_id = u.booking_id and m.stage_id = u.stage_id and m.trigger = 'stage_approved';
    perform public.emit_event('construction_update_approved:' || u.id, 'construction_update_approved', u.booking_id, jsonb_build_object('update_id', u.id, 'villa_id', u.villa_id, 'stage_id', u.stage_id, 'auto', true));
    insert into audit_logs(actor, action, entity, entity_id, details) values (null, 'construction_auto_approved', 'construction_updates', u.id::text, jsonb_build_object('after_hours', hrs));
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- automatic payment requests ----------
create function public.autopilot_check_booking(p_booking uuid, p_update uuid default null) returns text language plpgsql security definer set search_path = public as $$
declare b bookings; sg jsonb; sugg bigint; open_dem bigint; cap bigint; minp bigint; gate boolean; ttl text; stg text; vn text; cn text; upd uuid := p_update;
begin
  if not public.setting_bool('autopilot_enabled', true) then return 'none'; end if;
  select * into b from bookings where id = p_booking and status = 'confirmed' for update;
  if b.id is null then return 'none'; end if;
  sg := public.suggest_demand_calc(p_booking);
  sugg := (sg ->> 'suggested_paise')::bigint; open_dem := (sg ->> 'open_demand_paise')::bigint; gate := (sg ->> 'gate_open')::boolean;
  minp := public.setting_int('auto_ask_min_rupees', 25000)::bigint * 100;
  if sugg is null or sugg <= 0 or sugg < minp then return 'none'; end if;
  if upd is null and gate then
    select u.id into upd from construction_updates u where u.villa_id = b.villa_id and u.new_status = 'completed' and u.approval in ('approved','not_required') order by u.submitted_at desc limit 1;
  end if;
  if not gate then
    -- before construction: ask once, only after earlier requests are paid, to reach the start percentage
    if not public.setting_bool('auto_ask_pre_construction', true) or open_dem > 0 then return 'none'; end if;
    ttl := 'Payment before construction starts'; upd := null;
  else
    cap := (b.contract_value_paise * public.setting_int('auto_ask_max_percent', 10)) / 100;
    select s.name into stg from construction_updates u join construction_stages s on s.id = u.stage_id where u.id = upd;
    ttl := coalesce(stg || ' payment', 'Construction payment');
    if sugg > cap then
      select v.villa_number into vn from villas v where v.id = b.villa_id; select c.full_name into cn from customers c where c.id = b.customer_id;
      perform public.notify_directors('payment', 'Your OK is needed: ask ' || cn || ' for ' || public.fmt_inr(sugg) || '?', 'Villa ' || vn || ': this is more than the automatic limit.', '/bookings/' || p_booking || '/demand', 'bigask:' || p_booking || ':' || sugg);
      return 'needs_ok';
    end if;
  end if;
  perform public.raise_demand_core(p_booking, sugg, ttl, public.setting_int('default_demand_due_days', 7), upd, 'Requested automatically', sugg, 'auto:' || p_booking || ':' || sugg || ':' || open_dem, null, true);
  return 'asked';
end $$;

create function public.autopilot_tick() returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; res text; a int; asked int := 0; ok int := 0;
begin
  if auth.uid() is not null and not public.is_director() then raise exception 'Not authorized' using errcode = '42501'; end if;
  a := public.auto_approve_pending();
  for r in select id from bookings where status = 'confirmed' loop
    begin res := public.autopilot_check_booking(r.id);
      if res = 'asked' then asked := asked + 1; elsif res = 'needs_ok' then ok := ok + 1; end if;
    exception when others then perform public.autopilot_log('error', 'booking ' || r.id || ': ' || left(sqlerrm, 200)); end;
  end loop;
  perform public.process_pending_events();
  insert into autopilot_runs(kind, auto_approved, auto_asked, needs_ok) values ('tick', a, asked, ok);
  delete from autopilot_runs where ran_at < now() - interval '30 days';
  return jsonb_build_object('auto_approved', a, 'auto_asked', asked, 'needs_ok', ok);
end $$;

create function public.remind_pending_payments() returns void language plpgsql security definer set search_path = public as $$
declare n int; amt bigint;
begin
  if auth.uid() is not null and not public.is_director() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select count(*), coalesce(sum(amount_paise), 0) into n, amt from payments where verification = 'pending';
  if n > 0 then perform public.notify_directors('payment', n || ' payment(s) to confirm', 'Check your bank, then confirm them in one tap. Total ' || public.fmt_inr(amt) || '.', '/payments', 'payconfirm:' || current_date); end if;
end $$;

-- ---------- Salesperson prepares a booking; the Director only confirms ----------
create function public.start_booking(p_villa uuid, p_customer uuid, p_token_paise bigint default null, p_method text default 'upi', p_reference text default null,
  p_received_on date default current_date, p_request_id text default null) returns uuid language plpgsql security definer set search_path = public as $$
declare uid uuid; v villas; c customers; price bigint; tpl uuid; bid uuid; existing uuid;
begin
  uid := public.require_role('salesperson', 'director');
  select id into existing from bookings where villa_id = p_villa and customer_id = p_customer and status = 'draft' and created_by = uid and created_at > now() - interval '5 minutes';
  if existing is not null then return existing; end if;
  select * into v from villas where id = p_villa; select * into c from customers where id = p_customer;
  if v.id is null or c.id is null then raise exception 'Villa or customer not found'; end if;
  if public.app_role() = 'salesperson' and (v.salesperson_id is distinct from uid or c.salesperson_id is distinct from uid) then raise exception 'You can only book your own villas for your own customers' using errcode = '42501'; end if;
  if v.status not in ('available', 'reserved') or exists (select 1 from bookings where villa_id = p_villa and status in ('draft', 'confirmed', 'completed')) then raise exception 'This villa is not available'; end if;
  select list_price_paise into price from villa_pricing where villa_id = p_villa;
  if price is null then raise exception 'This villa has no price yet. Ask the Director to add it.'; end if;
  select t.id into tpl from payment_plan_templates t where t.is_active and exists (select 1 from payment_plan_template_milestones m where m.template_id = t.id and m.is_pool)
    order by (t.name like 'Riverdale standard%') desc, t.created_at limit 1;
  if tpl is null then raise exception 'No payment plan is set up yet. Ask the Director.'; end if;
  insert into bookings(villa_id, customer_id, salesperson_id, package_price_paise, created_by) values (p_villa, p_customer, case when public.app_role() = 'salesperson' then uid else v.salesperson_id end, price, uid) returning id into bid;
  perform public.create_booking_schedule_core(bid, tpl);
  if p_token_paise is not null and p_token_paise > 0 then perform public.report_payment(bid, p_token_paise, p_method, p_reference, p_received_on, 'Token', p_request_id); end if;
  perform public.notify_directors('booking', 'New booking ready to confirm: Villa ' || v.villa_number, c.full_name || case when p_token_paise > 0 then ' - token ' || public.fmt_inr(p_token_paise) else '' end, '/bookings/' || bid, 'newbk:' || bid);
  return bid;
end $$;

-- ---------- what the Director sees ----------
create function public.flow_overview() returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; stuck jsonb := '[]'; r record; last_run timestamptz; failed int; flow_st text := 'green'; head text; n_asks int; amt_asks bigint; big jsonb; cap_pct int := public.setting_int('auto_ask_max_percent', 10);
  site_days int := public.setting_int('stuck_site_days', 7); fol_days int := public.setting_int('stuck_follow_days', 3);
begin
  perform public.require_role('director');
  select max(ran_at) into last_run from autopilot_runs where kind = 'tick';
  select count(*) into failed from domain_events where processed_at is null and attempts >= 5;
  for r in select v.villa_number, p.full_name, coalesce((select max(u.submitted_at) from construction_updates u where u.villa_id = v.id), b.confirmed_at) as last_at
           from villas v join bookings b on b.villa_id = v.id and b.status = 'confirmed' join profiles p on p.id = v.site_manager_id
           where v.status in ('booked', 'under_construction') and public.gate_open(b.id) and coalesce((select max(u.submitted_at) from construction_updates u where u.villa_id = v.id), b.confirmed_at) < now() - make_interval(days => site_days) loop
    stuck := stuck || jsonb_build_object('who', r.full_name, 'role', 'Site Manager', 'text', 'Villa ' || r.villa_number || ': no site update for ' || extract(day from now() - r.last_at)::int || ' days');
  end loop;
  for r in select p.full_name, count(*) n from follow_up_tasks t join profiles p on p.id = t.assigned_to where t.status = 'open' and t.due_date < current_date - fol_days group by p.full_name loop
    stuck := stuck || jsonb_build_object('who', r.full_name, 'role', 'Salesperson', 'text', r.n || ' follow-up call(s) more than ' || fol_days || ' days late');
  end loop;
  for r in select p.full_name, count(*) n from customer_message_drafts d join profiles p on p.id = d.assigned_to where d.status = 'pending' and d.created_at < now() - interval '2 days' group by p.full_name loop
    stuck := stuck || jsonb_build_object('who', r.full_name, 'role', 'Salesperson', 'text', r.n || ' customer message(s) not sent for over 2 days');
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('booking_id', x.bid, 'villa', x.vn, 'customer', x.cn, 'suggested_paise', x.s)), '[]') into big from (
    select b.id bid, v.villa_number vn, c.full_name cn, (public.suggest_demand_calc(b.id) ->> 'suggested_paise')::bigint s, b.contract_value_paise cv
    from bookings b join villas v on v.id = b.villa_id join customers c on c.id = b.customer_id where b.status = 'confirmed' and public.gate_open(b.id)) x
    where x.s > 0 and x.s > (x.cv * cap_pct) / 100 and x.s >= public.setting_int('auto_ask_min_rupees', 25000)::bigint * 100;
  select count(*), coalesce(sum(amount_paise), 0) into n_asks, amt_asks from payment_demands where auto and created_at > now() - interval '7 days';
  if failed > 0 or (last_run is not null and last_run < now() - interval '2 hours') then flow_st := 'red';
  elsif jsonb_array_length(stuck) > 0 or jsonb_array_length(big) > 0 or last_run is null then flow_st := 'amber'; end if;
  head := case flow_st when 'green' then 'Everything is running automatically' when 'amber' then 'A few things need a nudge' else 'The automatic system needs attention' end;
  if flow_st = 'red' and failed > 0 then head := head || ': ' || failed || ' automatic alert(s) failed'; end if;
  if last_run is null then stuck := stuck || jsonb_build_object('who', 'System', 'role', 'System', 'text', 'Automatic checks have never run. Turn on the scheduler or press "Run autopilot now" in More, Settings.');
  elsif last_run < now() - interval '2 hours' then stuck := stuck || jsonb_build_object('who', 'System', 'role', 'System', 'text', 'Automatic checks last ran ' || to_char(last_run, 'DD Mon HH24:MI') || '. The scheduler may be off.'); end if;
  return jsonb_build_object('status', flow_st, 'headline', head, 'last_run_at', last_run,
    'draft_bookings', (select count(*) from bookings where status = 'draft'),
    'collecting', (select count(*) from bookings b where b.status = 'confirmed' and not public.gate_open(b.id)),
    'building', (select count(*) from bookings b join villas v on v.id = b.villa_id where b.status = 'confirmed' and public.gate_open(b.id) and v.status <> 'handed_over'),
    'handed_over', (select count(*) from villas where status = 'handed_over'),
    'received_7d', coalesce((select sum(case kind when 'receipt' then amount_paise else -amount_paise end) from payments where verification = 'verified' and verified_at > now() - interval '7 days'), 0),
    'asked_open_paise', coalesce((select sum(activated_outstanding_paise) from v_booking_balances where booking_status = 'confirmed'), 0),
    'overdue_paise', coalesce((select sum(overdue_paise) from v_booking_balances where booking_status = 'confirmed'), 0),
    'auto_asks_7d', n_asks, 'auto_asks_amount_7d', amt_asks,
    'auto_approved_7d', (select count(*) from construction_updates where auto_approved and approved_at > now() - interval '7 days'),
    'pending_confirm', (select count(*) from payments where verification = 'pending'), 'pending_confirm_paise', coalesce((select sum(amount_paise) from payments where verification = 'pending'), 0),
    'ready_to_confirm', coalesce((select jsonb_agg(jsonb_build_object('booking_id', b.id, 'villa', v.villa_number, 'customer', c.full_name)) from bookings b join villas v on v.id = b.villa_id join customers c on c.id = b.customer_id
        where b.status = 'draft' and exists (select 1 from booking_payment_milestones m where m.booking_id = b.id)), '[]'),
    'big_asks', big, 'stuck', stuck, 'pending_key_approvals', (select count(*) from construction_updates where approval = 'pending'));
end $$;

create function public.activity_feed(p_limit int default 15) returns table(at timestamptz, kind text, line text) language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role('director');
  return query select x.at, x.kind, x.line from (
    select d.created_at as at, 'ask'::text as kind, (case when d.auto then 'The system asked ' else 'You asked ' end || c.full_name || ' for ' || public.fmt_inr(d.amount_paise) || ' (' || d.title || ') - Villa ' || v.villa_number) as line
      from payment_demands d join bookings b on b.id = d.booking_id join customers c on c.id = b.customer_id join villas v on v.id = b.villa_id
    union all select p.verified_at, 'money', 'Payment of ' || public.fmt_inr(p.amount_paise) || ' confirmed from ' || c.full_name || ' - Villa ' || v.villa_number
      from payments p join bookings b on b.id = p.booking_id join customers c on c.id = p.customer_id join villas v on v.id = b.villa_id where p.verification = 'verified' and p.kind = 'receipt'
    union all select p.created_at, 'report', coalesce(pr.full_name, 'Someone') || ' reported ' || public.fmt_inr(p.amount_paise) || ' from ' || c.full_name || ' - waiting for your confirmation'
      from payments p join customers c on c.id = p.customer_id left join profiles pr on pr.id = p.entered_by where p.verification = 'pending'
    union all select u.submitted_at, 'build', coalesce(pr.full_name, 'Site Manager') || ' updated Villa ' || v.villa_number || ': ' || s.name || ' (' || replace(u.new_status::text, '_', ' ') || ')'
      from construction_updates u join villas v on v.id = u.villa_id join construction_stages s on s.id = u.stage_id left join profiles pr on pr.id = u.submitted_by
    union all select u.approved_at, 'build', 'Approved automatically: ' || s.name || ' at Villa ' || v.villa_number
      from construction_updates u join villas v on v.id = u.villa_id join construction_stages s on s.id = u.stage_id where u.auto_approved
    union all select b.confirmed_at, 'booking', 'Booking confirmed: Villa ' || v.villa_number || ' - ' || c.full_name from bookings b join villas v on v.id = b.villa_id join customers c on c.id = b.customer_id where b.confirmed_at is not null
    union all select m.handled_at, 'message', 'WhatsApp message sent to ' || c.full_name from customer_message_drafts m join customers c on c.id = m.customer_id where m.status = 'sent' and m.handled_at is not null
  ) x where x.at is not null order by x.at desc limit p_limit;
end $$;

revoke execute on function public.setting_bool(text, boolean), public.autopilot_log(text, text), public.suggest_demand_calc(uuid), public.raise_demand_core(uuid, bigint, text, int, uuid, text, bigint, text, uuid, boolean),
  public.create_booking_schedule_core(uuid, uuid), public.auto_approve_pending(), public.autopilot_check_booking(uuid, uuid), public.autopilot_tick(), public.remind_pending_payments(),
  public.start_booking(uuid, uuid, bigint, text, text, date, text), public.flow_overview(), public.activity_feed(int) from public, anon;
grant execute on function public.autopilot_tick(), public.remind_pending_payments(), public.start_booking(uuid, uuid, bigint, text, text, date, text), public.flow_overview(), public.activity_feed(int) to authenticated;

-- schedule (only if the scheduler extension is switched on; otherwise use "Run autopilot now" in Settings)
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('riverdale-autopilot', '*/15 * * * *', 'select public.autopilot_tick()');
    perform cron.schedule('riverdale-confirm-reminder', '30 12 * * *', 'select public.remind_pending_payments()');   -- 18:00 India
  end if;
end $$;
