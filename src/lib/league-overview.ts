import { formatFantasyPoints } from "./scoring";

export interface LeagueSummary {
  id: string;
  name: string;
  season_year: number;
  manager_count: number;
  draft_rounds: number;
}
export interface LeagueManager {
  id: string;
  league_id: string;
  display_name: string;
  role: "member" | "commissioner";
  departed_at: string | null;
}
export const LEAGUE_COLUMNS = "id,name,season_year,manager_count,draft_rounds";
// Deliberately excludes user_id, created_at, updated_at, and future invitation data.
export const MANAGER_COLUMNS = "id,league_id,display_name,role,departed_at";

export const SCORING_CATEGORIES = [
  ["passing_yards_hundredths", "Passing yard"],
  ["rushing_yards_hundredths", "Rushing yard"],
  ["receiving_yards_hundredths", "Receiving yard"],
  ["receptions_hundredths", "Reception"],
  ["passing_touchdowns_hundredths", "Passing touchdown"],
  ["rushing_touchdowns_hundredths", "Rushing touchdown"],
  ["receiving_touchdowns_hundredths", "Receiving touchdown"],
  ["return_touchdowns_hundredths", "Individual return touchdown"],
  ["passing_two_point_conversions_hundredths", "Passing two-point conversion"],
  ["rushing_two_point_conversions_hundredths", "Rushing two-point conversion"],
  ["receiving_two_point_conversions_hundredths", "Receiving two-point conversion"],
  ["interceptions_thrown_hundredths", "Interception thrown"],
  ["fumbles_lost_hundredths", "Fumble lost"],
  ["field_goals_made_under_40_hundredths", "Field goal made under 40 yards"],
  ["field_goals_made_40_to_49_hundredths", "Field goal made 40–49 yards"],
  ["field_goals_made_50_plus_hundredths", "Field goal made 50+ yards"],
  ["extra_points_made_hundredths", "Extra point made"],
  ["field_goals_missed_hundredths", "Missed field goal"],
  ["extra_points_missed_hundredths", "Missed extra point"],
] as const;
type ScoringCategory = typeof SCORING_CATEGORIES[number][0];
export type LeagueScoringVersion = { league_id: string; version: number; ruleset: string } & Record<ScoringCategory, number>;
export const SCORING_COLUMNS = ["league_id", "version", "ruleset", ...SCORING_CATEGORIES.map(([key]) => key)].join(",");

export function isLeagueId(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
export function seasonLabel(year: number): string {
  return `${year} NFL season · Playoffs ${year + 1}`;
}
export function scoringRows(version: LeagueScoringVersion) {
  return SCORING_CATEGORIES.map(([key, label]) => ({ key, label, points: formatFantasyPoints(version[key]) }));
}
