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
./scripts/build-paddle-web.sh
lua5.1 targets/paddle/tests/test_logic.lua
npm run verify:lovejs-cache
./scripts/verify-release-container.sh
npm ci && npm run browser:install
npm run verify:web
npm run verify:deployed
./scripts/build-desktop.sh
./scripts/build-desktop.sh --windows
./scripts/build-ios.sh

# macOS only: unsigned build, install, real process launch, logs, screenshot
./scripts/verify-ios-simulator.sh
```

The active auto-battler web result remains in `dist/web/`. The independent
Touch Input deliverable is candidate-owned under `targets/paddle/` and builds
to `dist/paddle-web/` through `scripts/build-paddle-web.sh`; neither target
overwrites or relabels the other. Both use content-addressed JavaScript, data,
and WebAssembly filenames.

Each `callack-build-manifest.json` binds the exact Git revision/tree, explicit
runtime target/path, source-file set, build recipe, authenticated toolchain, the
exact packaged `.love` archive, and SHA-256 of every served asset. The
candidate lock in `scripts/lovejs-toolchain-lock.json` pins the love.js npm
archive by URL, byte count, SHA-256, SHA-512/SRI, and every extracted runtime
file used by the candidate-owned packager. `CALLACK_NODE_CACHE_DIR` can select
only the archive storage directory: cache entries are authenticated before
extraction, cached executables are never run, and stale, mixed, altered, or
symlinked entries fail closed. The paddle browser verifier completes
the full flow at both 390×844 and 1280×800, validates moving canonical physics,
and writes review captures to `dist/verification/`.

The iOS Simulator verifier always rebuilds the candidate-owned paddle output,
re-seeds and syncs
the lockfile-pinned Capacitor project, builds with signing disabled, installs it
on a clean available iPhone Simulator, and requires a launch marker emitted by
the app process. Inspectable build logs, launch logs, identities, hashes, and a
screenshot are written to `dist/ios-simulator-smoke/`. The
`iOS Simulator smoke` workflow runs this secret-free path independently of the
manually gated TestFlight job.

`npm run verify:deployed` independently exercises the paddle target at 390×844
and desktop size. Before accepting the journey, it rebuilds
`dist/paddle-web/callack-build-manifest.json` from the checked-out
`targets/paddle` sources and fixed recipe, then requires the loaded HTML and
every runtime asset to agree exactly. `CALLACK_EXPECTED_BUILD_MANIFEST` is
rejected rather than treated as a trust root. Optional
`CALLACK_TARGET_SOURCE_COMMIT`, `CALLACK_TARGET_SOURCE_TREE`, and
`CALLACK_TARGET_NAME` labels are assertions only and cannot override the
candidate-derived identity. It records requested
and final URLs, redirects, loaded and complete asset digests, render,
collision, score-change, loss, touch, and keyboard evidence under
`dist/deployed-verification/`; it never deploys or changes the target. For a
known stale route, `CALLACK_IDENTITY_REPORT_ONLY=1` continues the behavioral
observation after recording the identity failure, but the command still cannot
produce a passing exact-build verdict.
CI rebuilds the checked-out head and rejects wrong bytes, mixed assets, stale or
altered manifests, missing identity fields, and unexpected redirects.

Touch or click the visible controls; drag a selected brick or marble onto a
legal destination, or use the equivalent tap sequence. Tab and Enter navigate
the same semantic actions. During battle, tap or click any marble or brick to
inspect its owner, mechanic, and material state; activate it again to close the
inspector. Space pauses and Right Arrow advances one exact fixed step. `M`
toggles generated audio and `V` toggles reduced motion. On the result screen,
`R` opens replay and `N` starts the next seeded run. Mute and reduced-motion
preferences persist across runs.

## Repository map

```
battle/                 Pure-Lua draft, setup, continuous physics, rules, recording
src/                    LÖVE and pure presentation controllers; no combat rules
targets/paddle/         Independent 800x600 touch-paddle runtime, tests, and shell
tests/                  Plain-Lua run, snapshot, and recorded-frame replay tests
scripts/                love.js, desktop, and Capacitor packaging
web-shell/              Responsive 390x844 browser shell
capacitor/              Preserved mobile wrapper and iOS scaffold
docs/decisions/          Settled engine and simulation decisions
docs/art-direction/      Accepted presentation contract and reference boards
```

## Runtime pins

The web build uses `love.js@11.4.1`, which embeds LÖVE 11.4. Desktop packaging
uses LÖVE 11.5. The wrapper pins Capacitor 6.2.0 and commits its npm lockfile.
