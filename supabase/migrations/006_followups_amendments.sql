-- Riverdale Villas — Phase 4 / 006: follow-up outcomes, schedule amendments, faster dashboard view.
-- Run once in the Supabase SQL Editor AFTER 001-005.

alter table follow_up_tasks add column promised_date date;

create table follow_up_activity_logs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references follow_up_tasks(id),
  booking_id uuid not null references bookings(id),
  actor uuid references profiles(id),
  outcome text not null check (outcome in ('contacted_will_pay','contacted_more_time','contacted_already_paid','no_answer','wrong_number','dispute','needs_director','other','completed')),
  note text,
  promised_date date,
  created_at timestamptz not null default now()
);
create index on follow_up_activity_logs(task_id, created_at desc);
create trigger followup_log_immutable before update or delete on follow_up_activity_logs for each row execute function public.trg_ledger_immutable();
alter table follow_up_activity_logs enable row level security;
revoke all on follow_up_activity_logs from anon, authenticated;
grant select on follow_up_activity_logs to authenticated;
create policy followup_logs_read on follow_up_activity_logs for select to authenticated
  using (public.is_director() or task_id in (select id from follow_up_tasks where assigned_to = auth.uid()));

-- Old schedules are kept forever: every amendment stores the previous schedule first.
create table booking_schedule_versions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  version int not null,
  snapshot jsonb not null,
  reason text not null check (length(trim(reason)) > 0),
  changed_by uuid references profiles(id),
  changed_at timestamptz not null default now(),
  unique (booking_id, version)
);
create trigger schedule_versions_immutable before update or delete on booking_schedule_versions for each row execute function public.trg_ledger_immutable();
alter table booking_schedule_versions enable row level security;
revoke all on booking_schedule_versions from anon, authenticated;
grant select on booking_schedule_versions to authenticated;
create policy schedule_versions_dir on booking_schedule_versions for select to authenticated using (public.is_director());

-- Let the amendment function (and only it) change a frozen schedule.
create or replace function public.trg_milestones_freeze() returns trigger language plpgsql as $$
declare st booking_status;
begin
  if public.is_api_caller() then raise exception 'Payment milestones can only change through server functions'; end if;
  if current_setting('app.amending', true) = 'on' then return coalesce(new, old); end if;
  select status into st from bookings where id = coalesce(new.booking_id, old.booking_id);
  if st <> 'draft' then
    if tg_op in ('DELETE','INSERT') then raise exception 'Confirmed schedule is frozen'; end if;
    if (new.seq, new.name, new.trigger, new.stage_id, new.amount_paise, new.due_days, new.grace_days, new.booking_id)
       is distinct from (old.seq, old.name, old.trigger, old.stage_id, old.amount_paise, old.due_days, old.grace_days, old.booking_id) then
      raise exception 'Confirmed schedule is frozen; use a payment-plan amendment';
    end if;
  end if;
  return coalesce(new, old);
end $$;

-- Amend only FUTURE (not yet activated) milestones; the schedule must still total the contract value.
-- p_changes: [{"milestone_id":"...","amount_paise":123,"due_days":7,"grace_days":3}] (due_days / grace_days optional)
create function public.amend_booking_schedule(p_booking uuid, p_changes jsonb, p_reason text) returns int
language plpgsql security definer set search_path = public as $$
declare b bookings; c jsonb; m booking_payment_milestones; v int; total bigint;
begin
  perform public.require_role('director');
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;
  select * into b from bookings where id = p_booking for update;
  if b.status <> 'confirmed' then raise exception 'Only a confirmed booking can be amended'; end if;
  if jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then raise exception 'No changes supplied'; end if;
  select coalesce(max(version), 0) + 1 into v from booking_schedule_versions where booking_id = p_booking;
  insert into booking_schedule_versions(booking_id, version, snapshot, reason, changed_by)
    select p_booking, v, jsonb_agg(to_jsonb(x) order by x.seq), p_reason, auth.uid() from booking_payment_milestones x where x.booking_id = p_booking;
  perform set_config('app.amending', 'on', true);
  for c in select * from jsonb_array_elements(p_changes) loop
    select * into m from booking_payment_milestones where id = (c->>'milestone_id')::uuid and booking_id = p_booking for update;
    if m.id is null then raise exception 'Milestone does not belong to this booking'; end if;
    if m.activated_at is not null then raise exception 'Milestone "%" is already active and cannot be changed', m.name; end if;
    if (c->>'amount_paise')::bigint <= 0 then raise exception 'Amounts must be positive'; end if;
    update booking_payment_milestones set amount_paise = (c->>'amount_paise')::bigint,
      due_days = coalesce((c->>'due_days')::int, due_days), grace_days = coalesce((c->>'grace_days')::int, grace_days), source_percent_bp = null
      where id = m.id;
  end loop;
  perform set_config('app.amending', 'off', true);
  select sum(amount_paise) into total from booking_payment_milestones where booking_id = p_booking;
  if total <> b.contract_value_paise then
    raise exception 'Amended schedule totals % paise but the contract value is % paise', total, b.contract_value_paise; end if;
  perform public.emit_event('payment_plan_amended:' || p_booking || ':' || v, 'payment_plan_amended', p_booking, jsonb_build_object('version', v));
  perform public.write_audit('payment_plan_amended', 'bookings', p_booking::text, jsonb_build_object('version', v, 'reason', p_reason));
  return v;
end $$;

-- Follow-up outcomes. Promised dates reschedule the SAME task (never a duplicate); unanswered calls retry tomorrow.
create function public.record_follow_up_outcome(p_task uuid, p_outcome text, p_note text default null, p_promised date default null) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid; t follow_up_tasks; log_id uuid := gen_random_uuid();
begin
  uid := public.require_role('salesperson','director');
  select * into t from follow_up_tasks where id = p_task for update;
  if t.id is null or t.status <> 'open' then raise exception 'This follow-up is not open'; end if;
  if public.app_role() = 'salesperson' and t.assigned_to is distinct from uid then
    raise exception 'This follow-up is not assigned to you' using errcode = '42501'; end if;
  if p_outcome not in ('contacted_will_pay','contacted_more_time','contacted_already_paid','no_answer','wrong_number','dispute','needs_director','other') then
    raise exception 'Unknown outcome'; end if;
  if p_outcome in ('other','dispute','needs_director') and (p_note is null or length(trim(p_note)) = 0) then
    raise exception 'A note is required for this outcome'; end if;
  if p_outcome = 'contacted_will_pay' and p_promised is null then raise exception 'Enter the date the customer promised to pay'; end if;
  if p_promised is not null and (p_promised < current_date or p_promised > current_date + 365) then raise exception 'Promised date must be within the next year'; end if;

  insert into follow_up_activity_logs(id, task_id, booking_id, actor, outcome, note, promised_date) values (log_id, t.id, t.booking_id, uid, p_outcome, p_note, p_promised);
  if p_outcome in ('contacted_will_pay','contacted_more_time') and p_promised is not null then
    update follow_up_tasks set due_date = p_promised, promised_date = p_promised where id = t.id;
    perform public.emit_event('follow_up_rescheduled:' || log_id, 'follow_up_rescheduled', t.booking_id, jsonb_build_object('task_id', t.id, 'promised_date', p_promised));
  elsif p_outcome = 'no_answer' then
    update follow_up_tasks set due_date = greatest(due_date, current_date + 1) where id = t.id;
  elsif p_outcome in ('dispute','needs_director') then
    update follow_up_tasks set priority = 'high' where id = t.id;
    perform public.emit_event('follow_up_escalated:' || log_id, 'follow_up_escalated', t.booking_id, jsonb_build_object('task_id', t.id, 'outcome', p_outcome));
  end if;
end $$;

create function public.complete_follow_up(p_task uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid; t follow_up_tasks;
begin
  uid := public.require_role('salesperson','director');
  select * into t from follow_up_tasks where id = p_task for update;
  if t.id is null or t.status <> 'open' then raise exception 'This follow-up is not open'; end if;
  if public.app_role() = 'salesperson' and t.assigned_to is distinct from uid then
    raise exception 'This follow-up is not assigned to you' using errcode = '42501'; end if;
  update follow_up_tasks set status = 'done' where id = t.id;
  insert into follow_up_activity_logs(task_id, booking_id, actor, outcome, note) values (t.id, t.booking_id, uid, 'completed', p_note);
end $$;

revoke execute on function public.amend_booking_schedule(uuid, jsonb, text), public.record_follow_up_outcome(uuid, text, text, date), public.complete_follow_up(uuid, text) from public, anon;
grant execute on function public.amend_booking_schedule(uuid, jsonb, text), public.record_follow_up_outcome(uuid, text, text, date), public.complete_follow_up(uuid, text) to authenticated;

-- Dashboard speed: expose booking status on the balance view so one query is enough.
create or replace view public.v_booking_balances with (security_invoker = true) as
select b.id as booking_id, b.contract_value_paise,
  coalesce(p.net, 0)::bigint as net_receipts_paise,
  (b.contract_value_paise - coalesce(p.net, 0))::bigint as outstanding_paise,
  coalesce(p.pending, 0)::bigint as pending_verification_paise,
  coalesce(ms.activated, 0)::bigint as activated_obligation_paise,
  coalesce(ms.act_out, 0)::bigint as activated_outstanding_paise,
  coalesce(ms.overdue, 0)::bigint as overdue_paise,
  b.status as booking_status
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
  from v_milestone_balances where booking_id = b.id) ms on true;

-- Speed: indexes for the lists the app opens most.
create index if not exists idx_followups_open on follow_up_tasks(assigned_to, due_date) where status = 'open';
create index if not exists idx_payments_pending on payments(created_at) where verification = 'pending';
create index if not exists idx_cu_pending on construction_updates(submitted_at) where approval = 'pending';
create index if not exists idx_villas_sm on villas(site_manager_id);
create index if not exists idx_villas_sp on villas(salesperson_id);
create index if not exists idx_customers_sp on customers(salesperson_id);

-- Director can pause a milestone (e.g. an agreed dispute). Held milestones are skipped by auto-allocation and show as "On hold".
create function public.set_milestone_hold(p_milestone uuid, p_hold boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role('director');
  if p_hold and coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required to put a milestone on hold'; end if;
  update booking_payment_milestones set on_hold = p_hold, on_hold_reason = case when p_hold then p_reason else null end where id = p_milestone;
  if not found then raise exception 'Milestone not found'; end if;
  perform public.write_audit(case when p_hold then 'milestone_hold_on' else 'milestone_hold_off' end, 'booking_payment_milestones', p_milestone::text, jsonb_build_object('reason', p_reason));
end $$;
revoke execute on function public.set_milestone_hold(uuid, boolean, text) from public, anon;
grant execute on function public.set_milestone_hold(uuid, boolean, text) to authenticated;
