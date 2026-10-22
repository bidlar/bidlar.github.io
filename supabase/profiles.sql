-- Public author names and avatars, derived only from GitHub OAuth identities.
-- Run as the project database administrator in Supabase SQL Editor.
-- Safe to rerun. Does not alter comments, bookmarks, or moderation policies.
begin;

create schema if not exists community_private;
revoke all on schema community_private from public, anon, authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'GitHub member'
    check (char_length(display_name) between 1 and 100),
  avatar_url text
    check (
      avatar_url is null or
      avatar_url ~ '^https://avatars[.]githubusercontent[.]com/u/[0-9]+([?]v=[0-9]+)?$'
    )
);
comment on table public.profiles is
  'Public GitHub author identity: names and avatars only; written by Auth identity triggers.';

alter table public.profiles enable row level security;
revoke all on public.profiles from public, anon, authenticated;
revoke all (id, display_name, avatar_url) on public.profiles
  from public, anon, authenticated;
-- Column grants intentionally avoid exposing future columns by accident.
grant select (id, display_name, avatar_url) on public.profiles to anon, authenticated;

drop policy if exists "Public author profiles" on public.profiles;
create policy "Public author profiles" on public.profiles
  for select to anon, authenticated using (true);
-- These boundaries also defeat older permissive write policies, if present.
drop policy if exists "No client profile inserts" on public.profiles;
create policy "No client profile inserts" on public.profiles
  as restrictive for insert to anon, authenticated with check (false);
drop policy if exists "No client profile updates" on public.profiles;
create policy "No client profile updates" on public.profiles
  as restrictive for update to anon, authenticated using (false) with check (false);
drop policy if exists "No client profile deletes" on public.profiles;
create policy "No client profile deletes" on public.profiles
  as restrictive for delete to anon, authenticated using (false);

create or replace function community_private.refresh_github_profile(subject_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  identity_payload jsonb;
  field_name text;
  safe_name text := 'GitHub member';
  candidate_name text;
  safe_avatar text;
begin
  if subject_id is null then
    return;
  end if;

  -- Serialize link/unlink/login refreshes for the same Auth account.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(subject_id::text, 78622)
  );

  -- Use Auth-managed GitHub identity data, never client-editable user_metadata.
  -- A user can have multiple linked identities; choose a deterministic GitHub one.
  select i.identity_data into identity_payload
    from auth.identities i
    join auth.users u on u.id = i.user_id
    where i.user_id = subject_id and i.provider = 'github'
    order by i.updated_at desc nulls last, i.created_at desc nulls last, i.id
    limit 1;

  if not found then
    delete from public.profiles where id = subject_id;
    return;
  end if;

  foreach field_name in array array['full_name', 'name', 'user_name', 'preferred_username']
  loop
    if pg_catalog.jsonb_typeof(identity_payload -> field_name) = 'string' then
      candidate_name := pg_catalog.btrim(pg_catalog.regexp_replace(
        identity_payload ->> field_name, '[[:cntrl:]]', ' ', 'g'
      ));
      if candidate_name <> '' then
        safe_name := pg_catalog.left(candidate_name, 100);
        exit;
      end if;
    end if;
  end loop;

  -- Only GitHub's avatar host and user-image path are published.
  -- Unsupported/missing URLs become null so the page can show initials.
  safe_avatar := identity_payload ->> 'avatar_url';
  if safe_avatar is null or safe_avatar !~
    '^https://avatars[.]githubusercontent[.]com/u/[0-9]+([?]v=[0-9]+)?$' then
    safe_avatar := null;
  end if;

  insert into public.profiles (id, display_name, avatar_url)
    values (subject_id, safe_name, safe_avatar)
    on conflict (id) do update
      set display_name = excluded.display_name,
          avatar_url = excluded.avatar_url;
end;
$$;
revoke all on function community_private.refresh_github_profile(uuid)
  from public, anon, authenticated;

create or replace function community_private.sync_github_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_user_id uuid;
  next_user_id uuid;
  subject_id uuid;
begin
  if tg_op <> 'INSERT' and old.provider = 'github' then
    prior_user_id := old.user_id;
  end if;
  if tg_op <> 'DELETE' and new.provider = 'github' then
    next_user_id := new.user_id;
  end if;

  -- Sorted locks also cover administrative reassignment of an identity.
  for subject_id in
    select distinct candidate_id
      from pg_catalog.unnest(array[prior_user_id, next_user_id]) as candidates(candidate_id)
      where candidate_id is not null
      order by candidate_id
  loop
    perform community_private.refresh_github_profile(subject_id);
  end loop;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke all on function community_private.sync_github_profile()
  from public, anon, authenticated;

-- Only this application's trigger is replaced. Auth rows/schema are untouched.
drop trigger if exists npu_sync_github_profile on auth.identities;
create trigger npu_sync_github_profile
  after insert or update or delete on auth.identities
  for each row execute function community_private.sync_github_profile();

-- Backfill existing users and remove stale profiles on a repeated migration.
do $$
declare
  subject_id uuid;
begin
  for subject_id in
    select candidate_id from (
      select user_id as candidate_id from auth.identities where provider = 'github'
      union
      select id as candidate_id from public.profiles
    ) as subjects
    order by candidate_id
  loop
    perform community_private.refresh_github_profile(subject_id);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
