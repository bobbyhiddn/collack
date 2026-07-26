# Callack Auto-Battler

Callack is a deterministic two-player marble-and-brick auto battler built with
LÖVE/Lua. The pure engine in `battle/` advances a canonical fixed-timestep
continuous world; `src/` renders interpolated snapshots and replays recorded
canonical frames. The event log is an exact-tick audit/effect output, not a
trajectory script.

The implementation follows
[`ADR 0005`](docs/decisions/0005-continuous-vertical-slice.md) and the
[`Battle Engine vertical slice`](docs/specs/battle-engine-vertical-slice.md).
Draft and setup integration consume the value-only battle API documented in
[`battle/README.md`](battle/README.md).

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
server. The browser verifier starts and stops its own local server, boots the
packaged canvas at 390x844, checks the live replay guard, and exercises touch
new-seed input. `R` starts immutable recorded-frame replay after a result, `N`
starts a new seed, Space pauses, and Right Arrow advances one exact fixed step.

## Repository map

```
battle/                 Pure-Lua continuous physics, rules, content, recording
src/                    LÖVE snapshot projector/controller; no combat rules
tests/                  Plain-Lua snapshot and recorded-frame replay tests
scripts/                love.js, desktop, and Capacitor packaging
web-shell/              Responsive 390x844 browser shell
capacitor/              Preserved mobile wrapper and iOS scaffold
docs/decisions/          Settled engine and simulation decisions
```

## Runtime pins

The web build uses `love.js@11.4.1`, which embeds LÖVE 11.4. Desktop packaging
uses LÖVE 11.5. Capacitor remains on the existing 6.x scaffold.
