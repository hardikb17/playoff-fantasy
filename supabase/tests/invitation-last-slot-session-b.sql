-- Run during A's 30-second hold in a SECOND dedicated postgres SQL connection.
-- Same private league/commissioner substitutions as A. No Auth changes/emails.
-- Expected: lock timeout is caught explicitly, PASS, final ROLLBACK.
-- If A was not holding its lock, this fails and rolls back B's attempted work.
begin;
set local lock_timeout = '2s';
set local statement_timeout = '15s';
do $test$
declare
  v_league uuid := 'REPLACE_WITH_DEVELOPMENT_LEAGUE_UUID';
  v_actor uuid := 'REPLACE_WITH_CONFIRMED_COMMISSIONER_UUID';
  v_blocked boolean := false;
begin
  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin
    perform public.issue_invitation(v_league,gen_random_uuid(),'SYNTHETIC last slot B','last-slot-b@example.invalid');
  exception when lock_not_available then
    v_blocked:=true; -- SQLSTATE 55P03: lock_timeout, not a generic caught error.
  end;
  execute 'reset role';
  if not v_blocked then raise exception 'B did not block: rerun B while A is holding the league lock'; end if;
end;
$test$;
select 'PASS' as invitation_last_slot_session_b;
rollback;
