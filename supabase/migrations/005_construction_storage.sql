-- Riverdale Villas — Phase 3 / 005: construction extras + private photo storage.
-- Run once in the Supabase SQL Editor AFTER 001-004.

-- Which stage means "the villa is handed over" is a Director setting, not a hard-coded name.
alter table construction_stages add column is_handover boolean not null default false;
update construction_stages set is_handover = true where name = 'Handover completed';

-- Villa status follows construction: first update on a booked villa -> under construction;
-- completed + approved handover stage -> handed over (and a handover_completed event for Phase 5).
create function public.trg_construction_villa_status() returns trigger language plpgsql security definer set search_path = public as $$
declare ho boolean;
begin
  update villas set status = 'under_construction' where id = new.villa_id and status = 'booked';
  if new.new_status = 'completed' and new.approval in ('approved','not_required')
     and (tg_op = 'INSERT' or old.approval is distinct from new.approval) then
    select is_handover into ho from construction_stages where id = new.stage_id;
    if ho then
      update villas set status = 'handed_over', actual_completion = coalesce(actual_completion, current_date) where id = new.villa_id;
      perform public.emit_event('handover_completed:' || new.villa_id, 'handover_completed', new.booking_id, jsonb_build_object('villa_id', new.villa_id));
    end if;
  end if;
  return new;
end $$;
create trigger construction_villa_status after insert or update of approval on construction_updates
  for each row execute function public.trg_construction_villa_status();

-- A photo row must point inside its own villa's folder (folder name = villa id).
create function public.trg_photo_path_check() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if split_part(new.storage_path, '/', 1) is distinct from (select villa_id::text from construction_updates where id = new.update_id) then
    raise exception 'Photo path must start with the villa id';
  end if;
  return new;
end $$;
create trigger photo_path_check before insert on construction_update_photos for each row execute function public.trg_photo_path_check();

-- Storage: private bucket, folder per villa. Directors: everything. Site Manager: upload to / view own villas.
-- Salesperson: view photos of villas assigned to them. No update/delete policy exists, so photos can never be changed or removed.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('construction-photos', 'construction-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create function public.can_access_villa_folder(p_path text, p_write boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.app_role() is null then false
    when public.app_role() = 'director' then true
    when p_write then public.app_role() = 'site_manager' and exists (
      select 1 from villas v where v.id::text = (string_to_array(p_path, '/'))[1] and v.site_manager_id = auth.uid())
    else exists (select 1 from villas v where v.id::text = (string_to_array(p_path, '/'))[1]
      and (v.site_manager_id = auth.uid() or v.salesperson_id = auth.uid()))
  end $$;
revoke execute on function public.can_access_villa_folder(text, boolean), public.trg_construction_villa_status(), public.trg_photo_path_check() from public, anon;
grant execute on function public.can_access_villa_folder(text, boolean) to authenticated;

create policy construction_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'construction-photos' and public.can_access_villa_folder(name, false));
create policy construction_photos_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'construction-photos' and public.can_access_villa_folder(name, true));
