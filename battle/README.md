# `battle/` — Callack battle simulation core

Headless, deterministic, pure Lua. No `love.*`, no graphics, no input. This runs
under plain `lua` or `luajit` from the command line so CI can test it without a
display.

Callack is a **two-player auto battler**. Each player has a brick formation and a
sling loaded with marbles, and fires at the opponent. There is no paddle.

The design decisions behind this model are recorded in
[`docs/decisions/0004-battle-sim-model.md`](../docs/decisions/0004-battle-sim-model.md).

## Run it

From the repository root:

```
lua5.1 battle/cli.lua --seed 4242          # print the whole battle log
lua5.1 battle/cli.lua --seed 4242 --quiet  # result line only
lua5.1 battle/tests/run_all.lua            # the test suite
```

Same seed, same setup, same log — byte for byte, on any machine:

```
lua5.1 battle/cli.lua --seed 7 > a.log
lua5.1 battle/cli.lua --seed 7 > b.log
diff a.log b.log        # empty
```

## The model

**Marble** — a core wrapped in an ordered array of shells, outermost first.
`shells[1]` takes the next hit. Rarity caps shell count: common 1, uncommon 2,
rare 3, epic 4, legendary 5. Every marble has at least one shell, so the core is
never exposed while the marble is in play.

**Core** — supplies a trajectory vector (negative drifts left, positive right,
zero flies straight) and, at uncommon and above, a release effect. Common cores
get baseline blowback only. Release effects *add to* baseline blowback; they
never replace it.

**Shell** — supplies mineral, pattern, a collision effect, and durability.
Collisions spend durability. At zero the shell breaks and the next one inward
becomes outermost.

**Brick** — a static formation element with behaviour, not just hit points:

| archetype | behaviour |
|---|---|
| `plain_block`, `chalk_block` | inert — the control. Takes damage, dies, does nothing else. |
| `basalt_absorber` | soaks 1 off every hit and grinds an extra point of durability off the shell. |
| `mirror_pane` | if it survives the hit, throws the marble back and flips its trajectory. |
| `powder_keg` | detonates on death into its orthogonal neighbours, which can chain. |

**Sling** — modifies every marble in the hand: damage, durability, momentum,
aim, and scatter. Applied once at build time and baked into the marble's stats.

## How a battle runs

Play advances in **volleys**. In each volley both players commit their next
marble *before* either cascade resolves; the cascades then resolve one at a
time, each to completion; and win conditions are checked once, after both are
done. That is what makes it simultaneous rather than turn-taking — neither side
can be denied its shot, and neither side can win "first" inside a volley. A
mutual kill in one volley is a **draw**.

A launched marble **cascades**: it enters the enemy formation and steps forward
row by row, drifting sideways by its trajectory, colliding with whatever it
meets. It stops when it runs out of momentum, leaves the grid, or loses its last
shell.

When the last shell breaks the core is exposed and **releases**. The release
always produces baseline blowback, which displaces marbles within a radius on
**both racks — the firing player's own marbles included**. A marble with nowhere
to be shoved takes the force instead and loses shell durability. That is what
makes clustering dangerous.

**Win conditions**, symmetric: all opponent bricks destroyed is victory; all own
marbles destroyed is defeat.

## Layout

```
battle/
  rng.lua           MINSTD generator — deterministic, replaces math.random
  effects.lua       collision and release profiles, as data
  marble.lua        marble construction and the rarity/shell invariants
  formation.lua     the fixed brick grid
  battlelog.lua     the battle log and its canonical text rendering
  engine.lua        cascade, blowback, volleys, win conditions
  setup.lua         hardcoded marble / brick / sling sets and the demo matchup
  cli.lua           run one battle from a seed and print the log
  content/          cores, shells, bricks, slings
  tests/            headless test suite — run_all.lua is the entry point
```

## The log

Every event renders as one line: sequence, volley, side, type, then the event's
own fields as `key=value` pairs **sorted by key**. Sorting is what makes the
rendering independent of Lua's table iteration order, which is not stable across
runs. Nothing may emit event fields in `pairs()` order.

```
0016 v02 A launch aimed_col=3 core=shrapnel_geode entry_col=3 lane=3 marble=2 ...
0017 v02 A collision brick=plain_block col=3 damage=2 effect=cleave marble=2 ...
0018 v02 B brick_damaged brick=plain_block col=3 damage=2 hp_left=0 row=1 ...
```

## Scope

Marble, brick and sling sets are hardcoded here on purpose. Content generation,
procedural art and the asset pipeline are a separate project. There is no
rendering, no input handling and no LÖVE integration in this directory, and
`battle/tests/test_purity.lua` fails the build if any of it appears.
