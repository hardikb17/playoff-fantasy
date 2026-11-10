-- MANUAL DEVELOPMENT SETUP, NOT A MIGRATION. Never execute on production.
-- Replace the single placeholder in your private SQL Editor copy; do not commit it.
-- Run the ENTIRE file as postgres. On failure run ROLLBACK before other SQL.
begin;

do $bootstrap$
declare
  v_user_text constant text := 'REPLACE_WITH_YOUR_CONFIRMED_AUTH_USER_UUID';
  v_user uuid;
  v_league uuid;
  v_name constant text := 'DEVELOPMENT — 2026 Playoff Fantasy';
  v_created boolean := false;
  v_weights constant jsonb := '{
    "passing_yards_hundredths":4,"rushing_yards_hundredths":10,"receiving_yards_hundredths":10,
    "receptions_hundredths":100,"passing_touchdowns_hundredths":400,"rushing_touchdowns_hundredths":600,
    "receiving_touchdowns_hundredths":600,"return_touchdowns_hundredths":600,
    "passing_two_point_conversions_hundredths":200,"rushing_two_point_conversions_hundredths":200,
    "receiving_two_point_conversions_hundredths":200,"interceptions_thrown_hundredths":-200,"fumbles_lost_hundredths":-200,
    "field_goals_made_under_40_hundredths":300,"field_goals_made_40_to_49_hundredths":400,"field_goals_made_50_plus_hundredths":500,
    "extra_points_made_hundredths":100,"field_goals_missed_hundredths":-100,"extra_points_missed_hundredths":-100
  }';
begin
  if v_user_text like 'REPLACE_%' then
    raise exception 'Replace the confirmed Auth account UUID placeholder in a private copy';
  end if;
  v_user := v_user_text::uuid;
  if not exists (select 1 from auth.users where id = v_user and email is not null and email_confirmed_at is not null and deleted_at is null) then
    raise exception 'The specified account must exist and be email-confirmed and not deleted';
  end if;
  -- Serialize reruns of this setup; the ID is deterministic per confirmed account.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('playoff-fantasy-dev:2026:3b1-bootstrap', 0));
  v_league := pg_catalog.md5('playoff-fantasy-dev:2026:3b1-bootstrap:' || v_user::text)::uuid;
  if exists (select 1 from public.leagues where name = v_name and id <> v_league) then
    raise exception 'A differently owned/named bootstrap league exists; inspect manually rather than modifying it';
  end if;
  insert into public.nfl_seasons (season_year, playoffs_end_year) values (2026, 2027)
    on conflict (season_year) do nothing;
  if not exists (select 1 from public.nfl_seasons where season_year = 2026 and playoffs_end_year = 2027) then
    raise exception 'Existing season does not match 2026 NFL season / playoffs 2027';
  end if;
  if not exists (select 1 from public.leagues where id = v_league) then
    insert into public.leagues (id, season_year, name, manager_count, draft_rounds)
      values (v_league, 2026, v_name, 10, 8);
    insert into public.league_scoring_versions (league_id, version) values (v_league, 1);
    insert into public.league_memberships (league_id, user_id, display_name, role)
      values (v_league, v_user, 'Development commissioner', 'commissioner');
    v_created := true;
  end if;
  -- Never repair/promote/reassign existing records silently on a rerun.
  if not exists (select 1 from public.leagues where id = v_league and name = v_name
    and season_year = 2026 and manager_count = 10 and draft_rounds = 8) then
    raise exception 'Existing league conflicts with this bootstrap; no changes committed';
  end if;
  if not exists (select 1 from public.league_memberships where league_id = v_league
    and user_id = v_user and role = 'commissioner' and departed_at is null) then
    raise exception 'Existing commissioner membership is absent/inactive or has another role; refusing to promote or claim';
  end if;
  if not exists (select 1 from public.league_scoring_versions s where league_id = v_league
    and version = 1 and ruleset = 'nfl-playoffs-2026-v1' and pg_catalog.to_jsonb(s) @> v_weights) then
    raise exception 'Existing scoring version conflicts with the agreed rules';
  end if;
  raise notice 'Development league ready (newly created: %). No draft, NFL teams/players, or other manager memberships created.', v_created;
end;
$bootstrap$;
commit;
