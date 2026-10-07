-- TEST ONLY: imitates the parts of Supabase that migrations depend on. Never run on a real Supabase project.
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
create schema tests;
grant usage on schema tests to authenticated;
create function tests.as_user(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u::text, false); perform set_config('role', 'authenticated', false); end $$;
create function tests.as_admin() returns void language plpgsql as $$
begin perform set_config('role', 'postgres', false); perform set_config('request.jwt.claim.sub', '', false); end $$;
create function tests.eq(actual anyelement, expected anyelement, name text) returns void language plpgsql as $$
begin
  if actual is not distinct from expected then raise notice 'PASS: %', name;
  else raise exception 'FAIL: % (expected %, got %)', name, expected, actual; end if;
end $$;
create function tests.expect_fail(q text, name text) returns void language plpgsql as $$
declare failed boolean := false;
begin
  begin execute q; exception when others then failed := true; end;
  if failed then raise notice 'PASS: %', name; else raise exception 'FAIL: % (expected an error, got none)', name; end if;
end $$;
create function tests.pass(name text) returns void language plpgsql as $$ begin raise notice 'PASS: %', name; end $$;
grant execute on all functions in schema tests to authenticated;

-- storage imitation (test only)
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'),1)-1] $$;
grant usage on schema storage to authenticated;
grant select, insert on storage.objects to authenticated;

grant execute on all functions in schema tests to authenticated;
