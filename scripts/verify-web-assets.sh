#!/usr/bin/env bash
# Assert that the packaged shell and both generated loader dependency chains use
# content-addressed names. Safe to run independently against a built dist/web.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/web}"
HTML="$OUT/index.html"
NGINX="$ROOT/deploy/fly/nginx.conf"

fail() {
    echo "[web-assets] FAIL: $*" >&2
    exit 1
}

[ -f "$HTML" ] || fail "missing $HTML"

GAME_JS_NAME="$(sed -nE 's|.*src="(game\.[0-9a-f]{16}\.js)".*|\1|p' "$HTML")"
LOVE_JS_NAME="$(sed -nE 's|.*src="(love\.[0-9a-f]{16}\.js)".*|\1|p' "$HTML")"
[ -n "$GAME_JS_NAME" ] || fail "index.html does not name a hashed game loader"
[ -n "$LOVE_JS_NAME" ] || fail "index.html does not name a hashed LÖVE loader"
[ -f "$OUT/$GAME_JS_NAME" ] || fail "missing HTML-referenced $GAME_JS_NAME"
[ -f "$OUT/$LOVE_JS_NAME" ] || fail "missing HTML-referenced $LOVE_JS_NAME"

GAME_DATA_NAME="$(grep -Eo 'game\.[0-9a-f]{16}\.data' "$OUT/$GAME_JS_NAME" | head -n 1)"
LOVE_WASM_NAME="$(grep -Eo 'love\.[0-9a-f]{16}\.wasm' "$OUT/$LOVE_JS_NAME" | head -n 1)"
[ -n "$GAME_DATA_NAME" ] || fail "$GAME_JS_NAME does not name hashed game data"
[ -n "$LOVE_WASM_NAME" ] || fail "$LOVE_JS_NAME does not name hashed WebAssembly"
[ -f "$OUT/$GAME_DATA_NAME" ] || fail "missing loader-referenced $GAME_DATA_NAME"
[ -f "$OUT/$LOVE_WASM_NAME" ] || fail "missing loader-referenced $LOVE_WASM_NAME"

verify_hash() {
    local name="$1"
    local path="$2"
    local without_extension="${name%.*}"
    local expected="${without_extension##*.}"
    local actual
    actual="$(shasum -a 256 "$path" | awk '{print substr($1, 1, 16)}')"
    [ "$actual" = "$expected" ] || fail "$name hash is $expected but content hashes to $actual"
}

verify_hash "$GAME_DATA_NAME" "$OUT/$GAME_DATA_NAME"
verify_hash "$GAME_JS_NAME" "$OUT/$GAME_JS_NAME"
verify_hash "$LOVE_WASM_NAME" "$OUT/$LOVE_WASM_NAME"
verify_hash "$LOVE_JS_NAME" "$OUT/$LOVE_JS_NAME"

for stale_name in game.js game.data love.js love.wasm; do
    [ ! -e "$OUT/$stale_name" ] || fail "stale fixed bundle URL is still shipped: $stale_name"
done
grep -Fq 'src="game.js"' "$HTML" && fail "index.html still references game.js"
grep -Fq 'src="love.js"' "$HTML" && fail "index.html still references love.js"
grep -Fq "game.data" "$OUT/$GAME_JS_NAME" && fail "$GAME_JS_NAME still references game.data"
grep -Fq "love.wasm" "$OUT/$LOVE_JS_NAME" && fail "$LOVE_JS_NAME still references love.wasm"
grep -Fq "__GAME_JS__" "$HTML" && fail "game loader placeholder was not replaced"
grep -Fq "__LOVE_JS__" "$HTML" && fail "LÖVE loader placeholder was not replaced"
[ -f "$NGINX" ] || fail "missing Fly nginx config"
grep -Fq 'location ~* \.[0-9a-f]{16}\.(wasm|js|data)$ {' "$NGINX"
grep -Fq 'Cache-Control "public, max-age=31536000, immutable"' "$NGINX"
grep -Fq 'location ~* \.(wasm|js|data)$ {' "$NGINX" \
    && fail "nginx still marks unhashed runtime URLs immutable"

echo "[web-assets] OK: $GAME_JS_NAME → $GAME_DATA_NAME; $LOVE_JS_NAME → $LOVE_WASM_NAME"
