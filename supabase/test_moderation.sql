-- Optional integration checks AFTER moderation.sql, in a Supabase SQL Editor.
-- Run the WHOLE file together as postgres. All test records/policies roll back.
-- If an error leaves the session aborted, execute ROLLBACK before continuing.
begin;
select set_config('npu_test.actor_a', gen_random_uuid()::text, true);
select set_config('npu_test.actor_b', gen_random_uuid()::text, true);
select set_config('npu_test.page', 'test-' || gen_random_uuid()::text, true);
insert into auth.users(id) values
  (current_setting('npu_test.actor_a')::uuid),
  (current_setting('npu_test.actor_b')::uuid);

-- A leftover permissive policy must not defeat the restrictive boundary.
create policy "npu_temporary_test_allow_reads" on public.comments
  for select to anon, authenticated using (true);

select set_config('request.jwt.claim.sub', current_setting('npu_test.actor_a'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('npu_test.actor_a'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.comments(page_id, content) values (current_setting('npu_test.page'), 'Pending test comment');
do $$ begin
  if (select count(*) from public.comments where page_id = current_setting('npu_test.page') and status = 'pending') <> 1 then
    raise exception 'FAIL: author must see one pending comment';
  end if;
  begin
    update public.comments set status = 'approved' where page_id = current_setting('npu_test.page');
    -- Column-level SELECT/UPDATE restrictions may reject or RLS may filter all rows.
    if found then raise exception 'FAIL: author approved a comment'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.comments(page_id, content, status) values (current_setting('npu_test.page'), 'Forged approval', 'approved');
    raise exception 'FAIL: explicit status insert was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.comments(page_id, content, user_id) values (current_setting('npu_test.page'), 'Forged author', current_setting('npu_test.actor_b')::uuid);
    raise exception 'FAIL: explicit author insert was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select set_config('request.jwt.claim.sub', current_setting('npu_test.actor_b'), true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('npu_test.actor_b'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin
  if exists (select 1 from public.comments where page_id = current_setting('npu_test.page')) then
    raise exception 'FAIL: another user can read pending comments';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $$ begin
  if exists (select 1 from public.comments where page_id = current_setting('npu_test.page')) then
    raise exception 'FAIL: anonymous reader can see pending comments';
  end if;
  begin
    insert into public.comments(page_id, content) values (current_setting('npu_test.page'), 'Anonymous write');
    raise exception 'FAIL: anonymous comment was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
update public.comments set status = 'approved' where page_id = current_setting('npu_test.page');
set local role anon;
do $$ begin
  if (select count(*) from public.comments where page_id = current_setting('npu_test.page')) <> 1 then
    raise exception 'FAIL: approved comment should be public';
  end if;
end $$;
reset role;
update public.comments set status = 'rejected' where page_id = current_setting('npu_test.page');
set local role anon;
do $$ begin
  if exists (select 1 from public.comments where page_id = current_setting('npu_test.page')) then
    raise exception 'FAIL: rejected comment should not be public';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', current_setting('npu_test.actor_a'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('npu_test.actor_a'), 'role', 'authenticated')::text, true);
set local role authenticated;
delete from public.comments where page_id = current_setting('npu_test.page');
do $$ begin
  begin
    insert into public.comments(page_id, content) values (current_setting('npu_test.page'), 'Retry after deletion');
    raise exception 'FAIL: deletion bypassed the minute limit';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'COMMENT_RATE_MINUTE' then raise; end if;
  end;
  begin
    delete from community_private.comment_submissions;
    raise exception 'FAIL: user can clear rate history';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
delete from community_private.comment_submissions where user_id = current_setting('npu_test.actor_a')::uuid;
insert into community_private.comment_submissions(comment_id, user_id, submitted_at)
select gen_random_uuid(), current_setting('npu_test.actor_a')::uuid, now() - interval '2 hours'
from generate_series(1, 10);
set local role authenticated;
do $$ begin
  begin
    insert into public.comments(page_id, content) values (current_setting('npu_test.page'), 'Eleventh submission');
    raise exception 'FAIL: daily limit was bypassed';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'COMMENT_RATE_DAY' then raise; end if;
  end;
end $$;

reset role;
update community_private.comment_submissions set submitted_at = now() - interval '25 hours'
where user_id = current_setting('npu_test.actor_a')::uuid;
insert into public.comment_bans(user_id, reason) values (current_setting('npu_test.actor_a')::uuid, 'Temporary test');
set local role authenticated;
do $$ begin
  begin
    insert into public.comments(page_id, content) values (current_setting('npu_test.page'), 'Banned user submission');
    raise exception 'FAIL: banned user can comment';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'COMMENT_BANNED' then raise; end if;
  end;
  begin
    delete from public.comment_bans where user_id = auth.uid();
    raise exception 'FAIL: user can remove ban';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
delete from public.comment_bans where user_id = current_setting('npu_test.actor_a')::uuid;
set local role authenticated;
insert into public.comments(page_id, content) values (current_setting('npu_test.page'), 'Allowed after unban and expiry');
reset role;
do $$ begin
  if (select count(*) from public.comments where page_id = current_setting('npu_test.page') and status = 'pending') <> 1 then
    raise exception 'FAIL: unban/expiry did not restore pending submissions';
  end if;
end $$;
rollback;
select 'Moderation integration checks passed; all test changes rolled back.' as result;
