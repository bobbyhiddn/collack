#!/usr/bin/env node

import assert from "node:assert/strict";
import {
  legacyCollisionAndScore,
  requireCollisionAndScore,
  requireFreshRound,
} from "./paddle-browser-transition-contract.mjs";

const state = (overrides = {}) => ({
  frameHash: "fresh-moving",
  brickPixels: 42_695,
  hudHash: "score-zero",
  centerBrightPixels: 0,
  ...overrides,
});
const fresh = state();
const collision = state({
  frameHash: "first-collision",
  brickPixels: 41_115,
  hudHash: "score-thirty",
});
const loss = state({
  frameHash: "stable-loss",
  brickPixels: 41_115,
  hudHash: "score-thirty",
  centerBrightPixels: 126,
});

assert.equal(legacyCollisionAndScore(collision, [collision, loss]), null,
  "legacy observer unexpectedly proved a collision that happened before attachment");

const delayedSchedule = [loss, loss, fresh, fresh, collision, collision];
const restarted = requireFreshRound(loss, delayedSchedule);
assert.equal(restarted.index, 2, "controlled observer missed the reset transition");
const proof = requireCollisionAndScore(restarted.state, delayedSchedule.slice(restarted.index + 1));
assert.equal(proof.collision.frameHash, "first-collision");
assert.equal(proof.score.frameHash, "first-collision");

assert.throws(
  () => requireCollisionAndScore(fresh, [fresh, state({ frameHash: "hud-only", hudHash: "score-thirty" })]),
  /no observed brick-collision transition/,
  "missing collision evidence did not fail closed",
);
assert.throws(
  () => requireCollisionAndScore(fresh, [fresh, state({ frameHash: "brick-only", brickPixels: 41_115 })]),
  /no observed score transition/,
  "missing score evidence did not fail closed",
);
assert.throws(
  () => requireFreshRound(loss, [loss, loss]),
  /no observed fresh-round transition/,
  "missing retry evidence did not fail closed",
);

console.log("[paddle-browser-sync] OK: delayed attachment race reproduced; controlled round and 3 negative controls passed");
