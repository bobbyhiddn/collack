# Callack Auto-Battler

Callack is a deterministic two-player marble-and-brick auto battler built with
LÖVE/Lua. The pure engine in `battle/` advances a canonical fixed-timestep
continuous world; `src/` renders interpolated snapshots and replays recorded
canonical frames. The event log is an exact-tick audit/effect output, not a
trajectory script.

The implementation follows
[`ADR 0005`](docs/decisions/0005-continuous-vertical-slice.md) and the
[`Battle Engine vertical slice`](docs/specs/battle-engine-vertical-slice.md):
draft, setup, canonical continuous autobattle and recorded-state result/replay.
The pure-Lua draft/setup controller and its presentation boundary are now
implemented and documented in
[`Draft and setup controller contract`](docs/specs/draft-setup-controller.md).
The value-only battle API is documented in [`battle/README.md`](battle/README.md).

## Quick start

```bash
# Headless engine and presentation tests:
lua5.1 battle/tests/run_all.lua
lua5.1 tests/test_logic.lua

# Inspect a deterministic battle:
lua5.1 battle/cli.lua --seed 9125

# Build targets:
./scripts/build-web.sh
./scripts/verify-release-container.sh
npm ci && npm run browser:install
npm run verify:web
./scripts/build-desktop.sh
./scripts/build-desktop.sh --windows
./scripts/build-ios.sh
```

The web result is written to `dist/web/` with content-addressed JavaScript,
data, and WebAssembly filenames. Serve that directory with any static HTTP
server. The browser verifier starts and stops its own local server, completes
the full flow at both 390×844 and 1280×800, validates moving canonical physics,
and writes review captures to `dist/verification/`.

Touch or click the visible controls; drag a selected brick or marble onto a
legal destination, or use the equivalent tap sequence. Tab and Enter navigate
the same semantic actions. During battle, Space pauses and Right Arrow advances
one exact fixed step. `M` toggles generated audio and `V` toggles reduced
motion. On the result screen, `R` opens replay and `N` starts the next seeded
run. Mute and reduced-motion preferences persist across runs.

## Repository map

```
battle/                 Pure-Lua draft, setup, continuous physics, rules, recording
src/                    LÖVE and pure presentation controllers; no combat rules
tests/                  Plain-Lua run, snapshot, and recorded-frame replay tests
scripts/                love.js, desktop, and Capacitor packaging
web-shell/              Responsive 390x844 browser shell
capacitor/              Preserved mobile wrapper and iOS scaffold
docs/decisions/          Settled engine and simulation decisions
docs/art-direction/      Accepted presentation contract and reference boards
```

## Runtime pins

The web build uses `love.js@11.4.1`, which embeds LÖVE 11.4. Desktop packaging
uses LÖVE 11.5. Capacitor remains on the existing 6.x scaffold.
