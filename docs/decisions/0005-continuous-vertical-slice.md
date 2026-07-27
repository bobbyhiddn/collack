# ADR 0005 — The product is a continuous draft autobattler

- **Date:** 2026-07-26
- **Status:** Accepted
- **Decided by:** Alpha, implementing the operator's rejection of the fixed-seed
  event-log exhibition
- **Scope:** The Battle Engine Core vertical slice
- **Follows:** [ADR 0001](0001-game-engine.md)
- **Partially supersedes:** [ADR 0004](0004-battle-sim-model.md)

## Decision

Callack ships one complete run:

`draft → setup → autobattle → result`

The battle is driven by one canonical continuous 2D state stepped at 120 Hz.
Marbles have positions, velocities, radii, mass and shells. Bricks occupy the
fixed formation grid but collide as bodies in world space. Walls, marbles,
bricks and force fields resolve through that state, and the winner is calculated
from it. The renderer interpolates read-only snapshots; it does not infer
motion from an event log.

Both sides commit the head of their ordered bag on the same simulation tick.
Those marbles then fly concurrently in a shared arena. The next pair is not
committed until both are destroyed or settled and all effects from the exchange
have resolved. Win conditions are checked only at that boundary, so resolution
order cannot award a mutual finish to one side.

## What remains from ADR 0004

- Formation editing uses a 3 × 7 fixed grid.
- The player explicitly orders the marble bag.
- Bricks use small HP pools and distinct behaviours.
- Shell caps, core release, friendly-and-enemy blowback, content identities,
  recursion guards and both win conditions remain.
- Pure Lua rules remain headless-testable and use a controlled seeded RNG.

## What is replaced

- Grid-cell drift and integer momentum are not combat physics.
- A completed event sequence is not the canonical battle.
- Cascades do not run A then B while pretending to be simultaneous.
- `src/presentation.lua` is not a permanent compatibility boundary.
- The default fixed matchup is a fixture, not a product mode.

Repository history preserves the discrete prototype. The migration will not
carry a second simulation or compatibility adapter merely to protect that sunk
work.

## Determinism and replay boundary

The simulation uses a fixed step, domain-separated seeds, stable entity IDs and
stable collision ordering. Same-build resimulation must reach the same
quantized checkpoints and result.

Cross-runtime playback does not depend on floating-point identity. During a
battle, the engine records visible state at 30 Hz, discrete effect events at
their simulation tick, a full keyframe every second, and the final result.
Replay consumes that immutable recording and never re-runs combat. The run
journal still records the seed and player commands for diagnostics and
same-build verification.

## Consequences

The existing content vocabulary and build pipeline are useful. The existing
discrete resolution loop and required text feed are not. Downstream work starts
from the contracts in
[`docs/specs/battle-engine-vertical-slice.md`](../specs/battle-engine-vertical-slice.md)
and `battle/vslice_contract.lua`.
