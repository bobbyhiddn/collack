# ADR 0004 — Battle simulation model: the five open questions

- **Date:** 2026-07-26
- **Status:** Partially superseded by
  [ADR 0005](0005-continuous-vertical-slice.md)
- **Decided by:** Alpha (worker), Battle Engine Core, first development slice.
  Every one of these is cheap to reverse while `battle/` is headless and has no
  client bound to it. That stops being true the moment the LÖVE client renders a
  battle log, so revisit them before that, not after.
- **Scope:** `battle/` — the headless simulation. Not the client, not rendering,
  not content generation.
- **Follows:** [ADR 0001](0001-game-engine.md) (LÖVE + Lua is the engine, which
  is why this is pure Lua and not Go).

## Supersession note

The fixed grid, player-ordered bag, brick HP pools, shell/core rules, content
families, friendly-fire blowback, and symmetric win conditions remain product
decisions.

ADR 0005 supersedes section 3's one-cascade-at-a-time resolution, section 5's
discrete cell stepping, and the event log as the output of record. The shipped
vertical slice instead advances both launched marbles in one continuous
fixed-step world and renders that canonical state. This file remains an
accurate description of the current prototype until the migration lands; it is
not the target architecture.

## Why this note exists

The Callack spec describes the battle well enough to argue about and not well
enough to build. Five questions were genuinely open, and you cannot write a
single line of resolution code without answering all five. ADR 0001 exists
because an engine mismatch went unrecorded and the project shipped the wrong
game. These are the same shape of choice: silent, structural, and expensive to
find out about later.

---

## 1. Brick placement: **fixed grid**, not freeform

Formations are a rectangular grid of rows × columns. Row 1 is the front row,
the one an incoming marble meets first. The shipped formations are 3 × 7.

**Why.** Freeform placement means float coordinates, which means float
comparisons in collision resolution, which puts the determinism requirement at
the mercy of floating-point behaviour across platforms. The whole slice is
headless and seed-reproducible; paying that risk for placement freedom nobody
has asked for is a bad trade. Integer grid cells also give chain bricks and
blowback a cheap, unambiguous notion of "adjacent".

**Cost.** Formation design is coarser. Diagonal or overlapping layouts are not
expressible. If the game later wants organic-looking formations, the renderer
can draw a grid formation with jitter without the simulation knowing.

## 2. Marble sequence: **player-ordered**, not shuffled

A player's hand fires in the order the player declared it. Marbles that survive
a cascade return to the back of the queue, so the hand cycles in order.

**Why.** This is an auto battler: once the battle starts the player does
nothing. Loadout order is one of the very few real decisions they get, and
shuffling deletes it. Randomising the firing order would also spend the seed on
noise rather than on outcomes that are interesting to watch.

**Cost.** The opening of a battle is fully predictable from the two loadouts.
That is a feature at this stage — it makes the sim easy to reason about — but it
does mean matchup knowledge will matter a lot once there is a metagame.

## 3. Launch cadence: **fully simultaneous, volley-locked**

Play advances in *volleys*. In each volley:

1. Both players commit their next marble **before either cascade resolves**.
2. The two cascades resolve one at a time, each running to completion.
3. Win conditions are checked **once, after both cascades are done**.

**Why.** The spec asks for "one at a time in sequence, simultaneously on both
sides", which sounds contradictory until you separate *commitment* from
*resolution*. Committing both marbles up front is what makes it simultaneous:
neither side can be denied its shot by what the other side did this volley.
Resolving one cascade at a time is what makes it sequential and legible.

The honest residue: A's cascade is computed before B's, so A can destroy a brick
that B's marble would otherwise have hit. That asymmetry is real. It is bounded
to *within a single volley*, and the two things that would make it decisive are
both closed off — B never loses its shot, and neither side can win mid-volley.
If both sides meet a winning condition in the same volley the result is a
**draw**, explicitly, rather than a win for whoever was resolved first. There is
a test for that case specifically; it is the one assertion that fails loudly if
anyone ever "simplifies" this into turn-taking.

**Cost.** A marble committed at the start of a volley can be destroyed by the
opponent's blowback before it fires. It is logged as `launch_aborted` and the
shot is lost. That is a consequence of simultaneity, not a bug.

## 4. Brick durability: **HP pools**, not binary destruction

Bricks carry a small integer HP pool (1–3 in the shipped set).

**Why.** Binary destruction makes half the brick archetypes meaningless. An
absorb brick that dies to any hit absorbs nothing; a reflect brick that dies to
any hit reflects nothing, because reflection only happens when the pane
survives. Behaviour needs a brick to be able to *take* a hit. Binary destruction
is not lost either — it is exactly HP 1, and the `chalk_block` and `powder_keg`
archetypes use it.

**Cost.** One more number to balance per archetype.

## 5. Firing model: **strictly sequential discrete steps**, not real time

There is no `dt`, no velocity, no continuous physics. A cascade is a sequence of
discrete steps through grid cells: the marble occupies a cell, either collides
or drifts, and advances by its trajectory. Momentum — an integer — is how many
collisions it can push through before it comes to rest.

**Why.** Determinism, and testability. A real-time model would make the battle
log a function of frame timing, and the requirement is that a seed reproduces a
log exactly. Real time is a *presentation* concern: the LÖVE client can animate
a completed log at any speed it likes, including making it look continuous. The
simulation does not need to know.

**Cost.** Some physical effects are not expressible — no spin, no angle of
incidence, no partial deflection. If those turn out to matter to how the game
feels, this is the decision to revisit first, and it is the most expensive of
the five to reverse.

---

## Further choices this forced

These were not among the five, but they were unavoidable to build anything and
would otherwise have been silent.

**The sling aims; the rack lane only biases the aim.** Originally a marble
entered the enemy formation at its own rack lane. That deadlocks: once a lane's
column is cleared, the marble flies through empty space every volley forever,
lands no collisions, wears no shells, and *every seed* ends on the volley limit.
The sling now aims at the live brick nearest the marble's lane and back-computes
the entry column from the core's drift. Aiming is what a sling is for, the rack
lane still decides which part of the formation you threaten, and scatter is the
sling's inaccuracy on top.

**Column space and lane space are the same integer space.** Column *c* of either
formation is lane *c* of either rack. This is the coupling that lets a core
released deep in the enemy formation shove your own marbles around, and it is
why both formations must be the same width.

**A released core returns to the bag but not to the battle.** The spec says the
core "returns to the bag" when the last shell breaks. Taken literally as a
combat resource, marbles could never be depleted and the "all own marbles
destroyed" defeat condition would be unreachable. So the bag is post-battle
inventory: the marble leaves play permanently, the core is what you keep.

**Blowback that cannot displace, crushes.** A marble shoved toward a lane that
is off the rack or already occupied cannot move, so it takes the force instead
and loses a point of shell durability. Without this, clustering would be
harmless, and clustering being dangerous is the stated point of blowback.

**Recursion is depth-capped.** Chain bricks detonating chain bricks, and
blowback kills triggering further blowback, are both capped at depth 3 and log
`chain_capped` / `blowback_capped` when they hit it. A cap that truncates
silently would look like a rules bug from the log.

**Battles are capped at 40 volleys and end in a draw.** A stalemate is a
legitimate outcome and is reported as `volley_limit`, never as a win.

**Randomness is our own MINSTD generator, not `math.random`.** `math.random` is
the host C library's, so the same seed gives different streams on different
platforms and Lua builds. `battle/rng.lua` implements Lehmer/MINSTD in exact
integer arithmetic. Logs are byte-identical across processes and interpreters;
`battle/tests/test_purity.lua` fails the build if `math.random`, `os.time`,
`os.clock` or any `love.*` call appears in `battle/`.
