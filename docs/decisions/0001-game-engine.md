# ADR 0001 — Game engine: LÖVE (Love2D), not Go + Ebiten

- **Date:** 2026-07-26
- **Status:** Accepted
- **Decided by:** Micah (operator ruling, 2026-07-26)
- **Scope:** The Callack battle engine and every runtime component of the game client.

## Decision

Callack is built on **LÖVE (Love2D) 11.x with Lua**.

## Rejected alternative

**Go + Ebiten**, which is what the original Callack design spec (Legate,
2026-04-24, "Callack (Marbles and Bricks) — Auto Battler") named as the stack.
That line of the spec is now superseded by this note.

## Why

1. **Operator ruling.** Micah settled it directly on 2026-07-26: "Love is canon."
2. **Lua everywhere.** Kindling ported off Godot onto LÖVE for the same reasons,
   and Prism's client is Lua. Callack on LÖVE makes the portfolio one language
   for game runtime code, so tooling, patterns, and agent-written code carry
   between projects. Boss Spa stays on Defold deliberately and is the exception.
3. **The iOS pipeline is already proven here.** This repository's spike
   demonstrated love.js → Capacitor → iOS end to end. That pipeline is now on the
   critical path rather than a side branch.

## Why this note exists

The Battle Engine Core project's first requirement blocks all battle-engine code
until the engine choice is written down in the repo. It exists because the
mismatch went unrecorded the first time: the spec said Go + Ebiten, the spike was
Love2D, nobody reconciled them, and the pipeline work quietly became "the game" —
producing a single-player brick breaker instead of the two-player auto battler
the design describes. A verbal decision that lives only in chat can repeat that.

## Open sub-decision (not settled by this note)

The **Marble Generator** is specced in Go, partly justified by "eventual Ebiten
integration." That justification is void as of this decision. Go remains
defensible on its own terms — the generator is a standalone offline tool whose
spec mandates engine-agnostic output (PNG + JSON content packs) and forbids any
runtime dependency in the game — but the language must be confirmed or changed
deliberately when the Generator Core project starts. Do not let it drift into a
second unrecorded engine mismatch.
