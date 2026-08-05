#!/usr/bin/env bash
# Serve only the candidate-owned paddle output and run the strict browser gate.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${CALLACK_PADDLE_VERIFY_PORT:-4173}"
HOST="127.0.0.1"
OUT="$ROOT/dist/paddle-web"
SERVER_LOG="$ROOT/dist/paddle-verifier-http.log"

mkdir -p "$OUT"
python3 -m http.server "$PORT" --bind "$HOST" --directory "$OUT" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

CALLACK_DEPLOYED_URL="http://$HOST:$PORT/" \
    node "$ROOT/scripts/verify-deployed-spike.mjs"
