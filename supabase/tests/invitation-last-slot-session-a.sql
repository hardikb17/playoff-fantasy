-- TWO-SESSION rollback-only test, session A (postgres, dedicated SQL connection).
-- Use an EXISTING DEVELOPMENT league and its provisioned active commissioner.
-- Substitute ONLY in a private execution copy. No Auth modifications or email.
-- Start B during the 30-second hold. On ANY error issue ROLLBACK in BOTH sessions.
begin;
set local statement_timeout = '90s';
do $test$
declare
  v_league uuid := 'REPLACE_WITH_DEVELOPMENT_LEAGUE_UUID';
  v_actor uuid := 'REPLACE_WITH_CONFIRMED_COMMISSIONER_UUID';
  v_active integer;
  v_result jsonb;
begin
  perform 1 from public.leagues where id=v_league for update;
  if not found then raise exception 'Development league missing'; end if;
  perform 1 from public.drafts where league_id=v_league for update;
  if exists(select 1 from public.drafts where league_id=v_league and (started_at is not null or frozen_at is not null)) then
    raise exception 'Use a pre-start development league'; end if;
  if not exists(select 1 from auth.users where id=v_actor and email_confirmed_at is not null)
    or not exists(select 1 from public.league_memberships where league_id=v_league and user_id=v_actor and role='commissioner' and departed_at is null) then
    raise exception 'Use its confirmed active commissioner'; end if;
  if exists(select 1 from app_private.league_invitations where league_id=v_league and state='pending' and expires_at>clock_timestamp()) then
    raise exception 'Use a development league without live pending invitations'; end if;
  select count(*) into v_active from public.league_memberships where league_id=v_league and departed_at is null;
  -- Transaction-local fixture: reserve exactly one free slot, then roll back.
  update public.leagues set manager_count=v_active+1,updated_at=clock_timestamp() where id=v_league;
  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_result:=public.issue_invitation(v_league,gen_random_uuid(),'SYNTHETIC last slot A','last-slot-a@example.invalid');
  if v_result->>'status' is distinct from 'prepared' then raise exception 'A failed to reserve last slot'; end if;
  if public.issue_invitation(v_league,gen_random_uuid(),'SYNTHETIC extra','last-slot-extra@example.invalid')->>'status' is distinct from 'capacity_full' then
    raise exception 'Last slot overbooked'; end if;
  execute 'reset role';
  raise notice 'A holds league lock and last slot for 30 seconds: run session B NOW.';
  perform pg_sleep(30);
  -- Verify B could not add an invitation behind A's lock.
  if (select count(*) from app_private.league_invitations where league_id=v_league and state='pending' and expires_at>clock_timestamp())<>1 then
    raise exception 'Concurrent reservation bypassed league lock'; end if;
end;
$test$;
select 'PASS' as invitation_last_slot_session_a;
rollback;
