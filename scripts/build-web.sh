#!/usr/bin/env bash
# build-web.sh — package the LÖVE client plus canonical battle engine for love.js.
#
# Pinned versions:
#   LÖVE         : 11.4 (see src/conf.lua — runtime parity with love.js)
#   love.js (npm): 11.4.1   ← latest published; embeds the LÖVE 11.4 runtime.
#                            Declaring t.version = "11.5" in conf.lua triggered
#                            indirect WASM calls to functions absent in 11.4
#                            (RuntimeError: null function on init). Pinning to
#                            11.4 fixes the client. To use 11.5 LÖVE features
#                            here, build Davidobot/love.js master against
#                            LÖVE 11.5 (requires Emscripten in build image).
#
# Output: dist/web/{index.html, *.<content-hash>.js,
#                  *.<content-hash>.wasm, *.<content-hash>.data}
#
# Run locally:
#   ./scripts/build-web.sh
#   (cd dist/web && python3 -m http.server 8000) → http://localhost:8000

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
OUT="$ROOT/dist/web"
LOVE_JS_VERSION="11.4.1"  # latest published on npm (see header note)
ARCHIVE_TIMESTAMP="200001010000.00"

# Keep archive ordering, timestamps, permissions, and locale-dependent tool
# behaviour independent of the checkout and caller environment.
export LC_ALL=C
export TZ=UTC
unset ZIP ZIPOPT
umask 022

BUILD_TMP=""
cleanup() {
    if [ -n "$BUILD_TMP" ] && [ -d "$BUILD_TMP" ]; then
        rm -rf "$BUILD_TMP"
    fi
}
trap cleanup EXIT

rm -rf "$OUT"
mkdir -p "$OUT"

# Build the .love archive from normalized staging files. Info-ZIP otherwise
# records checkout mtimes, modes, UID/GID extra fields, and filesystem traversal
# order. src/ owns presentation only; the canonical pure-Lua rules and content
# retain their battle/ module paths.
LOVE_ARCHIVE="$ROOT/dist/collack-spike.love"
mkdir -p "$ROOT/dist"
BUILD_TMP="$(mktemp -d "$ROOT/dist/.web-build.XXXXXX")"
ARCHIVE_ROOT="$BUILD_TMP/archive"
ARCHIVE_FILE_LIST="$BUILD_TMP/archive-files.txt"
ARCHIVE_ACTUAL_LIST="$BUILD_TMP/archive-actual.txt"

mkdir -p "$ARCHIVE_ROOT"
cp -R "$SRC/." "$ARCHIVE_ROOT/"
mkdir -p "$ARCHIVE_ROOT/battle"
cp -R "$ROOT/battle/." "$ARCHIVE_ROOT/battle/"
if [ -d "$ROOT/assets" ]; then
    cp -R "$ROOT/assets" "$ARCHIVE_ROOT/assets"
fi
rm -rf "$ARCHIVE_ROOT/battle/tests"
rm -f "$ARCHIVE_ROOT/battle/cli.lua" "$ARCHIVE_ROOT/battle/README.md"
find "$ARCHIVE_ROOT" -name '.DS_Store' -delete
find "$ARCHIVE_ROOT" -type d -exec chmod 0755 {} +
find "$ARCHIVE_ROOT" -type f -exec chmod 0644 {} +
find "$ARCHIVE_ROOT" -type f -exec touch -t "$ARCHIVE_TIMESTAMP" {} +

(
    cd "$ARCHIVE_ROOT"
    find . -type f -print | sort | sed 's|^\./||'
) > "$ARCHIVE_FILE_LIST"
[ -s "$ARCHIVE_FILE_LIST" ] || {
    echo "[web] ERROR: deterministic archive input list is empty" >&2
    exit 1
}

rm -f "$LOVE_ARCHIVE"
(
    cd "$ARCHIVE_ROOT"
    zip -X -9 "$LOVE_ARCHIVE" -@ < "$ARCHIVE_FILE_LIST" >/dev/null
)
unzip -tqq "$LOVE_ARCHIVE"
unzip -Z -1 "$LOVE_ARCHIVE" > "$ARCHIVE_ACTUAL_LIST"
if ! cmp -s "$ARCHIVE_FILE_LIST" "$ARCHIVE_ACTUAL_LIST"; then
    echo "[web] ERROR: archive entries differ from the stable input order" >&2
    diff -u "$ARCHIVE_FILE_LIST" "$ARCHIVE_ACTUAL_LIST" >&2 || true
    exit 1
fi

# Fail the build if an integration module or the data-only art contract falls
# out of the archive. Tests and the CLI are deliberately not shipped.
REQUIRED_RUNTIME_FILES=(
    "main.lua"
    "conf.lua"
    "presentation.lua"
    "run_controller.lua"
    "run_presentation.lua"
    "run_loop.lua"
    "ui/art_tokens.lua"
    "ui/procedural_audio.lua"
    "battle/engine.lua"
    "battle/physics.lua"
    "battle/checkpoints.lua"
    "battle/run.lua"
    "battle/draft.lua"
    "battle/opponent.lua"
    "battle/setup.lua"
    "battle/setup_rules.lua"
)
for required in "${REQUIRED_RUNTIME_FILES[@]}"; do
    grep -Fxq "$required" "$ARCHIVE_ACTUAL_LIST" || {
        echo "[web] ERROR: runtime archive is missing $required" >&2
        exit 1
    }
done
if grep -Eq '^battle/(tests/|cli\.lua$)' "$ARCHIVE_ACTUAL_LIST"; then
    echo "[web] ERROR: quarantined headless/demo paths entered the runtime archive" >&2
    exit 1
fi
echo "[web] built $LOVE_ARCHIVE ($(du -h "$LOVE_ARCHIVE" | cut -f1))"

# Install love.js once into a local node_modules cache.
NODE_CACHE="${CALLACK_NODE_CACHE_DIR:-$ROOT/.node_cache}"
if [ ! -x "$NODE_CACHE/node_modules/.bin/love.js" ]; then
    mkdir -p "$NODE_CACHE"
    pushd "$NODE_CACHE" >/dev/null
    if [ ! -f package.json ]; then echo '{}' > package.json; fi
    npm install --no-audit --no-fund --silent "love.js@${LOVE_JS_VERSION}"
    popd >/dev/null
fi

LOVE_JS_BIN="$NODE_CACHE/node_modules/.bin/love.js"

# love.js flags reference:
#   -c                  compatibility build (no SharedArrayBuffer; works on file://, GH Pages, plain http servers)
#   -t <title>          window title
#   -m <bytes>          memory quota (default 16MB; 64MB safe for placeholder, bump for full Collack)
# Use -c for max portability — Capacitor file:// scheme requires it; SharedArrayBuffer requires COOP/COEP headers.
"$LOVE_JS_BIN" -c -t "Callack Auto-Battler" -m 67108864 "$LOVE_ARCHIVE" "$OUT" >/dev/null

echo "[web] love.js compile complete → $OUT"

content_digest() {
    local path="$1"
    shasum -a 256 "$path" | awk '{print $1}'
}

content_name() {
    local stem="$1"
    local extension="$2"
    local path="$3"
    local digest
    digest="$(content_digest "$path")"
    printf '%s.%s.%s' "$stem" "${digest:0:16}" "$extension"
}

rewrite_reference() {
    local old_name="$1"
    local new_name="$2"
    local path="$3"
    local escaped_old="${old_name//./\\.}"
    local temporary="${path}.rewrite"
    sed "s|${escaped_old}|${new_name}|g" "$path" > "$temporary"
    mv "$temporary" "$path"
}

# love.js 11.4.1 has no deterministic packaging flag and unconditionally emits
# uuid() into game.js. That UUID is only compared as an IndexedDB cache identity,
# so replace it with the full packaged-data digest: deterministic, and guaranteed
# to change whenever the cached package bytes change.
GAME_DATA_DIGEST="$(content_digest "$OUT/game.data")"
PACKAGE_ID="sha256-$GAME_DATA_DIGEST"
PACKAGE_ID_COUNT="$(grep -Eo '"package_uuid":"[^"]+"' "$OUT/game.js" | wc -l | tr -d '[:space:]')"
if [ "$PACKAGE_ID_COUNT" != "1" ]; then
    echo "[web] ERROR: expected one love.js package_uuid, found $PACKAGE_ID_COUNT" >&2
    exit 1
fi
PACKAGE_ID_TMP="$OUT/game.js.package-id"
sed -E "s|\"package_uuid\":\"[^\"]+\"|\"package_uuid\":\"$PACKAGE_ID\"|" \
    "$OUT/game.js" > "$PACKAGE_ID_TMP"
mv "$PACKAGE_ID_TMP" "$OUT/game.js"
grep -Fq "\"package_uuid\":\"$PACKAGE_ID\"" "$OUT/game.js" || {
    echo "[web] ERROR: deterministic package identity was not installed" >&2
    exit 1
}

# Content-address every runtime URL. The generated JavaScript names its own
# data/WASM dependency, so rewrite those edges before hashing the loaders.
GAME_DATA_NAME="$(content_name game data "$OUT/game.data")"
mv "$OUT/game.data" "$OUT/$GAME_DATA_NAME"
rewrite_reference "game.data" "$GAME_DATA_NAME" "$OUT/game.js"
GAME_JS_NAME="$(content_name game js "$OUT/game.js")"
mv "$OUT/game.js" "$OUT/$GAME_JS_NAME"

LOVE_WASM_NAME="$(content_name love wasm "$OUT/love.wasm")"
mv "$OUT/love.wasm" "$OUT/$LOVE_WASM_NAME"
rewrite_reference "love.wasm" "$LOVE_WASM_NAME" "$OUT/love.js"
LOVE_JS_NAME="$(content_name love js "$OUT/love.js")"
mv "$OUT/love.js" "$OUT/$LOVE_JS_NAME"

# Replace the stock love.js index.html with our responsive shell. The stock
# template uses a fixed loading canvas that draws offscreen on mobile portrait
# viewports (and a pink/cyan theme/bg.png that dominates the layout).
# Our web-shell/index.html is viewport-aware, centers both canvases via flex,
# uses a solid black background, and replaces the loadingCanvas progress with
# a DOM-rendered "Loading…" overlay.
SHELL_HTML="$ROOT/web-shell/index.html"
if [ -f "$SHELL_HTML" ]; then
    cp "$SHELL_HTML" "$OUT/index.html"
    rewrite_reference "__GAME_JS__" "$GAME_JS_NAME" "$OUT/index.html"
    rewrite_reference "__LOVE_JS__" "$LOVE_JS_NAME" "$OUT/index.html"
    echo "[web] installed responsive shell → $OUT/index.html"
else
    echo "[web] ERROR: web-shell/index.html is required for hashed asset references" >&2
    exit 1
fi

find "$OUT" -type d -exec chmod 0755 {} +
find "$OUT" -type f -exec chmod 0644 {} +

bash "$ROOT/scripts/verify-web-assets.sh" "$OUT"

ls -lh "$OUT"
echo "[web] OK. Serve with: (cd $OUT && python3 -m http.server 8000)"
