-- Riverdale Villas — Phase 6 / 009: safe CSV import for villas and customers.
-- Rules: Director only. All-or-nothing: if ANY row has a problem nothing is saved and every problem is listed.
-- Existing records are NEVER overwritten: rows that already exist are skipped and reported.
-- Bookings, payments and schedules are deliberately NOT importable (money records must be created one by one, with checks).

create function public.normalize_phone(p text) returns text language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p, ''), '[\s-]', '', 'g');
begin
  if d ~ '^[6-9]\d{9}$' then return '+91' || d; end if;
  if d ~ '^\+?(91|0)[6-9]\d{9}$' then return '+91' || right(regexp_replace(d, '^\+', ''), 10); end if;
  if d ~ '^\+[1-9]\d{7,14}$' then return d; end if;
  return null;
end $$;

create function public.parse_inr_paise(p text) returns bigint language plpgsql immutable as $$
declare s text := regexp_replace(coalesce(p, ''), '[,\s₹]', '', 'g');
begin
  if s !~ '^\d+(\.\d{1,2})?$' then return null; end if;
  return (s::numeric * 100)::bigint;       -- exact decimal arithmetic, no floating point
end $$;

create function public.import_villas(p_rows jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; i int; msgs text[]; errs jsonb := '[]'; dups jsonb := '[]'; seen text[] := '{}'; k text; price bigint; proj uuid; vid uuid; ins int := 0; d date;
begin
  perform public.require_role('director');
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'The file has no rows'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'At most 500 rows can be imported at a time'; end if;
  i := 0;
  for r in select value from jsonb_array_elements(p_rows) loop
    i := i + 1; msgs := '{}';
    if trim(coalesce(r ->> 'project', '')) = '' then msgs := msgs || 'project is required'::text; end if;
    if trim(coalesce(r ->> 'villa_number', '')) = '' then msgs := msgs || 'villa_number is required'::text; end if;
    price := public.parse_inr_paise(r ->> 'list_price_inr');
    if price is null or price <= 0 then msgs := msgs || 'list_price_inr must be a positive amount in rupees'::text; end if;
    if trim(coalesce(r ->> 'land_area', '')) <> '' and (r ->> 'land_area' !~ '^\d+(\.\d+)?$' or (r ->> 'land_area')::numeric <= 0) then msgs := msgs || 'land_area must be a positive number'::text; end if;
    if trim(coalesce(r ->> 'expected_completion', '')) <> '' then
      begin d := (r ->> 'expected_completion')::date; if r ->> 'expected_completion' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'x'; end if;
      exception when others then msgs := msgs || 'expected_completion must be a real date like 2027-12-31'::text; end;
    end if;
    k := lower(trim(coalesce(r ->> 'project', ''))) || '|' || lower(trim(coalesce(r ->> 'villa_number', '')));
    if k = any(seen) then msgs := msgs || 'this villa appears twice in the file'::text; end if;
    seen := seen || k;
    if array_length(msgs, 1) > 0 then errs := errs || jsonb_build_object('row', i, 'problems', to_jsonb(msgs)); end if;
  end loop;
  if jsonb_array_length(errs) > 0 then return jsonb_build_object('ok', false, 'errors', errs); end if;

  i := 0;
  for r in select value from jsonb_array_elements(p_rows) loop
    i := i + 1;
    select id into proj from projects where lower(name) = lower(trim(r ->> 'project'));
    if proj is null then insert into projects(name) values (trim(r ->> 'project')) returning id into proj; end if;
    if exists (select 1 from villas where project_id = proj and lower(villa_number) = lower(trim(r ->> 'villa_number'))) then
      dups := dups || jsonb_build_object('row', i, 'reason', 'villa already exists - left unchanged'); continue;
    end if;
    insert into villas(project_id, villa_number, configuration, plot_details, land_area, land_unit, expected_completion)
      values (proj, trim(r ->> 'villa_number'), nullif(trim(r ->> 'configuration'), ''), nullif(trim(r ->> 'plot_details'), ''),
              nullif(trim(r ->> 'land_area'), '')::numeric, coalesce(nullif(trim(r ->> 'land_unit'), ''), 'katha'), nullif(trim(r ->> 'expected_completion'), '')::date)
      returning id into vid;
    insert into villa_pricing(villa_id, list_price_paise) values (vid, public.parse_inr_paise(r ->> 'list_price_inr'));
    ins := ins + 1;
  end loop;
  perform public.write_audit('import_villas', 'villas', null, jsonb_build_object('inserted', ins, 'skipped', jsonb_array_length(dups)));
  return jsonb_build_object('ok', true, 'inserted', ins, 'duplicates', dups);
end $$;

create function public.import_customers(p_rows jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; i int; msgs text[]; errs jsonb := '[]'; dups jsonb := '[]'; seen text[] := '{}'; ph text; cid uuid; ins int := 0; consent boolean; pan text;
begin
  perform public.require_role('director');
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'The file has no rows'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'At most 500 rows can be imported at a time'; end if;
  i := 0;
  for r in select value from jsonb_array_elements(p_rows) loop
    i := i + 1; msgs := '{}';
    if trim(coalesce(r ->> 'full_name', '')) = '' then msgs := msgs || 'full_name is required'::text; end if;
    ph := public.normalize_phone(r ->> 'phone');
    if ph is null then msgs := msgs || 'phone is not a valid mobile number'::text; elsif ph = any(seen) then msgs := msgs || 'this phone number appears twice in the file'::text; end if;
    seen := seen || coalesce(ph, '');
    if trim(coalesce(r ->> 'alt_phone', '')) <> '' and public.normalize_phone(r ->> 'alt_phone') is null then msgs := msgs || 'alt_phone is not valid'::text; end if;
    if trim(coalesce(r ->> 'email', '')) <> '' and (r ->> 'email') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then msgs := msgs || 'email is not valid'::text; end if;
    if trim(coalesce(r ->> 'pan', '')) <> '' and upper(trim(r ->> 'pan')) !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' then msgs := msgs || 'pan must look like ABCDE1234F'::text; end if;
    if lower(trim(coalesce(r ->> 'whatsapp_consent', ''))) not in ('', 'yes', 'no', 'y', 'n', 'true', 'false') then msgs := msgs || 'whatsapp_consent must be yes or no'::text; end if;
    if array_length(msgs, 1) > 0 then errs := errs || jsonb_build_object('row', i, 'problems', to_jsonb(msgs)); end if;
  end loop;
  if jsonb_array_length(errs) > 0 then return jsonb_build_object('ok', false, 'errors', errs); end if;

  i := 0;
  for r in select value from jsonb_array_elements(p_rows) loop
    i := i + 1; ph := public.normalize_phone(r ->> 'phone');
    if exists (select 1 from customers where phone = ph) then dups := dups || jsonb_build_object('row', i, 'reason', 'a customer with this phone already exists - left unchanged'); continue; end if;
    consent := lower(trim(coalesce(r ->> 'whatsapp_consent', ''))) in ('yes', 'y', 'true');
    insert into customers(full_name, phone, alt_phone, email, address, notes, whatsapp_opt_in, whatsapp_opt_in_at)
      values (trim(r ->> 'full_name'), ph, public.normalize_phone(r ->> 'alt_phone'), nullif(trim(r ->> 'email'), ''), nullif(trim(r ->> 'address'), ''), nullif(trim(r ->> 'notes'), ''), consent, case when consent then now() end)
      returning id into cid;
    pan := upper(trim(coalesce(r ->> 'pan', '')));
    if pan <> '' then insert into customer_sensitive(customer_id, pan) values (cid, pan); end if;
    ins := ins + 1;
  end loop;
  perform public.write_audit('import_customers', 'customers', null, jsonb_build_object('inserted', ins, 'skipped', jsonb_array_length(dups)));
  return jsonb_build_object('ok', true, 'inserted', ins, 'duplicates', dups);
end $$;

revoke execute on function public.normalize_phone(text), public.parse_inr_paise(text), public.import_villas(jsonb), public.import_customers(jsonb) from public, anon;
grant execute on function public.import_villas(jsonb), public.import_customers(jsonb) to authenticated;
