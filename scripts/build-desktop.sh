#!/usr/bin/env bash
# build-desktop.sh — produce .love archive + fused Linux x86_64 binary.
# Bonus: produce Windows .exe via the cat-recipe if love-11.5-win64.zip is fetched.
#
# Output:
#   dist/collack-spike.love
#   dist/desktop/collack-spike.x86_64    (fused Linux AppImage; runs standalone)
#   dist/desktop/collack-spike-win64.zip (if --windows flag passed)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
DIST="$ROOT/dist"
DESKTOP="$DIST/desktop"
LOVE_VERSION="11.5"
LOVE_APPIMAGE_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-x86_64.AppImage"
LOVE_WIN64_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-win64.zip"
CACHE="$ROOT/.love_cache"

mkdir -p "$DESKTOP" "$CACHE"

# 1. Build presentation plus the canonical battle modules.
LOVE_ARCHIVE="$DIST/collack-spike.love"
rm -f "$LOVE_ARCHIVE"
( cd "$SRC" && zip -9 -r "$LOVE_ARCHIVE" . -x '*.DS_Store' >/dev/null )
( cd "$ROOT" && zip -9 -r "$LOVE_ARCHIVE" battle \
    -x 'battle/tests/*' 'battle/cli.lua' 'battle/README.md' '*.DS_Store' >/dev/null )
if [ -d "$ROOT/assets" ]; then
    ( cd "$ROOT" && zip -9 -r "$LOVE_ARCHIVE" assets -x '*.DS_Store' >/dev/null )
fi
unzip -tqq "$LOVE_ARCHIVE"
ARCHIVE_LIST="$(unzip -Z -1 "$LOVE_ARCHIVE")"
for required in \
    main.lua conf.lua presentation.lua run_controller.lua run_presentation.lua \
    run_loop.lua ui/art_tokens.lua battle/engine.lua battle/physics.lua \
    battle/checkpoints.lua battle/run.lua battle/draft.lua battle/opponent.lua \
    battle/setup.lua battle/setup_rules.lua
do
    grep -Fxq "$required" <<<"$ARCHIVE_LIST" || {
        echo "[desktop] ERROR: runtime archive is missing $required" >&2
        exit 1
    }
done
if grep -Eq '^battle/(tests/|cli\.lua$)' <<<"$ARCHIVE_LIST"; then
    echo "[desktop] ERROR: quarantined headless/demo paths entered the runtime archive" >&2
    exit 1
fi
echo "[desktop] built $LOVE_ARCHIVE"

# 2. Fetch LÖVE Linux AppImage runtime (cached).
APPIMAGE="$CACHE/love-${LOVE_VERSION}-x86_64.AppImage"
if [ ! -f "$APPIMAGE" ]; then
    echo "[desktop] fetching LÖVE ${LOVE_VERSION} AppImage..."
    curl -fL --progress-bar "$LOVE_APPIMAGE_URL" -o "$APPIMAGE"
    chmod +x "$APPIMAGE"
fi

# 3. Fuse: cat AppImage + .love → standalone binary (LÖVE auto-mounts trailing zip).
LINUX_BIN="$DESKTOP/collack-spike.x86_64"
cat "$APPIMAGE" "$LOVE_ARCHIVE" > "$LINUX_BIN"
chmod +x "$LINUX_BIN"
echo "[desktop] built $LINUX_BIN ($(du -h "$LINUX_BIN" | cut -f1))"

# 4. Optional Windows build.
if [ "${1:-}" = "--windows" ]; then
    WIN_ZIP="$CACHE/love-${LOVE_VERSION}-win64.zip"
    if [ ! -f "$WIN_ZIP" ]; then
        echo "[desktop] fetching LÖVE ${LOVE_VERSION} win64 zip..."
        curl -fL --progress-bar "$LOVE_WIN64_URL" -o "$WIN_ZIP"
    fi
    WIN_DIR="$CACHE/love-win64"
    rm -rf "$WIN_DIR" && mkdir -p "$WIN_DIR"
    unzip -q "$WIN_ZIP" -d "$WIN_DIR"
    LOVE_DIR=$(find "$WIN_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)
    # cat love.exe + .love → fused exe.
    cat "$LOVE_DIR/love.exe" "$LOVE_ARCHIVE" > "$LOVE_DIR/collack-spike.exe"
    rm -f "$LOVE_DIR/love.exe" "$LOVE_DIR/lovec.exe"
    ( cd "$LOVE_DIR" && zip -9 -r "$DESKTOP/collack-spike-win64.zip" . >/dev/null )
    echo "[desktop] built $DESKTOP/collack-spike-win64.zip"
fi

echo "[desktop] OK"
