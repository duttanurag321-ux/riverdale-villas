-- Riverdale Villas — Phase 1 / 002: business logic, guards, balance views.
-- All state-changing business operations are SECURITY DEFINER functions that check the caller's
-- role from the profiles table (never from anything the browser sends).

create function public.is_api_caller() returns boolean language sql stable
as $$ select current_user in ('anon','authenticated','service_role') $$;

create function public.app_role() returns user_role language sql stable security definer set search_path = public
as $$ select role from profiles where id = auth.uid() and is_active $$;

create function public.is_director() returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.app_role() = 'director', false) $$;

create function public.require_role(variadic allowed user_role[]) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare r user_role := public.app_role();
begin
  if r is null or not (r = any(allowed)) then
    raise exception 'Not authorized for this action' using errcode = '42501';
  end if;
  return auth.uid();
end $$;

create function public.write_audit(p_action text, p_entity text, p_entity_id text, p_details jsonb default '{}')
returns void language sql security definer set search_path = public
as $$ insert into audit_logs(actor, action, entity, entity_id, details) values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_details,'{}')) $$;

create function public.emit_event(p_key text, p_type text, p_booking uuid, p_payload jsonb default '{}')
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into domain_events(event_key, event_type, booking_id, payload) values (p_key, p_type, p_booking, coalesce(p_payload,'{}'))
  on conflict (event_key) do nothing;
  get diagnostics n = row_count;
  return n = 1;
end $$;

create function public.next_receipt_number() returns text language plpgsql security definer set search_path = public as $$
declare ist timestamp := now() at time zone 'Asia/Kolkata'; fy int;
begin
  fy := case when extract(month from ist) >= 4 then extract(year from ist) else extract(year from ist) - 1 end;
  return 'RV/' || fy || '-' || right((fy + 1)::text, 2) || '/' || lpad(nextval('receipt_number_seq')::text, 6, '0');
end $$;

-- ---------- guards (these protect against direct table access via the API) ----------

create function public.trg_bookings_guard() returns trigger language plpgsql as $$
begin
  if public.is_api_caller() then
    if tg_op = 'INSERT' then
      new.status := 'draft'; new.confirmed_at := null; new.confirmed_by := null;
      new.cancelled_at := null; new.cancel_reason := null; new.created_by := auth.uid();
    else
      if new.status is distinct from old.status or new.confirmed_at is distinct from old.confirmed_at
         or new.cancelled_at is distinct from old.cancelled_at then
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
create trigger bookings_guard before insert or update on bookings for each row execute function public.trg_bookings_guard();

create function public.trg_milestones_freeze() returns trigger language plpgsql as $$
declare st booking_status;
begin
  if public.is_api_caller() then raise exception 'Payment milestones can only change through server functions'; end if;
  select status into st from bookings where id = coalesce(new.booking_id, old.booking_id);
  if st <> 'draft' then
    if tg_op = 'DELETE' then raise exception 'Confirmed schedule is frozen'; end if;
    if tg_op = 'INSERT' then raise exception 'Confirmed schedule is frozen'; end if;
    if (new.seq, new.name, new.trigger, new.stage_id, new.amount_paise, new.due_days, new.grace_days, new.booking_id)
       is distinct from (old.seq, old.name, old.trigger, old.stage_id, old.amount_paise, old.due_days, old.grace_days, old.booking_id) then
      raise exception 'Confirmed schedule is frozen; use a payment-plan amendment';
    end if;
  end if;
  return coalesce(new, old);
end $$;
create trigger milestones_freeze before insert or update or delete on booking_payment_milestones for each row execute function public.trg_milestones_freeze();

create function public.trg_ledger_immutable() returns trigger language plpgsql as $$
begin
  raise exception '% is append-only: rows cannot be deleted or edited', tg_table_name;
end $$;
create trigger audit_immutable before update or delete on audit_logs for each row execute function public.trg_ledger_immutable();
create trigger alloc_immutable before update or delete on payment_allocations for each row execute function public.trg_ledger_immutable();

create function public.trg_payments_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'payments is append-only: rows cannot be deleted'; end if;
  if (new.amount_paise, new.booking_id, new.customer_id, new.kind, new.entered_by, new.received_on, new.method, new.reverses_payment_id)
     is distinct from (old.amount_paise, old.booking_id, old.customer_id, old.kind, old.entered_by, old.received_on, old.method, old.reverses_payment_id) then
    raise exception 'Payment facts cannot be edited; record a reversal instead';
  end if;
  if old.verification = 'pending' and new.verification in ('verified','rejected') then
    return new;
  end if;
  if old.verification = 'verified' and new.verification = 'verified' and old.receipt_document_path is null
     and new.receipt_document_path is not null and new.receipt_number = old.receipt_number and new.verified_by = old.verified_by then
    return new;
  end if;
  raise exception 'Illegal change to a payment record';
end $$;
create trigger payments_guard before update or delete on payments for each row execute function public.trg_payments_guard();

-- Allocation rules: only verified payments, same booking, activated milestone, never over-allocate.
create function public.trg_allocation_check() returns trigger language plpgsql as $$
declare pay payments; m booking_payment_milestones; pay_total bigint; m_total bigint;
begin
  select * into pay from payments where id = new.payment_id;
  if pay.verification <> 'verified' then raise exception 'Only verified payments can be allocated'; end if;
  select * into m from booking_payment_milestones where id = new.milestone_id for update;
  if m.booking_id <> pay.booking_id then raise exception 'Allocation must target the same booking as the payment'; end if;
  if m.activated_at is null then raise exception 'Cannot allocate to a milestone that is not activated'; end if;
  select coalesce(sum(amount_paise),0) into pay_total from payment_allocations where payment_id = new.payment_id;
  if pay.kind = 'receipt' then
    if new.amount_paise <= 0 or pay_total + new.amount_paise > pay.amount_paise then
      raise exception 'Allocations exceed the payment amount'; end if;
  else
    if new.amount_paise >= 0 or pay_total + new.amount_paise < -pay.amount_paise then
      raise exception 'Reversal allocations exceed the reversed amount'; end if;
  end if;
  select coalesce(sum(amount_paise),0) into m_total from payment_allocations where milestone_id = new.milestone_id;
  if m_total + new.amount_paise > m.amount_paise then raise exception 'Allocation exceeds the milestone amount'; end if;
  if m_total + new.amount_paise < 0 then raise exception 'Milestone allocation cannot go negative'; end if;
  return new;
end $$;
create trigger allocation_check before insert on payment_allocations for each row execute function public.trg_allocation_check();

-- Profile safety: audit role changes; never remove the last active Director.
create function public.trg_profiles_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.role is distinct from old.role or new.is_active is distinct from old.is_active) then
    if old.role = 'director' and old.is_active and (new.role <> 'director' or not new.is_active)
       and not exists (select 1 from profiles where role = 'director' and is_active and id <> old.id) then
      raise exception 'Cannot remove or deactivate the last active Director';
    end if;
    perform public.write_audit('profile_role_or_status_changed', 'profiles', old.id::text,
      jsonb_build_object('old_role', old.role, 'new_role', new.role, 'old_active', old.is_active, 'new_active', new.is_active));
  end if;
  return new;
end $$;
create trigger profiles_guard before update on profiles for each row execute function public.trg_profiles_guard();

-- Customer changes are audited by column NAME only (never values; PAN stays out of logs).
create function public.trg_audit_changes() returns trigger language plpgsql security definer set search_path = public as $$
declare cols text[]; pk text;
begin
  pk := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'customer_id');
  if tg_op = 'UPDATE' then
    select array_agg(n.key) into cols from jsonb_each(to_jsonb(new)) n join jsonb_each(to_jsonb(old)) o using (key) where n.value is distinct from o.value;
  end if;
  perform public.write_audit(lower(tg_op) || '_' || tg_table_name, tg_table_name, pk, jsonb_build_object('changed_columns', cols));
  return new;
end $$;
create trigger audit_customers after insert or update on customers for each row execute function public.trg_audit_changes();
create trigger audit_customer_sensitive after insert or update on customer_sensitive for each row execute function public.trg_audit_changes();

-- ---------- bootstrap (run from the Supabase SQL Editor only; not callable from the API) ----------
create function public.bootstrap_first_director(p_user_id uuid, p_full_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from profiles where role = 'director') then raise exception 'A Director already exists'; end if;
  insert into profiles(id, full_name, role) values (p_user_id, p_full_name, 'director');
  insert into audit_logs(actor, action, entity, entity_id) values (p_user_id, 'bootstrap_first_director', 'profiles', p_user_id::text);
end $$;

-- ---------- payment plan -> contract schedule ----------
create function public.check_template(p_template uuid) returns void language plpgsql stable security definer set search_path = public as $$
declare pct int; fx int; total_bp int;
begin
  select count(*) filter (where kind='percent'), count(*) filter (where kind='fixed'), coalesce(sum(percent_bp),0)
    into pct, fx, total_bp from payment_plan_template_milestones where template_id = p_template;
  if pct + fx = 0 then raise exception 'Template has no milestones'; end if;
  if pct > 0 and fx > 0 then raise exception 'A template must be all percentage-based or all fixed-amount'; end if;
  if pct > 0 and total_bp <> 10000 then
    raise exception 'Percentages total % %%, must be exactly 100', total_bp / 100.0; end if;
end $$;

-- Rounding rule: each percentage milestone = floor(contract_value * bp / 10000); any leftover paise
-- go to the LAST milestone so the schedule always totals the contract value exactly.
create function public.create_booking_schedule(p_booking uuid, p_template uuid) returns void
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
      due_days, grace_days, notify_customer, is_mandatory)
    values (p_booking, t.seq, t.name, t.trigger, t.stage_id, amt, t.percent_bp, t.due_days, t.grace_days, t.notify_customer, t.is_mandatory);
  end loop;
  perform public.write_audit('booking_schedule_created', 'bookings', p_booking::text, jsonb_build_object('template_id', p_template));
end $$;

-- Internal. Idempotent: a milestone activates once; retries are no-ops.
create function public.activate_milestone(p_milestone uuid) returns boolean
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
  perform public.emit_event('milestone_activated:' || m.id, 'payment_milestone_activated', b.id,
    jsonb_build_object('milestone_id', m.id, 'milestone_name', m.name, 'amount_paise', m.amount_paise,
                       'due_date', current_date + m.due_days, 'notify_customer', m.notify_customer));
  return true;
end $$;

create function public.confirm_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b bookings; total bigint; m record;
begin
  perform public.require_role('director');
  select * into b from bookings where id = p_booking for update;
  if b.status <> 'draft' then raise exception 'Only a draft booking can be confirmed'; end if;
  select coalesce(sum(amount_paise),0) into total from booking_payment_milestones where booking_id = p_booking;
  if total <> b.contract_value_paise then
    raise exception 'Payment schedule (% paise) does not equal contract value (% paise)', total, b.contract_value_paise; end if;
  update bookings set status = 'confirmed', confirmed_at = now(), confirmed_by = auth.uid() where id = p_booking;
  update villas set status = 'booked' where id = b.villa_id;
  for m in select id from booking_payment_milestones where booking_id = p_booking and trigger = 'booking_confirmed' order by seq loop
    perform public.activate_milestone(m.id);
  end loop;
  perform public.emit_event('booking_confirmed:' || p_booking, 'booking_confirmed', p_booking, '{}');
  perform public.write_audit('booking_confirmed', 'bookings', p_booking::text);
end $$;

create function public.cancel_booking(p_booking uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare b bookings;
begin
  perform public.require_role('director');
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A cancellation reason is required'; end if;
  select * into b from bookings where id = p_booking for update;
  if b.status in ('cancelled','completed') then raise exception 'Booking cannot be cancelled in status %', b.status; end if;
  update bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = p_reason where id = p_booking;
  update follow_up_tasks set status = 'cancelled' where booking_id = p_booking and status = 'open';
  update villas set status = 'available' where id = b.villa_id;
  perform public.emit_event('booking_cancelled:' || p_booking, 'booking_cancelled', p_booking, '{}');
  perform public.write_audit('booking_cancelled', 'bookings', p_booking::text, jsonb_build_object('reason', p_reason));
end $$;

-- ---------- construction ----------
create function public.submit_construction_update(p_villa uuid, p_stage uuid, p_new_status update_status,
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

create function public.approve_construction_update(p_update uuid, p_approve boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid; u construction_updates;
begin
  uid := public.require_role('director');
  select * into u from construction_updates where id = p_update for update;
  if u.id is null then raise exception 'Update not found'; end if;
  if (p_approve and u.approval = 'approved') or (not p_approve and u.approval = 'rejected') then return; end if; -- idempotent
  if u.approval <> 'pending' then raise exception 'Update is not awaiting a decision'; end if;
  if not p_approve and (p_reason is null or length(trim(p_reason)) = 0) then raise exception 'A rejection reason is required'; end if;
  if p_approve then
    update construction_updates set approval = 'approved', approved_by = uid, approved_at = now() where id = p_update;
    update villas set current_stage_id = u.stage_id where id = u.villa_id;
    perform public.activate_milestone(m.id) from booking_payment_milestones m
      where m.booking_id = u.booking_id and m.stage_id = u.stage_id and m.trigger = 'stage_approved';
    perform public.emit_event('construction_update_approved:' || p_update, 'construction_update_approved', u.booking_id,
      jsonb_build_object('update_id', p_update, 'villa_id', u.villa_id, 'stage_id', u.stage_id));
  else
    update construction_updates set approval = 'rejected', approved_by = uid, approved_at = now(), rejection_reason = p_reason where id = p_update;
    perform public.emit_event('construction_update_rejected:' || p_update, 'construction_update_rejected', u.booking_id,
      jsonb_build_object('update_id', p_update, 'villa_id', u.villa_id));
  end if;
  perform public.write_audit(case when p_approve then 'construction_approved' else 'construction_rejected' end,
    'construction_updates', p_update::text, jsonb_build_object('reason', p_reason));
end $$;

-- ---------- payments ----------
create function public.report_payment(p_booking uuid, p_amount_paise bigint, p_method text, p_reference text,
  p_received_on date, p_notes text default null, p_request_id text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid; b bookings; existing uuid; new_id uuid;
begin
  uid := public.require_role('salesperson','director');
  if p_request_id is not null then
    select id into existing from payments where client_request_id = p_request_id;
    if existing is not null then return existing; end if;
  end if;
  select * into b from bookings where id = p_booking;
  if b.id is null or b.status <> 'confirmed' then raise exception 'Payments can only be reported for a confirmed booking'; end if;
  if public.app_role() = 'salesperson' and b.salesperson_id is distinct from uid then
    raise exception 'This booking is not assigned to you' using errcode = '42501'; end if;
  insert into payments(booking_id, customer_id, amount_paise, received_on, method, reference, entered_by, notes, client_request_id)
  values (p_booking, b.customer_id, p_amount_paise, p_received_on, p_method, p_reference, uid, p_notes, p_request_id) returning id into new_id;
  perform public.emit_event('payment_reported:' || new_id, 'payment_reported', p_booking,
    jsonb_build_object('payment_id', new_id, 'amount_paise', p_amount_paise));
  return new_id;
end $$;

-- p_allocations: optional [{"milestone_id": "...", "amount_paise": 123}]. If omitted, the payment is
-- applied to activated milestones, earliest due date first; any remainder stays unallocated (customer credit).
create function public.verify_payment(p_payment uuid, p_allocations jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; p payments; rcpt text; remaining bigint; m record; take bigint; a jsonb;
begin
  uid := public.require_role('director');
  select * into p from payments where id = p_payment for update;
  if p.id is null or p.kind <> 'receipt' then raise exception 'Payment not found'; end if;
  if p.verification <> 'pending' then raise exception 'Payment is already %', p.verification; end if;
  rcpt := public.next_receipt_number();
  update payments set verification = 'verified', verified_by = uid, verified_at = now(), receipt_number = rcpt where id = p_payment;
  remaining := p.amount_paise;
  if p_allocations is not null then
    for a in select * from jsonb_array_elements(p_allocations) loop
      insert into payment_allocations(payment_id, milestone_id, amount_paise)
        values (p_payment, (a->>'milestone_id')::uuid, (a->>'amount_paise')::bigint);
      remaining := remaining - (a->>'amount_paise')::bigint;
    end loop;
  else
    for m in select bm.id, bm.amount_paise - coalesce((select sum(amount_paise) from payment_allocations where milestone_id = bm.id),0) as outstanding
             from booking_payment_milestones bm
             where bm.booking_id = p.booking_id and bm.activated_at is not null and not bm.cancelled and not bm.on_hold
             order by bm.due_date, bm.seq for update of bm loop
      exit when remaining <= 0;
      continue when m.outstanding <= 0;
      take := least(remaining, m.outstanding);
      insert into payment_allocations(payment_id, milestone_id, amount_paise) values (p_payment, m.id, take);
      remaining := remaining - take;
    end loop;
  end if;
  update follow_up_tasks t set status = 'done' where t.status = 'open' and t.kind = 'payment_due' and t.booking_id = p.booking_id
    and (select coalesce(sum(amount_paise),0) from payment_allocations where milestone_id = t.milestone_id)
        >= (select amount_paise from booking_payment_milestones where id = t.milestone_id);
  perform public.emit_event('payment_verified:' || p_payment, 'payment_verified', p.booking_id,
    jsonb_build_object('payment_id', p_payment, 'receipt_number', rcpt, 'amount_paise', p.amount_paise));
  perform public.write_audit('payment_verified', 'payments', p_payment::text, jsonb_build_object('receipt_number', rcpt));
  return jsonb_build_object('receipt_number', rcpt, 'unallocated_paise', remaining);
end $$;

create function public.reject_payment(p_payment uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid; p payments;
begin
  uid := public.require_role('director');
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;
  select * into p from payments where id = p_payment for update;
  if p.id is null or p.verification <> 'pending' then raise exception 'Only a pending payment can be rejected'; end if;
  update payments set verification = 'rejected', verified_by = uid, verified_at = now(), notes = coalesce(notes || ' | ', '') || 'Rejected: ' || p_reason where id = p_payment;
  perform public.write_audit('payment_rejected', 'payments', p_payment::text, jsonb_build_object('reason', p_reason));
end $$;

-- Full reversal only in Phase 1 (partial refunds arrive with Phase 4). Original row is untouched.
create function public.reverse_payment(p_payment uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid; p payments; new_id uuid; al record;
begin
  uid := public.require_role('director');
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;
  select * into p from payments where id = p_payment for update;
  if p.id is null or p.kind <> 'receipt' or p.verification <> 'verified' then raise exception 'Only a verified receipt can be reversed'; end if;
  if exists (select 1 from payments where reverses_payment_id = p_payment) then raise exception 'Payment is already reversed'; end if;
  insert into payments(booking_id, customer_id, kind, amount_paise, received_on, method, entered_by, verification, verified_by, verified_at, reverses_payment_id, notes)
  values (p.booking_id, p.customer_id, 'reversal', p.amount_paise, current_date, p.method, uid, 'verified', uid, now(), p_payment, p_reason)
  returning id into new_id;
  for al in select milestone_id, amount_paise from payment_allocations where payment_id = p_payment loop
    insert into payment_allocations(payment_id, milestone_id, amount_paise) values (new_id, al.milestone_id, -al.amount_paise);
  end loop;
  perform public.emit_event('payment_reversed:' || p_payment, 'payment_reversed', p.booking_id, jsonb_build_object('payment_id', p_payment, 'reversal_id', new_id));
  perform public.write_audit('payment_reversed', 'payments', p_payment::text, jsonb_build_object('reason', p_reason, 'reversal_id', new_id));
  return new_id;
end $$;

-- ---------- derived balances (nobody edits these) ----------
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
  coalesce(ms.overdue, 0)::bigint as overdue_paise
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
