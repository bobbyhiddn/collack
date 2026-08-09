#!/usr/bin/env bash
# Publish and deploy only an already-built, validated immutable paddle image.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_CONFIG="$ROOT/deploy/fly/paddle.fly.toml"
REGISTRY_REPOSITORY="registry.fly.io/collack-spike"
ENGINE="${CALLACK_CONTAINER_ENGINE:-}"
IMAGE_ID=""

fail() { echo "[paddle-fly] FAIL: $*" >&2; exit 1; }
container() { case "$ENGINE" in podman) podman "$@" ;; docker) docker "$@" ;; *) fail "unsupported container engine: $ENGINE" ;; esac; }
engine_works() { case "$1" in podman) command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1 ;; docker) command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 ;; *) return 1 ;; esac; }

if [ "$#" -ne 3 ] || [ "$1" != "--deploy" ] || [ "$2" != "--image" ]; then
    fail "usage: $0 --deploy --image sha256:<64-hex-image-id>"
fi
IMAGE_ID="$3"
[[ "$IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "release image must be an immutable local image ID"
command -v flyctl >/dev/null 2>&1 || fail "flyctl is not installed"
[ -f "$SOURCE_CONFIG" ] || fail "missing dedicated paddle Fly config"
if [ -n "$ENGINE" ]; then
    case "$ENGINE" in podman|docker) engine_works "$ENGINE" || fail "requested container engine is unavailable: $ENGINE" ;; *) fail "CALLACK_CONTAINER_ENGINE must be podman or docker" ;; esac
elif engine_works podman; then ENGINE=podman
elif engine_works docker; then ENGINE=docker
else fail "neither Podman nor Docker is available"
fi

# This gate reads the image by ID, not dist/ or a tag, and independently binds
# its filesystem and labels to the exact checked-out revision/tree.
CALLACK_CONTAINER_ENGINE="$ENGINE" bash "$ROOT/scripts/verify-paddle-release-image.sh" "$IMAGE_ID"
PUBLISH_TAG="$REGISTRY_REPOSITORY:candidate-${IMAGE_ID#sha256:}"
container tag "$IMAGE_ID" "$PUBLISH_TAG"
[ "$(container image inspect --format '{{.Id}}' "$PUBLISH_TAG")" = "$IMAGE_ID" ] \
    || fail "registry staging tag does not resolve to the validated image"
PUSH_OUTPUT="$(container push "$PUBLISH_TAG" 2>&1)" || fail "registry publication failed"
printf '%s\n' "$PUSH_OUTPUT"
REMOTE_DIGEST="$(node -e 'const m=process.argv[1].match(/digest:\s*(sha256:[0-9a-f]{64})/g); if(!m)process.exit(2); process.stdout.write(m.at(-1).match(/sha256:[0-9a-f]{64}/)[0])' "$PUSH_OUTPUT")" \
    || fail "registry publication did not return an immutable digest"
REMOTE_REF="$REGISTRY_REPOSITORY@$REMOTE_DIGEST"
REMOTE_MANIFEST="$(container manifest inspect "$REMOTE_REF")" || fail "published digest cannot be inspected"
REMOTE_CONFIG="$(node -e 'const m=JSON.parse(process.argv[1]); const d=m.config?.digest; if(!/^sha256:[0-9a-f]{64}$/.test(d??""))process.exit(2); process.stdout.write(d)' "$REMOTE_MANIFEST")" \
    || fail "published manifest has no immutable config identity"
[ "$REMOTE_CONFIG" = "$IMAGE_ID" ] \
    || fail "published digest config $REMOTE_CONFIG differs from validated image $IMAGE_ID"

echo "[paddle-fly] deploying validated image=$IMAGE_ID as $REMOTE_REF"
# --image prevents Fly from rebuilding or reading a working-tree build context.
flyctl deploy --config "$SOURCE_CONFIG" --image "$REMOTE_REF"
echo "[paddle-fly] OK: released immutable reference=$REMOTE_REF"
