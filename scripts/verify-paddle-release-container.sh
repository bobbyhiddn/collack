#!/usr/bin/env bash
# Build and exercise the dedicated paddle Fly image, including real browser input.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_ROOT="$ROOT/dist/paddle-web"
ENGINE="${CALLACK_CONTAINER_ENGINE:-}"
VERIFY_BROWSER="${CALLACK_PADDLE_CONTAINER_BROWSER:-1}"
RUN_ID="$$-$RANDOM"
CONTAINER_NAME="callack-paddle-release-smoke-$RUN_ID"
IMAGE_TAG="localhost/callack-paddle-release-smoke:$RUN_ID"
TEMP_ROOT=""

fail() {
    echo "[paddle-release-container] FAIL: $*" >&2
    exit 1
}

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

cleanup() {
    local status=$?
    local cleanup_failed=0

    trap - EXIT INT TERM
    set +e
    if [ -n "$ENGINE" ]; then
        container rm --force "$CONTAINER_NAME" >/dev/null 2>&1
        if container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
            echo "[paddle-release-container] FAIL: cleanup left $CONTAINER_NAME behind" >&2
            cleanup_failed=1
        fi
        container image rm --force "$IMAGE_TAG" >/dev/null 2>&1
    fi
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
    if [ "$status" -eq 0 ] && [ "$cleanup_failed" -ne 0 ]; then
        status=1
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "$VERIFY_BROWSER" in
    0|1)
        ;;
    *)
        fail "CALLACK_PADDLE_CONTAINER_BROWSER must be 0 or 1"
        ;;
esac

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

for dependency in curl cmp find sort awk node sha256sum; do
    command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done
[ -f "$WEB_ROOT/index.html" ] \
    || fail "missing dist/paddle-web/index.html; run scripts/build-paddle-web.sh first"

mapfile -t ARTIFACTS < <(
    cd "$WEB_ROOT"
    find . -type f -print | LC_ALL=C sort | sed 's|^\./||'
)
[ "${#ARTIFACTS[@]}" -gt 0 ] || fail "dist/paddle-web contains no files"

HASHED_ASSET=""
UNHASHED_ASSET=""
for relative_path in "${ARTIFACTS[@]}"; do
    if [[ "$relative_path" =~ \.[0-9a-f]{16}\.(wasm|js|data)$ ]]; then
        if [ -z "$HASHED_ASSET" ]; then
            HASHED_ASSET="$relative_path"
        fi
    elif [[ "$relative_path" == theme/* ]] && [ -z "$UNHASHED_ASSET" ]; then
        UNHASHED_ASSET="$relative_path"
    fi
done
[ -n "$HASHED_ASSET" ] || fail "paddle output contains no content-addressed runtime asset"
[ -n "$UNHASHED_ASSET" ] || fail "paddle output contains no unversioned theme asset"

CALLACK_CONTAINER_ENGINE="$ENGINE" \
    bash "$ROOT/scripts/build-paddle-release-image.sh" "$IMAGE_TAG"
IMAGE_ID="$(container image inspect --format '{{.Id}}' "$IMAGE_TAG")"

TEMP_ROOT="$(mktemp -d "$ROOT/dist/.paddle-release-container.XXXXXX")"
LIVE_ROOT="$TEMP_ROOT/live"
IMAGE_ROOT="$TEMP_ROOT/image-root"
mkdir -p "$LIVE_ROOT" "$IMAGE_ROOT"

container run --detach \
    --name "$CONTAINER_NAME" \
    --publish 127.0.0.1::8080 \
    "$IMAGE_TAG" >/dev/null

CONTAINER_ID="$(container inspect --format '{{.Id}}' "$CONTAINER_NAME")"
PORT_BINDING="$(container port "$CONTAINER_NAME" 8080/tcp | sed -n '1p')"
HOST_PORT="${PORT_BINDING##*:}"
case "$HOST_PORT" in
    ""|*[!0-9]*)
        fail "could not determine ephemeral host port from: $PORT_BINDING"
        ;;
esac
BASE_URL="http://127.0.0.1:$HOST_PORT"

READY=0
for _attempt in {1..30}; do
    status=""
    if status="$(curl --connect-timeout 1 --max-time 1 --output /dev/null \
        --silent --write-out '%{http_code}' "$BASE_URL/")" && [ "$status" = "200" ]; then
        READY=1
        break
    fi
    running="$(container inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)"
    if [ "$running" != "true" ]; then
        container logs "$CONTAINER_NAME" >&2
        fail "container exited before HTTP readiness"
    fi
    sleep 0.25
done
[ "$READY" -eq 1 ] || fail "container did not become ready"

# Prove the final image filesystem contains exactly the canonical paddle files.
container cp "$CONTAINER_NAME:/srv/callack/paddle-web/." "$IMAGE_ROOT"
mapfile -t IMAGE_ARTIFACTS < <(
    cd "$IMAGE_ROOT"
    find . -type f -print | LC_ALL=C sort | sed 's|^\./||'
)
[ "${ARTIFACTS[*]}" = "${IMAGE_ARTIFACTS[*]}" ] \
    || fail "image asset set differs: image=${IMAGE_ARTIFACTS[*]} candidate=${ARTIFACTS[*]}"
for relative_path in "${ARTIFACTS[@]}"; do
    cmp -s "$WEB_ROOT/$relative_path" "$IMAGE_ROOT/$relative_path" \
        || fail "image bytes differ for $relative_path"
done

fetch() {
    local request_path="$1"
    local body_path="$2"
    local headers_path="$3"
    local expected_status="${4:-200}"
    local status
    status="$(curl \
        --connect-timeout 2 \
        --dump-header "$headers_path" \
        --max-time 15 \
        --output "$body_path" \
        --path-as-is \
        --silent \
        --show-error \
        --write-out '%{http_code}' \
        "$BASE_URL$request_path")" \
        || fail "request failed for $request_path"
    [ "$status" = "$expected_status" ] \
        || fail "$request_path returned HTTP $status, expected $expected_status"
}

header_value() {
    local header_name="$1"
    local headers_path="$2"
    awk -v wanted="$header_name" '
        tolower($1) == tolower(wanted ":") {
            $1 = ""
            sub(/^[[:space:]]+/, "")
            sub(/\r$/, "")
            print
            exit
        }
    ' "$headers_path"
}

for relative_path in "${ARTIFACTS[@]}"; do
    live_path="$LIVE_ROOT/$relative_path"
    headers_path="$TEMP_ROOT/artifact.headers"
    mkdir -p "$(dirname "$live_path")"
    fetch "/$relative_path" "$live_path" "$headers_path"
    cmp -s "$WEB_ROOT/$relative_path" "$live_path" \
        || fail "served bytes differ for /$relative_path"
done

fetch "/" "$TEMP_ROOT/root.body" "$TEMP_ROOT/root.headers"
fetch "/index.html" "$TEMP_ROOT/index.body" "$TEMP_ROOT/index.headers"
cmp -s "$TEMP_ROOT/root.body" "$TEMP_ROOT/index.body" \
    || fail "root base path does not serve exact index.html"
[ -z "$(header_value location "$TEMP_ROOT/root.headers")" ] \
    || fail "root base path redirected"
ROOT_CACHE="$(header_value cache-control "$TEMP_ROOT/root.headers")"
INDEX_CACHE="$(header_value cache-control "$TEMP_ROOT/index.headers")"
if [ "$ROOT_CACHE" != "no-cache" ] || [ "$INDEX_CACHE" != "no-cache" ]; then
    fail "root/index cache policy is '$ROOT_CACHE'/'$INDEX_CACHE', expected no-cache"
fi

fetch "/callack-build-manifest.json" \
    "$TEMP_ROOT/manifest.body" "$TEMP_ROOT/manifest.headers"
MANIFEST_CACHE="$(header_value cache-control "$TEMP_ROOT/manifest.headers")"
[ "$MANIFEST_CACHE" = "no-cache" ] \
    || fail "manifest cache policy is '$MANIFEST_CACHE', expected no-cache"

fetch "/callack-toolchain-identity.json" \
    "$TEMP_ROOT/toolchain.body" "$TEMP_ROOT/toolchain.headers"
TOOLCHAIN_CACHE="$(header_value cache-control "$TEMP_ROOT/toolchain.headers")"
[ "$TOOLCHAIN_CACHE" = "no-cache" ] \
    || fail "toolchain identity cache policy is '$TOOLCHAIN_CACHE', expected no-cache"

fetch "/$HASHED_ASSET" "$TEMP_ROOT/hashed.body" "$TEMP_ROOT/hashed.headers"
HASHED_CACHE="$(header_value cache-control "$TEMP_ROOT/hashed.headers")"
[ "$HASHED_CACHE" = "public, max-age=31536000, immutable" ] \
    || fail "$HASHED_ASSET cache policy is '$HASHED_CACHE'"

fetch "/$UNHASHED_ASSET" "$TEMP_ROOT/unhashed.body" "$TEMP_ROOT/unhashed.headers"
UNHASHED_CACHE="$(header_value cache-control "$TEMP_ROOT/unhashed.headers")"
case "$UNHASHED_CACHE" in
    *immutable*|*max-age=31536000*)
        fail "$UNHASHED_ASSET unexpectedly has immutable one-year caching"
        ;;
esac

WASM_ASSET="$(printf '%s\n' "${ARTIFACTS[@]}" | awk '/\.wasm$/ { print; exit }')"
DATA_ASSET="$(printf '%s\n' "${ARTIFACTS[@]}" | awk '/\.data$/ { print; exit }')"
fetch "/$WASM_ASSET" "$TEMP_ROOT/wasm.body" "$TEMP_ROOT/wasm.headers"
fetch "/$DATA_ASSET" "$TEMP_ROOT/data.body" "$TEMP_ROOT/data.headers"
[ "$(header_value content-type "$TEMP_ROOT/wasm.headers")" = "application/wasm" ] \
    || fail "WASM MIME type is incorrect"
[ "$(header_value content-type "$TEMP_ROOT/data.headers")" = "application/octet-stream" ] \
    || fail "data MIME type is incorrect"

for rejected_path in \
    "/paddle/" \
    "/dist/paddle-web/index.html" \
    "/dist/web/index.html" \
    "/game.js"; do
    safe_name="$(printf '%s' "$rejected_path" | tr '/.' '__')"
    fetch "$rejected_path" "$TEMP_ROOT/$safe_name.body" "$TEMP_ROOT/$safe_name.headers" 404
done

if [ "$VERIFY_BROWSER" = "1" ]; then
    [ -d "$ROOT/node_modules/playwright" ] \
        || fail "Playwright is not installed; run npm ci before the browser container gate"
    echo "[paddle-release-container] exercising genuine phone touch and desktop keyboard journeys"
    CALLACK_DEPLOYED_URL="$BASE_URL/" \
        PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$ROOT/.playwright-browsers}" \
        node "$ROOT/scripts/verify-deployed-spike.mjs"
fi

RUNNING="$(container inspect --format '{{.State.Running}}' "$CONTAINER_NAME")"
[ "$RUNNING" = "true" ] || fail "container stopped during verification"
MANIFEST_SHA256="$(sha256sum "$WEB_ROOT/callack-build-manifest.json" | awk '{print $1}')"
EVIDENCE_SHA256="not-run"
if [ "$VERIFY_BROWSER" = "1" ]; then
    EVIDENCE_SHA256="$(sha256sum "$ROOT/dist/deployed-verification/evidence.json" | awk '{print $1}')"
fi

echo "[paddle-release-container] OK: engine=$ENGINE image=$IMAGE_ID container=${CONTAINER_ID:0:12}"
echo "[paddle-release-container] OK: ${#ARTIFACTS[@]} exact paddle files in image and over HTTP"
echo "[paddle-release-container] OK: root-only base path; shell/manifest=no-cache; hashed=immutable"
echo "[paddle-release-container] OK: manifest=$MANIFEST_SHA256 browserEvidence=$EVIDENCE_SHA256"
