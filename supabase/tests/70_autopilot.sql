\set ON_ERROR_STOP on
\set dir  '''d0000000-0000-0000-0000-000000000001'''
\set sm   '''a0000000-0000-0000-0000-000000000002'''
\set sal  '''b0000000-0000-0000-0000-000000000003'''
\set sal2 '''b0000000-0000-0000-0000-000000000004'''
\set vl   '''c0000000-0000-0000-0000-0000000000a7'''
\set cu   '''c0000000-0000-0000-0000-0000000000b7'''

select tests.as_admin();
update system_settings set value='true' where key='autopilot_enabled';
update system_settings set value='10' where key='auto_ask_max_percent';
update system_settings set value='25000' where key='auto_ask_min_rupees';
update construction_stages set requires_approval = (name in ('Foundation completed','First slab / ceiling completed','Final inspection','Handover completed'));
select tests.eq((select requires_approval from construction_stages where name='Excavation'), false, 'ordinary steps need no approval');
select tests.eq((select requires_approval from construction_stages where name='Foundation completed'), true, 'key steps still need approval');
select id as st_exc from construction_stages where name='Excavation' \gset
select id as st_fnd from construction_stages where name='Foundation completed' \gset
select id as st_brk from construction_stages where name='Brickwork completed' \gset
select id as st_plin from construction_stages where name='Plinth completed' \gset

-- ===== the Salesperson prepares the booking =====
select tests.as_user(:dir);
insert into villas(id,project_id,villa_number,site_manager_id,salesperson_id) values (:vl,'c0000000-0000-0000-0000-000000000001','AP1',:sm,:sal);
insert into villa_pricing values (:vl, 600000000);
select tests.as_user(:sal);
insert into customers(id,full_name,phone,salesperson_id,whatsapp_opt_in,whatsapp_opt_in_at) values (:cu,'Autopilot Customer','+919000000007',:sal,true,now());
select tests.pass('salesperson can add their own customer');
select tests.expect_fail($$insert into customers(full_name,phone,salesperson_id) values ('Not Mine','+919000000008','b0000000-0000-0000-0000-000000000004')$$, 'salesperson cannot add a customer for someone else');
select tests.expect_fail($$insert into bookings(villa_id,customer_id,package_price_paise) values ('c0000000-0000-0000-0000-0000000000a7','c0000000-0000-0000-0000-0000000000b7',1)$$, 'salesperson cannot create a booking directly (no price control)');
select public.start_booking(:vl, :cu, 10000000, 'upi', 'TKN-7', current_date, 'sb-1') as bk \gset
select tests.eq(public.start_booking(:vl, :cu, 10000000, 'upi', 'TKN-7', current_date, 'sb-1'), :'bk'::uuid, 'double tap does not create a second booking');
select tests.as_admin();
select tests.eq((select package_price_paise from bookings where id=:'bk'), 600000000::bigint, 'price comes from the villa list price, not from the salesperson');
select tests.eq((select status::text from bookings where id=:'bk'), 'draft', 'booking waits for the Director as a draft');
select tests.eq((select count(*) from booking_payment_milestones where booking_id=:'bk')::int, 2, 'starter plan applied automatically');
select tests.eq((select count(*) from notifications where user_id=:dir and title='New booking ready to confirm: Villa AP1')::int, 1, 'Director told a booking is ready to confirm');
select tests.eq((select purpose from payments where booking_id=:'bk'), 'token', 'token recorded');
select tests.as_user(:sal2);
select tests.expect_fail(format($$select public.start_booking(%L, %L)$$, :vl, :cu), 'other salesperson cannot book this villa');
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.confirm_booking(%L)$$, :'bk'), 'salesperson cannot confirm the booking');
select tests.as_admin();
select id as tk from payments where booking_id=:'bk' \gset
select tests.as_user(:dir);
select public.verify_payment(:'tk');
select public.confirm_booking(:'bk');

-- ===== autopilot asks for the pre-construction money, only after the booking amount is paid =====
select (public.autopilot_tick())->>'auto_asked' as a0 \gset
select tests.eq(:'a0'::int, 0, 'no automatic request while the booking amount is still unpaid');
select tests.as_user(:sal);
select public.report_payment(:'bk', 50000000, 'bank_transfer', 'AP-5', current_date) as pa \gset
select tests.as_user(:dir);
select public.verify_payment(:'pa');
select (public.autopilot_tick())->>'auto_asked' as a1 \gset
select tests.eq(:'a1'::int, 1, 'booking amount paid: the system asks for the pre-construction payment by itself');
select tests.as_admin();
select tests.eq((select amount_paise from payment_demands where booking_id=:'bk' and auto), 180000000::bigint, 'it asks for exactly enough to reach 40%');
select tests.eq((select created_by is null and title = 'Payment before construction starts' from payment_demands where booking_id=:'bk' and auto), true, 'recorded as an automatic request');
select tests.eq((select count(*) from follow_up_tasks t join payment_demands d on d.milestone_id=t.milestone_id where d.booking_id=:'bk')::int, 1, 'salesperson gets the call task automatically');
select tests.eq((select count(*) from customer_message_drafts where booking_id=:'bk' and kind='payment_demand')::int, 1, 'WhatsApp message prepared automatically');
select tests.as_user(:dir);
select (public.autopilot_tick())->>'auto_asked' as a2 \gset
select tests.eq(:'a2'::int, 0, 'running autopilot again does not ask twice');
select tests.as_user(:sal);
select public.report_payment(:'bk', 180000000, 'bank_transfer', 'LOAN-7', current_date, null, null, 'bank') as pl \gset
select tests.as_user(:dir);
select public.verify_payment(:'pl');
select (public.autopilot_tick())->>'auto_asked' as a3 \gset
select tests.eq(:'a3'::int, 0, 'nothing more is asked while construction has not progressed');

-- ===== construction progress triggers automatic requests (within the limit) =====
select tests.as_user(:sm);
select public.submit_construction_update(:vl, :'st_exc', 'completed', 'excavation done', false, 'ap-1') as ue \gset
select tests.as_admin();
select tests.eq((select approval::text from construction_updates where id=:'ue'), 'not_required', 'ordinary step counted without waiting for the Director');
select tests.eq((select amount_paise from payment_demands where booking_id=:'bk' and title='Excavation payment' and auto), 23000000::bigint, 'step completed: the system asked for the suggested amount automatically');
select tests.eq((select update_id = :'ue'::uuid from payment_demands where title='Excavation payment' and booking_id=:'bk'), true, 'request is linked to the construction update');
select tests.eq((select position('Progress: Excavation' in body) > 0 from customer_message_drafts where booking_id=:'bk' and kind='payment_demand' order by created_at desc limit 1), true, 'customer message mentions the construction update');

-- ===== key step: waits, then is approved automatically; big requests need the Director's OK =====
select tests.as_user(:sm);
select public.submit_construction_update(:vl, :'st_fnd', 'completed', 'foundation done', false, 'ap-2') as uf \gset
select tests.as_user(:dir);
select public.autopilot_tick();
select tests.as_admin();
select tests.eq((select approval::text from construction_updates where id=:'uf'), 'pending', 'key step is not approved immediately');
update construction_updates set submitted_at = now() - interval '2 hours' where id=:'uf';
update system_settings set value='1' where key='auto_ask_max_percent';
select tests.as_user(:dir);
select public.autopilot_tick();
select tests.as_admin();
select tests.eq((select approval::text from construction_updates where id=:'uf'), 'pending', 'still waiting inside the 24 hour window');
update construction_updates set submitted_at = now() - interval '25 hours' where id=:'uf';
select tests.as_user(:dir);
select public.autopilot_tick();
select tests.as_admin();
select tests.eq((select approval::text from construction_updates where id=:'uf'), 'approved', 'after 24 hours of silence it is approved automatically');
select tests.eq((select auto_approved and approved_by is null from construction_updates where id=:'uf'), true, 'marked as automatic approval, not a person');
select tests.eq((select current_stage_id::text from villas where id=:vl), :'st_fnd', 'villa stage updated by the automatic approval');
select tests.eq((select count(*) from payment_demands where booking_id=:'bk')::int, 2, 'bigger than the automatic limit: no request was made by itself');
select tests.eq((select count(*) from notifications where user_id=:dir and title like 'Your OK is needed%')::int, 1, 'Director asked for one-tap OK');
select tests.as_user(:dir);
select public.autopilot_tick();
select tests.as_admin();
select tests.eq((select count(*) from notifications where user_id=:dir and title like 'Your OK is needed%')::int, 1, 'the OK request is not repeated');
select tests.as_user(:dir);
select jsonb_array_length((public.flow_overview())->'big_asks') as nb \gset
select tests.eq(:'nb'::int, 1, 'Home shows the request waiting for the Director');
select public.raise_demand(:'bk', 24000000, 'Foundation completed payment', 7, :'uf', null, 24000000, 'ap-rq-1');
select jsonb_array_length((public.flow_overview())->'big_asks') as nb2 \gset
select tests.eq(:'nb2'::int, 0, 'after the Director asks, nothing is waiting');

-- ===== switches =====
select tests.as_admin();
update system_settings set value='10' where key='auto_ask_max_percent';
update system_settings set value='false' where key='autopilot_enabled';
select count(*) as dem_before from payment_demands where booking_id=:'bk' \gset
select tests.as_user(:sm);
select public.submit_construction_update(:vl, :'st_plin', 'completed', 'plinth', false, 'ap-3');
select tests.as_admin();
select tests.eq((select count(*) from payment_demands where booking_id=:'bk'), :dem_before::bigint, 'autopilot switched off: no automatic request');
update system_settings set value='true' where key='autopilot_enabled';
update system_settings set value='100000000' where key='auto_ask_min_rupees';
select tests.as_user(:sm);
select public.submit_construction_update(:vl, :'st_brk', 'completed', 'brickwork', false, 'ap-4');
select tests.as_admin();
select tests.eq((select count(*) from payment_demands where booking_id=:'bk'), :dem_before::bigint, 'requests below the minimum amount are not made');
update system_settings set value='25000' where key='auto_ask_min_rupees';

-- ===== what the Director sees =====
select tests.as_user(:sal);
select tests.expect_fail($$select public.flow_overview()$$, 'salesperson cannot open the Director overview');
select tests.expect_fail($$select * from public.activity_feed()$$, 'salesperson cannot read the activity feed');
select tests.expect_fail($$select public.autopilot_tick()$$, 'salesperson cannot run autopilot');
select tests.eq((select count(*) from autopilot_runs)::int, 0, 'salesperson cannot read autopilot logs');
select tests.as_user(:dir);
select (public.flow_overview())->>'building' as bn \gset
select tests.eq(:'bn'::int >= 1, true, 'overview counts villas that are building');
select tests.eq(((public.flow_overview())->>'auto_asks_7d')::int >= 2, true, 'overview counts automatic requests this week');
select tests.eq(((public.flow_overview())->>'auto_approved_7d')::int, 1, 'overview counts automatic approvals');
select tests.eq((select count(*) from public.activity_feed(50) where line like 'The system asked Autopilot Customer for%')::int >= 2, true, 'activity feed shows what the system did in plain words');
select tests.eq((select count(*) from public.activity_feed(50) where line like 'Approved automatically:%')::int, 1, 'feed shows the automatic approval');
select tests.as_admin();
update follow_up_tasks set due_date = current_date - 10 where status='open';
select tests.as_user(:dir);
select tests.eq((public.flow_overview())->>'status', 'amber', 'late follow-ups turn the overview amber');
select tests.eq((select count(*) from jsonb_array_elements((public.flow_overview())->'stuck') s where s->>'text' like '%follow-up call(s) more than%')::int >= 1, true, 'overview names the slow salesperson');
select tests.as_admin();
update follow_up_tasks set due_date = current_date + 5 where status='open';
update customer_message_drafts set status='skipped', handled_at=now() where status='pending';
update autopilot_runs set ran_at = now() - interval '5 hours';
select tests.as_user(:dir);
select tests.eq((public.flow_overview())->>'status', 'red', 'automatic checks not running turns the overview red');
select public.autopilot_tick();
select tests.eq((public.flow_overview())->>'status', 'green', 'once it runs and nothing is stuck, everything shows green');

-- ===== daily confirmation reminder =====
select tests.as_user(:sal);
select public.report_payment(:'bk', 5000, 'upi', 'PEND-1', current_date);
select tests.as_user(:dir);
select public.remind_pending_payments();
select public.remind_pending_payments();
select tests.as_admin();
select tests.eq((select count(*) from notifications where user_id=:dir and title like '%payment(s) to confirm' and created_at::date = current_date)::int, 1, 'one daily reminder to confirm payments');
\echo ALL PHASE 8 DB TESTS PASSED
