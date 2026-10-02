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
grant execute on all functions in schema tests to authenticated;
