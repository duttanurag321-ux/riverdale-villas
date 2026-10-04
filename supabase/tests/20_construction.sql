\set ON_ERROR_STOP on
\set dir  '''d0000000-0000-0000-0000-000000000001'''
\set sm   '''a0000000-0000-0000-0000-000000000002'''
\set sm2  '''a0000000-0000-0000-0000-000000000022'''
\set sal  '''b0000000-0000-0000-0000-000000000003'''
\set sal2 '''b0000000-0000-0000-0000-000000000004'''
\set v2   '''c0000000-0000-0000-0000-0000000000a2'''

select tests.as_admin();
insert into auth.users(id,email) values (:sm2,'sm2@example.test');
insert into profiles(id,full_name,role) values (:sm2,'Second Site Manager','site_manager');
insert into villas(id,project_id,villa_number,status,site_manager_id,salesperson_id)
  values (:v2,'c0000000-0000-0000-0000-000000000001','A2','booked',:sm,:sal);

-- === storage policies ===
select tests.as_user(:sm);
insert into storage.objects(bucket_id,name) values ('construction-photos','c0000000-0000-0000-0000-0000000000a2/req1/0.jpg');
select tests.pass('assigned site manager can upload into own villa folder');
select tests.expect_fail($$insert into storage.objects(bucket_id,name) values ('construction-photos','c0000000-0000-0000-0000-0000000000ff/req1/0.jpg')$$, 'cannot upload into an unknown/other villa folder');
select tests.as_user(:sm2);
select tests.expect_fail($$insert into storage.objects(bucket_id,name) values ('construction-photos','c0000000-0000-0000-0000-0000000000a2/x/0.jpg')$$, 'other site manager cannot upload to this villa');
select tests.eq((select count(*) from storage.objects)::int, 0, 'other site manager cannot see this villa photos');
select tests.as_user(:sal);
select tests.eq((select count(*) from storage.objects)::int, 1, 'assigned salesperson can view villa photos');
select tests.expect_fail($$insert into storage.objects(bucket_id,name) values ('construction-photos','c0000000-0000-0000-0000-0000000000a2/s/0.jpg')$$, 'salesperson cannot upload photos');
select tests.as_user(:sal2);
select tests.eq((select count(*) from storage.objects)::int, 0, 'unassigned salesperson cannot view photos');
select tests.as_user(:dir);
select tests.eq((select count(*) from storage.objects)::int, 1, 'director can view all photos');

-- === submit / reject / resubmit / approve ===
select id as plinth from construction_stages where name='Plinth completed' \gset
select id as handover from construction_stages where name='Handover completed' \gset
select id as prep from construction_stages where name='Site preparation' \gset
select tests.as_user(:sm);
select public.submit_construction_update(:v2, :'plinth', 'completed', 'plinth done', false, 'r-a') as u1 \gset
insert into construction_update_photos(update_id, storage_path) values (:'u1', 'c0000000-0000-0000-0000-0000000000a2/req1/0.jpg');
select tests.expect_fail(format($$insert into construction_update_photos(update_id, storage_path) values (%L, 'c0000000-0000-0000-0000-0000000000ff/req1/9.jpg')$$, :'u1'), 'photo path must stay inside the villa folder');
select tests.expect_fail($$select public.submit_construction_update('c0000000-0000-0000-0000-0000000000a2', (select id from construction_stages where name='Plinth completed'), 'completed', 'again', false, 'r-b')$$, 'second pending update for same stage is blocked');
select tests.eq((select status::text from villas where id=:v2), 'under_construction', 'first update moves a booked villa to under construction');
select tests.as_user(:sm2);
select tests.expect_fail(format($$select public.submit_construction_update(%L, %L, 'in_progress', null, false, 'r-c')$$, :v2, :'plinth'), 'unassigned site manager cannot submit for this villa');
select tests.eq((select count(*) from construction_updates)::int, 0, 'unassigned site manager cannot read updates');
select tests.as_user(:dir);
select tests.expect_fail(format($$select public.approve_construction_update(%L, false, null)$$, :'u1'), 'rejection requires a reason');
select public.approve_construction_update(:'u1', false, 'Photos are blurry');
select tests.eq((select approval::text from construction_updates where id=:'u1'), 'rejected', 'update rejected and preserved');
select tests.as_user(:sm);
select public.submit_construction_update(:v2, :'plinth', 'completed', 'plinth redone', false, 'r-d') as u2 \gset
select tests.eq((select count(*) from construction_updates where villa_id=:v2)::int, 2, 'rejected update kept, corrected submission added');
select tests.as_user(:dir);
select public.approve_construction_update(:'u2', true);
select tests.eq((select current_stage_id::text from villas where id=:v2), :'plinth', 'approval sets current stage');

-- non-approval stage completes immediately
select tests.as_user(:sm);
select public.submit_construction_update(:v2, :'prep', 'completed', 'site ready', false, 'r-e') as u3 \gset
select tests.eq((select approval::text from construction_updates where id=:'u3'), 'not_required', 'stage without approval needs none');

-- handover stage flips villa to handed over + event, only after approval
select public.submit_construction_update(:v2, :'handover', 'completed', 'keys handed', false, 'r-f') as u4 \gset
select tests.eq((select status::text from villas where id=:v2), 'under_construction', 'handover not final before approval');
select tests.as_user(:dir);
select public.approve_construction_update(:'u4', true);
select tests.eq((select status::text from villas where id=:v2), 'handed_over', 'approved handover marks villa handed over');
select tests.eq((select count(*) from domain_events where event_type='handover_completed')::int, 1, 'handover event recorded once');
select public.approve_construction_update(:'u4', true);
select tests.eq((select count(*) from domain_events where event_type='handover_completed')::int, 1, 'repeat approval does not duplicate handover event');

-- stage configuration is Director-only
update construction_stages set requires_approval = false where name='Excavation';
select tests.eq((select requires_approval from construction_stages where name='Excavation'), false, 'director can configure stage approval');
select tests.as_user(:sm);
update construction_stages set requires_approval = false where name='Foundation completed';
select tests.as_admin();
select tests.eq((select requires_approval from construction_stages where name='Foundation completed'), true, 'site manager cannot change stage settings');
\echo ALL PHASE 3 DB TESTS PASSED
