import assert from "node:assert/strict";
import { test } from "node:test";
import { formatFantasyPoints, scoreFantasyStats, type NormalizedStats } from "./scoring";

// Explicitly synthetic, complete normalized fixture; production never defaults missing data.
const ZERO: Readonly<NormalizedStats> = Object.freeze({
  passingYards: 0, rushingYards: 0, receivingYards: 0, receptions: 0,
  passingTouchdowns: 0, rushingTouchdowns: 0, receivingTouchdowns: 0,
  returnTouchdowns: 0, passingTwoPointConversions: 0, rushingTwoPointConversions: 0,
  receivingTwoPointConversions: 0, interceptionsThrown: 0, fumblesLost: 0,
  fieldGoalsMadeUnder40: 0, fieldGoalsMade40To49: 0, fieldGoalsMade50Plus: 0,
  extraPointsMade: 0, fieldGoalsMissed: 0, extraPointsMissed: 0,
});

// Independent expected values from SPEC, not imported production weights.
const CASES: [keyof NormalizedStats, number][] = [
  ["passingYards", 4], ["rushingYards", 10], ["receivingYards", 10],
  ["receptions", 100], ["passingTouchdowns", 400], ["rushingTouchdowns", 600],
  ["receivingTouchdowns", 600], ["returnTouchdowns", 600],
  ["passingTwoPointConversions", 200], ["rushingTwoPointConversions", 200],
  ["receivingTwoPointConversions", 200], ["interceptionsThrown", -200],
  ["fumblesLost", -200], ["fieldGoalsMadeUnder40", 300],
  ["fieldGoalsMade40To49", 400], ["fieldGoalsMade50Plus", 500],
  ["extraPointsMade", 100], ["fieldGoalsMissed", -100], ["extraPointsMissed", -100],
];

for (const [category, expected] of CASES) {
  test(`${category} scores independently in hundredths`, () => {
    const result = scoreFantasyStats({ ...ZERO, [category]: 1 });
    assert.equal(result.total, expected);
    assert.deepEqual(result.breakdown, { ...ZERO, [category]: expected });
  });
}

test("complete zero line is valid and input is not mutated", () => {
  const before = { ...ZERO };
  assert.deepEqual(scoreFantasyStats(ZERO), { breakdown: ZERO, total: 0 });
  assert.deepEqual(ZERO, before);
  const stats = Object.freeze({ ...ZERO, passingYards: 17, interceptionsThrown: 1 });
  assert.equal(scoreFantasyStats(stats).total, -132);
  assert.deepEqual(stats, { ...ZERO, passingYards: 17, interceptionsThrown: 1 });
});

test("combined synthetic line matches a hand-calculated 68.98 points", () => {
  const stats: NormalizedStats = {
    passingYards: 287, rushingYards: -3, receivingYards: 48, receptions: 5,
    passingTouchdowns: 2, rushingTouchdowns: 1, receivingTouchdowns: 1,
    returnTouchdowns: 1, passingTwoPointConversions: 1, rushingTwoPointConversions: 1,
    receivingTwoPointConversions: 1, interceptionsThrown: 2, fumblesLost: 1,
    fieldGoalsMadeUnder40: 2, fieldGoalsMade40To49: 1, fieldGoalsMade50Plus: 2,
    extraPointsMade: 4, fieldGoalsMissed: 1, extraPointsMissed: 1,
  };
  // 11.48 - .30 + 4.80 + 5 + 8 + 6 + 6 + 6 + 2 + 2 + 2
  // - 4 - 2 + 6 + 4 + 10 + 4 - 1 - 1 = 68.98
  assert.equal(scoreFantasyStats(stats).total, 6898);
});

test("negative yardage in each category and negative totals are preserved", () => {
  const score = scoreFantasyStats({ ...ZERO, passingYards: -7, rushingYards: -3, receivingYards: -2 });
  assert.equal(score.total, -78);
  assert.equal(score.breakdown.passingYards, -28);
  assert.equal(score.breakdown.rushingYards, -30);
  assert.equal(score.breakdown.receivingYards, -20);
  assert.equal(formatFantasyPoints(score.total), "-0.78");
});

test("interceptions and fumbles lost remain separate penalties", () => {
  const score = scoreFantasyStats({ ...ZERO, interceptionsThrown: 2, fumblesLost: 3 });
  assert.equal(score.breakdown.interceptionsThrown, -400);
  assert.equal(score.breakdown.fumblesLost, -600);
  assert.equal(score.total, -1000);
});

test("passing yards are exact, with no yardage or long-play bonuses", () => {
  assert.equal(scoreFantasyStats({ ...ZERO, passingYards: 1 }).total, 4);
  assert.equal(scoreFantasyStats({ ...ZERO, passingYards: 333 }).total, 1332);
  // Yardage beyond customary bonus thresholds and multiple TDs stays linear.
  assert.equal(scoreFantasyStats({ ...ZERO, passingYards: 400, rushingYards: 200,
    receivingYards: 200, receivingTouchdowns: 2 }).total, 6800);
});

test("made field goal bands score 3, 4, and 5 points, without classifying distances", () => {
  // The normalizer assigns raw distances, including 39/40/49/50 boundaries.
  assert.equal(scoreFantasyStats({ ...ZERO, fieldGoalsMadeUnder40: 2,
    fieldGoalsMade40To49: 3, fieldGoalsMade50Plus: 4 }).total, 3800);
});

test("normalizers supply disjoint TD and conversion counts; no implied ordinary stats", () => {
  const score = scoreFantasyStats({ ...ZERO, passingTwoPointConversions: 1,
    rushingTwoPointConversions: 1, receivingTwoPointConversions: 1 });
  assert.equal(score.total, 600);
  assert.equal(score.breakdown.passingTouchdowns, 0);
  assert.equal(score.breakdown.rushingTouchdowns, 0);
  assert.equal(score.breakdown.receivingTouchdowns, 0);
  assert.equal(score.breakdown.receptions, 0);
});

test("every category must be present and a finite safe integer", () => {
  for (const [category] of CASES) {
    const incomplete: Partial<NormalizedStats> = { ...ZERO };
    delete incomplete[category];
    assert.throws(() => scoreFantasyStats(incomplete as NormalizedStats), /Missing stat category/);
    for (const value of [undefined, null, "1", NaN, Infinity, -Infinity, 0.5,
      Number.MAX_SAFE_INTEGER + 1, Number.MIN_SAFE_INTEGER - 1]) {
      assert.throws(() => scoreFantasyStats({ ...ZERO, [category]: value } as NormalizedStats), RangeError);
    }
    if (!["passingYards", "rushingYards", "receivingYards"].includes(category)) {
      assert.throws(() => scoreFantasyStats({ ...ZERO, [category]: -1 }), RangeError);
    }
  }
  for (const invalid of [null, undefined, [], 0, "stats", Object.create(ZERO)]) {
    assert.throws(() => scoreFantasyStats(invalid as NormalizedStats), TypeError);
  }
});

test("rejects unsafe category products and cumulative arithmetic", () => {
  assert.throws(() => scoreFantasyStats({ ...ZERO, passingYards: Number.MAX_SAFE_INTEGER }), /Unsafe scoring result/);
  assert.throws(() => scoreFantasyStats({ ...ZERO, interceptionsThrown: Number.MAX_SAFE_INTEGER }), /Unsafe scoring result/);
  // Each product is safe; their sum is not.
  assert.throws(() => scoreFantasyStats({ ...ZERO, passingYards: 2_000_000_000_000_000,
    rushingYards: 200_000_000_000_000 }), /Unsafe cumulative/);
  assert.throws(() => scoreFantasyStats({ ...ZERO, passingYards: -2_000_000_000_000_000,
    rushingYards: -200_000_000_000_000 }), /Unsafe cumulative/);
});

test("formats safe integer hundredths to exactly two decimals without rounding", () => {
  for (const [input, expected] of [
    [0, "0.00"], [-0, "0.00"], [1, "0.01"], [-1, "-0.01"], [10, "0.10"],
    [100, "1.00"], [-1234, "-12.34"], [7598, "75.98"],
    [Number.MAX_SAFE_INTEGER, "90071992547409.91"],
    [Number.MIN_SAFE_INTEGER, "-90071992547409.91"],
  ] as const) {
    assert.equal(formatFantasyPoints(input), expected);
  }
  for (const invalid of [NaN, Infinity, -Infinity, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => formatFantasyPoints(invalid), RangeError);
  }
});
