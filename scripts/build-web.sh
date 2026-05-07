#!/usr/bin/env bash
# build-web.sh — compile src/ via love.js into a runnable browser bundle.
#
# Pinned versions:
#   LÖVE         : 11.5
#   love.js (npm): 11.4.1   ← latest published; npm release lags LÖVE proper
#                            (the Emscripten runtime is 11.4 but it can compile
#                            11.5 .love files; if 11.5 LÖVE-only APIs are used,
#                            either pin LÖVE source to 11.4 or build love.js
#                            from Davidobot/love.js master.)
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
LOVE_VERSION="11.5"
LOVE_JS_VERSION="11.4.1"  # latest published on npm (see header note)

mkdir -p "$OUT"
rm -rf "$OUT"/*

# Build the .love archive.
LOVE_ARCHIVE="$ROOT/dist/collack-spike.love"
mkdir -p "$ROOT/dist"
( cd "$SRC" && zip -9 -r "$LOVE_ARCHIVE" . -x '*.DS_Store' >/dev/null )
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
"$LOVE_JS_BIN" -c -t "Collack Spike" -m 67108864 "$LOVE_ARCHIVE" "$OUT" >/dev/null

echo "[web] love.js compile complete → $OUT"

# love.js outputs an index.html that includes its own UI shell. We optionally inject viewport + safe-area CSS for mobile.
if [ -f "$OUT/index.html" ]; then
    # Idempotent: only add viewport if not present.
    if ! grep -q 'name="viewport"' "$OUT/index.html"; then
        sed -i 's|<head>|<head>\n<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">|' "$OUT/index.html"
    fi
fi

ls -lh "$OUT"
echo "[web] OK. Serve with: (cd $OUT && python3 -m http.server 8000)"
