#!/usr/bin/env bash
# Build one paddle image, then promote its immutable ID only after validation.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="$ROOT/deploy/fly/Dockerfile.paddle"
ENGINE="${CALLACK_CONTAINER_ENGINE:-}"
IMAGE_TAG="${1:-localhost/callack-paddle-release:verified}"

fail() { echo "[paddle-release-image] FAIL: $*" >&2; exit 1; }
container() {
    case "$ENGINE" in
        podman) podman "$@" ;;
        docker) docker "$@" ;;
        *) fail "unsupported container engine: $ENGINE" ;;
    esac
}
engine_works() {
    case "$1" in
        podman) command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1 ;;
        docker) command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

[ "$#" -le 1 ] || fail "usage: $0 [image-tag]"
[ -n "$IMAGE_TAG" ] || fail "image tag must not be empty"
if [ -n "$ENGINE" ]; then
    case "$ENGINE" in podman|docker) engine_works "$ENGINE" || fail "requested container engine is unavailable: $ENGINE" ;; *) fail "CALLACK_CONTAINER_ENGINE must be podman or docker" ;; esac
elif engine_works podman; then ENGINE=podman
elif engine_works docker; then ENGINE=docker
else fail "neither Podman nor Docker is available"
fi
command -v node >/dev/null 2>&1 || fail "node is required"
[ -f "$DOCKERFILE" ] || fail "missing dedicated paddle Dockerfile"

# Canonical output is always rebuilt from the clean checked-out commit with the
# repository-pinned tool/archive contract. No caller-provided artifact is used.
[ -z "$(git -C "$ROOT" status --porcelain=v1 --untracked-files=no)" ] \
    || fail "paddle image build requires a clean tracked checkout"
bash "$ROOT/scripts/build-paddle-web.sh"
node "$ROOT/scripts/verify-paddle-release.mjs"

FIELDS="$(cd "$ROOT" && node --input-type=module -e '
  import { validatePaddleReleaseArtifact } from "./scripts/paddle-release-contract.mjs";
  const r = await validatePaddleReleaseArtifact("./dist/paddle-web");
  const tool = r.releaseFiles.find((f) => f.path === "callack-toolchain-identity.json");
  process.stdout.write(JSON.stringify({revision:r.manifest.revision,tree:r.manifest.tree,target:r.manifest.target,manifest:r.manifestSha256,assetSet:r.manifest.assetSetSha256,fileSet:r.releaseFileSetSha256,archive:r.manifest.toolchain.candidateArchive.sha256,tool:tool.sha256}));
')"
field() { node -e 'const v=JSON.parse(process.argv[1])[process.argv[2]]; if(typeof v!=="string"||!v)process.exit(2); process.stdout.write(v)' "$FIELDS" "$1"; }
REVISION="$(field revision)"; TREE="$(field tree)"; TARGET="$(field target)"
MANIFEST_SHA256="$(field manifest)"; ASSET_SET_SHA256="$(field assetSet)"
FILE_SET_SHA256="$(field fileSet)"; ARCHIVE_SHA256="$(field archive)"; TOOL_SHA256="$(field tool)"
[ "$TARGET" = paddle-web ] || fail "authenticated target is not paddle-web"

echo "[paddle-release-image] building once from canonical dist/paddle-web with $ENGINE"
container build --file "$DOCKERFILE" --tag "$IMAGE_TAG" \
    --label "org.opencontainers.image.revision=$REVISION" \
    --label "io.callack.release.source-tree=$TREE" \
    --label "io.callack.release.manifest-sha256=$MANIFEST_SHA256" \
    --label "io.callack.release.asset-set-sha256=$ASSET_SET_SHA256" \
    --label "io.callack.release.file-set-sha256=$FILE_SET_SHA256" \
    --label "io.callack.release.archive-sha256=$ARCHIVE_SHA256" \
    --label "io.callack.release.toolchain-sha256=$TOOL_SHA256" "$ROOT"

IMAGE_ID="$(container image inspect --format '{{.Id}}' "$IMAGE_TAG")"
[[ "$IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "container engine returned a non-immutable image ID: $IMAGE_ID"
# From here onward the mutable tag is never trusted. The actual image is
# independently checked against a fresh exact-source rebuild by immutable ID.
CALLACK_CONTAINER_ENGINE="$ENGINE" bash "$ROOT/scripts/verify-paddle-release-image.sh" "$IMAGE_ID"
echo "[paddle-release-image] OK: candidate=$IMAGE_ID revision=$REVISION tree=$TREE"
echo "CALLACK_VALIDATED_IMAGE=$IMAGE_ID"
