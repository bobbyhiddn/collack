# Callack Auto-Battler

Callack is a deterministic two-player marble-and-brick auto battler built with
LÖVE/Lua. The pure engine in `battle/` resolves fixed-grid, volley-locked
battles; `src/` is a thin controller and renderer that animates its event log.

The current executable is a discrete exhibition prototype. The accepted
product migration is defined by
[`ADR 0005`](docs/decisions/0005-continuous-vertical-slice.md) and the
[`Battle Engine vertical slice`](docs/specs/battle-engine-vertical-slice.md):
draft, setup, canonical continuous autobattle and recorded-state result/replay.
The pure-Lua draft/setup controller and its presentation boundary are now
implemented and documented in
[`Draft and setup controller contract`](docs/specs/draft-setup-controller.md);
the continuous physics and final LÖVE surface remain downstream integration.

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
packaged canvas at 390x844, and exercises mouse replay plus touch new-seed
input. The in-canvas controls use `R` and `N` as keyboard equivalents, with
Space to pause and Right Arrow to single-step.

## Repository map

```
battle/                 Canonical deterministic pure-Lua simulation and content
src/                    Pure run presentation/controller plus the legacy LÖVE UI
tests/                  Plain-Lua presentation/replay tests
scripts/                love.js, desktop, and Capacitor packaging
web-shell/              Responsive 390x844 browser shell
capacitor/              Preserved mobile wrapper and iOS scaffold
docs/decisions/          Settled engine and simulation decisions
```

## Runtime pins

The web build uses `love.js@11.4.1`, which embeds LÖVE 11.4. Desktop packaging
uses LÖVE 11.5. Capacitor remains on the existing 6.x scaffold.
