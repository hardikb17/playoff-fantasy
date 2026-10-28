import assert from "node:assert/strict";
import { test } from "node:test";
import { generateSnakeDraftOrder, getSnakeDraftTurn } from "./draft-order";

for (const [count, rounds, total] of [[10, 8, 80], [12, 7, 84], [10, 7, 70]]) {
  test(`${count} managers × ${rounds} rounds distributes ${total} picks`, () => {
    const ids = Object.freeze(Array.from({ length: count }, (_, i) => `manager-${i + 1}`));
    const before = [...ids];
    const order = generateSnakeDraftOrder(ids, rounds);
    assert.equal(order.length, total);
    for (const id of ids) {
      assert.equal(order.filter((turn) => turn.managerId === id).length, rounds);
    }
    for (let round = 1; round <= rounds; round++) {
      const turns = order.slice((round - 1) * count, round * count);
      assert.deepEqual(turns.map((turn) => turn.managerId), round % 2 ? ids : [...ids].reverse());
      assert.deepEqual(turns.map((turn) => turn.positionInRound), Array.from({ length: count }, (_, i) => i + 1));
      assert.ok(turns.every((turn) => turn.round === round));
    }
    for (const [index, turn] of order.entries()) {
      assert.equal(turn.overallPick, index + 1);
      assert.deepEqual(getSnakeDraftTurn(ids, rounds, index + 1), turn);
    }
    assert.deepEqual(ids, before);
  });
}

test("round boundaries repeat the endpoint manager; first and last picks are one-based", () => {
  const ids = ["a", "b", "c"];
  assert.deepEqual(generateSnakeDraftOrder(ids, 3).map((turn) => turn.managerId), [
    "a", "b", "c", "c", "b", "a", "a", "b", "c",
  ]);
  assert.deepEqual(getSnakeDraftTurn(ids, 3, 1), { overallPick: 1, round: 1, positionInRound: 1, managerId: "a" });
  assert.deepEqual(getSnakeDraftTurn(ids, 3, 9), { overallPick: 9, round: 3, positionInRound: 3, managerId: "c" });
  assert.equal(getSnakeDraftTurn(ids, 3, 3).managerId, getSnakeDraftTurn(ids, 3, 4).managerId);
  assert.equal(getSnakeDraftTurn(ids, 3, 6).managerId, getSnakeDraftTurn(ids, 3, 7).managerId);
});

test("one manager gets every turn, including a one-round draft", () => {
  assert.deepEqual(generateSnakeDraftOrder(["solo"], 3), [
    { overallPick: 1, round: 1, positionInRound: 1, managerId: "solo" },
    { overallPick: 2, round: 2, positionInRound: 1, managerId: "solo" },
    { overallPick: 3, round: 3, positionInRound: 1, managerId: "solo" },
  ]);
  assert.deepEqual(generateSnakeDraftOrder(["solo"], 1), [getSnakeDraftTurn(["solo"], 1, 1)]);
});

test("both entry points reject empty, blank, duplicate and non-string IDs", () => {
  for (const ids of [[], [""], [" \t"], ["a", "a"], ["a", 1], Array(2)]) {
    assert.throws(() => generateSnakeDraftOrder(ids as string[], 2), TypeError);
    assert.throws(() => getSnakeDraftTurn(ids as string[], 2, 1), TypeError);
  }
});

test("both entry points reject invalid rounds and unsafe total picks", () => {
  for (const rounds of [0, -1, 1.5, NaN, Infinity, -Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => generateSnakeDraftOrder(["a"], rounds), RangeError);
    assert.throws(() => getSnakeDraftTurn(["a"], rounds, 1), RangeError);
  }
  assert.throws(() => generateSnakeDraftOrder(["a", "b"], Number.MAX_SAFE_INTEGER), RangeError);
  assert.throws(() => getSnakeDraftTurn(["a", "b"], Number.MAX_SAFE_INTEGER, 1), RangeError);
  assert.throws(() => generateSnakeDraftOrder(["a"], 2 ** 32), RangeError);
});

test("rejects picks outside the draft, fractional, nonfinite, or unsafe", () => {
  for (const pick of [0, -1, 7, 1.5, NaN, Infinity, -Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => getSnakeDraftTurn(["a", "b"], 3, pick), RangeError);
  }
});
