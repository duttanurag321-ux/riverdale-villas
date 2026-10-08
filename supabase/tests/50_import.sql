\set ON_ERROR_STOP on
\set dir '''d0000000-0000-0000-0000-000000000001'''
\set sm  '''a0000000-0000-0000-0000-000000000002'''
\set sal '''b0000000-0000-0000-0000-000000000003'''

select tests.as_admin();
select tests.eq(public.normalize_phone('90000-00101'), '+919000000101', 'phone: 10 digits');
select tests.eq(public.normalize_phone('+91 90000 00101'), '+919000000101', 'phone: +91 with spaces');
select tests.eq(public.normalize_phone('09000000101'), '+919000000101', 'phone: leading zero');
select tests.eq(public.normalize_phone('12345'), null, 'phone: junk rejected');
select tests.eq(public.parse_inr_paise('60,00,000'), 600000000::bigint, 'amount: Indian commas');
select tests.eq(public.parse_inr_paise('₹5500000.50'), 550000050::bigint, 'amount: rupee sign and paise');
select tests.eq(public.parse_inr_paise('12.345'), null, 'amount: three decimals rejected');

select tests.as_user(:sal);
select tests.expect_fail($$select public.import_villas('[{"project":"X","villa_number":"1","list_price_inr":"1"}]')$$, 'salesperson cannot import villas');
select tests.expect_fail($$select public.import_customers('[{"full_name":"X","phone":"9000000199"}]')$$, 'salesperson cannot import customers');
select tests.as_user(:sm);
select tests.expect_fail($$select public.import_villas('[{"project":"X","villa_number":"1","list_price_inr":"1"}]')$$, 'site manager cannot import');

select tests.as_user(:dir);
select (public.import_villas('[{"project":"Import Project (TEST)","villa_number":"I1","configuration":"2 BHK","land_area":"3","land_unit":"katha","list_price_inr":"60,00,000","expected_completion":"2027-12-31"},
  {"project":"Import Project (TEST)","villa_number":"I2","list_price_inr":"5500000.50"}]'))->>'inserted' as ins \gset
select tests.eq(:'ins'::int, 2, 'two villas imported');
select tests.eq((select list_price_paise from villa_pricing p join villas v on v.id=p.villa_id where v.villa_number='I1'), 600000000::bigint, 'price stored in paise');
select tests.eq((select list_price_paise from villa_pricing p join villas v on v.id=p.villa_id where v.villa_number='I2'), 550000050::bigint, 'paise preserved');
select jsonb_array_length((public.import_villas('[{"project":"import project (test)","villa_number":"i1","list_price_inr":"1"}]'))->'duplicates') as nd \gset
select tests.eq(:'nd'::int, 1, 're-import is reported as duplicate');
select tests.eq((select list_price_paise from villa_pricing p join villas v on v.id=p.villa_id where v.villa_number='I1'), 600000000::bigint, 'existing villa price NOT overwritten');
select jsonb_array_length((public.import_villas('[{"project":"Brand New Project","villa_number":"I9","list_price_inr":"abc"},{"project":"Brand New Project","villa_number":"I8","list_price_inr":"100","expected_completion":"31-12-2027"},{"project":"","villa_number":"I7","list_price_inr":"1"}]'))->'errors') as ne \gset
select tests.eq(:'ne'::int, 3, 'every bad row is reported');
select tests.eq((select count(*) from projects where name='Brand New Project')::int, 0, 'nothing saved when any row is bad (project not created)');
select tests.eq((select (public.import_villas('[{"project":"P","villa_number":"Z1","list_price_inr":"1"},{"project":"p","villa_number":"z1","list_price_inr":"1"}]'))->>'ok'), 'false', 'same villa twice in one file is an error');
select tests.expect_fail($$select public.import_villas('[]')$$, 'empty file refused');
select tests.expect_fail($$select public.import_customers((select jsonb_agg(jsonb_build_object('full_name','n'||g,'phone','9000100000')) from generate_series(1,501) g))$$, 'more than 500 rows refused');

select (public.import_customers('[{"full_name":"Imported One","phone":"90000-00101","whatsapp_consent":"yes","pan":"abcde1234f","email":"one@example.test"},
  {"full_name":"Imported Two","phone":"+91 9000000102","whatsapp_consent":"no"}]'))->>'inserted' as ci \gset
select tests.eq(:'ci'::int, 2, 'two customers imported');
select tests.eq((select phone from customers where full_name='Imported One'), '+919000000101', 'imported phone normalised');
select tests.eq((select whatsapp_opt_in and whatsapp_opt_in_at is not null from customers where full_name='Imported One'), true, 'consent yes records opt-in time');
select tests.eq((select whatsapp_opt_in from customers where full_name='Imported Two'), false, 'consent no stays off');
select tests.eq((select pan from customer_sensitive s join customers c on c.id=s.customer_id where c.full_name='Imported One'), 'ABCDE1234F', 'PAN stored in the restricted table, upper-cased');
select jsonb_array_length((public.import_customers('[{"full_name":"Changed Name","phone":"9000000101"}]'))->'duplicates') as cd \gset
select tests.eq(:'cd'::int, 1, 'existing phone is reported as duplicate');
select tests.eq((select count(*) from customers where full_name='Changed Name')::int, 0, 'existing customer NOT overwritten');
select jsonb_array_length((public.import_customers('[{"full_name":"","phone":"123"},{"full_name":"A","phone":"9000000103","pan":"BAD"},{"full_name":"B","phone":"9000000104","email":"nope"},{"full_name":"C","phone":"9000000105","whatsapp_consent":"maybe"},{"full_name":"D","phone":"9000000105"}]'))->'errors') as ce \gset
select tests.eq(:'ce'::int, 5, 'all customer problems listed (blank name, bad phone, PAN, email, consent, repeated phone)');
select tests.eq((select count(*) from customers where phone in ('+919000000103','+919000000104','+919000000105'))::int, 0, 'nothing saved when any customer row is bad');
select tests.as_admin();
select tests.eq((select count(*) from audit_logs where action in ('import_villas','import_customers'))::int >= 2, true, 'imports are audited');
\echo ALL PHASE 6 DB TESTS PASSED
