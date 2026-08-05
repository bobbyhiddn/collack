const defaultBrickDelta = 900;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

export function legacyCollisionAndScore(baseline, samples, brickDelta = defaultBrickDelta) {
  return samples.find((state) => state.brickPixels < baseline.brickPixels - brickDelta
    && state.hudHash !== baseline.hudHash) ?? null;
}

export function requireFreshRound(loss, samples) {
  const index = samples.findIndex((state) => state.centerBrightPixels < 50
    && state.frameHash !== loss.frameHash
    && state.brickPixels >= loss.brickPixels - 100);
  assert(index >= 0, "controlled retry produced no observed fresh-round transition");
  return { index, state: samples[index] };
}

export function requireCollisionAndScore(freshRound, samples, brickDelta = defaultBrickDelta) {
  const collisionIndex = samples.findIndex(
    (state) => state.brickPixels < freshRound.brickPixels - brickDelta,
  );
  const scoreIndex = samples.findIndex((state) => state.hudHash !== freshRound.hudHash);
  assert(collisionIndex >= 0, "controlled round produced no observed brick-collision transition");
  assert(scoreIndex >= 0, "controlled round produced no observed score transition");
  const proofIndex = Math.max(collisionIndex, scoreIndex);
  return {
    collisionIndex,
    collision: samples[collisionIndex],
    scoreIndex,
    score: samples[scoreIndex],
    proofIndex,
    proof: samples[proofIndex],
  };
}
