-- Milestone 3B1: member-scoped reads only. Review/apply separately to DEVELOPMENT.
begin;

-- app_private is NOT an exposed Data API schema. No client CREATE privileges.
create schema app_private authorization postgres;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;

-- Owner must bypass membership RLS so this lookup never recurses into its policy.
-- No actor parameter: the caller can ask only about their OWN active membership.
create function app_private.has_active_league_membership(p_league_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.league_memberships as membership
    where membership.league_id = p_league_id
      and membership.user_id = (select auth.uid())
      and membership.departed_at is null
  );
$$;
alter function app_private.has_active_league_membership(uuid) owner to postgres;
revoke all on function app_private.has_active_league_membership(uuid) from public, anon, authenticated;
grant execute on function app_private.has_active_league_membership(uuid) to authenticated;

-- Foundation already enables RLS; reaffirm it explicitly on these three tables.
alter table public.leagues enable row level security;
alter table public.league_memberships enable row level security;
alter table public.league_scoring_versions enable row level security;
revoke all on public.leagues, public.league_memberships, public.league_scoring_versions
  from public, anon, authenticated;

-- Column grants prevent future columns (e.g. invitation email) becoming readable.
-- No table-level SELECT: clients must request explicit safe columns, not '*'.
grant select (id, name, season_year, manager_count, draft_rounds)
  on public.leagues to authenticated;
grant select (id, league_id, display_name, role, departed_at)
  on public.league_memberships to authenticated;
grant select (
  league_id, version, ruleset,
  passing_yards_hundredths, rushing_yards_hundredths, receiving_yards_hundredths,
  receptions_hundredths, passing_touchdowns_hundredths, rushing_touchdowns_hundredths,
  receiving_touchdowns_hundredths, return_touchdowns_hundredths,
  passing_two_point_conversions_hundredths, rushing_two_point_conversions_hundredths,
  receiving_two_point_conversions_hundredths, interceptions_thrown_hundredths,
  fumbles_lost_hundredths, field_goals_made_under_40_hundredths,
  field_goals_made_40_to_49_hundredths, field_goals_made_50_plus_hundredths,
  extra_points_made_hundredths, field_goals_missed_hundredths, extra_points_missed_hundredths
) on public.league_scoring_versions to authenticated;

create policy leagues_active_member_read on public.leagues
  for select to authenticated
  using (app_private.has_active_league_membership(id));
create policy league_memberships_active_member_read on public.league_memberships
  for select to authenticated
  using (app_private.has_active_league_membership(league_id));
create policy league_scoring_versions_active_member_read on public.league_scoring_versions
  for select to authenticated
  using (app_private.has_active_league_membership(league_id));

-- No mutations, invitations, claims, public-schema RPCs, or other table grants.
commit;
