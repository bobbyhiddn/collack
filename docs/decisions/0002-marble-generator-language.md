# ADR 0002 — Marble Generator stays in Go, on new grounds

- **Date:** 2026-07-26
- **Status:** Accepted
- **Decided by:** ForgePrime (director call). Reversible cheaply until the
  Generator Core project writes code; flag it if you disagree.
- **Scope:** The Callack Marble Generator only — the standalone offline module
  that produces PNG + JSON content packs. Not the game client.
- **Follows:** [ADR 0001](0001-game-engine.md), which made LÖVE the canonical
  game engine.

## Decision

The Marble Generator's **module, CLI, data model, and content-pack pipeline are
written in Go**.

The **renderer is deliberately left open** — see "The renderer is a separate
question" below. This note settles the language of the tool, not the technology
that produces the pixels.

## Why this needed a note at all

The generator spec picks Go, and one of its stated reasons was "eventual Ebiten
integration." ADR 0001 killed Ebiten. So the generator was left standing on a
justification that no longer exists — the same shape of unrecorded mismatch that
produced a single-player brick breaker against a two-player auto-battler spec.
Confirming Go without re-deriving the reason would repeat that mistake in
miniature. This note replaces the dead justification with a live one.

## Why Go, independent of Ebiten

1. **The generator never runs inside the game.** Its spec mandates
   engine-agnostic output (PNG + JSON content packs) and forbids any runtime
   dependency in the game. The game consumes files, not a library. So the
   generator's language is invisible across that boundary, and the
   Lua-everywhere argument from ADR 0001 — which is about game runtime code —
   does not reach it.
2. **Everything runs headless, and that is a LÖVE weakness.** Driving LÖVE as a
   batch tool means `love.graphics`, which wants a window and a GL context.
   Content packs are generated in CI with no display. Go runs headless by
   default and shells out cleanly to whatever renderer we pick.
3. **Determinism and testability.** REQ-GCACP-006 requires that the same seed
   and parameters reproduce identical images and identical data cards, with
   golden-image comparison in CI. Go gives explicit seeded RNG, a first-class
   golden-file test story, and a static binary that behaves the same on a dev
   box and a CI runner.

## The renderer is a separate question — do not treat this note as settling it

REQ-GCACP-004 asks for real transmission and refraction, 3D pattern geometry
suspended inside the glass, and an emissive core casting light outward. That is
a path-traced render, not a 2D drawing job, and Go's `image/png` gets nowhere
near it on its own. Two candidates, both compatible with everything above:

- **A CPU path tracer in Go.** Fully deterministic, parallelises across
  goroutines, no external dependency, one binary. Most control, most code.
- **Headless Blender + Cycles, driven by the Go CLI.** Physically-based glass
  and emission for free and the standard tool for this look, at the cost of a
  heavy external dependency and pinning Blender's version for reproducibility.

Pick this during the Generator Core design phase and record it as ADR 0003.
Whichever wins, the Go decision above holds, because the choice is about what
the tool invokes rather than what the tool is written in.

## What would change the Go decision itself

If the generator ever needs to share rendering code with the game client — the
same shader or draw path producing both the content-pack art and the in-game
marble — that is a real argument for LÖVE, and this note should be revisited
rather than worked around. Nothing in the current spec requires it: per
REQ-GCACP-007 the game loads finished PNGs and carries no runtime dependency on
the generator at all.
