#!/usr/bin/env bash
# Authenticate canonical dist/paddle-web, then build the dedicated release image.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="$ROOT/deploy/fly/Dockerfile.paddle"
MANIFEST="$ROOT/dist/paddle-web/callack-build-manifest.json"
ENGINE="${CALLACK_CONTAINER_ENGINE:-}"
IMAGE_TAG="${1:-localhost/callack-paddle-release:verified}"
TEMP_ROOT=""
INSPECT_CONTAINER=""

fail() {
    echo "[paddle-release-image] FAIL: $*" >&2
    exit 1
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    if [ -n "$INSPECT_CONTAINER" ] && [ -n "$ENGINE" ]; then
        container rm --force "$INSPECT_CONTAINER" >/dev/null 2>&1
    fi
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$#" -le 1 ] || fail "usage: $0 [image-tag]"
[ -n "$IMAGE_TAG" ] || fail "image tag must not be empty"

container() {
    case "$ENGINE" in
        podman)
            podman "$@"
            ;;
        docker)
            docker "$@"
            ;;
        *)
            fail "unsupported container engine: $ENGINE"
            ;;
    esac
}

engine_works() {
    case "$1" in
        podman)
            command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1
            ;;
        docker)
            command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

if [ -n "$ENGINE" ]; then
    case "$ENGINE" in
        podman|docker)
            engine_works "$ENGINE" \
                || fail "requested container engine is unavailable: $ENGINE"
            ;;
        *)
            fail "CALLACK_CONTAINER_ENGINE must be podman or docker"
            ;;
    esac
elif engine_works podman; then
    ENGINE="podman"
elif engine_works docker; then
    ENGINE="docker"
else
    fail "neither Podman nor Docker is available"
fi

command -v node >/dev/null 2>&1 || fail "node is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
[ -f "$DOCKERFILE" ] || fail "missing dedicated paddle Dockerfile"

# This is the artifact trust gate. It derives identity from clean checked-out
# Git state and compares every supplied byte with an independent source rebuild.
node "$ROOT/scripts/verify-paddle-release.mjs"

manifest_field() {
    node -e '
      const fs = require("node:fs");
      const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const value = manifest[process.argv[2]];
      if (typeof value !== "string" || value.length === 0) process.exit(2);
      process.stdout.write(value);
    ' "$MANIFEST" "$1"
}

REVISION="$(manifest_field revision)"
TREE="$(manifest_field tree)"
TARGET="$(manifest_field target)"
ASSET_SET_SHA256="$(manifest_field assetSetSha256)"
MANIFEST_SHA256="$(sha256sum "$MANIFEST" | awk '{print $1}')"
[ "$TARGET" = "paddle-web" ] || fail "authenticated target changed before image build"
RELEASE_FILE_SET_SHA256="$(
    cd "$ROOT"
    node --input-type=module -e '
      import { validatePaddleReleaseArtifact } from "./scripts/paddle-release-contract.mjs";
      const release = await validatePaddleReleaseArtifact("./dist/paddle-web");
      process.stdout.write(release.releaseFileSetSha256);
    '
)"

echo "[paddle-release-image] building $IMAGE_TAG from authenticated dist/paddle-web with $ENGINE"
container build \
    --file "$DOCKERFILE" \
    --tag "$IMAGE_TAG" \
    --label "org.opencontainers.image.revision=$REVISION" \
    --label "io.callack.release.source-tree=$TREE" \
    --label "io.callack.release.manifest-sha256=$MANIFEST_SHA256" \
    --label "io.callack.release.asset-set-sha256=$ASSET_SET_SHA256" \
    "$ROOT"

IMAGE_ID="$(container image inspect --format '{{.Id}}' "$IMAGE_TAG")"
for label_and_expected in \
    "io.callack.release.target=paddle-web" \
    "io.callack.release.artifact-path=dist/paddle-web" \
    "org.opencontainers.image.revision=$REVISION" \
    "io.callack.release.source-tree=$TREE" \
    "io.callack.release.manifest-sha256=$MANIFEST_SHA256" \
    "io.callack.release.asset-set-sha256=$ASSET_SET_SHA256"; do
    label="${label_and_expected%%=*}"
    expected="${label_and_expected#*=}"
    actual="$(container image inspect --format "{{ index .Config.Labels \"$label\" }}" "$IMAGE_TAG")"
    [ "$actual" = "$expected" ] \
        || fail "image label $label is '$actual', expected '$expected'"
done

# Close the validation/build race: extract the final image without running it,
# revalidate its exact file set, and compare it with the pre-build sealed set.
TEMP_ROOT="$(mktemp -d "$ROOT/dist/.paddle-image-inspect.XXXXXX")"
IMAGE_ROOT="$TEMP_ROOT/dist/paddle-web"
mkdir -p "$IMAGE_ROOT"
INSPECT_CONTAINER="callack-paddle-image-inspect-$$-$RANDOM"
container create --name "$INSPECT_CONTAINER" "$IMAGE_TAG" >/dev/null
container cp "$INSPECT_CONTAINER:/srv/callack/paddle-web/." "$IMAGE_ROOT"
IMAGE_FILE_SET_SHA256="$(
    cd "$ROOT"
    node --input-type=module -e '
      import { validatePaddleReleaseArtifact } from "./scripts/paddle-release-contract.mjs";
      const release = await validatePaddleReleaseArtifact(process.argv[1]);
      process.stdout.write(release.releaseFileSetSha256);
    ' "$IMAGE_ROOT"
)"
[ "$IMAGE_FILE_SET_SHA256" = "$RELEASE_FILE_SET_SHA256" ] \
    || fail "built image file set $IMAGE_FILE_SET_SHA256 differs from authenticated $RELEASE_FILE_SET_SHA256"

echo "[paddle-release-image] OK: image=$IMAGE_ID target=$TARGET revision=$REVISION tree=$TREE"
echo "[paddle-release-image] OK: manifest=$MANIFEST_SHA256 assetSet=$ASSET_SET_SHA256 fileSet=$IMAGE_FILE_SET_SHA256"
