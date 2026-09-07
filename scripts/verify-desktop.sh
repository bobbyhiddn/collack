#!/usr/bin/env bash
# Real Linux startup and native-save smoke, on an isolated virtual display.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" != "--inside-display" ]; then
    exec timeout 60s xvfb-run -a bash "$0" --inside-display
fi

EVIDENCE="$ROOT/dist/desktop-verification"
mkdir -p "$EVIDENCE"
PROFILE="$(mktemp -d "$EVIDENCE/profile.XXXXXX")"
GAME_PID=""
cleanup() {
    if [ -n "$GAME_PID" ]; then
        kill "$GAME_PID" 2>/dev/null || true
        wait "$GAME_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

XDG_DATA_HOME="$PROFILE" LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null \
    stdbuf -oL "$ROOT/dist/desktop/collack-spike.x86_64" --desktop --seed=9125 \
    > "$EVIDENCE/native.log" 2>&1 &
GAME_PID=$!

wait_for_log() {
    local expected="$1"
    for _attempt in {1..200}; do
        if grep -Fq "$expected" "$EVIDENCE/native.log"; then return; fi
        if ! kill -0 "$GAME_PID" 2>/dev/null; then break; fi
        sleep 0.1
    done
    cat "$EVIDENCE/native.log"
    echo "[desktop-smoke] missing: $expected" >&2
    exit 1
}

wait_for_log 'CALLACK_ACTION ready seed=9125 phase=setup'
WINDOW="$(xdotool search --onlyvisible --name '^Collack | SETUP | Seed 9125$' | head -1)"
xdotool windowfocus --sync "$WINDOW"
xdotool key Return
wait_for_log 'COLLACK_MENU new'
xdotool mousemove --window "$WINDOW" 160 618 click 1
wait_for_log 'CALLACK_ACTION quick_arrange'
test -s "$PROFILE/love/collack-spike/expedition.save"
echo '[desktop-smoke] OK: bundled native game boots, arranges bricks, and writes a native save'
