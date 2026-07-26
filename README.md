# Callack Auto-Battler

Callack is a deterministic two-player marble-and-brick auto battler built with
LÖVE/Lua. The pure engine in `battle/` resolves fixed-grid, volley-locked
battles; `src/` is a thin controller and renderer that animates its event log.

## Quick start

```bash
# Headless engine and presentation tests:
lua5.1 battle/tests/run_all.lua
lua5.1 tests/test_logic.lua

# Inspect a deterministic battle:
lua5.1 battle/cli.lua --seed 9125

# Build targets:
./scripts/build-web.sh
./scripts/build-desktop.sh
./scripts/build-desktop.sh --windows
./scripts/build-ios.sh
```

The web result is written to `dist/web/`. Serve that directory with any static
HTTP server. The in-canvas controls replay the fixed seed or advance to a new
seed; keyboard equivalents are `R` and `N`, with Space to pause and Right Arrow
to single-step.

## Repository map

```
battle/                 Canonical deterministic pure-Lua simulation and content
src/                    LÖVE event-log adapter UI; no combat rules
tests/                  Plain-Lua presentation/replay tests
scripts/                love.js, desktop, and Capacitor packaging
web-shell/              Responsive 390x844 browser shell
capacitor/              Preserved mobile wrapper and iOS scaffold
docs/decisions/          Settled engine and simulation decisions
```

## Runtime pins

The web build uses `love.js@11.4.1`, which embeds LÖVE 11.4. Desktop packaging
uses LÖVE 11.5. Capacitor remains on the existing 6.x scaffold.
