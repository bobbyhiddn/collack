# Battle Engine vertical slice

This is the build contract for REQ-BEC-009, REQ-BEC-010 and REQ-BEC-011. It
defines the first product-shaped run and the boundary between rules, physics,
recording and presentation.

## 1. Run state machine

`RunState` is the only canonical owner of progression.

| Phase | Canonical player command | Exit condition |
|---|---|---|
| `draft` | `choose_offer(offer_id, choice_id)` | 1 sling, 4 marbles and 4 two-brick kits chosen |
| `setup` | `place_brick(brick_uid, cell)`, `move_bag(marble_uid, before_uid)`, `lock_setup()` | all 8 bricks placed, 4 unique marbles ordered |
| `battle` | none | a win condition or the exchange limit resolves |
| `result` | `new_run()` | creates a new `RunState` in `draft` |

`replay_battle`, inspect, pause, speed, mute and reduced-motion controls are view
commands. They cannot change `RunState` or the recorded result. Invalid or
out-of-phase commands return a structured error and leave state unchanged.

The durable value-only shape is:

```text
RunState {
  schema_version, run_id, run_seed, content_version, rules_version, phase,
  draft { stage, round, offer, picks },
  player { sling, marbles, bricks },
  opponent { recipe_id, name, scout_tags, sling, marbles, formation, bag_order },
  setup { formation[3][7], bag_order[4], valid, errors },
  battle { tick, exchange, world, pending_events, recording },
  result { outcome, winner, reason, exchanges },
  journal[]
}
```

Transitions are monotonic. `new_run()` constructs another run rather than
rewinding the prior one.

## 2. Draft contract

There is no shop currency or reroll in this slice. Every offer contains three
curated, comparable choices and is generated before the player's choice. The
offer and chosen ID are journaled.

### Sling

The first offer contains the three supported slice archetypes:

- **Momentum** converts the whole bag toward launch impulse and penetration.
- **Ricochet** converts impact energy into rebound and chained angles.
- **Effect Amplifier** enlarges fields, release impulse and non-chip effects.

Volley, spread and precision remain content for later slices. Excluding them
keeps the paired one-marble cadence legible while the physical model is proven.

### Marbles

Four rounds each offer three complete marble blueprints, never loose random
parts. A card exposes shell order and durability, core angle bias and release,
collision effect, physical role, rarity, and synergy tags. Curated roles include
opener, breaker, survivor, fuse, control and finisher.

Choices in one offer have the same `draft_value` band. After round one, the
generator guarantees at least one choice that shares a tag with the current
build and at least one that adds a new tag. The third may counter a visible CPU
scout tag. It must not always be correct to select the highest rarity.

The existing `chalk_common`, `quartz_common`, `drifter_common`,
`geode_uncommon`, `warden_rare`, `lodestone_epic` and `cinder_legendary`
blueprints seed this catalog. Their numbers may be rebalanced for continuous
physics without changing their identities.

### Brick kits

Four rounds each offer three kits of two bricks, yielding eight bricks. Kits are
curated positional ideas, not two unrelated random IDs. Initial kits cover:

- absorber + fortifier: adjacent protection;
- mirror + anchor: rebound lane;
- regenerator + aegis: sustain;
- venom + rime: control field;
- lodestone + void: cluster then strip;
- shatter + powder keg: burst chain;
- splice + powder keg: adjacency damage;
- vault + temporal: protected depth.

Cards show both behaviours, suggested relative placement, tags, `draft_value`,
current synergies and any scouted counter. Offer validation requires unique
choice IDs, mechanics copy and tags; placeholder stat-only cards are invalid.

All random selection uses the `draft` seed stream. Offer generation cannot
consume the opponent or battle streams.

## 3. Seeded asymmetric CPU

At run creation, the `opponent` seed selects one of at least three validated
recipes:

- **Bastion:** more defensive bricks and a short durable bag.
- **Fuse Garden:** fewer walls, release-heavy marbles and effect fields.
- **Glass Cannon:** a sparse quality formation and hard penetrating shots.

A recipe owns a formation constraint, bag role order, sling family and
same-value substitutions. It is generated once, before the player drafts, and
does not inspect later player choices. The player sees its name and two honest
scout tags from the first draft screen.

CPU counts may differ from the player's 8 bricks and 4 marbles; that asymmetry is
intentional and recipe-balanced. CPU marbles still obey rarity shell caps, its
formation has no overlaps, and its bag is an exact permutation of its roster.
A mirrored copy of the player loadout is never an accepted opponent.

Seeds derive independently from `run_seed` as `draft`, `opponent` and `battle`.
Adding a draft draw must not change the already-created opponent or battle RNG.

## 4. Setup rules

The player's eight drafted bricks must each occupy one unique cell in a 3 × 7
grid. Empty cells are legal. Local row 1 faces the arena centre; the world
transform rotates the CPU grid so the same local rule applies to both sides.
Bricks cannot overlap, rotate or be placed outside the grid in this slice.

The four drafted marbles form an explicit bag permutation. Index 1 launches
first. A surviving marble returns to the tail after an exchange; a destroyed
marble is removed. Order never shuffles. A lock is accepted only when both the
formation and bag permutation validate.

Setup previews adjacency and build tags, but predicted damage or winner odds are
not required.

## 5. Canonical continuous battle

The arena is one shared portrait world: player at the bottom, CPU at the top.
Static brick AABBs are created from both local grids. Dynamic launched marbles
have stable IDs, position, velocity, radius, mass, restitution, shell state,
owner and statuses. Walls, marbles and fields live in the same world.

At an exchange boundary both sides remove the bag head and launch on the same
tick. The world then advances in exact `1/120 s` steps. A render frame may run
zero or many fixed steps, capped at eight per update; canonical time is never
advanced with a variable `dt` and queued steps are not silently dropped.
Rendering interpolates between the last two completed snapshots.

Minimum collision surface:

- swept circle against arena walls and brick AABBs;
- circle against circle;
- time-of-impact then stable entity-ID ordering;
- rebound and impulse response from normal velocity, mass and restitution;
- a maximum launch speed that prevents tunnelling beyond the swept solver;
- collision impulse driving shell wear, brick damage and effect activation.

Core trajectory becomes launch-angle bias; discrete per-row drift is retired.
Sling momentum becomes launch impulse or mass tuning; discrete cascade momentum
is retired. Reflect and ricochet alter physical rebound. Magnetic, poison and
freeze are fixed-step fields/statuses. Shatter, shell break, core release,
baseline blowback and scorch apply damage or radial impulse to every qualifying
marble regardless of owner. Presentation-only hits are forbidden.

An active marble settles after its speed remains below the sleep threshold for
the configured number of ticks, or is destroyed when its final shell releases.
Both active marbles and transient fields must settle before the next exchange.
The battle ends at that boundary when either formation has no live bricks or
either roster has no live marbles. Simultaneous winning conditions draw. A
40-exchange cap and a per-exchange simulated-time cap produce explicit draws,
never a frame-rate-dependent result.

## 6. State, events and presentation APIs

Downstream modules implement these boundaries:

```text
run.new({ run_seed, content_version }) -> RunState
run.dispatch(state, RunCommand) -> { state, events } | CommandError
run.snapshot(state) -> RunSnapshot

draft.make_offer(state) -> DraftOffer
opponent.build(opponent_seed, recipe_id?) -> OpponentSpec
setup.validate(loadout) -> true | ValidationError[]

battle.new({ battle_seed, player, opponent, rules_version }) -> BattleWorld
battle.step(world, 1/120) -> DomainEvent[]
battle.snapshot(world) -> BattleFrame
battle.result(world) -> BattleResult | nil

recording.append(frame_or_event)
recording.finish(result) -> BattleRecording
presentation.project(run_snapshot, previous_frame, current_frame, alpha)
  -> PresentationState
```

`RunSnapshot`, `BattleFrame`, `DomainEvent`, `BattleRecording` and
`PresentationState` contain serializable values only and carry schema versions.
The client may hold snapshots, never mutable engine objects.

`PresentationState` supplies screen, labels, art IDs, mechanics/tags, enabled
actions, world transforms, HP/shell ratios, effect cues and result copy. The
renderer chooses art, particles, sound and interpolation. It does not choose
targets, calculate damage, move canonical bodies or determine a winner.

Domain events cue particles, sound, haptics and accessibility narration. They
are not a required visible feed and are not used to invent trajectories.

## 7. Replay

`RunRecord` stores:

- schema/content/rules versions and all three derived seeds;
- every accepted canonical command and generated offer;
- immutable player and CPU match specs;
- a `BattleRecording`;
- terminal result and quantized checkpoint hashes.

`BattleRecording` stores visible state every four ticks (30 Hz), events at exact
ticks, a full keyframe every 120 ticks, and the final state/result. Frames use
stable IDs and quantized transforms for portable playback. Replay begins from
the recording, seeks from keyframes and interpolates frames; it never calls
`battle.step`.

Headless verification separately resimulates the journal on the same build and
compares one-second checkpoint hashes plus the result. A mismatch is a
determinism failure, not permission for the presentation to patch the outcome.

## 8. Mobile interaction map

All required actions work at 390 × 844 with safe-area insets and targets at
least 44 × 44 logical pixels. Mouse performs the same hit actions on desktop.

| Surface | Required touch path |
|---|---|
| Draft | tap card to inspect in a bottom sheet; tap its explicit Select action |
| Setup formation | tap a brick, then a legal cell; tapping another cell moves it; drag is optional |
| Setup bag | tap a marble then an insertion slot; drag reorder is optional |
| Setup lock | persistent bottom action, disabled with visible validation reasons |
| Battle | no reflex input; tap entity to inspect; pause, 1×/2×, mute and reduced-motion are view controls |
| Result | Replay Battle uses the recording; New Run creates the next seeded draft |

No mechanic depends on hover, right click, keyboard, tiny grid dragging or a
text event log. Long press may be an inspection shortcut but cannot be the only
path.

## 9. Presentation acceptance

Draft, setup, battle and result share the warm handcrafted tabletop direction:
luminous collector glass, mineral bricks, brass-and-wood sling details, clear
type, restrained magical effects and readable motion. Art IDs and effect cues
come through `PresentationState`.

Mechanical family, rarity, shell count, damage state, targeting and major
effects must read from cards, objects and motion. Sound is muteable. Reduced
motion replaces shake, long trails and rapid pulses while preserving positions,
state changes and outcome.

Debug primitives, default controls and the old event feed may exist behind a
development flag only.

## 10. Migration and downstream gates

1. Keep `battle/rng.lua`, content IDs, shell/core constraints, fixed formation
   validation, HP/effect vocabulary, win rules and packaging scripts.
2. Add run, draft, opponent and setup modules against
   `battle/vslice_contract.lua`; remove `default_matchup()` from the product
   boot path.
3. Replace the internals of `battle/engine.lua` with the fixed-step world.
   Rework effect values at the physical boundary; do not wrap or call the
   discrete cascade engine.
4. Replace the event-only presentation adapter with snapshot projection and the
   four run surfaces.
5. Rewrite applicable rule tests against the new world, add fixed-step,
   collision, seed-stream, CPU, recording and state-machine tests, then delete
   obsolete event-order assertions and the required-feed UI.
6. Update browser verification to complete the entire touch run at phone size,
   replay its recording, and exercise mouse on desktop. Build and deployment
   plumbing remains unchanged until the reviewed product path passes.

No downstream battle implementation is accepted unless:

- variable render frame partitions produce matching checkpoint hashes/results;
- visible transforms come from `BattleFrame`;
- replay succeeds with `battle.step` unavailable;
- player and CPU loadouts validate and are not mirrors;
- touch can complete draft, setup, lock, battle and result;
- headless rules/physics tests and the packaged browser build pass.
