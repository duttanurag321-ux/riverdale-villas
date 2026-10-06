\set ON_ERROR_STOP on
\set dir  '''d0000000-0000-0000-0000-000000000001'''
\set sm   '''a0000000-0000-0000-0000-000000000002'''
\set sal  '''b0000000-0000-0000-0000-000000000003'''
\set sal2 '''b0000000-0000-0000-0000-000000000004'''
\set v3   '''c0000000-0000-0000-0000-0000000000a3'''
\set bk   '''c0000000-0000-0000-0000-0000000000c3'''
select tests.as_user(:dir);
insert into villas(id,project_id,villa_number,site_manager_id,salesperson_id) values (:v3,'c0000000-0000-0000-0000-000000000001','A3',:sm,:sal);
insert into customers(id,full_name,phone,salesperson_id) values ('c0000000-0000-0000-0000-0000000000b3','Third Fictional Customer','+919000000003',:sal);
insert into bookings(id,villa_id,customer_id,salesperson_id,package_price_paise) values (:bk,:v3,'c0000000-0000-0000-0000-0000000000b3',:sal,600000000);
select public.create_booking_schedule(:bk,'c0000000-0000-0000-0000-0000000000d1');
select public.confirm_booking(:bk);
select id as task from follow_up_tasks where booking_id=:bk \gset

-- === follow-up outcomes ===
select tests.as_user(:sal2);
select tests.expect_fail(format($$select public.record_follow_up_outcome(%L,'no_answer')$$, :'task'), 'other salesperson cannot log outcome');
select tests.as_user(:sm);
select tests.expect_fail(format($$select public.record_follow_up_outcome(%L,'no_answer')$$, :'task'), 'site manager cannot log outcome');
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.record_follow_up_outcome(%L,'contacted_will_pay')$$, :'task'), 'promise outcome needs a date');
select tests.expect_fail(format($$select public.record_follow_up_outcome(%L,'other')$$, :'task'), 'other outcome needs a note');
select tests.expect_fail(format($$select public.record_follow_up_outcome(%L,'contacted_will_pay',null,current_date-1)$$, :'task'), 'promise date cannot be in the past');
select public.record_follow_up_outcome(:'task','contacted_will_pay','Will pay after salary', current_date + 5);
select tests.eq((select promised_date from follow_up_tasks where id=:'task'), current_date + 5, 'promise recorded on the task');
select tests.eq((select due_date from follow_up_tasks where id=:'task'), current_date + 5, 'same task rescheduled to promised date');
select tests.eq((select count(*) from follow_up_tasks where booking_id=:bk)::int, 1, 'no duplicate task created by rescheduling');
select public.record_follow_up_outcome(:'task','no_answer');
select public.record_follow_up_outcome(:'task','dispute','Customer disputes charge');
select tests.eq((select priority from follow_up_tasks where id=:'task'), 'high', 'dispute raises priority');
select tests.eq((select count(*) from follow_up_activity_logs where task_id=:'task')::int, 3, 'every contact attempt logged');
select tests.as_admin();
select tests.eq((select count(*) from domain_events where event_type='follow_up_escalated')::int, 1, 'escalation event recorded');
select tests.expect_fail($$delete from follow_up_activity_logs$$, 'follow-up history cannot be deleted');
select tests.as_user(:sal);
select public.complete_follow_up(:'task','Closed manually');
select tests.eq((select status from follow_up_tasks where id=:'task'), 'done', 'task can be completed');
select tests.expect_fail(format($$select public.record_follow_up_outcome(%L,'no_answer')$$, :'task'), 'closed task takes no more outcomes');

-- === schedule amendment ===
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.amend_booking_schedule(%L,'[]'::jsonb,'x')$$, :'bk'), 'salesperson cannot amend schedule');
select tests.as_user(:dir);
select id as m_found from booking_payment_milestones where booking_id=:bk and name='Foundation completed' \gset
select id as m_plinth from booking_payment_milestones where booking_id=:bk and name='Plinth completed' \gset
select id as m_book from booking_payment_milestones where booking_id=:bk and name='Booking' \gset
select tests.expect_fail(format($$select public.amend_booking_schedule(%L,'[{"milestone_id":"%s","amount_paise":70000000}]'::jsonb,'bad total')$$, :'bk', :'m_found'), 'amendment that breaks the total is refused');
select tests.expect_fail(format($$select public.amend_booking_schedule(%L,'[{"milestone_id":"%s","amount_paise":70000000}]'::jsonb,'active one')$$, :'bk', :'m_book'), 'active milestone cannot be amended');
select tests.expect_fail(format($$select public.amend_booking_schedule(%L,'[{"milestone_id":"%s","amount_paise":50000000},{"milestone_id":"%s","amount_paise":70000000}]'::jsonb,'')$$, :'bk', :'m_found', :'m_plinth'), 'amendment needs a reason');
select tests.eq((select amount_paise from booking_payment_milestones where id=:'m_found'), 60000000::bigint, 'failed amendments changed nothing');
select public.amend_booking_schedule(:bk, format('[{"milestone_id":"%s","amount_paise":50000000},{"milestone_id":"%s","amount_paise":70000000}]', :'m_found', :'m_plinth')::jsonb, 'Customer negotiated shift');
select tests.eq((select amount_paise from booking_payment_milestones where id=:'m_found'), 50000000::bigint, 'future milestone amended');
select tests.eq((select sum(amount_paise) from booking_payment_milestones where booking_id=:bk)::bigint, 600000000::bigint, 'schedule still totals contract value');
select tests.eq((select jsonb_array_length(snapshot) from booking_schedule_versions where booking_id=:bk and version=1), 8, 'previous schedule preserved as version 1');
select tests.eq((select (snapshot->1->>'amount_paise')::bigint from booking_schedule_versions where booking_id=:bk and version=1), 60000000::bigint, 'preserved copy holds the OLD amount');
select tests.expect_fail($$update booking_payment_milestones set amount_paise=1$$, 'direct edits still blocked after an amendment');
select tests.as_admin();
select tests.expect_fail($$delete from booking_schedule_versions$$, 'schedule history cannot be deleted');
-- === hold ===
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.set_milestone_hold(%L,true,'x')$$, :'m_book'), 'salesperson cannot hold milestones');
select tests.as_user(:dir);
select tests.expect_fail(format($$select public.set_milestone_hold(%L,true,'')$$, :'m_book'), 'hold needs a reason');
select public.set_milestone_hold(:'m_book', true, 'Dispute under review');
select tests.eq((select derived_status from v_milestone_balances where id=:'m_book'), 'on_hold', 'held milestone shows on_hold');
select tests.as_user(:sal);
select public.report_payment(:bk, 10000, 'upi', 'HOLD-1', current_date) as ph \gset
select tests.as_user(:dir);
select tests.eq((public.verify_payment(:'ph')->>'unallocated_paise')::bigint, 10000::bigint, 'on-hold milestone gets no auto-allocation');
select public.set_milestone_hold(:'m_book', false);
\echo ALL PHASE 4 DB TESTS PASSED
