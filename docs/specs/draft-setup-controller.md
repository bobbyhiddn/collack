# Draft and setup controller contract

This document records the implementation boundary delivered by
`dispatch/callack-vslice-draft`. It specializes the APIs in
[`battle-engine-vertical-slice.md`](battle-engine-vertical-slice.md) without
changing that blueprint.

## Canonical state machine

`battle/run.lua` is the only owner of run progression:

```text
draft
  choose_offer × 9
    1 sling → 4 marble blueprints → 4 two-brick kits
setup
  place_brick / move_bag
  lock_setup
battle
  no player commands
  engine consumes battle_handoff and returns immutable completion
result
  new_run constructs another RunState in draft
```

All accepted commands return `{ state, events }`. All rejected commands return
`nil, CommandError`; `CommandError.state_unchanged` is true, and the input state
is not mutated. Accepted commands also return a new state rather than mutating
their input.

The public pure-Lua contracts are:

```text
run.new({ run_seed, content_version, rules_version, player_name? }) -> RunState
run.dispatch(state, RunCommand) -> { state, events } | nil, CommandError
run.snapshot(state) -> RunSnapshot
run.complete_battle(state, BattleCompletion) -> { state, events } | nil, CommandError
run.battle_handoff(state) -> BattleHandoff | nil
run.record(state) -> RunRecord | nil, CommandError
run.replay(record) -> RunState | nil, ReplayError

draft.make_offer(state) -> DraftOffer
opponent.build(opponent_seed, recipe_id?) -> OpponentSpec
setup.validate(loadout) -> true | ValidationError[]

presentation.project(run_snapshot, previous_frame, current_frame, alpha)
  -> PresentationState
```

`battle/setup.lua` exports the union-returning setup validator for the blueprint
API (`validate_detailed` exposes the internal boolean-plus-errors form) while
retaining the discrete prototype fixtures until physics integration removes
them.

## Offers and player choices

Every offer has exactly three cards. A card contains mechanics copy, synergy
tags with readable labels/descriptions, comparable `draft_value`, an art ID,
and inspectable category details:

- sling cards expose the whole-bag physical modifier;
- marble cards expose role, rarity, ordered shells, durability, collisions,
  core angle bias, and release;
- kit cards expose both brick behaviours and suggested relative placement.

After the first pick, every generated offer includes a current-build match and
a new direction. The generator excludes already selected marble blueprints and
kits for the current run. Offer generation uses only `domain_seeds.draft`.

The catalog contains 3 supported slings, 12 marble blueprints, 8 positional
brick kits spanning all 18 existing brick archetypes, and 21 readable synergy
identities. Individual picks become stable player instances (`player-m01…04`,
`player-b01…08`); there is no whole-army choice.

## Opponent boundary

`opponent.build` runs once in `run.new`, before the first player offer, using
only `domain_seeds.opponent`. It chooses among:

- Bastion: 10 bricks, 3 marbles;
- Fuse Garden: 6 bricks, 4 marbles;
- Glass Cannon: 5 bricks, 3 marbles.

Each recipe owns two visible scout tags, sling options, formation constraints,
bag role order, and seeded same-value substitutions. Validation checks shell
caps, unique IDs, exact bag permutation, known content, and formation overlap.
Every recipe count is intentionally asymmetric with the player's 8/4 loadout,
so it cannot be a mirrored player army.

## Setup and battle handoff

The setup formation is a local 3 × 7 UID grid. The bag is an exact permutation
of the four drafted marble UIDs. `lock_setup` succeeds only after every drafted
brick is placed once and the bag validates.

The emitted `battle_handoff` value contains:

```text
{
  schema_version, run_id, battle_seed, rules_version, content_version,
  player {
    name, sling_id, sling, marbles, bricks, formation, bag_order, build_tags
  },
  opponent {
    recipe_id, name, scout_tags, sling_id, sling,
    marbles, bricks, formation, bag_order
  }
}
```

The continuous engine creates its world from this value. Combat is automatic:
the controller exposes no player completion or targeting action. When the
engine finishes, integration calls `run.complete_battle` (or
`run_controller.complete_battle`) with serializable `{ result, recording }`.
The recording must contain frames, exact-tick events, and keyframes.

## Input and presentation

`src/run_controller.lua` is pure Lua and holds view selection separately from
`RunState`. The required touch path is expressed through semantic action IDs:

```text
offer:<choice_id> → select:<choice_id> → confirm_offer
brick:<uid> → cell:<row>:<col>
marble:<uid> → slot:<before_uid | tail>
lock_setup
entity:<id>, battle_pause, battle_speed, battle_mute, battle_motion
replay_battle → replay_next / replay_close
new_run
```

Touch and mouse both call `run_controller.activate(model, action_id, source)`;
`source` never changes rules or branching. `PresentationState.actions` carries
the same IDs, enabled state, and logical bounds no smaller than 44 × 44 on the
390 × 844 surface.

Inspect, pending selection, entity inspection, pause, speed, mute, reduced
motion, and replay cursor are view state. They cannot alter `RunState`. Replay
reads stored frames directly and never calls combat stepping.

## Integration ownership

This branch deliberately does not implement continuous physics or replace the
current exhibition renderer. The physics integration must:

1. map the handoff's UID formations and ordered rosters into the continuous
   world without regenerating content;
2. feed canonical adjacent `BattleFrame` snapshots to `presentation.project`;
3. call the engine-only completion API with a versioned recording;
4. preserve run/domain seeds and stable UIDs in checkpoints and recording.

The presentation integration may replace the legacy event adapter and
`src/main.lua`, but must keep the semantic action IDs and controller calls. It
must not copy draft legality, placement validation, bag ordering, or winner
rules into LÖVE input/rendering.
