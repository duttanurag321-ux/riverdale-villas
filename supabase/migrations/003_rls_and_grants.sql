-- Riverdale Villas — Phase 1 / 003: Row Level Security and privileges.
-- Default stance: the browser can READ what its role needs and WRITE only Director-managed master data.
-- Everything money-, approval- or status-related changes only through the functions in 002.

alter table profiles enable row level security;
alter table projects enable row level security;
alter table construction_stages enable row level security;
alter table villas enable row level security;
alter table villa_pricing enable row level security;
alter table customers enable row level security;
alter table customer_sensitive enable row level security;
alter table payment_plan_templates enable row level security;
alter table payment_plan_template_milestones enable row level security;
alter table bookings enable row level security;
alter table booking_payment_milestones enable row level security;
alter table construction_updates enable row level security;
alter table construction_update_photos enable row level security;
alter table payments enable row level security;
alter table payment_allocations enable row level security;
alter table follow_up_tasks enable row level security;
alter table domain_events enable row level security;
alter table audit_logs enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
-- Director-managed master data (RLS below restricts these writes to Directors):
grant insert, update on profiles to authenticated;
grant insert, update, delete on projects, construction_stages, villas, villa_pricing, customers, customer_sensitive,
  payment_plan_templates, payment_plan_template_milestones to authenticated;
grant insert, update on bookings to authenticated;   -- guard trigger forces draft / blocks status edits
grant insert on construction_update_photos to authenticated;

-- Functions the app may call
grant execute on function public.app_role(), public.is_director(), public.is_api_caller() to authenticated, anon, service_role;
grant execute on function public.create_booking_schedule(uuid, uuid), public.confirm_booking(uuid), public.cancel_booking(uuid, text),
  public.submit_construction_update(uuid, uuid, update_status, text, boolean, text),
  public.approve_construction_update(uuid, boolean, text),
  public.report_payment(uuid, bigint, text, text, date, text, text),
  public.verify_payment(uuid, jsonb), public.reject_payment(uuid, text), public.reverse_payment(uuid, text)
  to authenticated;
-- NOT granted: activate_milestone, emit_event, write_audit, bootstrap_first_director, next_receipt_number.

-- helpers inside policies
create function public.my_booking_ids() returns setof uuid language sql stable security definer set search_path = public
as $$ select id from bookings where salesperson_id = auth.uid() $$;
create function public.my_villa_ids() returns setof uuid language sql stable security definer set search_path = public
as $$ select id from villas where site_manager_id = auth.uid() or salesperson_id = auth.uid() $$;
grant execute on function public.my_booking_ids(), public.my_villa_ids() to authenticated;

-- profiles: own row, Directors see and manage all. Nobody can edit their own role (only Directors write).
create policy profiles_read on profiles for select to authenticated using (id = auth.uid() or public.is_director());
create policy profiles_dir_ins on profiles for insert to authenticated with check (public.is_director());
create policy profiles_dir_upd on profiles for update to authenticated using (public.is_director()) with check (public.is_director());

-- reference data: any active employee reads, Director writes
create policy projects_read on projects for select to authenticated using (public.app_role() is not null);
create policy projects_dir on projects for all to authenticated using (public.is_director()) with check (public.is_director());
create policy stages_read on construction_stages for select to authenticated using (public.app_role() is not null);
create policy stages_dir on construction_stages for all to authenticated using (public.is_director()) with check (public.is_director());

-- villas: Director all; Site Manager / Salesperson only their assigned villas
create policy villas_read on villas for select to authenticated using (public.is_director() or id in (select public.my_villa_ids()));
create policy villas_dir on villas for all to authenticated using (public.is_director()) with check (public.is_director());
create policy pricing_read on villa_pricing for select to authenticated
  using (public.is_director() or (public.app_role() = 'salesperson' and villa_id in (select public.my_villa_ids())));
create policy pricing_dir on villa_pricing for all to authenticated using (public.is_director()) with check (public.is_director());

-- customers: Director all; Salesperson only own. Site Manager: none.
create policy customers_read on customers for select to authenticated
  using (public.is_director() or (public.app_role() = 'salesperson' and salesperson_id = auth.uid()));
create policy customers_dir on customers for all to authenticated using (public.is_director()) with check (public.is_director());
create policy sensitive_dir on customer_sensitive for all to authenticated using (public.is_director()) with check (public.is_director());

-- plans: Director only
create policy plans_dir on payment_plan_templates for all to authenticated using (public.is_director()) with check (public.is_director());
create policy plan_ms_dir on payment_plan_template_milestones for all to authenticated using (public.is_director()) with check (public.is_director());

-- bookings & money: Director all; Salesperson only own bookings; Site Manager none
create policy bookings_read on bookings for select to authenticated
  using (public.is_director() or (public.app_role() = 'salesperson' and salesperson_id = auth.uid()));
create policy bookings_dir_ins on bookings for insert to authenticated with check (public.is_director());
create policy bookings_dir_upd on bookings for update to authenticated using (public.is_director()) with check (public.is_director());
create policy milestones_read on booking_payment_milestones for select to authenticated
  using (public.is_director() or (public.app_role() = 'salesperson' and booking_id in (select public.my_booking_ids())));
create policy payments_read on payments for select to authenticated
  using (public.is_director() or (public.app_role() = 'salesperson' and booking_id in (select public.my_booking_ids())));
create policy alloc_read on payment_allocations for select to authenticated
  using (public.is_director() or (public.app_role() = 'salesperson' and payment_id in (select id from payments where booking_id in (select public.my_booking_ids()))));
create policy tasks_read on follow_up_tasks for select to authenticated using (public.is_director() or assigned_to = auth.uid());

-- construction: Director all; Site Manager / Salesperson for their villas. Writes via functions only.
create policy cu_read on construction_updates for select to authenticated using (public.is_director() or villa_id in (select public.my_villa_ids()));
create policy cup_read on construction_update_photos for select to authenticated
  using (public.is_director() or update_id in (select id from construction_updates where villa_id in (select public.my_villa_ids())));
create policy cup_ins on construction_update_photos for insert to authenticated
  with check (update_id in (select id from construction_updates where submitted_by = auth.uid()));

create policy events_dir on domain_events for select to authenticated using (public.is_director());
create policy audit_dir on audit_logs for select to authenticated using (public.is_director());
