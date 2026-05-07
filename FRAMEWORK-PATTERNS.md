# Love2D → Browser + iOS + Desktop Framework Patterns

Source-of-truth doc. Read this before swapping the game source or extracting the
framework into its own repo. Adapted from `bobbyhiddn/GoAF` and the
`bobbyhiddn/capacitor-asteroids` reference implementation, swapping
Ebitengine→WASM for **LÖVE→love.js**.

---

## 1. Pinned versions

| Component | Version | Notes |
|---|---|---|
| LÖVE | **11.5** (Mysterious Mysteries) | Used for the Linux fused binary and (eventually) Windows .exe. |
| love.js (npm) | **11.4.1** | Latest published. The Emscripten runtime is **LÖVE 11.4** under the hood. If you need 11.5-only Lua APIs, build love.js from `Davidobot/love.js` master — npm lags upstream. |
| Capacitor | **6.x** | `@capacitor/core`, `@capacitor/cli`, `@capacitor/ios`, `@capacitor/splash-screen`. |
| Node | **20** in CI | 22.x works locally. |
| Ruby (Fastlane) | **3.2.6** | Match for cert/profile management; mirrors capacitor-asteroids. |

---

## 2. Directory layout the framework expects

```
.
├── src/                       # ← LÖVE source. This is the *only* thing you change to swap a game.
│   ├── conf.lua               #   love.conf — window, modules, identity.
│   ├── main.lua               #   love.* callbacks; thin shell over logic modules.
│   ├── logic.lua              #   Pure Lua, no love.* — testable from `lua tests/...`.
│   └── assets/                #   PNG/JPG/OGG/WAV — see §6 for love.js compatibility.
├── tests/
│   └── test_logic.lua         # Pure-Lua tests; no LÖVE runtime needed.
├── scripts/
│   ├── build-web.sh           # love.js → dist/web/
│   ├── build-desktop.sh       # zip + cat → dist/desktop/<name>.x86_64
│   └── build-ios.sh           # web bundle → capacitor/dist + cap sync
├── capacitor/
│   ├── package.json           # @capacitor/* deps.
│   ├── capacitor.config.json  # appId, appName, webDir, server, plugins, ios.orientation.
│   ├── dist/                  # Generated: copy of dist/web/.
│   ├── ios-template/          # Source-controlled clean iOS scaffold (seeds capacitor/ios/).
│   └── ios/                   # Generated on first build-ios.sh run; cap sync target.
├── .github/workflows/
│   └── build.yml              # Matrix: ubuntu(web,desktop) + gated macos(ios).
├── dist/
│   ├── collack-spike.love     # Plain .love archive (used by every target).
│   ├── web/                   # love.js output: index.html, love.js, love.wasm, game.data.
│   └── desktop/               # Fused binaries.
├── FRAMEWORK-PATTERNS.md      # This doc.
└── REPORT.md                  # Spike GO/NO-GO record.
```

**Hard rule on `src/`**: keep `love.*` calls *only* inside `main.lua`'s callbacks
or other clearly engine-coupled modules. Pure logic goes in modules that
`require()` cleanly under stock `lua` 5.1+.

---

## 3. love.js — flags and known browser quirks

`love.js -c -t "<title>" -m <bytes> <input.love> <output_dir>`

| Flag | Why |
|---|---|
| `-c` | **Compatibility build.** No `SharedArrayBuffer`, no COOP/COEP headers needed. Required for Capacitor's `file://` scheme on iOS, GitHub Pages, plain `python -m http.server`, and Itch.io. |
| `-t "<title>"` | Window/tab title. |
| `-m 67108864` | Memory quota (bytes). 16 MB default is too small for almost anything beyond a placeholder. 64 MB is safe for medium games; bump to 128–256 MB for asset-heavy titles. **Set this too low and the runtime crashes mid-load with `out of memory`.** |

### Browser quirks observed in the spike

1. **Audio context unlock**: love.js needs a user gesture to unlock audio.
   This works automatically with the love.js shell's "Run" button. If you
   replace the shell, call `Module._love_audio_unlock()` (or invoke the
   shell's tap-to-start overlay) on first click/touch.
2. **No threading**: with `-c`, `love.thread` is unavailable. Code accordingly.
3. **File I/O**: `love.filesystem.write` writes to IDBFS, persisted across
   sessions on the same origin. Capacitor `file://` makes this per-app.
4. **Mobile Safari memory pressure**: iOS WebKit kills tabs over ~250 MB.
   Keep `-m` ≤ 256 MB and avoid loading every asset on boot.
5. **Pixel-perfect rendering**: include `image-rendering: pixelated;` and the
   `image-rendering: crisp-edges;` fallback in CSS — see capacitor-asteroids
   `src/index.html` for the canonical viewport+canvas setup.
6. **Touch events**: with `t.modules.touch = true` in `conf.lua`, LÖVE
   delivers `love.touchpressed/moved/released`. Browsers also fire mouse
   events — debounce or filter on `id` if you handle both.

---

## 4. Capacitor config skeleton

`capacitor/capacitor.config.json`:

```json
{
  "appId": "io.bobbyhiddn.collack",
  "appName": "Collack Spike",
  "webDir": "dist",
  "server": {
    "iosScheme": "file",
    "androidScheme": "file",
    "hostname": "app",
    "cleartext": true,
    "allowNavigation": ["*"]
  },
  "plugins": {
    "SplashScreen": {
      "launchAutoHide": true,
      "launchShowDuration": 1500,
      "backgroundColor": "#000000",
      "spinnerColor": "#FFFFFF"
    }
  },
  "ios": {
    "orientation": "landscape",
    "contentInset": "always",
    "limitsNavigationsToAppBoundDomains": false
  }
}
```

`capacitor/ios-template/App/App/Info.plist` — keep these keys (mirror of asteroids):

- `CFBundleDisplayName` → marketing name shown on home screen.
- `LSRequiresIPhoneOS` → `true`.
- `UISupportedInterfaceOrientations` → landscape pair (or portrait pair, match `capacitor.config.json` `ios.orientation`).
- `WKAppBoundDomains` → `["file://", "capacitor://"]` — required for the `file://` scheme.

Viewport meta (set in love.js's `index.html` by `build-web.sh`):

```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
```

---

## 5. GHA workflow — matrix shape & Fastlane Match wiring

The workflow at `.github/workflows/build.yml` has three jobs:

| Job | Runner | Trigger |
|---|---|---|
| `logic-test` | `ubuntu-latest` | Every push/PR. Fast (<10s). |
| `build` (matrix `web`, `desktop`) | `ubuntu-latest` | After `logic-test` passes. ~3–5 min each. |
| `ios` | `macos-latest` | **Gated**: `workflow_dispatch` with `build_ios=true` *or* PR carrying `ios-build` label. |

The macOS gating is what keeps the bill sane — macos-latest costs ~10× the
ubuntu rate. Default to web+desktop on every push; opt into iOS deliberately.

### Fastlane Match wiring

The iOS job inherits the **exact secret map** from `capacitor-asteroids`
(see `.github/workflows/ios.yml` there). Required GitHub secrets in the
`ios` environment:

- `MATCH_GIT_URL` — Match's cert repo (private GitHub repo).
- `MATCH_PASSWORD` — encryption passphrase.
- `GIT_AUTHORIZATION` — PAT with `repo` scope to clone the Match repo.
- `TEMP_KEYCHAIN_PASSWORD` — random per-run, set as a CI secret for stability.
- `APPLE_KEY_ID`, `APPLE_ISSUER_ID`, `APPLE_KEY_CONTENT` — App Store Connect API key (replaces password auth).
- `DEVELOPER_APP_IDENTIFIER` — bundle ID, e.g. `io.bobbyhiddn.collack`.
- `DEVELOPER_PORTAL_TEAM_ID`, `APP_STORE_CONNECT_TEAM_ID` — both team IDs.

Match-init flow: run the **`ios-match-init.yml`** workflow once
(copy from capacitor-asteroids verbatim) to populate the cert repo. After
that, every iOS build runs `match readonly` and signs without re-issuing certs.

`capacitor/ios/App/fastlane/Fastfile` and `Matchfile` are seeded from
`ios-template/` and committed to the repo — Fastlane reads them in CI.

---

## 6. "How to swap the game" recipe

To drop a different LÖVE game into this framework:

```bash
# 1. Replace src/ with the target game's tree. Keep src/conf.lua's
#    t.identity, t.window, and module fences sane for love.js.
rm -rf src/
cp -r /path/to/other-love2d-project src/

# 2. Rename in three config files:
#    a. capacitor/capacitor.config.json → appId + appName
#    b. capacitor/ios-template/App/App/capacitor.config.json → same
#    c. capacitor/ios-template/App/App/Info.plist → CFBundleDisplayName
#    d. scripts/build-desktop.sh → LOVE_ARCHIVE / LINUX_BIN names
sed -i 's/io.bobbyhiddn.collack/io.bobbyhiddn.YOURAPP/' \
    capacitor/capacitor.config.json \
    capacitor/ios-template/App/App/capacitor.config.json
# … etc.

# 3. Test logic separately if your game has pure modules:
lua tests/test_logic.lua

# 4. Run the three builds locally:
./scripts/build-desktop.sh
./scripts/build-web.sh
./scripts/build-ios.sh

# 5. Push. CI runs web+desktop. Trigger iOS via workflow_dispatch.
```

If the swapped game uses LÖVE 11.5-only APIs, see §1 about building
love.js from master.

---

## 7. Asset pipeline notes

### Image formats

- **PNG**: ✅ first-class. Use this.
- **JPG**: ✅ works. Use for photographic backgrounds; smaller than PNG.
- **GIF**: ⚠️ static only — LÖVE doesn't decode animated GIFs.
- **WebP**: ❌ not supported by LÖVE's image decoder. Convert to PNG.
- **TIFF/BMP/etc.**: ❌. Convert to PNG.

### Audio formats

- **OGG Vorbis (.ogg)**: ✅ recommended. Plays everywhere LÖVE does.
- **MP3**: ✅ but patent encumbered historically — OGG is the safer pick.
- **WAV**: ✅ but the file size kills your `-m` memory budget on web.
- **MOD/IT/XM (trackers)**: ✅ on desktop, ❌ on love.js — the tracker decoders aren't in the WASM build.
- **FLAC**: ✅ desktop, ⚠️ inflated WASM size on web.

For Collack: stick with **PNG sprites + OGG audio**. Mass-convert with:

```bash
# Convert all jpg/webp to png
find src/assets -iname '*.webp' -exec sh -c 'convert "$0" "${0%.webp}.png"' {} \;
# Convert all wav/mp3 to ogg
find src/assets -iname '*.wav' -exec sh -c 'ffmpeg -y -i "$0" -c:a libvorbis -q:a 5 "${0%.wav}.ogg"' {} \;
```

### Asset bundling

`build-web.sh` zips all of `src/` (including `src/assets/`) into the .love,
which love.js then unpacks into `game.data` (an Emscripten preload package).
Everything in `src/` ends up addressable via `love.filesystem` paths.

**Size watch**: love.wasm itself is ~4.6 MB. Add ~2 MB of assets and you're
at a 7 MB initial download — acceptable. Beyond ~25 MB total, splash-screen
the first-load experience or you'll lose mobile users.

---

## 8. Should the framework live in its own repo?

See `REPORT.md` § Recommendation. TL;DR: **build Collack into this repo
first, prove it for real, then extract the framework into
`love-capacitor-framework`** before Kindling adopts it.
