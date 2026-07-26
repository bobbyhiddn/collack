#!/usr/bin/env bash
# build-web.sh — package the LÖVE client plus canonical battle engine for love.js.
#
# Pinned versions:
#   LÖVE         : 11.4 (see src/conf.lua — runtime parity with love.js)
#   love.js (npm): 11.4.1   ← latest published; embeds the LÖVE 11.4 runtime.
#                            Declaring t.version = "11.5" in conf.lua triggered
#                            indirect WASM calls to functions absent in 11.4
#                            (RuntimeError: null function on init). Pinning to
#                            11.4 fixes the demo. To use 11.5 LÖVE features
#                            here, build Davidobot/love.js master against
#                            LÖVE 11.5 (requires Emscripten in build image).
#
# Output: dist/web/{index.html, *.js, *.wasm, *.data}
#
# Run locally:
#   ./scripts/build-web.sh
#   (cd dist/web && python3 -m http.server 8000) → http://localhost:8000

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
OUT="$ROOT/dist/web"
LOVE_JS_VERSION="11.4.1"  # latest published on npm (see header note)

mkdir -p "$OUT"
rm -rf "${OUT:?}/"*

# Build the .love archive from a clean file. src/ owns presentation only; the
# canonical pure-Lua rules and content retain their battle/ module paths.
LOVE_ARCHIVE="$ROOT/dist/collack-spike.love"
mkdir -p "$ROOT/dist"
rm -f "$LOVE_ARCHIVE"
( cd "$SRC" && zip -9 -r "$LOVE_ARCHIVE" . -x '*.DS_Store' >/dev/null )
( cd "$ROOT" && zip -9 -r "$LOVE_ARCHIVE" battle \
    -x 'battle/tests/*' 'battle/cli.lua' 'battle/README.md' '*.DS_Store' >/dev/null )
unzip -tqq "$LOVE_ARCHIVE"
echo "[web] built $LOVE_ARCHIVE ($(du -h "$LOVE_ARCHIVE" | cut -f1))"

# Install love.js once into a local node_modules cache.
NODE_CACHE="$ROOT/.node_cache"
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

# Replace the stock love.js index.html with our responsive shell. The stock
# template uses a fixed loading canvas that draws offscreen on mobile portrait
# viewports (and a pink/cyan theme/bg.png that dominates the layout).
# Our web-shell/index.html is viewport-aware, centers both canvases via flex,
# uses a solid black background, and replaces the loadingCanvas progress with
# a DOM-rendered "Loading…" overlay.
SHELL_HTML="$ROOT/web-shell/index.html"
if [ -f "$SHELL_HTML" ]; then
    cp "$SHELL_HTML" "$OUT/index.html"
    echo "[web] installed responsive shell → $OUT/index.html"
else
    echo "[web] WARN: web-shell/index.html missing; using stock love.js template" >&2
fi

ls -lh "$OUT"
echo "[web] OK. Serve with: (cd $OUT && python3 -m http.server 8000)"
