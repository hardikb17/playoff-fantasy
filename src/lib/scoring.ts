/** A complete normalized stat line; missing values are never confirmed zeros. */
export interface NormalizedStats {
  passingYards: number;
  rushingYards: number;
  receivingYards: number;
  receptions: number;
  passingTouchdowns: number;
  rushingTouchdowns: number;
  receivingTouchdowns: number;
  returnTouchdowns: number;
  passingTwoPointConversions: number;
  rushingTwoPointConversions: number;
  receivingTwoPointConversions: number;
  interceptionsThrown: number;
  fumblesLost: number;
  fieldGoalsMadeUnder40: number;
  fieldGoalsMade40To49: number;
  fieldGoalsMade50Plus: number;
  extraPointsMade: number;
  fieldGoalsMissed: number;
  extraPointsMissed: number;
}

const WEIGHTS: Readonly<Record<keyof NormalizedStats, number>> = {
  passingYards: 4,
  rushingYards: 10,
  receivingYards: 10,
  receptions: 100,
  passingTouchdowns: 400,
  rushingTouchdowns: 600,
  receivingTouchdowns: 600,
  returnTouchdowns: 600,
  passingTwoPointConversions: 200,
  rushingTwoPointConversions: 200,
  receivingTwoPointConversions: 200,
  interceptionsThrown: -200,
  fumblesLost: -200,
  fieldGoalsMadeUnder40: 300,
  fieldGoalsMade40To49: 400,
  fieldGoalsMade50Plus: 500,
  extraPointsMade: 100,
  fieldGoalsMissed: -100,
  extraPointsMissed: -100,
};

const YARDAGE = new Set<keyof NormalizedStats>([
  "passingYards", "rushingYards", "receivingYards",
]);

export interface FantasyScore {
  /** Each value and the total are integer hundredths of a fantasy point. */
  breakdown: Record<keyof NormalizedStats, number>;
  total: number;
}

/**
 * Scores normalized categories only. Normalizers must keep TD categories
 * disjoint, exclude conversion plays from ordinary play stats, and assign made
 * FGs to the under-40 / 40–49 / 50+ bands. Source-play deduplication is external.
 * Blocked-kick and unusual recovery-TD classifications remain unresolved.
 */
export function scoreFantasyStats(stats: Readonly<NormalizedStats>): FantasyScore {
  if (stats === null || typeof stats !== "object" || Array.isArray(stats)) {
    throw new TypeError("A complete normalized stat line is required.");
  }
  const breakdown = {} as FantasyScore["breakdown"];
  let total = 0;
  for (const category of Object.keys(WEIGHTS) as (keyof NormalizedStats)[]) {
    if (!Object.hasOwn(stats, category)) {
      throw new TypeError(`Missing stat category: ${category}`);
    }
    const value = stats[category];
    if (!Number.isSafeInteger(value) || (!YARDAGE.has(category) && value < 0)) {
      throw new RangeError(`${category} must be a safe integer${YARDAGE.has(category) ? "" : " count >= 0"}.`);
    }
    const points = value * WEIGHTS[category];
    if (!Number.isSafeInteger(points)) {
      throw new RangeError(`Unsafe scoring result for ${category}.`);
    }
    total += points;
    if (!Number.isSafeInteger(total)) {
      throw new RangeError("Unsafe cumulative scoring result.");
    }
    breakdown[category] = points === 0 ? 0 : points;
  }
  return { breakdown, total };
}

/** Formats integer hundredths without floating-point division/rounding. */
export function formatFantasyPoints(hundredths: number): string {
  if (!Number.isSafeInteger(hundredths)) {
    throw new RangeError("Fantasy points must be safe integer hundredths.");
  }
  const digits = Math.abs(hundredths).toString().padStart(3, "0");
  return `${hundredths < 0 ? "-" : ""}${digits.slice(0, -2)}.${digits.slice(-2)}`;
}
