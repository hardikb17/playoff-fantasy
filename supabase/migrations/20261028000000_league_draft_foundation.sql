-- Milestone 2B, slice 1: storage foundation only. No data, policies, or RPCs.
-- REVIEW ONLY: not applied or database-tested by this task.
-- All application-history FKs restrict deletion/update. The sole SET NULL FK
-- detaches auth.users from durable memberships; actor UUIDs are audit snapshots.
begin;

create table public.nfl_seasons (
  season_year integer primary key check (season_year between 1900 and 9998),
  playoffs_end_year integer not null,
  created_at timestamptz not null default now(),
  check (playoffs_end_year = season_year + 1)
);

create table public.nfl_teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default now()
);

create table public.nfl_players (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (length(btrim(display_name)) > 0),
  created_at timestamptz not null default now()
);

-- Season-specific labels survive later franchise/name changes.
create table public.nfl_season_teams (
  season_year integer not null references public.nfl_seasons(season_year) on delete restrict on update restrict,
  team_id uuid not null references public.nfl_teams(id) on delete restrict on update restrict,
  team_name text not null check (length(btrim(team_name)) > 0),
  abbreviation text not null check (length(btrim(abbreviation)) > 0),
  playoff_eligible boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (season_year, team_id),
  unique (season_year, team_id, playoff_eligible)
);
create index nfl_season_teams_team_idx on public.nfl_season_teams(team_id);

create table public.nfl_season_players (
  season_year integer not null,
  player_id uuid not null references public.nfl_players(id) on delete restrict on update restrict,
  team_id uuid not null,
  position text not null check (position in ('QB', 'RB', 'WR', 'TE', 'K')),
  -- TRUE is part of the FK: players here must belong to playoff-eligible teams.
  team_playoff_eligible boolean not null default true check (team_playoff_eligible),
  eligible boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (season_year, player_id),
  unique (season_year, player_id, team_id, position, eligible),
  foreign key (season_year, team_id, team_playoff_eligible)
    references public.nfl_season_teams(season_year, team_id, playoff_eligible) on delete restrict on update restrict
);
create index nfl_season_players_team_idx on public.nfl_season_players(season_year, team_id, team_playoff_eligible);
create index nfl_season_players_player_idx on public.nfl_season_players(player_id);

create table public.leagues (
  id uuid primary key default gen_random_uuid(),
  season_year integer not null references public.nfl_seasons(season_year) on delete restrict on update restrict,
  name text not null check (length(btrim(name)) > 0),
  manager_count integer not null check (manager_count > 0),
  draft_rounds integer not null check (draft_rounds > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, season_year),
  check (manager_count::bigint * draft_rounds <= 9007199254740991),
  check (updated_at >= created_at)
);
create index leagues_season_idx on public.leagues(season_year);

-- Membership is the durable competition identity, not an auth account.
create table public.league_memberships (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete restrict on update restrict,
  user_id uuid references auth.users(id) on delete set null on update restrict,
  display_name text not null check (length(btrim(display_name)) > 0),
  role text not null default 'member' check (role in ('member', 'commissioner')),
  departed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (league_id, id),
  unique (league_id, user_id),
  check (departed_at is null or departed_at >= created_at),
  check (updated_at >= created_at)
);
create index league_memberships_user_idx on public.league_memberships(user_id) where user_id is not null;

-- Each column is integer HUNDREDTHS per stat unit, not whole points.
-- Only the agreed ruleset is permitted; versioning does not authorize custom rules.
create table public.league_scoring_versions (
  league_id uuid not null references public.leagues(id) on delete restrict on update restrict,
  version integer not null check (version > 0),
  ruleset text not null default 'nfl-playoffs-2026-v1' check (ruleset = 'nfl-playoffs-2026-v1'),
  passing_yards_hundredths integer not null default 4 check (passing_yards_hundredths = 4),
  rushing_yards_hundredths integer not null default 10 check (rushing_yards_hundredths = 10),
  receiving_yards_hundredths integer not null default 10 check (receiving_yards_hundredths = 10),
  receptions_hundredths integer not null default 100 check (receptions_hundredths = 100),
  passing_touchdowns_hundredths integer not null default 400 check (passing_touchdowns_hundredths = 400),
  rushing_touchdowns_hundredths integer not null default 600 check (rushing_touchdowns_hundredths = 600),
  receiving_touchdowns_hundredths integer not null default 600 check (receiving_touchdowns_hundredths = 600),
  return_touchdowns_hundredths integer not null default 600 check (return_touchdowns_hundredths = 600),
  passing_two_point_conversions_hundredths integer not null default 200 check (passing_two_point_conversions_hundredths = 200),
  rushing_two_point_conversions_hundredths integer not null default 200 check (rushing_two_point_conversions_hundredths = 200),
  receiving_two_point_conversions_hundredths integer not null default 200 check (receiving_two_point_conversions_hundredths = 200),
  interceptions_thrown_hundredths integer not null default -200 check (interceptions_thrown_hundredths = -200),
  fumbles_lost_hundredths integer not null default -200 check (fumbles_lost_hundredths = -200),
  field_goals_made_under_40_hundredths integer not null default 300 check (field_goals_made_under_40_hundredths = 300),
  field_goals_made_40_to_49_hundredths integer not null default 400 check (field_goals_made_40_to_49_hundredths = 400),
  field_goals_made_50_plus_hundredths integer not null default 500 check (field_goals_made_50_plus_hundredths = 500),
  extra_points_made_hundredths integer not null default 100 check (extra_points_made_hundredths = 100),
  field_goals_missed_hundredths integer not null default -100 check (field_goals_missed_hundredths = -100),
  extra_points_missed_hundredths integer not null default -100 check (extra_points_missed_hundredths = -100),
  created_at timestamptz not null default now(),
  primary key (league_id, version)
);

create table public.drafts (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null unique,
  season_year integer not null,
  scoring_version integer not null,
  -- Copied settings become the historical settings at freeze/start.
  manager_count integer not null check (manager_count > 0),
  rounds integer not null check (rounds > 0),
  status text not null default 'configuring'
    check (status in ('configuring', 'running', 'paused', 'completed', 'blocked')),
  next_overall_pick bigint not null default 1,
  version bigint not null default 0 check (version between 0 and 9007199254740991),
  order_finalized_at timestamptz,
  pool_finalized_at timestamptz,
  frozen_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  -- First season-wide playoff kickoff; source/updates are a future decision.
  pick_cutoff_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (league_id, id),
  unique (league_id, id, season_year),
  foreign key (league_id, season_year) references public.leagues(id, season_year) on delete restrict on update restrict,
  foreign key (league_id, scoring_version) references public.league_scoring_versions(league_id, version) on delete restrict on update restrict,
  check (manager_count::bigint * rounds < 9007199254740991),
  check (next_overall_pick between 1 and manager_count::bigint * rounds + 1),
  check ((frozen_at is null) = (started_at is null)),
  check (status not in ('running', 'paused', 'completed') or
    (frozen_at is not null and order_finalized_at is not null and pool_finalized_at is not null and pick_cutoff_at is not null)),
  check (status <> 'configuring' or frozen_at is null),
  check (status <> 'completed' or (completed_at is not null and next_overall_pick = manager_count::bigint * rounds + 1)),
  check (started_at is null or started_at >= created_at),
  check (completed_at is null or (started_at is not null and completed_at >= started_at)),
  check (updated_at >= created_at)
);
create index drafts_scoring_idx on public.drafts(league_id, scoring_version);

create table public.draft_order (
  league_id uuid not null,
  draft_id uuid not null,
  membership_id uuid not null,
  order_position integer not null check (order_position > 0),
  created_at timestamptz not null default now(),
  primary key (draft_id, order_position),
  unique (league_id, draft_id, membership_id),
  foreign key (league_id, draft_id) references public.drafts(league_id, id) on delete restrict on update restrict,
  foreign key (league_id, membership_id) references public.league_memberships(league_id, id) on delete restrict on update restrict
);
create index draft_order_membership_idx on public.draft_order(league_id, membership_id);

create table public.draft_player_pool (
  league_id uuid not null,
  draft_id uuid not null,
  season_year integer not null,
  player_id uuid not null,
  team_id uuid not null,
  position text not null check (position in ('QB', 'RB', 'WR', 'TE', 'K')),
  eligible boolean not null default true check (eligible),
  created_at timestamptz not null default now(),
  primary key (league_id, draft_id, player_id),
  foreign key (league_id, draft_id, season_year) references public.drafts(league_id, id, season_year) on delete restrict on update restrict,
  foreign key (season_year, player_id, team_id, position, eligible)
    references public.nfl_season_players(season_year, player_id, team_id, position, eligible) on delete restrict on update restrict
);
create index draft_player_pool_player_idx on public.draft_player_pool(season_year, player_id, team_id, position, eligible);

-- Only successful, committed operations are stored. Failed attempts roll back.
-- actor_user_id is the immutable authenticated UUID captured by a FUTURE RPC;
-- deliberately NO auth.users FK, so deletion cannot erase/change retry identity.
create table public.draft_requests (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null,
  draft_id uuid not null,
  actor_user_id uuid not null,
  actor_membership_id uuid not null,
  request_key uuid not null,
  operation text not null check (operation in ('randomize_order', 'start', 'pick', 'pause', 'resume', 'undo')),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  result jsonb not null check (jsonb_typeof(result) = 'object'),
  version_before bigint not null check (version_before between 0 and 9007199254740990),
  version_after bigint not null check (version_after between 1 and 9007199254740991),
  created_at timestamptz not null default now(),
  unique (draft_id, actor_user_id, request_key),
  unique (league_id, draft_id, id),
  check (version_after = version_before + 1),
  foreign key (league_id, draft_id) references public.drafts(league_id, id) on delete restrict on update restrict,
  foreign key (league_id, actor_membership_id) references public.league_memberships(league_id, id) on delete restrict on update restrict
);
create index draft_requests_membership_idx on public.draft_requests(league_id, actor_membership_id);

create table public.draft_picks (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null,
  draft_id uuid not null,
  owner_membership_id uuid not null,
  player_id uuid not null,
  overall_pick bigint not null check (overall_pick between 1 and 9007199254740991),
  round integer not null check (round > 0),
  position_in_round integer not null check (position_in_round > 0),
  request_record_id uuid not null,
  on_behalf boolean not null default false,
  reversed_at timestamptz,
  reversal_request_record_id uuid,
  created_at timestamptz not null default now(),
  unique (league_id, draft_id, id),
  -- One successful request cannot produce multiple picks, even after undo.
  unique (request_record_id),
  foreign key (league_id, draft_id, owner_membership_id)
    references public.draft_order(league_id, draft_id, membership_id) on delete restrict on update restrict,
  foreign key (league_id, draft_id, player_id)
    references public.draft_player_pool(league_id, draft_id, player_id) on delete restrict on update restrict,
  foreign key (league_id, draft_id, request_record_id)
    references public.draft_requests(league_id, draft_id, id) on delete restrict on update restrict,
  foreign key (league_id, draft_id, reversal_request_record_id)
    references public.draft_requests(league_id, draft_id, id) on delete restrict on update restrict,
  check ((reversed_at is null) = (reversal_request_record_id is null)),
  check (reversed_at is null or reversed_at >= created_at),
  check (reversal_request_record_id is null or reversal_request_record_id <> request_record_id)
);
create unique index draft_picks_active_player_key on public.draft_picks(draft_id, player_id) where reversed_at is null;
create unique index draft_picks_active_overall_key on public.draft_picks(draft_id, overall_pick) where reversed_at is null;
create index draft_picks_owner_idx on public.draft_picks(league_id, draft_id, owner_membership_id);
create index draft_picks_pool_idx on public.draft_picks(league_id, draft_id, player_id);
create index draft_picks_reversal_idx on public.draft_picks(league_id, draft_id, reversal_request_record_id);

create table public.draft_audit_events (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null,
  draft_id uuid not null,
  request_record_id uuid,
  pick_id uuid,
  -- Snapshot UUID; not a live account link. Nullable for future system events.
  actor_user_id uuid,
  actor_membership_id uuid,
  event_type text not null check (length(btrim(event_type)) > 0),
  draft_version bigint not null check (draft_version between 0 and 9007199254740991),
  details jsonb not null check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  foreign key (league_id, draft_id) references public.drafts(league_id, id) on delete restrict on update restrict,
  foreign key (league_id, actor_membership_id) references public.league_memberships(league_id, id) on delete restrict on update restrict,
  foreign key (league_id, draft_id, request_record_id) references public.draft_requests(league_id, draft_id, id) on delete restrict on update restrict,
  foreign key (league_id, draft_id, pick_id) references public.draft_picks(league_id, draft_id, id) on delete restrict on update restrict
);
create index draft_audit_events_timeline_idx on public.draft_audit_events(league_id, draft_id, created_at, id);
create index draft_audit_events_membership_idx on public.draft_audit_events(league_id, actor_membership_id);
create index draft_audit_events_request_idx on public.draft_audit_events(league_id, draft_id, request_record_id);
create index draft_audit_events_pick_idx on public.draft_audit_events(league_id, draft_id, pick_id);

-- Explicit table-by-table protection, independent of dashboard/default grants.
-- No policies or mutation functions in this slice. No sequences (UUID IDs).
alter table public.nfl_seasons enable row level security;
alter table public.nfl_teams enable row level security;
alter table public.nfl_players enable row level security;
alter table public.nfl_season_teams enable row level security;
alter table public.nfl_season_players enable row level security;
alter table public.leagues enable row level security;
alter table public.league_memberships enable row level security;
alter table public.league_scoring_versions enable row level security;
alter table public.drafts enable row level security;
alter table public.draft_order enable row level security;
alter table public.draft_player_pool enable row level security;
alter table public.draft_requests enable row level security;
alter table public.draft_picks enable row level security;
alter table public.draft_audit_events enable row level security;

revoke all privileges on table
  public.nfl_seasons,
  public.nfl_teams,
  public.nfl_players,
  public.nfl_season_teams,
  public.nfl_season_players,
  public.leagues,
  public.league_memberships,
  public.league_scoring_versions,
  public.drafts,
  public.draft_order,
  public.draft_player_pool,
  public.draft_requests,
  public.draft_picks,
  public.draft_audit_events
from public, anon, authenticated;

commit;
