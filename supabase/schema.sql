-- Compatible with the schema provided in this tutorial. Preserves existing data.
begin;
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  page_id text not null check (char_length(page_id) between 1 and 200),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists comments_page_time on public.comments(page_id, created_at);
create table if not exists public.bookmarks (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  page_id text not null check (char_length(page_id) between 1 and 200),
  created_at timestamptz not null default now(),
  primary key (user_id, page_id)
);
alter table public.comments enable row level security;
alter table public.bookmarks enable row level security;
revoke all on public.comments, public.bookmarks from anon, authenticated;
grant select on public.comments to anon;
grant select, insert, delete on public.comments, public.bookmarks to authenticated;
drop policy if exists "Public comments" on public.comments;
create policy "Public comments" on public.comments for select to anon, authenticated using (true);
drop policy if exists "Create own comments" on public.comments;
create policy "Create own comments" on public.comments for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Delete own comments" on public.comments;
create policy "Delete own comments" on public.comments for delete to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Read own bookmarks" on public.bookmarks;
create policy "Read own bookmarks" on public.bookmarks for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Create own bookmarks" on public.bookmarks;
create policy "Create own bookmarks" on public.bookmarks for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Delete own bookmarks" on public.bookmarks;
create policy "Delete own bookmarks" on public.bookmarks for delete to authenticated using ((select auth.uid()) = user_id);


-- Moderation, bans, and per-account submission limits.


alter table public.comments
  add column if not exists status text not null default 'pending';
alter table public.comments alter column status set default 'pending';
alter table public.comments drop constraint if exists comments_status_check;
alter table public.comments add constraint comments_status_check
  check (status in ('pending', 'approved', 'rejected'));
create index if not exists comments_review_queue on public.comments(status, created_at);

-- Only database administrators can view or edit this table.
create table if not exists public.comment_bans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text not null default '',
  created_at timestamptz not null default now()
);
alter table public.comment_bans enable row level security;
revoke all on public.comment_bans from public, anon, authenticated;

-- Separate submission history survives deletion of a comment.
create schema if not exists community_private;
revoke all on schema community_private from public, anon, authenticated;
create table if not exists community_private.comment_submissions (
  comment_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  submitted_at timestamptz not null
);
create index if not exists comment_submissions_user_time
  on community_private.comment_submissions(user_id, submitted_at);
alter table community_private.comment_submissions enable row level security;
revoke all on community_private.comment_submissions from public, anon, authenticated;

insert into community_private.comment_submissions(comment_id, user_id, submitted_at)
select id, user_id, created_at from public.comments
where created_at > now() - interval '24 hours'
on conflict (comment_id) do nothing;

create or replace function community_private.guard_comment_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  submitted_time timestamptz;
begin
  -- SQL Editor/service-role administrators remain able to import and moderate data.
  if auth.role() = 'authenticated' then
    if actor is null or new.user_id is distinct from actor then
      raise exception using errcode = '42501', message = 'COMMENT_IDENTITY_INVALID';
    end if;

    -- Serialize concurrent submissions by the same account, across all pages.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text, 78621));
    submitted_time := pg_catalog.clock_timestamp();

    if exists (select 1 from public.comment_bans where user_id = actor) then
      raise exception using errcode = 'P0001', message = 'COMMENT_BANNED';
    end if;
    if exists (
      select 1 from community_private.comment_submissions
      where user_id = actor and submitted_at > submitted_time - interval '60 seconds'
    ) then
      raise exception using errcode = 'P0001', message = 'COMMENT_RATE_MINUTE';
    end if;
    if (select count(*) from community_private.comment_submissions
        where user_id = actor and submitted_at > submitted_time - interval '24 hours') >= 10 then
      raise exception using errcode = 'P0001', message = 'COMMENT_RATE_DAY';
    end if;

    new.status := 'pending';
    new.created_at := submitted_time;
    insert into community_private.comment_submissions(comment_id, user_id, submitted_at)
      values (new.id, actor, submitted_time);
  end if;
  return new;
end;
$$;
revoke all on function community_private.guard_comment_insert() from public, anon, authenticated;
drop trigger if exists guard_comment_insert on public.comments;
create trigger guard_comment_insert before insert on public.comments
  for each row execute function community_private.guard_comment_insert();

alter table public.comments enable row level security;
revoke all on public.comments from public, anon, authenticated;
-- Clear any pre-existing column grants too, before allowing only page_id/content inserts.
revoke all (id, page_id, user_id, content, created_at, status)
  on public.comments from public, anon, authenticated;
grant select on public.comments to anon, authenticated;
grant delete on public.comments to authenticated;
grant insert (page_id, content) on public.comments to authenticated;

drop policy if exists "Public comments" on public.comments;
drop policy if exists "Create own comments" on public.comments;
drop policy if exists "Delete own comments" on public.comments;
drop policy if exists "Moderated comment reads" on public.comments;
drop policy if exists "Comment visibility boundary" on public.comments;
drop policy if exists "Pending own comments" on public.comments;
drop policy if exists "Comment insert boundary" on public.comments;
drop policy if exists "Comment delete boundary" on public.comments;
drop policy if exists "No client moderation" on public.comments;

create policy "Moderated comment reads" on public.comments for select
  to anon, authenticated using (status = 'approved' or user_id = (select auth.uid()));
-- Restrictive boundaries also protect against older permissive policies still present.
create policy "Comment visibility boundary" on public.comments as restrictive for select
  to anon, authenticated using (status = 'approved' or user_id = (select auth.uid()));
create policy "Pending own comments" on public.comments for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');
create policy "Comment insert boundary" on public.comments as restrictive for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');
create policy "Delete own comments" on public.comments for delete to authenticated
  using (user_id = (select auth.uid()));
create policy "Comment delete boundary" on public.comments as restrictive for delete to authenticated
  using (user_id = (select auth.uid()));
create policy "No client moderation" on public.comments as restrictive for update to authenticated
  using (false) with check (false);

commit;
