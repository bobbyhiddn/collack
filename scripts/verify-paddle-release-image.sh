#!/usr/bin/env bash
# Validate one actual image by immutable ID against a fresh exact-source rebuild.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${CALLACK_CONTAINER_ENGINE:-}"
IMAGE_ID="${1:-}"
TEMP_ROOT=""; INSPECT_CONTAINER=""
fail() { echo "[paddle-release-image-verify] FAIL: $*" >&2; exit 1; }
container() { case "$ENGINE" in podman) podman "$@" ;; docker) docker "$@" ;; *) fail "unsupported container engine: $ENGINE" ;; esac; }
cleanup() { local status=$?; trap - EXIT INT TERM; set +e; [ -z "$INSPECT_CONTAINER" ] || container rm --force "$INSPECT_CONTAINER" >/dev/null 2>&1; [ -z "$TEMP_ROOT" ] || rm -rf "$TEMP_ROOT"; exit "$status"; }
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
[ "$#" -eq 1 ] || fail "usage: $0 sha256:<64-hex-image-id>"
[[ "$IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "image reference is not an immutable image ID: $IMAGE_ID"
case "$ENGINE" in podman|docker) ;; *) fail "CALLACK_CONTAINER_ENGINE must be podman or docker" ;; esac
[ "$(container image inspect --format '{{.Id}}' "$IMAGE_ID")" = "$IMAGE_ID" ] || fail "image ID changed during resolution"

TEMP_ROOT="$(mktemp -d "$ROOT/dist/.paddle-image-verify.XXXXXX")"
IMAGE_ROOT="$TEMP_ROOT/dist/paddle-web"; mkdir -p "$IMAGE_ROOT"
INSPECT_CONTAINER="callack-paddle-image-verify-$$-$RANDOM"
container create --name "$INSPECT_CONTAINER" "$IMAGE_ID" >/dev/null
container cp "$INSPECT_CONTAINER:/srv/callack/paddle-web/." "$IMAGE_ROOT"
FIELDS="$(cd "$ROOT" && node --input-type=module -e '
  import { verifyPaddleRelease } from "./scripts/verify-paddle-release.mjs";
  const r=await verifyPaddleRelease(process.cwd(),{artifactRoot:process.argv[1],enforceCanonicalPath:false,quiet:true});
  const tool=r.releaseFiles.find((f)=>f.path==="callack-toolchain-identity.json");
  process.stdout.write(JSON.stringify({revision:r.manifest.revision,tree:r.manifest.tree,target:r.manifest.target,manifest:r.manifestSha256,assetSet:r.manifest.assetSetSha256,fileSet:r.releaseFileSetSha256,archive:r.archiveSha256,tool:tool.sha256}));
' "$IMAGE_ROOT")"
field() { node -e 'const v=JSON.parse(process.argv[1])[process.argv[2]]; if(typeof v!=="string"||!v)process.exit(2); process.stdout.write(v)' "$FIELDS" "$1"; }
label() { container image inspect --format "{{ index .Config.Labels \"$1\" }}" "$IMAGE_ID"; }
for mapping in \
  'target:io.callack.release.target' \
  'revision:org.opencontainers.image.revision' \
  'tree:io.callack.release.source-tree' \
  'manifest:io.callack.release.manifest-sha256' \
  'assetSet:io.callack.release.asset-set-sha256' \
  'fileSet:io.callack.release.file-set-sha256' \
  'archive:io.callack.release.archive-sha256' \
  'tool:io.callack.release.toolchain-sha256'; do
    key="${mapping%%:*}"; image_label="${mapping#*:}"
    [ "$(label "$image_label")" = "$(field "$key")" ] || fail "image label $image_label disagrees with validated image filesystem"
done
[ "$(label io.callack.release.artifact-path)" = dist/paddle-web ] || fail "image artifact-path label is not canonical"
echo "[paddle-release-image-verify] OK: image=$IMAGE_ID revision=$(field revision) tree=$(field tree) fileSet=$(field fileSet)"
echo "CALLACK_VALIDATED_IMAGE=$IMAGE_ID"
