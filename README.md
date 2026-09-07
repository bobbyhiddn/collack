# Collack — Brickbreaker Autobattler

Build a defense, order your marbles, and let the ricochets decide. Collack is a
single-player, three-rival expedition built with LÖVE/Lua. Both collections
launch into one continuous arena: your marbles break enemy bricks while your
formation protects your side. **Combat is automatic; there is no manual paddle.**

## Play locally

Requires Node.js 20+, Bash, curl, zip, and unzip. The first build downloads the
pinned LÖVE web runtime; no game server or account is needed.

```bash
npm ci
npm run dev
```

Open **http://127.0.0.1:8080**. `PORT=8321 npm run dev` selects another port.
Re-run the command after source edits. The responsive canvas supports portrait
phones and desktop windows. Add `?seed=9125` to start a reproducible expedition.

Choose **New Expedition**, place every brick (or use **Quick Arrange**), set
your marble launch order, then **Start Autobattle**. Break all rival bricks or
outlast their marbles to win. After each of the first two victories, inspect
the three refit offers and choose one upgrade. Repair, replace, add, or reshape
your collection, then face the next rival. Defeat ends the expedition; three
victories complete it. Quick Arrange fills empty cells without moving your
existing placements; it is a starting point, not an optimized strategy.

Progress saves automatically at formation, refit, and result boundaries.
**Continue Expedition** restores the saved run. Closing the game mid-battle
returns you to that fight's last formation, with the same deterministic seed.
Browser saves are local to the browser/site and are lost if site data is
cleared. Native builds save in LÖVE's `collack-spike` user-data directory.
Starting a new run asks before replacing an unfinished expedition.

Tap/click a piece and a destination to arrange it, or drag it into place.
During battle, tap a piece to pause and inspect; tap it again or press Resume
to return to combat. The 1×/2× control changes viewing speed, not the outcome.
Mute and reduced-motion preferences persist. Keyboard controls:

- Tab / arrow keys, then Enter: navigate controls; Escape: menu.
- Space: pause/resume; Right Arrow while battling: one simulation step.
- M: mute; V: reduced motion; 1–3: inspect a refit offer.
- On the result screen, R: recorded-frame replay; N: new seeded expedition.

## Build and verify

```bash
# Lua 5.1 is needed for the headless tests.
npm test

# Production packaging requires a clean committed source tree.
npm run build
npm run browser:install
npm run verify:expedition  # ordinary menu → three fights → save/reload/replay
npm run verify:web         # exact-tick combat and rule inspection evidence

./scripts/build-desktop.sh --windows
./scripts/build-ios.sh

# macOS/Xcode only: unsigned build, install, launch, logs, screenshot
./scripts/verify-ios-simulator.sh
```

Web output is `dist/web/`; Linux and Windows packages are in `dist/desktop/`.
The iOS wrapper ships this same **autobattler**, with portrait iPhone support.
Normal-play screenshots and a check report go to `dist/expedition-verification/`.
If your host needs a system Chrome, set `CALLACK_BROWSER_EXECUTABLE` to its
executable path when running either autobattler browser verifier.
`npm run dev` intentionally omits release provenance; do not deploy that preview.

The pure engine in `battle/` owns deterministic 120 Hz continuous physics and
combat rules. `src/` interpolates its snapshots; the readable presentation clock
does not change physics. Recorded replays read the captured frames rather than
inventing trajectories. The implementation follows
[`ADR 0005`](docs/decisions/0005-continuous-vertical-slice.md), the
[`vertical slice`](docs/specs/battle-engine-vertical-slice.md), and the
[`draft/setup contract`](docs/specs/draft-setup-controller.md).
See [`battle/README.md`](battle/README.md) for the value-only engine API.

## Package integrity and mobile verification

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

The iOS Simulator verifier always rebuilds the candidate-owned autobattler output,
re-seeds and syncs
the lockfile-pinned Capacitor project, builds with signing disabled, installs it
on a clean available iPhone Simulator, and requires a launch marker emitted by
the app process. Inspectable build logs, launch logs, identities, hashes, and a
screenshot are written to `dist/ios-simulator-smoke/`. The
`iOS Simulator smoke` workflow runs this secret-free path independently of the
manually gated TestFlight job.

## Preserved paddle experiment

`targets/paddle/` is a separate manual-paddle prototype, **not the Collack game
or the default iOS target**. It is retained along with its historical release
gates. `scripts/build-paddle-web.sh` writes only `dist/paddle-web/`; neither
runtime overwrites or relabels the other.

`npm run verify:deployed` independently exercises that paddle target at 390×844
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

### Paddle Fly release path

The existing `deploy/fly/Dockerfile` and `deploy/fly/fly.toml` remain the
auto-battler release path and consume only `dist/web`. The paddle release is a
separate, explicit contract:

```bash
./scripts/build-paddle-web.sh
npm run verify:paddle:release
CALLACK_CONTAINER_ENGINE=docker ./scripts/build-paddle-release-image.sh
```

`deploy/fly/Dockerfile.paddle` can copy only `dist/paddle-web`; its
Dockerfile-specific ignore file excludes `dist/web`, and a pinned Node stage
checks the target, manifest structure, complete file set, and every asset byte
before nginx receives the bundle. Before invoking the container engine, the
host gate requires a clean tracked checkout, derives revision and tree from
Git, authenticates the candidate-owned manifest/source/recipe/toolchain, and
compares the supplied package and `.love` archive with an independent rebuild
of that exact commit. Image tags, service labels, and optional caller labels
never define artifact identity.

The image builder rebuilds canonical output, builds exactly once, resolves the
immutable local image ID, and validates that image's extracted filesystem and
labels against a fresh exact-source rebuild. The final
`CALLACK_VALIDATED_IMAGE=sha256:...` line is the only release candidate.

The dedicated `deploy/fly/paddle.fly.toml` still names the existing
`collack-spike` service, but marks the release target as `paddle-web`. A future
authorized deployment supplies that immutable ID to the guarded command:

```bash
./scripts/release-paddle-fly.sh --deploy --image sha256:<validated-image-id>
```

The wrapper revalidates the image by ID, publishes that same image, compares
the registry manifest's config digest with the validated local ID, and passes
only the returned digest-qualified reference to `flyctl deploy --image`. It
never sends a build context, rereads `dist/paddle-web`, or deploys a mutable tag.

The paddle nginx config serves the contract at `/` only, keeps the shell and
provenance files revalidated, and gives immutable caching only to 16-hex
content-addressed runtime assets. The container verifier compares the complete
image and HTTP file sets with `dist/paddle-web`, rejects auto-battler or nested
base paths, and runs the real 390×844 touch and desktop keyboard journeys.

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
