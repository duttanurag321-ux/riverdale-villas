\set ON_ERROR_STOP on
\set dir  '''d0000000-0000-0000-0000-000000000001'''
\set sm   '''a0000000-0000-0000-0000-000000000002'''
\set sal  '''b0000000-0000-0000-0000-000000000003'''
\set sal2 '''b0000000-0000-0000-0000-000000000004'''

-- fictional users
insert into auth.users(id,email) values (:dir,'dir@example.test'),(:sm,'sm@example.test'),(:sal,'sal@example.test'),(:sal2,'sal2@example.test');
select public.bootstrap_first_director(:dir, 'Test Director');
select tests.expect_fail($$select public.bootstrap_first_director('a0000000-0000-0000-0000-000000000002','Evil')$$, 'second bootstrap refused');
insert into profiles(id,full_name,role) values (:sm,'Test Site Manager','site_manager'),(:sal,'Test Salesperson','salesperson'),(:sal2,'Other Salesperson','salesperson');

-- === Director sets up master data through the API role (RLS write path) ===
select tests.as_user(:dir);
insert into projects(id,name,city) values ('c0000000-0000-0000-0000-000000000001','Riverdale Villas (TEST)','Siliguri');
insert into villas(id,project_id,villa_number,configuration,land_area,site_manager_id,salesperson_id)
  values ('c0000000-0000-0000-0000-0000000000a1','c0000000-0000-0000-0000-000000000001','A1','2 BHK',3,:sm,:sal);
insert into villa_pricing values ('c0000000-0000-0000-0000-0000000000a1', 600000000);
insert into customers(id,full_name,phone,salesperson_id) values ('c0000000-0000-0000-0000-0000000000b1','Fictional Customer','+919000000001',:sal);
insert into customer_sensitive values ('c0000000-0000-0000-0000-0000000000b1','ABCDE1234F');
-- direct attempt to create an already-confirmed booking is forced back to draft
insert into bookings(id,villa_id,customer_id,salesperson_id,package_price_paise,status)
  values ('c0000000-0000-0000-0000-0000000000c1','c0000000-0000-0000-0000-0000000000a1','c0000000-0000-0000-0000-0000000000b1',:sal,600000000,'confirmed');
select tests.eq((select status::text from bookings where id='c0000000-0000-0000-0000-0000000000c1'), 'draft', 'API cannot create a confirmed booking directly');
select tests.expect_fail($$update bookings set status='confirmed' where id='c0000000-0000-0000-0000-0000000000c1'$$, 'API cannot flip booking status directly');
select tests.expect_fail($$insert into bookings(villa_id,customer_id,package_price_paise) values ('c0000000-0000-0000-0000-0000000000a1','c0000000-0000-0000-0000-0000000000b1',1)$$, 'second live booking on same villa rejected');

-- template (illustrative, from the brief): 10/10/10/15/10/10/15/20
insert into payment_plan_templates(id,name,villa_configuration) values ('c0000000-0000-0000-0000-0000000000d1','Illustrative 2BHK (TEST)','2 BHK');
insert into payment_plan_template_milestones(template_id,seq,name,kind,percent_bp,trigger,stage_id,due_days,grace_days)
select 'c0000000-0000-0000-0000-0000000000d1', v.seq, v.name, 'percent', v.bp, v.trg::milestone_trigger, s.id, 7, 3
from (values (1,'Booking',1000,'booking_confirmed','Booking confirmed'),(2,'Foundation completed',1000,'stage_approved','Foundation completed'),
 (3,'Plinth completed',1000,'stage_approved','Plinth completed'),(4,'First slab',1500,'stage_approved','First slab / ceiling completed'),
 (5,'Brickwork',1000,'stage_approved','Brickwork completed'),(6,'Plastering',1000,'stage_approved','Plastering completed'),
 (7,'Flooring and fittings',1500,'stage_approved','Flooring and fittings'),(8,'Handover',2000,'stage_approved','Handover completed')) v(seq,name,bp,trg,stg)
join construction_stages s on s.name = v.stg;

-- invalid plan (99%) must be refused
insert into payment_plan_templates(id,name) values ('c0000000-0000-0000-0000-0000000000d2','Bad plan 99%');
insert into payment_plan_template_milestones(template_id,seq,name,kind,percent_bp,trigger) values
 ('c0000000-0000-0000-0000-0000000000d2',1,'A','percent',9900,'manual');
select tests.expect_fail($$select public.create_booking_schedule('c0000000-0000-0000-0000-0000000000c1','c0000000-0000-0000-0000-0000000000d2')$$, 'percent plan not totalling 100% rejected');
select tests.expect_fail($$select public.confirm_booking('c0000000-0000-0000-0000-0000000000c1')$$, 'cannot confirm booking without a schedule');

select public.create_booking_schedule('c0000000-0000-0000-0000-0000000000c1','c0000000-0000-0000-0000-0000000000d1');
select tests.eq((select sum(amount_paise) from booking_payment_milestones where booking_id='c0000000-0000-0000-0000-0000000000c1')::bigint, 600000000::bigint, 'schedule totals exactly the contract value');
select public.confirm_booking('c0000000-0000-0000-0000-0000000000c1');
select tests.eq((select count(*) from booking_payment_milestones where booking_id='c0000000-0000-0000-0000-0000000000c1' and activated_at is not null)::int, 1, 'only the booking milestone is active after confirmation');
select tests.eq((select count(*) from follow_up_tasks)::int, 1, 'follow-up task created for booking milestone');

-- === Salesperson reports Rs 6,00,000 booking payment; cannot verify it; Director verifies ===
select tests.as_user(:sal);
select public.report_payment('c0000000-0000-0000-0000-0000000000c1', 60000000, 'upi', 'UTR-TEST-1', current_date, null, 'req-1') as pay1 \gset
select tests.eq(public.report_payment('c0000000-0000-0000-0000-0000000000c1', 60000000, 'upi', 'UTR-TEST-1', current_date, null, 'req-1'), :'pay1'::uuid, 'retrying report with same request id creates no duplicate');
select tests.eq((select verification::text from payments where id=:'pay1'), 'pending', 'reported payment is pending verification');
select tests.eq((select outstanding_paise from v_booking_balances where booking_id='c0000000-0000-0000-0000-0000000000c1'), 600000000::bigint, 'pending payment does not reduce confirmed balance');
select tests.expect_fail(format($$select public.verify_payment(%L)$$, :'pay1'), 'salesperson cannot verify payments');
select tests.expect_fail(format($$update payments set verification='verified' where id=%L$$, :'pay1'), 'salesperson cannot flip verification via table update');
select tests.as_user(:sal2);
select tests.expect_fail($$select public.report_payment('c0000000-0000-0000-0000-0000000000c1', 100, 'upi','x',current_date)$$, 'other salesperson cannot report on this booking');
select tests.as_user(:dir);
select public.verify_payment(:'pay1') as vres \gset
select tests.eq((select receipt_number is not null from payments where id=:'pay1'), true, 'receipt number exists only after verification');
select tests.expect_fail(format($$select public.verify_payment(%L)$$, :'pay1'), 'double verification refused');
select tests.eq((select outstanding_paise from v_booking_balances where booking_id='c0000000-0000-0000-0000-0000000000c1'), 540000000::bigint, 'overall outstanding after Rs 6,00,000');

-- === Construction: Site Manager submits foundation completion ===
select tests.as_user(:sm);
select tests.eq((select count(*) from customers)::int, 0, 'site manager sees no customers');
select tests.eq((select count(*) from payments)::int, 0, 'site manager sees no payments');
select tests.eq((select count(*) from bookings)::int, 0, 'site manager sees no bookings');
select tests.eq((select count(*) from customer_sensitive)::int, 0, 'site manager cannot read PAN');
select tests.eq((select count(*) from villa_pricing)::int, 0, 'site manager cannot see prices');
select tests.eq((select count(*) from villas)::int, 1, 'site manager sees assigned villa');
select tests.expect_fail($$select public.verify_payment(gen_random_uuid())$$, 'site manager cannot verify payments');
update profiles set role='director' where id='a0000000-0000-0000-0000-000000000002';
select tests.as_admin();
select tests.eq((select role::text from profiles where id='a0000000-0000-0000-0000-000000000002'), 'site_manager', 'site manager cannot self-promote (update matched no rows)');
select tests.as_user(:sm);
select id as stg from construction_stages where name='Foundation completed' \gset
select public.submit_construction_update('c0000000-0000-0000-0000-0000000000a1', :'stg', 'completed', 'Foundation done', false, 'sm-req-1') as upd \gset
select tests.eq(public.submit_construction_update('c0000000-0000-0000-0000-0000000000a1', :'stg', 'completed', 'Foundation done', false, 'sm-req-1'), :'upd'::uuid, 'update retry is idempotent');
select tests.expect_fail(format($$select public.approve_construction_update(%L, true)$$, :'upd'), 'site manager cannot approve');
select tests.as_admin();
select tests.eq((select count(*) from booking_payment_milestones where booking_id='c0000000-0000-0000-0000-0000000000c1' and name='Foundation completed' and activated_at is not null)::int, 0, 'foundation payment NOT active before approval');

-- === Director approves; duplicates are harmless ===
select tests.as_user(:dir);
select public.approve_construction_update(:'upd', true);
select public.approve_construction_update(:'upd', true);
select tests.as_admin();
select tests.eq((select count(*) from domain_events where event_type='payment_milestone_activated')::int, 2, 'exactly 2 activation events (booking + foundation), none duplicated');
select tests.eq((select count(*) from follow_up_tasks)::int, 2, 'exactly 2 follow-up tasks');
select tests.eq(public.activate_milestone((select id from booking_payment_milestones where name='Foundation completed')), false, 're-running activation is a no-op');
select tests.eq((select count(*) from domain_events where event_type='construction_update_approved')::int, 1, 'single approval event');
select tests.eq((select assigned_to::text from follow_up_tasks t join booking_payment_milestones m on m.id=t.milestone_id where m.name='Foundation completed'), 'b0000000-0000-0000-0000-000000000003', 'task assigned to the booking salesperson');

-- === Partial foundation payment Rs 2,00,000 ===
select tests.as_user(:sal);
select public.report_payment('c0000000-0000-0000-0000-0000000000c1', 20000000, 'bank_transfer', 'REF-2', current_date) as pay2 \gset
select tests.eq((select outstanding_paise from v_milestone_balances where name='Foundation completed'), 60000000::bigint, 'milestone outstanding unchanged while pending');
select tests.eq((select pending_verification_paise from v_booking_balances where booking_id='c0000000-0000-0000-0000-0000000000c1'), 20000000::bigint, 'pending amount tracked separately');
select tests.as_user(:dir);
select public.verify_payment(:'pay2');
select tests.eq((select outstanding_paise from v_milestone_balances where name='Foundation completed'), 40000000::bigint, 'foundation outstanding = Rs 4,00,000');
select tests.eq((select derived_status from v_milestone_balances where name='Foundation completed'), 'partially_paid', 'part-paid milestone within due window shows partially_paid, not overdue');
select tests.eq((select outstanding_paise from v_booking_balances where booking_id='c0000000-0000-0000-0000-0000000000c1'), 520000000::bigint, 'overall outstanding = Rs 52,00,000');

-- over-allocation and non-activated allocation are blocked at DB level
select tests.as_user(:sal);
select public.report_payment('c0000000-0000-0000-0000-0000000000c1', 5000, 'upi', 'REF-3', current_date) as pay3 \gset
select tests.as_user(:dir);
select tests.expect_fail(format($$select public.verify_payment(%L, '[{"milestone_id":"%s","amount_paise":5000}]'::jsonb)$$, :'pay3',
   (select id from booking_payment_milestones where name='Plinth completed')), 'cannot allocate to non-activated milestone');
select tests.eq((select verification::text from payments where id=:'pay3'), 'pending', 'failed verification rolled back completely');
select tests.expect_fail(format($$select public.verify_payment(%L, '[{"milestone_id":"%s","amount_paise":999999999}]'::jsonb)$$, :'pay3',
   (select id from booking_payment_milestones where name='Foundation completed')), 'cannot over-allocate a milestone');

-- === Salesperson visibility ===
select tests.as_user(:sal2);
select tests.eq((select count(*) from customers)::int, 0, 'other salesperson sees no customers');
select tests.eq((select count(*) from payments)::int, 0, 'other salesperson sees no payments');
select tests.as_user(:sal);
select tests.eq((select count(*) from customer_sensitive)::int, 0, 'salesperson cannot read PAN');
select tests.eq((select count(*) from customers)::int, 1, 'salesperson sees own customer');
select tests.expect_fail($$select public.confirm_booking('c0000000-0000-0000-0000-0000000000c1')$$, 'salesperson cannot confirm bookings');
select tests.expect_fail($$update booking_payment_milestones set amount_paise=1$$, 'salesperson cannot edit schedule');
select tests.expect_fail($$delete from payments$$, 'salesperson cannot delete payments');
update bookings set package_price_paise=1;
select tests.as_admin();
select tests.eq((select min(package_price_paise) from bookings), 600000000::bigint, 'salesperson cannot change price (update matched no rows)');
select tests.as_user(:sal);

-- === Ledger immutability, reversal, frozen schedule ===
select tests.as_admin();
select tests.expect_fail($$delete from payments$$, 'ledger rows cannot be deleted even by admin');
select tests.expect_fail($$update payments set amount_paise=1 where verification='verified'$$, 'verified payment amount cannot be edited');
select tests.expect_fail($$delete from payment_allocations$$, 'allocations cannot be deleted');
select tests.expect_fail($$delete from audit_logs$$, 'audit log cannot be deleted');
select tests.expect_fail($$update booking_payment_milestones set amount_paise=amount_paise+1 where name='Plinth completed'$$, 'confirmed schedule is frozen');
select tests.as_user(:dir);
select public.reverse_payment(:'pay2', 'Cheque bounced (TEST)') as rev \gset
select tests.expect_fail(format($$select public.reverse_payment(%L, 'again')$$, :'pay2'), 'cannot reverse twice');
select tests.eq((select outstanding_paise from v_milestone_balances where name='Foundation completed'), 60000000::bigint, 'reversal restores milestone outstanding');
select tests.eq((select outstanding_paise from v_booking_balances where booking_id='c0000000-0000-0000-0000-0000000000c1'), 540000000::bigint, 'reversal restores overall outstanding');
select tests.eq((select count(*) from payments where id=:'pay2')::int, 1, 'original payment row still exists');
select tests.eq((select count(*) from audit_logs where action in ('payment_verified','payment_reversed','booking_confirmed','construction_approved'))::int >= 5, true, 'audit entries written');

-- === Overdue is derived from due date + grace, not from progress ===
select tests.as_admin();
update booking_payment_milestones set due_date = current_date - 20 where name='Foundation completed';
select tests.eq((select derived_status from v_milestone_balances where name='Foundation completed'), 'overdue', 'unpaid milestone past due+grace is overdue');
select tests.eq((select overdue_paise from v_booking_balances where booking_id='c0000000-0000-0000-0000-0000000000c1'), 60000000::bigint, 'overdue amount reported');
select tests.eq((select derived_status from v_milestone_balances where name='Plinth completed'), 'not_activated', 'unactivated milestone is never due/overdue');

-- === Cancellation preserves history; villa can be rebooked ===
select tests.as_user(:dir);
select public.cancel_booking('c0000000-0000-0000-0000-0000000000c1', 'Customer withdrew (TEST)');
select tests.eq((select count(*) from payments where booking_id='c0000000-0000-0000-0000-0000000000c1')::int, 4, 'all 4 ledger rows kept after cancellation');
insert into customers(id,full_name,phone) values ('c0000000-0000-0000-0000-0000000000b2','Second Fictional Customer','+919000000002');
insert into bookings(villa_id,customer_id,package_price_paise) values ('c0000000-0000-0000-0000-0000000000a1','c0000000-0000-0000-0000-0000000000b2',650000000);
select tests.eq((select count(*) from bookings)::int, 2, 'villa re-booked; old booking preserved');

-- === Role escalation / last director ===
select tests.as_user(:dir);
select tests.expect_fail($$update profiles set role='site_manager' where id='d0000000-0000-0000-0000-000000000001'$$, 'cannot demote the last Director');
select tests.as_admin();
\echo ALL PHASE 1 TESTS PASSED
