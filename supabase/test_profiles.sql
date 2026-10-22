-- Integration checks AFTER profiles.sql, in an isolated Supabase test project.
-- Run the WHOLE file as postgres. Test users, identities and grants roll back.
-- If the session is left aborted by a failure, execute ROLLBACK.
begin;
select set_config('npu_profiles_test.user_a', gen_random_uuid()::text, true);
select set_config('npu_profiles_test.user_b', gen_random_uuid()::text, true);
select set_config('npu_profiles_test.identity_a', gen_random_uuid()::text, true);
select set_config('npu_profiles_test.identity_b', gen_random_uuid()::text, true);

insert into auth.users (id, raw_user_meta_data) values
  (current_setting('npu_profiles_test.user_a')::uuid, '{"name":"Forged metadata name"}'),
  (current_setting('npu_profiles_test.user_b')::uuid, '{"name":"Not a GitHub identity"}');
insert into auth.identities (id, provider_id, user_id, provider, identity_data, created_at, updated_at)
values
  (current_setting('npu_profiles_test.identity_a')::uuid,
   'npu-test-' || current_setting('npu_profiles_test.identity_a'),
   current_setting('npu_profiles_test.user_a')::uuid, 'github',
   '{"name":"GitHub Alice","preferred_username":"github-alice","avatar_url":"https://avatars.githubusercontent.com/u/123?v=4","email":"private@example.invalid","access_token":"NEVER-PUBLISH"}',
   now(), now()),
  (current_setting('npu_profiles_test.identity_b')::uuid,
   'npu-test-' || current_setting('npu_profiles_test.identity_b'),
   current_setting('npu_profiles_test.user_b')::uuid, 'email',
   '{"name":"Email User","email":"private@example.invalid"}',
   now(), now());

do $$ begin
  if (select display_name from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 'GitHub Alice' then
    raise exception 'FAIL: GitHub identity insertion did not create the provider name';
  end if;
  if (select avatar_url from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 'https://avatars.githubusercontent.com/u/123?v=4' then
    raise exception 'FAIL: valid GitHub avatar was not copied';
  end if;
  if exists (select 1 from public.profiles where id = current_setting('npu_profiles_test.user_b')::uuid) then
    raise exception 'FAIL: email identity created a GitHub profile';
  end if;
  if exists (
    select 1 from information_schema.columns where table_schema = 'public'
    and table_name = 'profiles' and column_name not in ('id', 'display_name', 'avatar_url')
  ) then
    raise exception 'FAIL: public profiles unexpectedly contains other data columns';
  end if;
end $$;

update auth.users set raw_user_meta_data = '{"name":"Client impersonation","avatar_url":"https://evil.invalid/pixel"}'
where id = current_setting('npu_profiles_test.user_a')::uuid;
do $$ begin
  if (select display_name from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 'GitHub Alice' then
    raise exception 'FAIL: client-editable user metadata influenced public identity';
  end if;
end $$;

-- Trigger execution must work for the Auth role even though API users cannot call it.
set local role supabase_auth_admin;
update auth.identities set identity_data = '{"name":"Updated by Auth","avatar_url":"https://avatars.githubusercontent.com.evil.invalid/u/123?v=4"}'
where id = current_setting('npu_profiles_test.identity_a')::uuid;
reset role;
do $$ begin
  if (select display_name from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 'Updated by Auth' then
    raise exception 'FAIL: Auth role could not refresh the public profile';
  end if;
  if (select avatar_url from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid) is not null then
    raise exception 'FAIL: non-GitHub avatar host was accepted';
  end if;
end $$;

update auth.identities set identity_data = '{"name":"  ","full_name":{},"preferred_username":"fallback-user","avatar_url":"javascript:alert(1)"}'
where id = current_setting('npu_profiles_test.identity_a')::uuid;
do $$ begin
  if (select display_name from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 'fallback-user' then
    raise exception 'FAIL: username fallback is incorrect';
  end if;
  if (select avatar_url from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid) is not null then
    raise exception 'FAIL: unsafe avatar scheme was accepted';
  end if;
end $$;
update auth.identities set identity_data = '{"email":"private@example.invalid","name":null}'
where id = current_setting('npu_profiles_test.identity_a')::uuid;
do $$ begin
  if (select display_name from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 'GitHub member' then
    raise exception 'FAIL: missing name must use a generic name, never email';
  end if;
end $$;
update auth.identities set identity_data = jsonb_build_object('name', repeat('n', 150))
where id = current_setting('npu_profiles_test.identity_a')::uuid;
do $$ begin
  if (select char_length(display_name) from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 100 then
    raise exception 'FAIL: long name was not safely truncated';
  end if;
end $$;

set local role anon;
do $$ begin
  if not exists (select id, display_name, avatar_url from public.profiles
                 where id = current_setting('npu_profiles_test.user_a')::uuid) then
    raise exception 'FAIL: anonymous user cannot read the public profile';
  end if;
  begin
    insert into public.profiles (id, display_name)
      values (current_setting('npu_profiles_test.user_b')::uuid, 'Forged');
    raise exception 'FAIL: anonymous profile insertion was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform community_private.refresh_github_profile(current_setting('npu_profiles_test.user_b')::uuid);
    raise exception 'FAIL: anonymous user invoked the private refresh function';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

select set_config('request.jwt.claim.sub', current_setting('npu_profiles_test.user_a'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('npu_profiles_test.user_a'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin
  if not exists (select id, display_name, avatar_url from public.profiles
                 where id = current_setting('npu_profiles_test.user_a')::uuid) then
    raise exception 'FAIL: authenticated user cannot read public profiles';
  end if;
  begin
    insert into public.profiles (id, display_name)
      values (current_setting('npu_profiles_test.user_b')::uuid, 'Forged author');
    raise exception 'FAIL: authenticated user inserted another profile';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.profiles set display_name = 'Forged'
      where id = current_setting('npu_profiles_test.user_a')::uuid;
    raise exception 'FAIL: authenticated profile update was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid;
    raise exception 'FAIL: authenticated profile deletion was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform community_private.refresh_github_profile(current_setting('npu_profiles_test.user_b')::uuid);
    raise exception 'FAIL: authenticated user invoked the private refresh function';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Restrictive policies still protect identities if an old permissive policy exists.
grant insert, update, delete on public.profiles to authenticated;
create policy "npu_temporary_profile_write_policy" on public.profiles
  for all to authenticated using (true) with check (true);
set local role authenticated;
do $$ begin
  begin
    insert into public.profiles (id, display_name)
      values (current_setting('npu_profiles_test.user_b')::uuid, 'Forged author');
    raise exception 'FAIL: permissive policy bypassed profile INSERT boundary';
  exception when insufficient_privilege then null;
  end;
  update public.profiles set display_name = 'Forged'
    where id = current_setting('npu_profiles_test.user_a')::uuid;
  if found then raise exception 'FAIL: permissive policy bypassed profile UPDATE boundary'; end if;
  delete from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid;
  if found then raise exception 'FAIL: permissive policy bypassed profile DELETE boundary'; end if;
end $$;
reset role;
revoke insert, update, delete on public.profiles from authenticated;
drop policy "npu_temporary_profile_write_policy" on public.profiles;

-- Multiple linked GitHub identities select the latest and fall back on unlink.
update auth.identities set provider = 'github',
  identity_data = '{"name":"Second GitHub identity"}',
  user_id = current_setting('npu_profiles_test.user_a')::uuid,
  updated_at = now() + interval '1 second'
where id = current_setting('npu_profiles_test.identity_b')::uuid;
do $$ begin
  if (select display_name from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from 'Second GitHub identity' then
    raise exception 'FAIL: latest linked GitHub identity not selected';
  end if;
end $$;
delete from auth.identities where id = current_setting('npu_profiles_test.identity_b')::uuid;
do $$ begin
  if (select display_name from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid)
     is distinct from repeat('n', 100) then
    raise exception 'FAIL: unlink did not fall back to remaining GitHub identity';
  end if;
end $$;
delete from auth.identities where id = current_setting('npu_profiles_test.identity_a')::uuid;
do $$ begin
  if exists (select 1 from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid) then
    raise exception 'FAIL: profile remains after removing last GitHub identity';
  end if;
  if not exists (select 1 from auth.users where id = current_setting('npu_profiles_test.user_a')::uuid) then
    raise exception 'FAIL: profile cleanup removed an Auth user';
  end if;
end $$;
insert into auth.identities (id, provider_id, user_id, provider, identity_data)
values (current_setting('npu_profiles_test.identity_a')::uuid,
        'npu-test-' || current_setting('npu_profiles_test.identity_a'),
        current_setting('npu_profiles_test.user_a')::uuid,
        'github', '{"name":"Relinked"}');
delete from auth.users where id = current_setting('npu_profiles_test.user_a')::uuid;
do $$ begin
  if exists (select 1 from public.profiles where id = current_setting('npu_profiles_test.user_a')::uuid) then
    raise exception 'FAIL: deleting Auth user did not remove public profile';
  end if;
end $$;
rollback;
select 'Public profile integration checks passed; all test changes rolled back.' as result;
