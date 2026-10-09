-- Riverdale Villas — Phase 7 / 010: the real Riverdale flow.
--   token -> 10% booking -> 40-50% before construction (self-funded or loan) -> payment demands as the company needs funds.
-- Run once in the Supabase SQL Editor AFTER 001-009.

-- ---------- new columns ----------
alter table payments add column purpose text not null default 'installment' check (purpose in ('token','installment'));
alter table payments add column paid_by text not null default 'customer' check (paid_by in ('customer','bank'));
alter table bookings add column funding_type text not null default 'self' check (funding_type in ('self','loan'));
alter table bookings add column loan_bank text;
alter table bookings add column loan_sanctioned_paise bigint check (loan_sanctioned_paise is null or loan_sanctioned_paise > 0);
alter table bookings add column start_threshold_bp int check (start_threshold_bp between 0 and 10000);
alter table bookings add column construction_released boolean not null default false;
alter table booking_payment_milestones add column is_pool boolean not null default false;
alter table booking_payment_milestones add check (not is_pool or trigger = 'manual');
create unique index one_pool_per_booking on booking_payment_milestones(booking_id) where is_pool;
alter table payment_plan_template_milestones add column is_pool boolean not null default false;
alter table payment_plan_template_milestones add check (not is_pool or trigger = 'manual');
create unique index one_pool_per_template on payment_plan_template_milestones(template_id) where is_pool;
alter table construction_stages add column weight int not null default 1 check (weight >= 0);

insert into system_settings(key, value) values
  ('start_threshold_percent', '40'), ('start_gate_enabled', 'true'), ('default_demand_due_days', '7'), ('suggestion_round_rupees', '10000')
on conflict (key) do nothing;

insert into message_templates(kind, title, body) values ('payment_demand', 'Payment request with construction update',
$t$Hello {{customer_name}},

Here is an update on your Riverdale Villas home.

Villa: {{villa_number}}
Progress: {{progress_note}}

As per our arrangement, the next payment is now requested.
For: {{milestone_name}}
Amount: {{milestone_amount}}
Please pay by: {{due_date}}

Please contact your Riverdale Villas representative for payment assistance.

Regards,
Riverdale Villas Team$t$) on conflict (kind) do nothing;

-- Every request for money is recorded forever, with what the system suggested at that moment.
create table payment_demands (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  milestone_id uuid not null unique references booking_payment_milestones(id),
  amount_paise bigint not null check (amount_paise > 0),
  title text not null,
  note text,
  update_id uuid references construction_updates(id),
  suggested_paise bigint,
  request_id text unique,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create trigger pd_immutable before update or delete on payment_demands for each row execute function public.trg_ledger_immutable();
alter table payment_demands enable row level security;
grant select on payment_demands to authenticated;
create policy pd_read on payment_demands for select to authenticated
  using (public.is_director() or (public.app_role() = 'salesperson' and booking_id in (select public.my_booking_ids())));

-- Starter plan: 10% at booking, the other 90% is "raised as construction progresses" (editable on the Payment plans page).
with t as (insert into payment_plan_templates(name, villa_configuration) values ('Riverdale standard (10% booking, balance on demand)', null) returning id)
insert into payment_plan_template_milestones(template_id, seq, name, kind, percent_bp, trigger, due_days, grace_days, is_pool)
select t.id, v.seq, v.name, 'percent', v.bp, v.trg::milestone_trigger, v.d, 0, v.pool
from t, (values (1, 'Booking amount', 1000, 'booking_confirmed', 0, false), (2, 'Balance - raised as construction progresses', 9000, 'manual', 7, true)) v(seq, name, bp, trg, d, pool);

-- ---------- patched existing functions ----------
create or replace function public.trg_bookings_guard() returns trigger language plpgsql as $$
begin
  if public.is_api_caller() then
    if tg_op = 'INSERT' then
      new.status := 'draft'; new.confirmed_at := null; new.confirmed_by := null;
      new.cancelled_at := null; new.cancel_reason := null; new.created_by := auth.uid(); new.construction_released := false;
    else
      if new.status is distinct from old.status or new.confirmed_at is distinct from old.confirmed_at
         or new.cancelled_at is distinct from old.cancelled_at or new.construction_released is distinct from old.construction_released then
        raise exception 'Booking status can only change through confirm_booking / cancel_booking';
      end if;
      if old.status <> 'draft' and (new.package_price_paise <> old.package_price_paise
         or new.extra_charges_paise <> old.extra_charges_paise or new.villa_id <> old.villa_id
         or new.customer_id <> old.customer_id) then
        raise exception 'Confirmed booking terms are frozen; use a payment-plan amendment';
      end if;
    end if;
  end if;
  return new;
end $$;

create or replace function public.create_booking_schedule(p_booking uuid, p_template uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b bookings; t record; running bigint := 0; last_seq int; amt bigint;
begin
  perform public.require_role('director');
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

create or replace function public.activate_milestone(p_milestone uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare m booking_payment_milestones; b bookings; sp uuid;
begin
  select * into m from booking_payment_milestones where id = p_milestone for update;
  if m.id is null or m.activated_at is not null or m.cancelled then return false; end if;
  select * into b from bookings where id = m.booking_id;
  if b.status <> 'confirmed' then return false; end if;
  update booking_payment_milestones set activated_at = now(), due_date = current_date + m.due_days where id = m.id;
  sp := coalesce(b.salesperson_id, (select salesperson_id from customers where id = b.customer_id));
  insert into follow_up_tasks(booking_id, milestone_id, assigned_to, due_date)
    values (b.id, m.id, sp, current_date + m.due_days) on conflict (milestone_id, kind) do nothing;
  perform public.apply_credit(b.id);
  perform public.emit_event('milestone_activated:' || m.id, 'payment_milestone_activated', b.id,
    jsonb_build_object('milestone_id', m.id, 'milestone_name', m.name, 'amount_paise', m.amount_paise,
                       'due_date', current_date + m.due_days, 'notify_customer', m.notify_customer));
  return true;
end $$;

create or replace function public.submit_construction_update(p_villa uuid, p_stage uuid, p_new_status update_status,
  p_remarks text default null, p_is_issue boolean default false, p_request_id text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid; v villas; s construction_stages; prev update_status; bk uuid; appr approval_status; uid_row uuid; new_id uuid;
begin
  uid := public.require_role('site_manager','director');
  if p_request_id is not null then
    select id into uid_row from construction_updates where client_request_id = p_request_id;
    if uid_row is not null then return uid_row; end if;     -- retry: same result, no duplicate
  end if;
  select * into v from villas where id = p_villa;
  if v.id is null then raise exception 'Villa not found'; end if;
  if public.app_role() = 'site_manager' and v.site_manager_id is distinct from uid then
    raise exception 'This villa is not assigned to you' using errcode = '42501'; end if;
  select * into s from construction_stages where id = p_stage and is_active;
  if s.id is null then raise exception 'Stage not found or disabled'; end if;
  if p_new_status = 'not_started' then raise exception 'Choose in_progress, delayed or completed'; end if;
  select new_status into prev from construction_updates where villa_id = p_villa and stage_id = p_stage
    and approval in ('not_required','approved','pending') order by submitted_at desc limit 1;
  prev := coalesce(prev, 'not_started');
  select id into bk from bookings where villa_id = p_villa and status = 'confirmed';
  if bk is not null and not public.gate_open(bk) then
    raise exception 'Construction cannot start yet. The Director will release it once the customer''s payment is confirmed.';
  end if;
  appr := case when p_new_status = 'completed' and s.requires_approval then 'pending' else 'not_required' end;
  insert into construction_updates(villa_id, booking_id, stage_id, previous_status, new_status, remarks, is_issue,
    submitted_by, approval, client_request_id)
  values (p_villa, bk, p_stage, prev, p_new_status, p_remarks, p_is_issue, uid, appr, p_request_id) returning id into new_id;
  perform public.emit_event('construction_update_submitted:' || new_id, 'construction_update_submitted', bk,
    jsonb_build_object('update_id', new_id, 'villa_id', p_villa, 'stage_id', p_stage, 'status', p_new_status, 'approval', appr));
  if p_new_status = 'delayed' then
    perform public.emit_event('construction_delayed:' || new_id, 'construction_delayed', bk, jsonb_build_object('villa_id', p_villa, 'stage_id', p_stage));
  end if;
  if appr = 'not_required' and p_new_status = 'completed' then
    update villas set current_stage_id = p_stage where id = p_villa;
    perform public.activate_milestone(m.id) from booking_payment_milestones m
      where m.booking_id = bk and m.stage_id = p_stage and m.trigger = 'stage_approved';
  end if;
  return new_id;
end $$;

create or replace function public.handle_event(p_event uuid) returns void language plpgsql security definer set search_path = public as $$
declare dtitle text; dnote text; dupd uuid; pn text; e domain_events; b bookings; vid uuid; vn text; cn text; sn text; mid uuid; mn text; ma bigint; mp bigint; mo bigint; md date; mnotify boolean;
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
    select d.title, d.note, d.update_id into dtitle, dnote, dupd from payment_demands d where d.milestone_id = mid;
    if dtitle is not null and mo > 0 then
      select s.name into pn from construction_updates u join construction_stages s on s.id = u.stage_id where u.id = dupd;
      perform public.queue_customer_message(b.id, 'payment_demand', jsonb_build_object('milestone_name', dtitle, 'milestone_amount', public.fmt_inr(ma),
        'milestone_outstanding', public.fmt_inr(mo), 'due_date', to_char(md, 'DD Mon YYYY'), 'progress_note', coalesce(pn, dnote, dtitle)), 'due:' || mid);
    elsif mnotify and mo > 0 and dtitle is null then
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

drop view public.v_booking_balances;
drop view public.v_milestone_balances;
create view public.v_milestone_balances with (security_invoker = true) as
select m.*,
  coalesce(a.paid, 0)::bigint as paid_paise,
  (case when m.activated_at is null then 0 else m.amount_paise - coalesce(a.paid, 0) end)::bigint as outstanding_paise,
  case when m.cancelled then 'cancelled'
       when m.on_hold then 'on_hold'
       when m.activated_at is null then 'not_activated'
       when coalesce(a.paid, 0) >= m.amount_paise then 'paid'
       when current_date > m.due_date + m.grace_days then 'overdue'
       when coalesce(a.paid, 0) > 0 then 'partially_paid'
       when current_date >= m.due_date then 'due'
       else 'upcoming' end as derived_status
from booking_payment_milestones m
left join (select milestone_id, sum(amount_paise) as paid from payment_allocations group by milestone_id) a on a.milestone_id = m.id;

create view public.v_booking_balances with (security_invoker = true) as
select b.id as booking_id, b.contract_value_paise,
  coalesce(p.net, 0)::bigint as net_receipts_paise,
  (b.contract_value_paise - coalesce(p.net, 0))::bigint as outstanding_paise,
  coalesce(p.pending, 0)::bigint as pending_verification_paise,
  coalesce(ms.activated, 0)::bigint as activated_obligation_paise,
  coalesce(ms.act_out, 0)::bigint as activated_outstanding_paise,
  coalesce(ms.overdue, 0)::bigint as overdue_paise,
  b.status as booking_status,
  (coalesce(p.net, 0) - coalesce(al.s, 0))::bigint as credit_paise
from bookings b
left join lateral (
  select sum(case when verification = 'verified' and kind = 'receipt' then amount_paise
                  when verification = 'verified' and kind = 'reversal' then -amount_paise else 0 end) as net,
         sum(case when verification = 'pending' then amount_paise else 0 end) as pending
  from payments where booking_id = b.id) p on true
left join lateral (
  select sum(amount_paise) filter (where activated_at is not null and not cancelled) as activated,
         sum(outstanding_paise) filter (where derived_status in ('due','upcoming','partially_paid','overdue')) as act_out,
         sum(outstanding_paise) filter (where derived_status = 'overdue') as overdue
  from v_milestone_balances where booking_id = b.id) ms on true
left join lateral (select sum(a.amount_paise) as s from payment_allocations a join booking_payment_milestones m on m.id = a.milestone_id where m.booking_id = b.id) al on true;

grant select on public.v_milestone_balances, public.v_booking_balances to authenticated;

-- ---------- credit, gate, suggestion, demand ----------
create function public.apply_credit(p_booking uuid) returns bigint language plpgsql security definer set search_path = public as $$
declare p record; m record; free_amt bigint; take bigint; total bigint := 0;
begin
  for p in select pay.id, pay.amount_paise - coalesce((select sum(a.amount_paise) from payment_allocations a where a.payment_id = pay.id), 0) as free
           from payments pay where pay.booking_id = p_booking and pay.kind = 'receipt' and pay.verification = 'verified'
             and not exists (select 1 from payments r where r.reverses_payment_id = pay.id) order by pay.verified_at, pay.created_at loop
    free_amt := p.free; continue when free_amt <= 0;
    for m in select bm.id, bm.amount_paise - coalesce((select sum(amount_paise) from payment_allocations where milestone_id = bm.id), 0) as outstanding
             from booking_payment_milestones bm where bm.booking_id = p_booking and bm.activated_at is not null and not bm.cancelled and not bm.on_hold
             order by bm.due_date, bm.seq for update of bm loop
      exit when free_amt <= 0; continue when m.outstanding <= 0;
      take := least(free_amt, m.outstanding);
      insert into payment_allocations(payment_id, milestone_id, amount_paise) values (p.id, m.id, take);
      free_amt := free_amt - take; total := total + take;
    end loop;
  end loop;
  update follow_up_tasks t set status = 'done' where t.booking_id = p_booking and t.status = 'open' and t.kind = 'payment_due'
    and (select coalesce(sum(amount_paise), 0) from payment_allocations where milestone_id = t.milestone_id) >= (select amount_paise from booking_payment_milestones where id = t.milestone_id);
  return total;
end $$;

-- Is construction allowed to start for this booking? (enough money confirmed, or the Director released it)
create function public.gate_open(p_booking uuid) returns boolean language plpgsql stable security definer set search_path = public as $$
declare b bookings; need_bp int; net bigint;
begin
  if coalesce((select value from system_settings where key = 'start_gate_enabled'), 'true'::jsonb) <> 'true'::jsonb then return true; end if;
  select * into b from bookings where id = p_booking; if b.id is null then return true; end if;
  if b.construction_released then return true; end if;
  need_bp := coalesce(b.start_threshold_bp, public.setting_int('start_threshold_percent', 40) * 100);
  select net_receipts_paise into net from v_booking_balances where booking_id = p_booking;
  return coalesce(net, 0) * 10000 >= need_bp::bigint * b.contract_value_paise;
end $$;

-- What the Site Manager may know: only open/closed, never amounts.
create function public.construction_gates() returns table(villa_id uuid, gate_open boolean) language sql stable security definer set search_path = public as $$
  select v.id, coalesce(public.gate_open(b.id), true) from villas v left join bookings b on b.villa_id = v.id and b.status = 'confirmed'
  where public.is_director() or v.site_manager_id = auth.uid() or v.salesperson_id = auth.uid()
$$;

create function public.release_construction(p_booking uuid, p_release boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role('director');
  update bookings set construction_released = p_release where id = p_booking and status = 'confirmed';
  if not found then raise exception 'Booking not found or not confirmed'; end if;
  perform public.write_audit(case when p_release then 'construction_released' else 'construction_locked' end, 'bookings', p_booking::text);
end $$;

-- The suggestion: collections should follow construction. Start target = start % (40% by default);
-- then it rises with the share of construction stages completed and approved (stage "weight" counts more for bigger stages).
create function public.suggest_demand(p_booking uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare b bookings; pool_amt bigint := 0; collected bigint; open_dem bigint; credit bigint; start_bp int; total_w int; done_w int; prog_bp int; target bigint; raw bigint; sugg bigint; step bigint;
begin
  perform public.require_role('director');
  select * into b from bookings where id = p_booking; if b.id is null then raise exception 'Booking not found'; end if;
  select coalesce(amount_paise, 0) into pool_amt from booking_payment_milestones where booking_id = p_booking and is_pool and not cancelled;
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

create function public.demand_opportunities() returns table(booking_id uuid, villa_number text, customer_name text, suggested_paise bigint) language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role('director');
  return query select x.bid, x.vn, x.cn, x.s from (
    select b.id bid, v.villa_number vn, c.full_name cn, (public.suggest_demand(b.id) ->> 'suggested_paise')::bigint s
    from bookings b join villas v on v.id = b.villa_id join customers c on c.id = b.customer_id where b.status = 'confirmed') x where x.s > 0 order by x.s desc limit 10;
end $$;

create function public.raise_demand(p_booking uuid, p_amount_paise bigint, p_title text, p_due_days int default 7, p_update uuid default null,
  p_note text default null, p_suggested_paise bigint default null, p_request_id text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid; b bookings; pool booking_payment_milestones; new_id uuid; nseq int; existing uuid;
begin
  uid := public.require_role('director');
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
  insert into payment_demands(booking_id, milestone_id, amount_paise, title, note, update_id, suggested_paise, request_id, created_by)
    values (p_booking, new_id, p_amount_paise, p_title, p_note, p_update, p_suggested_paise, p_request_id, uid);
  perform public.activate_milestone(new_id);
  perform public.write_audit('payment_demand_raised', 'bookings', p_booking::text, jsonb_build_object('amount_paise', p_amount_paise, 'title', p_title, 'suggested_paise', p_suggested_paise));
  return new_id;
end $$;

-- token (booking still a draft) or normal payment (booking confirmed); bank = loan instalment
drop function public.report_payment(uuid, bigint, text, text, date, text, text);
create function public.report_payment(p_booking uuid, p_amount_paise bigint, p_method text, p_reference text, p_received_on date,
  p_notes text default null, p_request_id text default null, p_paid_by text default 'customer') returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid; b bookings; existing uuid; new_id uuid; purp text;
begin
  uid := public.require_role('salesperson', 'director');
  if p_request_id is not null then select id into existing from payments where client_request_id = p_request_id; if existing is not null then return existing; end if; end if;
  if p_paid_by not in ('customer', 'bank') then raise exception 'Choose who paid'; end if;
  select * into b from bookings where id = p_booking;
  if b.id is null or b.status not in ('draft', 'confirmed') then raise exception 'Payments can only be recorded for a booking that is open (token) or confirmed'; end if;
  purp := case when b.status = 'draft' then 'token' else 'installment' end;
  if public.app_role() = 'salesperson' and b.salesperson_id is distinct from uid then raise exception 'This booking is not assigned to you' using errcode = '42501'; end if;
  insert into payments(booking_id, customer_id, amount_paise, received_on, method, reference, entered_by, notes, client_request_id, purpose, paid_by)
    values (p_booking, b.customer_id, p_amount_paise, p_received_on, p_method, p_reference, uid, p_notes, p_request_id, purp, p_paid_by) returning id into new_id;
  perform public.emit_event('payment_reported:' || new_id, 'payment_reported', p_booking, jsonb_build_object('payment_id', new_id, 'amount_paise', p_amount_paise, 'purpose', purp));
  return new_id;
end $$;

-- a booking being created reserves the villa
create function public.trg_booking_reserves_villa() returns trigger language plpgsql security definer set search_path = public as $$
begin update villas set status = 'reserved' where id = new.villa_id and status = 'available'; return new; end $$;
create trigger booking_reserves_villa after insert on bookings for each row execute function public.trg_booking_reserves_villa();

revoke execute on function public.apply_credit(uuid), public.gate_open(uuid), public.construction_gates(), public.release_construction(uuid, boolean), public.suggest_demand(uuid),
  public.demand_opportunities(), public.raise_demand(uuid, bigint, text, int, uuid, text, bigint, text),
  public.report_payment(uuid, bigint, text, text, date, text, text, text), public.trg_booking_reserves_villa() from public, anon;
grant execute on function public.construction_gates(), public.release_construction(uuid, boolean), public.suggest_demand(uuid), public.demand_opportunities(),
  public.raise_demand(uuid, bigint, text, int, uuid, text, bigint, text), public.report_payment(uuid, bigint, text, text, date, text, text, text) to authenticated;
