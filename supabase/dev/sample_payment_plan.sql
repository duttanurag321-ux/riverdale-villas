-- OPTIONAL, SAMPLE ONLY. Creates the illustrative 10/10/10/15/10/10/15/20 plan from the project brief
-- so you can try bookings before the Phase 4 plan-editor screen exists. Real percentages are the Director's to decide.
-- Run once in the Supabase SQL Editor AFTER migrations 001-004. Safe to delete afterwards.
with t as (
  insert into payment_plan_templates(name, villa_configuration) values ('SAMPLE 2 BHK plan (edit before real use)', '2 BHK') returning id)
insert into payment_plan_template_milestones(template_id, seq, name, kind, percent_bp, trigger, stage_id, due_days, grace_days)
select t.id, v.seq, v.name, 'percent', v.bp, v.trg::milestone_trigger, s.id, 7, 3
from t, (values (1,'Booking',1000,'booking_confirmed','Booking confirmed'),(2,'Foundation completed',1000,'stage_approved','Foundation completed'),
 (3,'Plinth completed',1000,'stage_approved','Plinth completed'),(4,'First slab completed',1500,'stage_approved','First slab / ceiling completed'),
 (5,'Brickwork completed',1000,'stage_approved','Brickwork completed'),(6,'Plastering completed',1000,'stage_approved','Plastering completed'),
 (7,'Flooring and fittings',1500,'stage_approved','Flooring and fittings'),(8,'Final completion / handover',2000,'stage_approved','Handover completed')
) v(seq,name,bp,trg,stg) join construction_stages s on s.name = v.stg;
