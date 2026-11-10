-- Run this ENTIRE file in playoff-fantasy-dev's SQL Editor as postgres.
-- Requires foundation 20261028000000 AND league reads 20261110000000.
-- Updated 3B1 access expectations; all existing storage assertions are retained.
-- No schema changes or auth fixtures.
-- All fixture UUIDs are generated; the synthetic season is chosen from unused keys.
-- On ANY error, issue ROLLBACK; before running other SQL in the same session.
-- A successful run returns foundation_verification = PASS and completes ROLLBACK.
begin;

-- Explicit exceptions are used instead of PL/pgSQL ASSERT (which can be disabled).
do $verification$
declare
  v_expected_tables constant text[] := array[
    'nfl_seasons', 'nfl_teams', 'nfl_players', 'nfl_season_teams',
    'nfl_season_players', 'leagues', 'league_memberships',
    'league_scoring_versions', 'drafts', 'draft_order', 'draft_player_pool',
    'draft_requests', 'draft_picks', 'draft_audit_events'
  ];
  v_name text;
  v_table record;
  v_role text;
  v_privilege text;
  v_season integer;
  v_team uuid := gen_random_uuid();
  v_players uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  v_leagues uuid[] := array[gen_random_uuid(), gen_random_uuid()];
  v_drafts uuid[] := array[gen_random_uuid(), gen_random_uuid()];
  -- A1, A2, A3 (not in saved order), B1, B2. All account links stay NULL.
  v_members uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  v_actors uuid[] := array[gen_random_uuid(), gen_random_uuid()];
  v_requests uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  v_request_key uuid := gen_random_uuid();
  v_pick uuid := gen_random_uuid();
  v_replacement_pick uuid := gen_random_uuid();
  v_original_request jsonb;
  v_current_request jsonb;
  v_case record;
  v_rejected boolean;
  v_state text;
  v_constraint text;
  v_expected_constraint text;
  v_i integer;
  v_count integer;
  v_column record;
  v_allowed_columns text[];
  v_expected_read boolean;
begin
  if to_regprocedure('app_private.has_active_league_membership(uuid)') is null then
    raise exception 'Apply the league membership read migration before this updated verification';
  end if;
  -- Existence, explicit RLS, PUBLIC ACLs, and effective client privileges.
  foreach v_name in array v_expected_tables loop
    select c.oid, c.relowner, c.relacl, c.relrowsecurity into v_table
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = v_name and c.relkind = 'r';
    if not found then
      raise exception 'Missing expected public table: %', v_name;
    end if;
    if v_table.relrowsecurity is not true then
      raise exception 'RLS is not enabled on public.%', v_name;
    end if;
    -- PUBLIC is the ACL pseudo-role with OID 0, not a pg_roles entry.
    if exists (
      select 1 from pg_catalog.aclexplode(
        coalesce(v_table.relacl, pg_catalog.acldefault('r', v_table.relowner))
      ) acl where acl.grantee = 0
    ) then
      raise exception 'PUBLIC has a table privilege on public.%', v_name;
    end if;
    foreach v_role in array array['anon', 'authenticated'] loop
      if not exists (select 1 from pg_catalog.pg_roles where rolname = v_role) then
        raise exception 'Expected database role is missing: %', v_role;
      end if;
      -- Enumerate server-supported table privileges, including MAINTAIN on PG17.
      -- has_table_privilege checks effective rights, including inherited grants.
      for v_privilege in
        select distinct acl.privilege_type
        from pg_catalog.aclexplode(pg_catalog.acldefault('r', v_table.relowner)) acl
      loop
        if pg_catalog.has_table_privilege(v_role, v_table.oid, v_privilege) then
          raise exception '% has % on public.%', v_role, v_privilege, v_name;
        end if;
      end loop;
    end loop;
    -- No table-level privileges are allowed, including on the three read tables.
    -- SELECT is granted only on the following exact columns for authenticated.
    v_allowed_columns := case v_name
      when 'leagues' then array['id','name','season_year','manager_count','draft_rounds']
      when 'league_memberships' then array['id','league_id','display_name','role','departed_at']
      when 'league_scoring_versions' then array[
        'league_id','version','ruleset',
        'passing_yards_hundredths','rushing_yards_hundredths','receiving_yards_hundredths','receptions_hundredths',
        'passing_touchdowns_hundredths','rushing_touchdowns_hundredths','receiving_touchdowns_hundredths','return_touchdowns_hundredths',
        'passing_two_point_conversions_hundredths','rushing_two_point_conversions_hundredths','receiving_two_point_conversions_hundredths',
        'interceptions_thrown_hundredths','fumbles_lost_hundredths','field_goals_made_under_40_hundredths',
        'field_goals_made_40_to_49_hundredths','field_goals_made_50_plus_hundredths','extra_points_made_hundredths',
        'field_goals_missed_hundredths','extra_points_missed_hundredths'
      ] else array[]::text[] end;
    for v_column in select attnum,attname,attacl from pg_catalog.pg_attribute
      where attrelid=v_table.oid and attnum>0 and not attisdropped
    loop
      if exists(select 1 from pg_catalog.aclexplode(v_column.attacl) acl where acl.grantee=0) then
        raise exception 'PUBLIC has a column privilege on %.%',v_name,v_column.attname;
      end if;
      foreach v_role in array array['anon','authenticated'] loop
        v_expected_read := v_role='authenticated' and v_column.attname=any(v_allowed_columns);
        if pg_catalog.has_column_privilege(v_role,v_table.oid,v_column.attnum,'SELECT') is distinct from v_expected_read then
          raise exception 'Wrong column SELECT privilege for % on %.%',v_role,v_name,v_column.attname;
        end if;
        foreach v_privilege in array array['INSERT','UPDATE','REFERENCES'] loop
          if pg_catalog.has_column_privilege(v_role,v_table.oid,v_column.attnum,v_privilege) then
            raise exception 'Unexpected column mutation privilege for % on %.%',v_role,v_name,v_column.attname;
          end if;
        end loop;
      end loop;
    end loop;
  end loop;

  -- Catalog-check detachment without reading, inserting, or deleting auth rows.
  if not exists (
    select 1
    from pg_catalog.pg_constraint fk
    join pg_catalog.pg_attribute child on child.attrelid = fk.conrelid
      and child.attname = 'user_id' and not child.attisdropped
    join pg_catalog.pg_attribute parent on parent.attrelid = fk.confrelid
      and parent.attname = 'id' and not parent.attisdropped
    where fk.contype = 'f'
      and fk.conrelid = 'public.league_memberships'::regclass
      and fk.confrelid = 'auth.users'::regclass
      and fk.conkey = array[child.attnum]::smallint[]
      and fk.confkey = array[parent.attnum]::smallint[]
      and fk.confdeltype = 'n' and fk.confupdtype = 'r'
      and fk.convalidated and not child.attnotnull
  ) then
    raise exception 'Membership account FK must be nullable, validated, ON DELETE SET NULL / ON UPDATE RESTRICT';
  end if;

  -- Do not reuse or edit any actual season. This is not imported NFL data.
  select candidate into v_season from generate_series(9998, 1900, -1) candidate
  where not exists (select 1 from public.nfl_seasons s where s.season_year = candidate)
  order by candidate desc limit 1;
  if v_season is null then
    raise exception 'No unused synthetic season key available';
  end if;
  insert into public.nfl_seasons (season_year, playoffs_end_year) values (v_season, v_season + 1);
  insert into public.nfl_teams (id, name) values (v_team, 'SYNTHETIC verification team');
  insert into public.nfl_season_teams (season_year, team_id, team_name, abbreviation, playoff_eligible)
  values (v_season, v_team, 'SYNTHETIC verification team', 'SYN', true);
  for v_i in 1..3 loop
    insert into public.nfl_players (id, display_name) values (v_players[v_i], 'SYNTHETIC player ' || v_i);
    insert into public.nfl_season_players (season_year, player_id, team_id, position)
    values (v_season, v_players[v_i], v_team, 'QB');
  end loop;
  for v_i in 1..2 loop
    insert into public.leagues (id, season_year, name, manager_count, draft_rounds)
    values (v_leagues[v_i], v_season, 'SYNTHETIC league ' || v_i, 2, 2);
    insert into public.league_scoring_versions (league_id, version) values (v_leagues[v_i], 1);
    insert into public.drafts (id, league_id, season_year, scoring_version, manager_count, rounds)
    values (v_drafts[v_i], v_leagues[v_i], v_season, 1, 2, 2);
  end loop;
  for v_i in 1..5 loop
    insert into public.league_memberships (id, league_id, display_name)
    values (v_members[v_i], v_leagues[case when v_i <= 3 then 1 else 2 end], 'SYNTHETIC member ' || v_i);
  end loop;
  insert into public.draft_order (league_id, draft_id, membership_id, order_position) values
    (v_leagues[1], v_drafts[1], v_members[1], 1),
    (v_leagues[1], v_drafts[1], v_members[2], 2),
    (v_leagues[2], v_drafts[2], v_members[4], 1),
    (v_leagues[2], v_drafts[2], v_members[5], 2);
  insert into public.draft_player_pool (league_id, draft_id, season_year, player_id, team_id, position) values
    (v_leagues[1], v_drafts[1], v_season, v_players[1], v_team, 'QB'),
    (v_leagues[1], v_drafts[1], v_season, v_players[2], v_team, 'QB'),
    (v_leagues[2], v_drafts[2], v_season, v_players[1], v_team, 'QB'),
    (v_leagues[2], v_drafts[2], v_season, v_players[3], v_team, 'QB');

  -- Deliberate owner-level storage fixtures, not authenticated RPC operations.
  -- These actor UUIDs are audit snapshots only; no auth.users records are created.
  insert into public.draft_requests (id, league_id, draft_id, actor_user_id, actor_membership_id,
    request_key, operation, payload, result, version_before, version_after) values
    (v_requests[1], v_leagues[1], v_drafts[1], v_actors[1], v_members[1], v_request_key,
      'pick', jsonb_build_object('player_id', v_players[1], 'overall_pick', 1),
      jsonb_build_object('pick_id', v_pick, 'overall_pick', 1, 'version', 1), 0, 1),
    (v_requests[2], v_leagues[1], v_drafts[1], v_actors[1], v_members[1], gen_random_uuid(),
      'pick', jsonb_build_object('synthetic_candidate', true), '{"synthetic_candidate":true}', 1, 2),
    (v_requests[3], v_leagues[2], v_drafts[2], v_actors[2], v_members[4], gen_random_uuid(),
      'pick', jsonb_build_object('player_id', v_players[1], 'overall_pick', 1),
      '{"synthetic_other_draft":true}', 0, 1),
    (v_requests[4], v_leagues[1], v_drafts[1], v_actors[1], v_members[1], gen_random_uuid(),
      'undo', jsonb_build_object('pick_id', v_pick), '{"synthetic_reversal":true}', 1, 2),
    (v_requests[5], v_leagues[1], v_drafts[1], v_actors[1], v_members[1], gen_random_uuid(),
      'pick', jsonb_build_object('player_id', v_players[1], 'overall_pick', 1),
      jsonb_build_object('pick_id', v_replacement_pick, 'overall_pick', 1, 'version', 3), 2, 3),
    (v_requests[6], v_leagues[2], v_drafts[2], v_actors[2], v_members[4], gen_random_uuid(),
      'pick', '{"synthetic_candidate":true}', '{"synthetic_candidate":true}', 1, 2);
  insert into public.draft_picks (id, league_id, draft_id, owner_membership_id, player_id,
    overall_pick, round, position_in_round, request_record_id)
  values (v_pick, v_leagues[1], v_drafts[1], v_members[1], v_players[1], 1, 1, 1, v_requests[1]);
  -- The same player is available independently in another league.
  insert into public.draft_picks (league_id, draft_id, owner_membership_id, player_id,
    overall_pick, round, position_in_round, request_record_id)
  values (v_leagues[2], v_drafts[2], v_members[4], v_players[1], 1, 1, 1, v_requests[3]);
  insert into public.draft_audit_events (league_id, draft_id, request_record_id, pick_id,
    actor_user_id, actor_membership_id, event_type, draft_version, details)
  values (v_leagues[1], v_drafts[1], v_requests[1], v_pick,
    v_actors[1], v_members[1], 'synthetic_pick', 1, '{"synthetic":true}');
  if (select count(*) from public.draft_picks where id = v_pick) <> 1 then
    raise exception 'Valid same-league pick was not persisted';
  end if;
  select to_jsonb(r) into strict v_original_request from public.draft_requests r where id = v_requests[1];

  -- Each case has exactly one intended invalid relationship. New pick IDs/defaults
  -- and unused request[2] isolate failures from other uniqueness constraints.
  for v_case in
    select * from (values
      ('cross-league order member', format(
        'insert into public.draft_order (league_id,draft_id,membership_id,order_position) values (%L,%L,%L,3)',
        v_leagues[1],v_drafts[1],v_members[4]),
        '23503', 'draft_order_league_id_membership_id_fkey'),
      ('cross-league draft/order pair', format(
        'insert into public.draft_order (league_id,draft_id,membership_id,order_position) values (%L,%L,%L,3)',
        v_leagues[2],v_drafts[1],v_members[4]),
        '23503', 'draft_order_league_id_draft_id_fkey'),
      ('owner from another draft', format(
        'insert into public.draft_picks (league_id,draft_id,owner_membership_id,player_id,overall_pick,round,position_in_round,request_record_id) values (%L,%L,%L,%L,2,1,2,%L)',
        v_leagues[1],v_drafts[1],v_members[4],v_players[2],v_requests[2]),
        '23503', 'draft_picks_league_id_draft_id_owner_membership_id_fkey'),
      ('same-league owner absent from saved order', format(
        'insert into public.draft_picks (league_id,draft_id,owner_membership_id,player_id,overall_pick,round,position_in_round,request_record_id) values (%L,%L,%L,%L,2,1,2,%L)',
        v_leagues[1],v_drafts[1],v_members[3],v_players[2],v_requests[2]),
        '23503', 'draft_picks_league_id_draft_id_owner_membership_id_fkey'),
      ('player only in another draft pool', format(
        'insert into public.draft_picks (league_id,draft_id,owner_membership_id,player_id,overall_pick,round,position_in_round,request_record_id) values (%L,%L,%L,%L,2,1,2,%L)',
        v_leagues[1],v_drafts[1],v_members[2],v_players[3],v_requests[2]),
        '23503', 'draft_picks_league_id_draft_id_player_id_fkey'),
      ('request belongs to another draft', format(
        'insert into public.draft_picks (league_id,draft_id,owner_membership_id,player_id,overall_pick,round,position_in_round,request_record_id) values (%L,%L,%L,%L,2,1,2,%L)',
        v_leagues[1],v_drafts[1],v_members[2],v_players[2],v_requests[6]),
        '23503', 'draft_picks_league_id_draft_id_request_record_id_fkey'),
      ('duplicate active player', format(
        'insert into public.draft_picks (league_id,draft_id,owner_membership_id,player_id,overall_pick,round,position_in_round,request_record_id) values (%L,%L,%L,%L,2,1,2,%L)',
        v_leagues[1],v_drafts[1],v_members[2],v_players[1],v_requests[2]),
        '23505', 'draft_picks_active_player_key'),
      ('duplicate active overall pick', format(
        'insert into public.draft_picks (league_id,draft_id,owner_membership_id,player_id,overall_pick,round,position_in_round,request_record_id) values (%L,%L,%L,%L,1,1,1,%L)',
        v_leagues[1],v_drafts[1],v_members[2],v_players[2],v_requests[2]),
        '23505', 'draft_picks_active_overall_key'),
      ('duplicate request identity with different payload', format(
        'insert into public.draft_requests (league_id,draft_id,actor_user_id,actor_membership_id,request_key,operation,payload,result,version_before,version_after) values (%L,%L,%L,%L,%L,''pick'',''{"conflicting":true}'',''{}'',0,1)',
        v_leagues[1],v_drafts[1],v_actors[1],v_members[1],v_request_key),
        '23505', 'draft_requests_draft_id_actor_user_id_request_key_key'),
      ('invalid player position', format(
        'update public.nfl_season_players set position = ''DEF'' where season_year = %L and player_id = %L',
        v_season,v_players[3]),
        '23514', 'nfl_season_players_position_check'),
      ('invalid frozen-pool position', format(
        'update public.draft_player_pool set position = ''DEF'' where draft_id = %L and player_id = %L',
        v_drafts[1],v_players[2]),
        '23514', 'draft_player_pool_position_check')
    ) as cases(label, command, expected_state, expected_constraint)
  loop
    v_rejected := false;
    begin
      execute v_case.command;
    exception when foreign_key_violation or unique_violation or check_violation then
      get stacked diagnostics v_state = returned_sqlstate, v_constraint = constraint_name;
      if v_state is distinct from v_case.expected_state or v_constraint is distinct from v_case.expected_constraint then
        raise exception 'Wrong failure for %: expected %/%, got %/%',
          v_case.label, v_case.expected_state, v_case.expected_constraint, v_state, v_constraint;
      end if;
      v_rejected := true;
    end;
    -- Outside the handler: this assertion cannot be mistaken for an expected error.
    if not v_rejected then
      raise exception 'Invalid operation unexpectedly succeeded: %', v_case.label;
    end if;
  end loop;

  -- Test EVERY scoring column independently. Catalog names avoid guessing names
  -- PostgreSQL may truncate for long automatically named CHECK constraints.
  for v_case in
    select * from (values
      ('passing_yards_hundredths',4), ('rushing_yards_hundredths',10),
      ('receiving_yards_hundredths',10), ('receptions_hundredths',100),
      ('passing_touchdowns_hundredths',400), ('rushing_touchdowns_hundredths',600),
      ('receiving_touchdowns_hundredths',600), ('return_touchdowns_hundredths',600),
      ('passing_two_point_conversions_hundredths',200), ('rushing_two_point_conversions_hundredths',200),
      ('receiving_two_point_conversions_hundredths',200), ('interceptions_thrown_hundredths',-200),
      ('fumbles_lost_hundredths',-200), ('field_goals_made_under_40_hundredths',300),
      ('field_goals_made_40_to_49_hundredths',400), ('field_goals_made_50_plus_hundredths',500),
      ('extra_points_made_hundredths',100), ('field_goals_missed_hundredths',-100),
      ('extra_points_missed_hundredths',-100)
    ) as weights(column_name, expected_value)
  loop
    execute format('select count(*) from public.league_scoring_versions where league_id = $1 and version = 1 and %I = $2', v_case.column_name)
      into v_count using v_leagues[1], v_case.expected_value;
    if v_count <> 1 then
      raise exception 'Scoring default mismatch: %', v_case.column_name;
    end if;
    select c.conname into strict v_expected_constraint
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attname = v_case.column_name
    where c.conrelid = 'public.league_scoring_versions'::regclass and c.contype = 'c'
      and c.conkey = array[a.attnum]::smallint[];
    v_rejected := false;
    begin
      execute format('update public.league_scoring_versions set %I = $1 where league_id = $2 and version = 1', v_case.column_name)
        using v_case.expected_value + 1, v_leagues[1];
    exception when check_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint is distinct from v_expected_constraint then
        raise exception 'Wrong scoring constraint for %: got %', v_case.column_name, v_constraint;
      end if;
      v_rejected := true;
    end;
    if not v_rejected then
      raise exception 'Invalid scoring weight unexpectedly accepted: %', v_case.column_name;
    end if;
  end loop;

  update public.draft_picks set reversed_at = now(), reversal_request_record_id = v_requests[4]
  where id = v_pick;
  if not found then
    raise exception 'Original pick missing during reversal';
  end if;
  insert into public.draft_picks (id, league_id, draft_id, owner_membership_id, player_id,
    overall_pick, round, position_in_round, request_record_id)
  values (v_replacement_pick, v_leagues[1], v_drafts[1], v_members[1], v_players[1], 1, 1, 1, v_requests[5]);
  if (select count(*) from public.draft_picks where draft_id = v_drafts[1] and overall_pick = 1) <> 2
    or (select count(*) from public.draft_picks where draft_id = v_drafts[1] and overall_pick = 1 and reversed_at is null) <> 1
    or not exists (select 1 from public.draft_picks where id = v_pick and reversed_at is not null)
    or not exists (select 1 from public.draft_picks where id = v_replacement_pick and player_id = v_players[1] and request_record_id = v_requests[5] and reversed_at is null)
  then
    raise exception 'Reversal/reuse did not preserve old pick and exactly one active replacement';
  end if;
  select to_jsonb(r) into v_current_request from public.draft_requests r where id = v_requests[1];
  if v_current_request is distinct from v_original_request then
    raise exception 'Original successful request changed or disappeared after reversal';
  end if;
  raise notice 'Foundation storage assertions passed. Executing ROLLBACK next.';
end;
$verification$;

-- Marker is inside the transaction. Success also requires the final ROLLBACK.
select 'PASS' as foundation_verification;
rollback;
