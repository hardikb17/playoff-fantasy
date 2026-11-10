-- REVIEW / MANUAL SQL EDITOR TEST. Requires BOTH migrations; not executed by implementation.
-- Run entire file as postgres in playoff-fantasy-dev. On ANY failure run ROLLBACK.
-- Privately replace A/B/C with THREE DISTINCT confirmed test Auth UUIDs provisioned
-- via the dashboard/admin createUser workflow in AUTH_SETUP.md. Never INSERT auth.users.
-- Fixtures use existing Auth identities but change ONLY generated application rows.
begin;

do $verification$
declare
  v_account_texts text[] := array[
    'REPLACE_WITH_CONFIRMED_TEST_AUTH_USER_A_UUID',
    'REPLACE_WITH_CONFIRMED_TEST_AUTH_USER_B_UUID',
    'REPLACE_WITH_CONFIRMED_TEST_AUTH_USER_C_UUID'
  ];
  v_accounts uuid[] := array[]::uuid[];
  v_leagues uuid[] := array[gen_random_uuid(),gen_random_uuid()];
  v_members uuid[] := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  v_season integer;
  v_i integer;
  v_count integer;
  v_expected integer;
  v_case record;
  v_denied boolean;
  v_name text;
  v_helper oid;
begin
  for v_i in 1..3 loop
    if v_account_texts[v_i] like 'REPLACE_%' then
      raise exception 'Replace all three confirmed Auth UUID placeholders in a private test copy';
    end if;
    v_accounts := array_append(v_accounts, v_account_texts[v_i]::uuid);
    if not exists (select 1 from auth.users where id = v_accounts[v_i] and email_confirmed_at is not null) then
      raise exception 'Test account % must exist and be email-confirmed', v_i;
    end if;
  end loop;
  if (select count(distinct id) from unnest(v_accounts) id) <> 3 then
    raise exception 'Use three distinct test Auth accounts';
  end if;
  v_helper := to_regprocedure('app_private.has_active_league_membership(uuid)');
  if v_helper is null then raise exception 'League read migration must be applied before this test'; end if;
  if not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_roles r on r.oid = p.proowner
    where p.oid = v_helper and p.prosecdef and r.rolname = 'postgres'
      and 'search_path=""' = any(p.proconfig)) then
    raise exception 'Membership helper must be postgres-owned SECURITY DEFINER with empty search_path';
  end if;
  if has_function_privilege('anon', v_helper, 'EXECUTE') or exists (
    select 1 from pg_catalog.pg_proc p,
    lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
    where p.oid = v_helper and acl.grantee = 0
  ) then raise exception 'Helper must not permit PUBLIC/anon execution'; end if;

  select candidate into v_season from generate_series(9998,1900,-1) candidate
    where not exists (select 1 from public.nfl_seasons where season_year = candidate)
    order by candidate desc limit 1;
  if v_season is null then raise exception 'No unused synthetic season available'; end if;
  insert into public.nfl_seasons(season_year,playoffs_end_year) values(v_season,v_season+1);
  for v_i in 1..2 loop
    insert into public.leagues(id,season_year,name,manager_count,draft_rounds)
      values(v_leagues[v_i],v_season,'SYNTHETIC RLS league '||v_i,10,8);
    insert into public.league_scoring_versions(league_id,version) values(v_leagues[v_i],1);
  end loop;
  insert into public.league_memberships(id,league_id,user_id,display_name,role,departed_at) values
    (v_members[1],v_leagues[1],v_accounts[1],'SYNTHETIC A','commissioner',null),
    (v_members[2],v_leagues[2],v_accounts[2],'SYNTHETIC B','member',null),
    (v_members[3],v_leagues[1],v_accounts[2],'SYNTHETIC B departed','member',now()),
    (v_members[4],v_leagues[1],null,'SYNTHETIC unclaimed slot','member',null);

  -- SQL Editor owner is privileged; ALL permission assertions below switch to
  -- the Data API role and a trusted test JWT context. No elevated app client.
  for v_i in 1..3 loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_accounts[v_i]::text,'role','authenticated')::text,true);
    perform set_config('request.jwt.claim.sub',v_accounts[v_i]::text,true);
    execute 'set local role authenticated';
    v_expected := case when v_i in (1,2) then 1 else 0 end;
    select count(*) into v_count from public.leagues where id = any(v_leagues);
    if v_count <> v_expected then raise exception 'Wrong visible league count for context %',v_i; end if;
    if v_i in (1,2) and not exists(select 1 from public.leagues where id=v_leagues[v_i]) then
      raise exception 'Expected own league missing for context %',v_i;
    end if;
    select count(*) into v_count from public.league_scoring_versions where league_id = any(v_leagues);
    if v_count <> v_expected then raise exception 'Scoring leaked or missing for context %',v_i; end if;
    select count(*) into v_count from public.league_memberships where league_id = any(v_leagues);
    if v_count <> (case v_i when 1 then 3 when 2 then 1 else 0 end) then
      raise exception 'Roster leaked or missing for context %',v_i;
    end if;
    -- Successful read also proves policies can evaluate without recursion.
    perform id,league_id,display_name,role,departed_at from public.league_memberships where league_id = any(v_leagues);
    if v_i=1 and not exists(select 1 from public.league_memberships where id=v_members[3] and departed_at is not null) then
      raise exception 'Member cannot read the safe departed-manager roster fields';
    end if;
    -- Column grants apply even to a member's own account link. Filtering and
    -- ordering by a hidden column are denied as well as selecting it.
    for v_case in select * from (values
      ('read auth UUIDs','select user_id from public.league_memberships limit 1'),
      ('wildcard roster','select * from public.league_memberships limit 1'),
      ('filter auth UUIDs','select id from public.league_memberships where user_id is not null'),
      ('order auth UUIDs','select id from public.league_memberships order by user_id'),
      ('insert membership',format('insert into public.league_memberships(league_id,display_name) values(%L,''SYNTHETIC forbidden'')',v_leagues[1])),
      ('change role',format('update public.league_memberships set role=''commissioner'' where id=%L',v_members[2])),
      ('delete membership',format('delete from public.league_memberships where id=%L',v_members[1])),
      ('edit league',format('update public.leagues set name=''SYNTHETIC forbidden'' where id=%L',v_leagues[1])),
      ('insert scoring',format('insert into public.league_scoring_versions(league_id,version) values(%L,2)',v_leagues[1])),
      ('edit scoring',format('update public.league_scoring_versions set receptions_hundredths=100 where league_id=%L',v_leagues[1])),
      ('delete scoring',format('delete from public.league_scoring_versions where league_id=%L',v_leagues[1]))
    ) cases(label,command) loop
      v_denied := false;
      begin
        execute v_case.command;
      exception when insufficient_privilege then v_denied:=true;
      end;
      if not v_denied then raise exception 'Forbidden operation succeeded: % (context %)',v_case.label,v_i; end if;
    end loop;
    execute 'reset role';
  end loop;

  -- Departure by the privileged fixture owner immediately revokes A's reads.
  update public.league_memberships set departed_at=now(),updated_at=now() where id=v_members[1];
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_accounts[1]::text,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',v_accounts[1]::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.leagues where id=any(v_leagues))
    or exists(select 1 from public.league_memberships where league_id=any(v_leagues))
    or exists(select 1 from public.league_scoring_versions where league_id=any(v_leagues)) then
    raise exception 'Departed membership still grants access';
  end if;
  execute 'reset role';

  -- Anonymous users are denied even if a forged sub GUC is present in this
  -- owner-run test: anon receives no table/column/function grants.
  execute 'set local role anon';
  foreach v_name in array array['leagues','league_memberships','league_scoring_versions'] loop
    v_denied:=false;
    begin
      execute format('select %I from public.%I limit 1',
        case when v_name='leagues' then 'id' else 'league_id' end,v_name);
    exception when insufficient_privilege then v_denied:=true;
    end;
    if not v_denied then raise exception 'Anonymous read unexpectedly allowed: %',v_name; end if;
  end loop;
  execute 'reset role';
  raise notice 'League membership read assertions passed; ROLLBACK follows.';
end;
$verification$;
select 'PASS' as league_membership_reads_verification;
rollback;
