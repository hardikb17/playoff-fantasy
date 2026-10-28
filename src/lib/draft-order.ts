export interface DraftTurn {
  overallPick: number;
  round: number;
  /** Chronological position in this round, not the original manager slot. */
  positionInRound: number;
  managerId: string;
}

function validateDraft(managerIds: readonly string[], rounds: number): number {
  if (!Array.isArray(managerIds) || managerIds.length === 0) {
    throw new TypeError("At least one manager ID is required.");
  }
  const seen = new Set<string>();
  for (const id of managerIds) {
    if (typeof id !== "string" || id.trim().length === 0) {
      throw new TypeError("Manager IDs must be nonempty strings.");
    }
    if (seen.has(id)) throw new TypeError("Manager IDs must be unique.");
    seen.add(id);
  }
  if (!Number.isSafeInteger(rounds) || rounds < 1) {
    throw new RangeError("Rounds must be a positive safe integer.");
  }
  const totalPicks = managerIds.length * rounds;
  if (!Number.isSafeInteger(totalPicks)) {
    throw new RangeError("Total picks must be a safe integer.");
  }
  return totalPicks;
}

function turnAt(managerIds: readonly string[], overallPick: number): DraftTurn {
  const round = Math.floor((overallPick - 1) / managerIds.length) + 1;
  const offset = (overallPick - 1) % managerIds.length;
  const managerIndex = round % 2 === 1 ? offset : managerIds.length - 1 - offset;
  return {
    overallPick,
    round,
    positionInRound: offset + 1,
    managerId: managerIds[managerIndex],
  };
}

/** IDs are already ordered; no randomization or input mutation occurs here. */
export function getSnakeDraftTurn(
  managerIds: readonly string[],
  rounds: number,
  overallPick: number,
): DraftTurn {
  const totalPicks = validateDraft(managerIds, rounds);
  if (!Number.isSafeInteger(overallPick) || overallPick < 1 || overallPick > totalPicks) {
    throw new RangeError("Overall pick must be an integer within the draft.");
  }
  return turnAt(managerIds, overallPick);
}

/** Returns one-based pick/round metadata in chronological pick order. */
export function generateSnakeDraftOrder(
  managerIds: readonly string[],
  rounds: number,
): DraftTurn[] {
  const totalPicks = validateDraft(managerIds, rounds);
  // Array lengths have a stricter limit than JavaScript safe integers.
  if (totalPicks > 0xffffffff) {
    throw new RangeError("Draft order exceeds the maximum array length.");
  }
  return Array.from({ length: totalPicks }, (_, index) => turnAt(managerIds, index + 1));
}
