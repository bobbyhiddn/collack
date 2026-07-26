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

The Marble Generator is written in **Go**.

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
2. **Headless generation is the whole job, and it is a LÖVE weakness.**
   Rendering marble art in LÖVE means `love.graphics`, which wants a window and
   a GL context. Generating content packs in CI, reproducibly, with no display,
   is awkward there and routine in Go with `image/png` in the standard library.
3. **Determinism and testability.** Content packs must be reproducible from a
   seed so the same pack can be regenerated and diffed. Go gives explicit seeded
   RNG, a first-class test story for golden-file comparison, and a static binary
   that runs identically on a dev box and a CI runner.

## What would change this

If the generator ever needs to share rendering code with the game client — the
same shader or draw path producing both the content-pack art and the in-game
marble — that would be a real argument for LÖVE, and this note should be
revisited rather than worked around. Nothing in the current spec requires it:
the game loads finished PNGs.
