\set ON_ERROR_STOP on
\set dir  '''d0000000-0000-0000-0000-000000000001'''
\set sm   '''a0000000-0000-0000-0000-000000000002'''
\set sal  '''b0000000-0000-0000-0000-000000000003'''
\set sal2 '''b0000000-0000-0000-0000-000000000004'''
\set bk   '''c0000000-0000-0000-0000-0000000000c6'''
\set vl   '''c0000000-0000-0000-0000-0000000000a6'''

-- ===== setup: token stage (booking still a draft) =====
select tests.as_user(:dir);
select id as plan from payment_plan_templates where name like 'Riverdale standard%' \gset
insert into villas(id,project_id,villa_number,site_manager_id,salesperson_id) values (:vl,'c0000000-0000-0000-0000-000000000001','R1',:sm,:sal);
insert into customers(id,full_name,phone,salesperson_id,whatsapp_opt_in,whatsapp_opt_in_at) values ('c0000000-0000-0000-0000-0000000000b6','Real Flow Customer','+919000000006',:sal,true,now());
insert into bookings(id,villa_id,customer_id,salesperson_id,package_price_paise) values (:bk,:vl,'c0000000-0000-0000-0000-0000000000b6',:sal,600000000);
select tests.eq((select status::text from villas where id=:vl), 'reserved', 'creating a booking reserves the villa');
select public.create_booking_schedule(:bk, :'plan');
select tests.eq((select count(*) from booking_payment_milestones where booking_id=:bk)::int, 2, 'starter plan: booking amount + balance');
select tests.eq((select amount_paise from booking_payment_milestones where booking_id=:bk and is_pool), 540000000::bigint, 'balance to be raised later is 90%');
select tests.eq((select sum(amount_paise) from booking_payment_milestones where booking_id=:bk)::bigint, 600000000::bigint, 'schedule totals the contract value');
select tests.expect_fail(format($$select public.raise_demand(%L, 100, 'x')$$, :bk), 'cannot ask for money before the booking is confirmed');

select tests.as_user(:sal2);
select tests.expect_fail(format($$select public.report_payment(%L, 100, 'upi', 'x', current_date)$$, :bk), 'other salesperson cannot record a token on this booking');
select tests.as_user(:sal);
select public.report_payment(:bk, 10000000, 'upi', 'TOKEN-1', current_date) as tk \gset
select tests.eq((select purpose from payments where id=:'tk'), 'token', 'a payment on an unconfirmed booking is a token');
select tests.as_user(:dir);
select public.verify_payment(:'tk');
select tests.eq((select credit_paise from v_booking_balances where booking_id=:bk), 10000000::bigint, 'verified token is held as customer credit');
select public.confirm_booking(:bk);
select tests.eq((select paid_paise from v_milestone_balances where booking_id=:bk and name='Booking amount'), 10000000::bigint, 'token is adjusted against the booking amount automatically');
select tests.eq((select outstanding_paise from v_milestone_balances where booking_id=:bk and name='Booking amount'), 50000000::bigint, 'booking amount outstanding after token');
select tests.eq((select credit_paise from v_booking_balances where booking_id=:bk), 0::bigint, 'no credit left over');
select tests.eq((select derived_status from v_milestone_balances where booking_id=:bk and is_pool), 'not_activated', 'the balance is never payable by itself');

-- ===== construction start gate =====
select tests.as_user(:sm);
select tests.eq((select gate_open from construction_gates() where villa_id=:vl), false, 'site manager sees the villa is locked (no amounts)');
select id as exc from construction_stages where name='Excavation' \gset
select id as fnd from construction_stages where name='Foundation completed' \gset
select tests.expect_fail(format($$select public.submit_construction_update(%L,%L,'in_progress',null,false,'g-1')$$, :vl, :'exc'), 'construction blocked until enough payment is confirmed');
select tests.expect_fail(format($$select public.release_construction(%L,true)$$, :bk), 'site manager cannot release construction');
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.release_construction(%L,true)$$, :bk), 'salesperson cannot release construction');
select tests.as_user(:dir);
select tests.expect_fail(format($$update bookings set construction_released=true where id=%L$$, :bk), 'release cannot be set by a direct table edit');
select public.release_construction(:bk, true);
select tests.as_user(:sm);
select public.submit_construction_update(:vl, :'exc', 'in_progress', 'started', false, 'g-2');
select tests.pass('after the Director releases, the site manager can start');
select tests.as_user(:dir);
select public.release_construction(:bk, false);
select tests.as_user(:sm);
select tests.expect_fail(format($$select public.submit_construction_update(%L,%L,'in_progress',null,false,'g-3')$$, :vl, :'exc'), 'locking again blocks updates again');

-- ===== suggestion: 40% target before construction =====
select tests.as_user(:sal);
select public.report_payment(:bk, 50000000, 'bank_transfer', 'BK-5L', current_date) as p5 \gset
select tests.as_user(:dir);
select public.verify_payment(:'p5');
select tests.eq((select outstanding_paise from v_booking_balances where booking_id=:bk), 540000000::bigint, 'after 10%: 90% still to collect');
select (public.suggest_demand(:bk)) as sg \gset
select tests.eq((:'sg'::jsonb->>'suggested_paise')::bigint, 180000000::bigint, 'suggestion before construction = collect up to 40% (Rs 18 lakh more)');
select tests.eq((:'sg'::jsonb->>'progress_bp')::int, 0, 'no stages completed yet');
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.suggest_demand(%L)$$, :bk), 'salesperson cannot use the suggestion tool');
select tests.expect_fail($$select * from public.demand_opportunities()$$, 'salesperson cannot list opportunities');
select tests.as_user(:dir);
select tests.eq((select suggested_paise from public.demand_opportunities() where booking_id=:bk), 180000000::bigint, 'opportunity list shows the booking');

-- ===== raise a demand =====
select tests.as_user(:sal);
select tests.expect_fail(format($$select public.raise_demand(%L, 100, 'x')$$, :bk), 'salesperson cannot raise a demand');
select tests.as_user(:dir);
select tests.expect_fail(format($$select public.raise_demand(%L, 0, 'x')$$, :bk), 'zero amount refused');
select tests.expect_fail(format($$select public.raise_demand(%L, 540000001, 'x')$$, :bk), 'cannot ask for more than the balance');
select tests.expect_fail(format($$select public.raise_demand(%L, 100, '')$$, :bk), 'a reason is required');
select tests.expect_fail(format($$select public.raise_demand(%L, 100, 'x', 7, gen_random_uuid())$$, :bk), 'linked update must belong to this villa');
select public.raise_demand(:bk, 180000000, 'Payment before construction starts', 7, null, 'Pre-construction payment', 180000000, 'rq-1') as d1 \gset
select tests.eq(public.raise_demand(:bk, 180000000, 'Payment before construction starts', 7, null, null, null, 'rq-1'), :'d1'::uuid, 'double click with the same request does not ask twice');
select tests.eq((select amount_paise from booking_payment_milestones where booking_id=:bk and is_pool), 360000000::bigint, 'balance reduced by the demand');
select tests.eq((select sum(amount_paise) from booking_payment_milestones where booking_id=:bk)::bigint, 600000000::bigint, 'schedule still totals the contract value');
select tests.eq((select due_date from booking_payment_milestones where id=:'d1'), current_date + 7, 'due date set from today');
select tests.eq((select count(*) from follow_up_tasks where milestone_id=:'d1')::int, 1, 'follow-up task created for the demand');
select tests.as_admin();
select tests.eq((select position('₹18,00,000' in body) > 0 and position('Payment before construction starts' in body) > 0 from customer_message_drafts where booking_id=:bk and kind='payment_demand' order by created_at limit 1), true, 'customer message drafted with amount and reason');
select tests.eq((select count(*) from customer_message_drafts where booking_id=:bk and kind='payment_demand')::int, 1, 'only one customer message');

-- ===== loan instalment from the bank opens the gate by itself =====
select tests.as_user(:sal);
select public.report_payment(:bk, 180000000, 'bank_transfer', 'LOAN-1', current_date, 'First loan instalment', null, 'bank') as pl \gset
select tests.eq((select paid_by from payments where id=:'pl'), 'bank', 'payment marked as paid by the bank');
select tests.as_user(:dir);
select public.verify_payment(:'pl');
select tests.eq((select derived_status from v_milestone_balances where id=:'d1'), 'paid', 'demand paid by the loan instalment');
select tests.as_user(:sm);
select tests.eq((select gate_open from construction_gates() where villa_id=:vl), true, 'gate opens automatically once 40% is confirmed');
select public.submit_construction_update(:vl, :'fnd', 'completed', 'foundation done', false, 'g-4') as uf \gset
select tests.as_user(:dir);
select public.approve_construction_update(:'uf', true);
select tests.as_admin();
select tests.eq((select count(*) from booking_payment_milestones where booking_id=:bk and activated_at is not null)::int, 2, 'approving a stage no longer triggers a payment by itself');

-- ===== suggestion follows construction progress =====
select tests.as_user(:dir);
select (public.suggest_demand(:bk)) as sg2 \gset
select tests.eq((:'sg2'::jsonb->>'progress_bp')::int, 666, 'progress = 1 of 15 stages');
select tests.eq((:'sg2'::jsonb->>'suggested_paise')::bigint, 23000000::bigint, 'suggestion rises with progress (rounded down to Rs 10,000)');
select tests.eq((select suggested_paise from public.demand_opportunities() where booking_id=:bk), 23000000::bigint, 'opportunity list updated');

-- ===== credit from an early payment is applied to the next demand =====
select tests.as_user(:sal);
select public.report_payment(:bk, 20000000, 'upi', 'EXTRA-2L', current_date) as pe \gset
select tests.as_user(:dir);
select public.verify_payment(:'pe');
select tests.eq((select credit_paise from v_booking_balances where booking_id=:bk), 20000000::bigint, 'early payment waits as credit');
select public.raise_demand(:bk, 50000000, 'Foundation payment', 7, :'uf', null, 23000000, 'rq-2') as d2 \gset
select tests.eq((select paid_paise from v_milestone_balances where id=:'d2'), 20000000::bigint, 'credit applied to the new demand immediately');
select tests.eq((select outstanding_paise from v_milestone_balances where id=:'d2'), 30000000::bigint, 'only the remainder is outstanding');
select tests.eq((select credit_paise from v_booking_balances where booking_id=:bk), 0::bigint, 'credit used up');
select tests.as_admin();
select tests.eq((select position('Progress: Foundation completed' in body) > 0 from customer_message_drafts where booking_id=:bk and kind='payment_demand' order by created_at desc limit 1), true, 'message mentions the linked construction update');
select tests.eq((select suggested_paise from payment_demands where milestone_id=:'d2'), 23000000::bigint, 'what the system suggested is recorded');

-- ===== funding route, visibility, immutability =====
select tests.as_user(:dir);
update bookings set funding_type='loan', loan_bank='Test Bank (FICTIONAL)', loan_sanctioned_paise=300000000 where id=:bk;
select tests.as_user(:sal);
update bookings set funding_type='self' where id=:bk;
select tests.as_admin();
select tests.eq((select funding_type from bookings where id=:bk), 'loan', 'loan details saved; salesperson cannot change them');
select tests.as_user(:sal);
select tests.eq((select count(*) from payment_demands where booking_id=:bk)::int, 2, 'salesperson can see why money was requested');
select tests.as_user(:sal2);
select tests.eq((select count(*) from payment_demands)::int, 0, 'other salesperson cannot');
select tests.as_admin();
select tests.expect_fail($$delete from payment_demands$$, 'demand history cannot be deleted');

-- ===== using the whole balance converts it; nothing left afterwards =====
select tests.as_user(:dir);
select public.raise_demand(:bk, 310000000, 'Final payment', 14, null, null, null, 'rq-3') as d3 \gset
select tests.eq((select count(*) from booking_payment_milestones where booking_id=:bk and is_pool)::int, 0, 'balance fully used: no placeholder left');
select tests.eq((select count(*) from booking_payment_milestones where booking_id=:bk)::int, 4, 'whole balance became the last demand (no extra row)');
select tests.eq((select sum(amount_paise) from booking_payment_milestones where booking_id=:bk)::bigint, 600000000::bigint, 'schedule still totals the contract value');
select tests.expect_fail(format($$select public.raise_demand(%L, 100, 'x')$$, :bk), 'nothing left to ask for afterwards');
\echo ALL PHASE 7 DB TESTS PASSED
