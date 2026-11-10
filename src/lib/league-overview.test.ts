import assert from "node:assert/strict";
import { test } from "node:test";
import { isLeagueId, LEAGUE_COLUMNS, MANAGER_COLUMNS, SCORING_CATEGORIES, SCORING_COLUMNS, scoringRows, seasonLabel, type LeagueScoringVersion } from "./league-overview";

test("league IDs reject malformed/filter input and seasons name both NFL and playoff years", () => {
  assert.ok(isLeagueId("00000000-0000-0000-0000-000000000001"));
  for (const id of ["", "not-a-uuid", "../account", "id.eq.foo", "00000000-0000-0000-0000-000000000001?x=y"]) assert.equal(isLeagueId(id),false);
  assert.equal(seasonLabel(2026), "2026 NFL season · Playoffs 2027");
});

test("app projections request only necessary roster fields and never wildcard/auth IDs", () => {
  assert.deepEqual(MANAGER_COLUMNS.split(","), ["id","league_id","display_name","role","departed_at"]);
  for (const projection of [LEAGUE_COLUMNS,MANAGER_COLUMNS,SCORING_COLUMNS]) {
    assert.doesNotMatch(projection,/\*|user_id|email|created_at|updated_at/);
  }
});

test("all 19 stored scoring categories display exact positive and negative hundredths", () => {
  const weights = [4,10,10,100,400,600,600,600,200,200,200,-200,-200,300,400,500,100,-100,-100];
  const version = {league_id:"synthetic",version:1,ruleset:"nfl-playoffs-2026-v1",
    ...Object.fromEntries(SCORING_CATEGORIES.map(([key],i)=>[key,weights[i]]))} as LeagueScoringVersion;
  const rows=scoringRows(version);
  assert.equal(rows.length,19);
  assert.equal(rows[0].points,"0.04");
  assert.equal(rows[11].points,"-2.00");
  assert.deepEqual(rows.slice(13,16).map(row=>row.points),["3.00","4.00","5.00"]);
});
