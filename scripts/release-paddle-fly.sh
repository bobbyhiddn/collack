#!/usr/bin/env bash
# Explicit deployment entry point for the provenance-safe paddle Fly target.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_CONFIG="$ROOT/deploy/fly/paddle.fly.toml"
SOURCE_DOCKERFILE="$ROOT/deploy/fly/Dockerfile.paddle"
TEMP_ROOT=""

fail() {
    echo "[paddle-fly] FAIL: $*" >&2
    exit 1
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$#" -ne 1 ] || [ "$1" != "--deploy" ]; then
    fail "deployment requires the explicit command: $0 --deploy"
fi
command -v flyctl >/dev/null 2>&1 || fail "flyctl is not installed"
[ -f "$SOURCE_CONFIG" ] || fail "missing dedicated paddle Fly config"
[ -f "$SOURCE_DOCKERFILE" ] || fail "missing dedicated paddle Dockerfile"

# Never let the service name, image tag, or caller-supplied source labels define
# artifact identity. The gate derives it from checked-out Git and exact bytes.
node "$ROOT/scripts/verify-paddle-release.mjs"

release_file_set() {
    local artifact_root="$1"
    (
        cd "$ROOT"
        node --input-type=module -e '
          import { validatePaddleReleaseArtifact } from "./scripts/paddle-release-contract.mjs";
          const release = await validatePaddleReleaseArtifact(process.argv[1]);
          process.stdout.write(release.releaseFileSetSha256);
        ' "$artifact_root"
    )
}

# Upload a sealed target-only context. Revalidate after copying so a concurrent
# source change cannot replace the authenticated artifact sent to Fly.
EXPECTED_FILE_SET="$(release_file_set "$ROOT/dist/paddle-web")"
TEMP_ROOT="$(mktemp -d "$ROOT/dist/.paddle-fly-context.XXXXXX")"
mkdir -p "$TEMP_ROOT/deploy/fly" "$TEMP_ROOT/scripts" "$TEMP_ROOT/dist"
cp "$SOURCE_DOCKERFILE" "$TEMP_ROOT/deploy/fly/Dockerfile.paddle"
cp "$ROOT/deploy/fly/Dockerfile.paddle.dockerignore" \
    "$TEMP_ROOT/deploy/fly/Dockerfile.paddle.dockerignore"
cp "$ROOT/deploy/fly/nginx.paddle.conf" "$TEMP_ROOT/deploy/fly/nginx.paddle.conf"
cp "$SOURCE_CONFIG" "$TEMP_ROOT/deploy/fly/paddle.fly.toml"
cp "$ROOT/scripts/paddle-release-contract.mjs" \
    "$TEMP_ROOT/scripts/paddle-release-contract.mjs"
cp -R "$ROOT/dist/paddle-web" "$TEMP_ROOT/dist/paddle-web"
SEALED_FILE_SET="$(release_file_set "$TEMP_ROOT/dist/paddle-web")"
[ "$SEALED_FILE_SET" = "$EXPECTED_FILE_SET" ] \
    || fail "sealed Fly context differs from authenticated paddle release"

echo "[paddle-fly] deploying authenticated target=paddle-web to app=collack-spike"
flyctl deploy "$TEMP_ROOT" \
    --config "$TEMP_ROOT/deploy/fly/paddle.fly.toml" \
    --dockerfile "deploy/fly/Dockerfile.paddle"
