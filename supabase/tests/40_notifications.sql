\set ON_ERROR_STOP on
\set dir  '''d0000000-0000-0000-0000-000000000001'''
\set sm   '''a0000000-0000-0000-0000-000000000002'''
\set sal  '''b0000000-0000-0000-0000-000000000003'''
\set sal2 '''b0000000-0000-0000-0000-000000000004'''
\set bk   '''c0000000-0000-0000-0000-0000000000c4'''

-- money formatting
select tests.eq(public.fmt_inr(600000000), '₹60,00,000', 'Indian grouping: 60 lakh');
select tests.eq(public.fmt_inr(20000000), '₹2,00,000', 'Indian grouping: 2 lakh');
select tests.eq(public.fmt_inr(12345), '₹123.45', 'paise shown when present');
select tests.eq(public.fmt_inr(100), '₹1', 'one rupee');
select tests.eq(public.fmt_inr(1234567800), '₹1,23,45,678', 'crore grouping');

-- setup: opted-in customer + confirmed booking (everything below uses fictional data)
select tests.as_user(:dir);
insert into villas(id,project_id,villa_number,site_manager_id,salesperson_id) values ('c0000000-0000-0000-0000-0000000000a4','c0000000-0000-0000-0000-000000000001','A4',:sm,:sal);
insert into customers(id,full_name,phone,salesperson_id,whatsapp_opt_in,whatsapp_opt_in_at) values ('c0000000-0000-0000-0000-0000000000b4','Opted In Customer','+919000000004',:sal,true,now());
insert into bookings(id,villa_id,customer_id,salesperson_id,package_price_paise) values (:bk,'c0000000-0000-0000-0000-0000000000a4','c0000000-0000-0000-0000-0000000000b4',:sal,600000000);
select public.create_booking_schedule(:bk,'c0000000-0000-0000-0000-0000000000d1');
select public.confirm_booking(:bk);
select public.release_construction(:bk, true);
select tests.as_admin();
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Booking confirmed: Villa A4%')::int, 1, 'salesperson notified of confirmed booking');
select tests.eq((select count(*) from notifications where user_id=:dir and title like 'Booking confirmed: Villa A4%')::int >= 1, true, 'director notified of confirmed booking');
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Payment now payable: Villa A4%')::int, 1, 'salesperson notified when booking milestone becomes payable');
select tests.eq((select position('Villa A4' in body) > 0 and position('₹60,00,000' in body) > 0 from customer_message_drafts where kind='booking_confirmed' and booking_id=:bk), true, 'booking-confirmed draft is rendered with villa and amount');
select tests.eq((select position('₹6,00,000' in body) > 0 from customer_message_drafts where kind='payment_due' and booking_id=:bk), true, 'payment-due draft shows the milestone amount');
select tests.eq((select count(*) from customer_message_drafts where customer_id='c0000000-0000-0000-0000-0000000000b1')::int, 0, 'no drafts for customers who have not opted in');
select tests.eq((select count(*) from domain_events where processed_at is null)::int, 0, 'no event left stuck after normal operations');

-- visibility
select tests.as_user(:sal2);
select tests.eq((select count(*) from notifications)::int, 0, 'other salesperson sees none of these notifications');
select tests.eq((select count(*) from customer_message_drafts)::int, 0, 'other salesperson sees none of these drafts');
select tests.as_user(:sal);
select tests.eq((select count(*) from customer_message_drafts)::int, 2, 'assigned salesperson sees own drafts');
update notifications set read_at = now() where user_id = :sal;
select tests.eq((select count(*) from notifications where read_at is null)::int, 0, 'user can mark own notifications read');
select tests.expect_fail($$update notifications set title='hacked'$$, 'notification text cannot be edited');
select tests.eq((select count(*) from message_templates)::int, 0, 'salesperson cannot see templates');

-- payment flow
select public.report_payment(:bk, 20000000, 'upi', 'N-1', current_date) as p1 \gset
select tests.as_admin();
select tests.eq((select count(*) from notifications where user_id=:dir and title='Payment to verify' and position('Opted In Customer' in body) > 0)::int, 1, 'director notified of reported payment');
select tests.as_user(:dir);
select public.verify_payment(:'p1') as v1 \gset
select tests.as_admin();
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Payment verified: Villa A4%')::int, 1, 'salesperson notified when payment verified');
select tests.eq((select position((select receipt_number from payments where id=:'p1') in body) > 0 from customer_message_drafts where kind='payment_ack' and booking_id=:bk), true, 'acknowledgement draft contains the receipt number');
select count(*) as n_before from notifications \gset
select count(*) as d_before from customer_message_drafts \gset
select public.handle_event(id) from domain_events where event_type in ('payment_verified','payment_reported','booking_confirmed');
select tests.eq((select count(*) from notifications), :n_before::bigint, 're-processing events creates no duplicate notifications');
select tests.eq((select count(*) from customer_message_drafts), :d_before::bigint, 're-processing events creates no duplicate drafts');

-- construction approval -> draft + activation notification
select id as fnd from construction_stages where name='Foundation completed' \gset
select tests.as_user(:sm);
select public.submit_construction_update('c0000000-0000-0000-0000-0000000000a4', :'fnd', 'completed', 'done', false, 'n-1') as u1 \gset
select tests.as_admin();
select tests.eq((select count(*) from notifications where user_id=:dir and title='Construction update needs approval')::int >= 1, true, 'director notified of update needing approval');
select tests.as_user(:dir);
select public.approve_construction_update(:'u1', true);
select tests.as_admin();
select tests.eq((select count(*) from customer_message_drafts where kind='construction_update' and position('Foundation completed' in body) > 0)::int, 1, 'construction draft names the stage');
select tests.eq((select count(*) from customer_message_drafts where kind='payment_due' and booking_id=:bk)::int, 2, 'foundation payment-due draft created on approval');
select tests.as_user(:sm);
select public.submit_construction_update('c0000000-0000-0000-0000-0000000000a4', (select id from construction_stages where name='Plinth completed'), 'completed', 'x', false, 'n-2') as u2 \gset
select tests.as_user(:dir);
select public.approve_construction_update(:'u2', false, 'Photos unclear');
select tests.as_admin();
select tests.eq((select count(*) from notifications where user_id=:sm and title like 'Update rejected%' and position('Photos unclear' in body) > 0)::int, 1, 'site manager told why the update was rejected');

-- failure isolation: a broken template must not undo the payment
create table tests.tpl_backup as select * from message_templates where kind='payment_ack';
delete from message_templates where kind='payment_ack';
select tests.as_user(:sal);
select public.report_payment(:bk, 1000, 'upi', 'N-2', current_date) as p2 \gset
select tests.as_user(:dir);
select public.verify_payment(:'p2');
select tests.as_admin();
select tests.eq((select verification::text from payments where id=:'p2'), 'verified', 'payment stays verified even when notification preparation fails');
select tests.eq((select attempts from domain_events where event_type='payment_verified' and payload->>'payment_id'=:'p2'), 1, 'failed event is kept for retry');
select public.process_pending_events(); select public.process_pending_events(); select public.process_pending_events(); select public.process_pending_events();
select tests.eq((select attempts from domain_events where event_type='payment_verified' and payload->>'payment_id'=:'p2'), 5, 'retries stop at the limit of 5');
select tests.eq((select count(*) from notifications where user_id=:dir and title='A notification could not be prepared')::int, 1, 'director alerted when retries are exhausted');
insert into message_templates select * from tests.tpl_backup;
update domain_events set attempts = 0 where event_type='payment_verified' and payload->>'payment_id'=:'p2';
select tests.eq(public.process_pending_events(), 1, 'after the fix, the stuck event is processed');
select tests.eq((select count(*) from customer_message_drafts where kind='payment_ack' and booking_id=:bk)::int, 2, 'missing acknowledgement draft created on retry');

-- daily jobs: reminders, due today, overdue, escalation, no duplicates
select id as m_f from booking_payment_milestones where booking_id=:bk and name='Foundation completed' \gset
update booking_payment_milestones set due_date = current_date + 7 where id=:'m_f';
select public.run_daily_jobs();
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Payment due in 7 days: Villa A4%' and position('Foundation' in body) > 0)::int, 1, '7-day reminder to salesperson');
select tests.eq((select count(*) from customer_message_drafts where kind='payment_upcoming' and booking_id=:bk and position('Foundation completed' in body) > 0)::int, 1, '7-day customer draft');
select public.run_daily_jobs();
select tests.eq((select count(*) from customer_message_drafts where kind='payment_upcoming' and booking_id=:bk and position('Foundation completed' in body) > 0)::int, 1, 'running the daily job twice does not duplicate reminders');
update booking_payment_milestones set due_date = current_date + 2 where id=:'m_f'; select public.run_daily_jobs();
select tests.eq((select count(*) from customer_message_drafts where kind='payment_upcoming' and booking_id=:bk and position('Foundation completed' in body) > 0)::int, 2, '2-day reminder is a separate reminder');
update booking_payment_milestones set due_date = current_date where id=:'m_f'; select public.run_daily_jobs();
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Payment due today: Villa A4%')::int, 1, 'due-today notification');
update booking_payment_milestones set due_date = current_date - 10 where id=:'m_f'; select public.run_daily_jobs(); select public.run_daily_jobs();
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Payment overdue: Villa A4%')::int, 1, 'single overdue notification to salesperson');
select tests.eq((select count(*) from customer_message_drafts where kind='payment_overdue' and booking_id=:bk)::int, 1, 'one overdue customer draft this week');
select tests.eq((select count(*) from notifications where user_id=:dir and title like 'Overdue 7 days: Villa A4%')::int, 1, 'director escalation after the configured days');
update booking_payment_milestones set due_date = current_date + 30 where id=:'m_f';   -- not due: must stay silent
select tests.eq((select derived_status from v_milestone_balances where id=:'m_f') in ('upcoming','partially_paid'), true, 'milestone not yet due is never called overdue');

-- follow-up task alerts
update follow_up_tasks set due_date = current_date - 1, promised_date = current_date - 1 where milestone_id=:'m_f';
select public.run_daily_jobs();
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Follow-up overdue: Villa A4%')::int, 1, 'overdue follow-up alert');
select tests.eq((select count(*) from notifications where user_id=:sal and title like 'Promised payment date missed: Villa A4%')::int, 1, 'missed promise flagged');
select tests.eq((select count(*) from notifications where user_id=:sal and title='Daily summary' and created_at::date = current_date)::int, 1, 'exactly one daily summary per person per day');
select tests.eq((select count(*) from notifications where user_id=:dir and title='Daily summary')::int, 1, 'director gets a daily summary');

-- permissions
select tests.as_user(:sal);
select tests.expect_fail($$select public.run_daily_jobs()$$, 'salesperson cannot run daily jobs');
select tests.expect_fail($$select public.process_pending_events()$$, 'salesperson cannot run event processing');
select tests.expect_fail($$select public.usage_stats()$$, 'salesperson cannot read usage stats');
select tests.as_user(:dir);
select tests.eq((public.usage_stats()->>'db_bytes')::bigint > 0, true, 'director can read usage stats');
select tests.eq((select count(*) from message_templates)::int, 8, 'director sees all 8 templates');
update message_templates set body = 'Hi {{customer_name}}!' where kind = 'handover';
select tests.as_admin();
select tests.eq(public.render_template('handover', '{"customer_name":"Asha"}'::jsonb), 'Hi Asha!', 'edited template is used and variables are filled');
select tests.as_user(:dir);
update system_settings set value = '[3]' where key = 'reminder_days_before';
select tests.eq((select value::text from system_settings where key='reminder_days_before'), '[3]', 'director can change reminder settings');
select tests.as_user(:sal);
update system_settings set value = '[99]' where key = 'reminder_days_before';
select tests.as_admin();
select tests.eq((select value::text from system_settings where key='reminder_days_before'), '[3]', 'salesperson cannot change settings');

-- message drafts: mark sent
select id as dr from customer_message_drafts where kind='booking_confirmed' and booking_id=:bk \gset
select tests.as_user(:sal2);
select tests.expect_fail(format($$select public.handle_message(%L,'sent')$$, :'dr'), 'other salesperson cannot mark my message sent');
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.handle_message(%L,'weird')$$, :'dr'), 'unknown action refused');
select public.handle_message(:'dr', 'sent');
select tests.eq((select status from customer_message_drafts where id=:'dr'), 'sent', 'message marked sent');
select tests.eq((select handled_by::text from customer_message_drafts where id=:'dr'), 'b0000000-0000-0000-0000-000000000003', 'who sent it is recorded');

-- retention keeps the database small
select tests.as_admin();
update notifications set created_at = now() - interval '200 days' where title='Daily summary' and user_id=:dir;
select count(*) as old_n from notifications where created_at < now() - interval '180 days' \gset
select public.purge_old_data();
select tests.eq((select count(*) from notifications where created_at < now() - interval '180 days')::int, 0, 'old notifications are purged');
select tests.eq(:old_n::int > 0, true, 'purge test had something to remove');
\echo ALL PHASE 5 DB TESTS PASSED
