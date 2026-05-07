# Collack Framework Spike

> Spike: Love2D source → browser + iOS + Linux/Windows desktop, via love.js + Capacitor.
> Adapted from `bobbyhiddn/GoAF` and `bobbyhiddn/capacitor-asteroids`.
> See **[REPORT.md](REPORT.md)** for the GO/NO-GO verdict and **[FRAMEWORK-PATTERNS.md](FRAMEWORK-PATTERNS.md)** for the framework spec.

## Quick start

```bash
# Run pure-logic tests (no LÖVE required):
lua tests/test_logic.lua

# Build everything:
./scripts/build-web.sh         # → dist/web/
./scripts/build-desktop.sh     # → dist/desktop/collack-spike.x86_64
./scripts/build-desktop.sh --windows  # also produces dist/desktop/collack-spike-win64.zip
./scripts/build-ios.sh         # → capacitor/ios/App/   (Xcode project)

# Run the web build locally:
(cd dist/web && python3 -m http.server 8000) && open http://localhost:8000

# Run the Linux build:
./dist/desktop/collack-spike.x86_64
```

## Repo map

```
src/                    LÖVE source — the only thing that changes when swapping games.
scripts/                Build scripts for each target.
capacitor/              Capacitor wrapper. ios-template/ seeds ios/ on first build.
.github/workflows/      CI: matrix(web,desktop) on ubuntu, gated ios on macos.
tests/                  Pure-Lua tests (no LÖVE).
dist/                   Build outputs (gitignored).
FRAMEWORK-PATTERNS.md   How the framework works + how to swap the game.
REPORT.md               Spike GO/NO-GO record.
```

## Pinned versions

| | |
|---|---|
| LÖVE | 11.5 |
| love.js (npm) | 11.4.1 (lags LÖVE; runtime is 11.4) |
| Capacitor | 6.x |

See `FRAMEWORK-PATTERNS.md § 1` for the full version table and `§ 3` for love.js flag rationale.
