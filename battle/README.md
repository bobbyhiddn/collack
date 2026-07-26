# `battle/` — canonical continuous battle core

This directory is deterministic, headless, pure Lua. It has no `love.*`,
graphics, input, wall-clock time, or global randomness and runs under Lua 5.1
and LuaJIT.

## Canonical APIs

```lua
local battle = require("battle.engine")

local world = battle.new({
  battle_seed = 9125,
  player = player_spec,
  opponent = opponent_spec,
  rules_version = "continuous-v1",
})

local events = battle.step(world, battle.FIXED_DT) -- exactly 1/120 s
local frame = battle.snapshot(world)               -- value-only BattleFrame
local result = battle.result(world)                -- nil until a boundary
local recording = battle.recording(world)          -- value-only 30 Hz frames
local pending = battle.drain_events(world)          -- exact-tick audit events
```

## Product run controller

`battle/run.lua` owns the deterministic
`draft → setup → battle handoff → result` progression. It generates nine
individual offers through `battle/draft.lua`, builds an asymmetric seeded CPU
through `battle/opponent.lua`, and validates the 3 × 7 formation plus explicit
four-marble bag through `battle/setup_rules.lua`. Combat remains input-free;
the continuous engine consumes `battle_handoff` and returns its result plus
immutable recording through `run.complete_battle`. The handoff adapter resolves
formation UIDs without regenerating content, launches the exact chosen bag
order, and retains drafted marble and brick identities in recorded frames.

The exact controller, input, presentation, and integration contracts are in
[`docs/specs/draft-setup-controller.md`](../docs/specs/draft-setup-controller.md).

`new_battle`, `run`, and `simulate` remain command-line/test conveniences over
the same implementation. They do not implement a second rules path.

The lower-level `battle.physics` API supplies `new`, `add_body`, `add_box`,
`add_field`, `step`, `apply_impulse`, `apply_radial_impulse`, `snapshot`,
`drain_events`, and `is_settled`. Its step rejects variable `dt`. Adaptive
microsteps bound travel to a fraction of the smallest active radius after
maximum-speed clamping, preventing fast circles from crossing thin colliders.

## Battle model

Both sides remove their ordered bag head and receive launch velocity on the
same canonical tick. Marbles then move concurrently in one portrait arena.
They have position, velocity, radius, mass, restitution, shell state, owner,
and statuses. Formation cells become static AABBs. Arena walls, every active or
blown marble, magnetic/status fields, and release fields occupy the same world.

Stable body IDs determine contact order. Circle/wall, circle/AABB, and
circle/circle contacts resolve penetration and impulse response. Sling
momentum changes launch speed and mass, core trajectory changes launch angle,
and ricochet/reflect change physical rebound. Poison, freeze, and magnetism
advance in fixed ticks.

Collision impulse activates shell and brick rules in `effects.lua`: absorb,
reflect, regenerate, fortify, poison, freeze, magnetic, shatter, chain, vault,
splice, dummy, aegis, void, mirror, and temporal. A final shell break removes
the marble body and releases its core at that exact transform. Release
blowback is a radial impulse against every qualifying body, regardless of
owner; nearby queued bodies wake into the same exchange.

An exchange ends only after its dynamic bodies sleep and transient fields
expire, or after the explicit simulated-time cap. Survivors return to the bag
tail. Win conditions are evaluated once at this boundary. Simultaneous
conditions draw, as do the 40-exchange and per-exchange caps.

## Snapshots, recording, and events

The event log is an exact-tick audit and effect-cue stream. It is not an
animation script and contains no invented path.

`battle.snapshot` returns a serializable `BattleFrame` with arena metadata,
physical transforms, velocities, AABBs/fields, shell and HP ratios' source
values, queues, statuses, and result. The LÖVE renderer interpolates two such
completed frames through `presentation.project`.

During simulation the engine records:

- a visible frame every four ticks (30 Hz);
- a full keyframe every 120 ticks;
- all domain events at their exact tick;
- the final frame and result.

`presentation.from_recording` replays these immutable values and never calls
`battle.step`. `battle/checkpoints.lua` signs the full one-second keyframes for
same-build partition/determinism verification.

## Run and verify

From the repository root:

```text
lua battle/cli.lua --seed 4242
lua battle/tests/run_all.lua
lua tests/test_presentation.lua
```

## Layout

```text
battle/
  physics.lua       fixed-timestep circles, AABBs, walls, fields, impulses
  engine.lua        launch cadence, content rules, boundaries, recording
  effects.lua       collision/release/status profiles
  marble.lua        shell/core construction and invariants
  formation.lua     fixed setup grid transformed into world AABBs
  checkpoints.lua   stable signatures for recorded one-second keyframes
  battlelog.lua     deterministic audit formatting
  rng.lua           controlled MINSTD generator
  setup.lua         public setup validation boundary
  run.lua           immutable product run state machine and recording journal
  draft.lua         curated seeded three-card offer generation
  opponent.lua      validated asymmetric CPU recipes
  setup_rules.lua   player formation and ordered-bag validation
  cli.lua           draft/setup a seeded run and print its canonical battle
  content/          cores, shells, bricks, and slings
  tests/            deterministic physics and end-to-end tests
```
