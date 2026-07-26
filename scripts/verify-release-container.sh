#!/usr/bin/env bash
# Build and exercise the production Fly image against the packaged web bundle.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_ROOT="$ROOT/dist/web"
DOCKERFILE="$ROOT/deploy/fly/Dockerfile"
ENGINE="${CALLACK_CONTAINER_ENGINE:-}"
RUN_ID="$$-$RANDOM"
CONTAINER_NAME="callack-release-smoke-$RUN_ID"
IMAGE_TAG="localhost/callack-release-smoke:$RUN_ID"
TEMP_ROOT=""

fail() {
    echo "[release-container] FAIL: $*" >&2
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
            echo "[release-container] FAIL: cleanup left container $CONTAINER_NAME behind" >&2
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

for dependency in curl cmp find sort awk; do
    command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

[ -f "$DOCKERFILE" ] || fail "missing $DOCKERFILE"
[ -f "$WEB_ROOT/index.html" ] \
    || fail "missing dist/web/index.html; run ./scripts/build-web.sh first"

mapfile -t ARTIFACTS < <(
    cd "$WEB_ROOT"
    find . -type f -print | LC_ALL=C sort | sed 's|^\./||'
)
[ "${#ARTIFACTS[@]}" -gt 0 ] || fail "dist/web contains no files"

HASHED_ASSET=""
UNHASHED_ASSET=""
for relative_path in "${ARTIFACTS[@]}"; do
    if [[ "$relative_path" =~ \.[0-9a-f]{16}\.(wasm|js|data)$ ]]; then
        if [ -z "$HASHED_ASSET" ]; then
            HASHED_ASSET="$relative_path"
        fi
    elif [ "$relative_path" != "index.html" ] && [ -z "$UNHASHED_ASSET" ]; then
        UNHASHED_ASSET="$relative_path"
    fi
done
[ -n "$HASHED_ASSET" ] || fail "dist/web contains no 16-hex runtime asset"
[ -n "$UNHASHED_ASSET" ] || fail "dist/web contains no unversioned asset"

echo "[release-container] building $IMAGE_TAG with $ENGINE"
container build --file "$DOCKERFILE" --tag "$IMAGE_TAG" "$ROOT"
IMAGE_ID="$(container image inspect --format '{{.Id}}' "$IMAGE_TAG")"

TEMP_ROOT="$(mktemp -d "$ROOT/dist/.release-container.XXXXXX")"
LIVE_ROOT="$TEMP_ROOT/live"
mkdir -p "$LIVE_ROOT"

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
    READINESS_STATUS=""
    if READINESS_STATUS="$(curl \
        --connect-timeout 1 \
        --max-time 1 \
        --output /dev/null \
        --silent \
        --write-out '%{http_code}' \
        "$BASE_URL/index.html")" && [ "$READINESS_STATUS" = "200" ]; then
        READY=1
        break
    fi

    RUNNING=""
    if ! RUNNING="$(container inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)"; then
        RUNNING="false"
    fi
    if [ "$RUNNING" != "true" ]; then
        container logs "$CONTAINER_NAME" >&2
        fail "container exited before HTTP readiness"
    fi
    sleep 0.25
done
if [ "$READY" -ne 1 ]; then
    container logs "$CONTAINER_NAME" >&2
    fail "container did not return HTTP 200 within the readiness deadline"
fi

fetch() {
    local relative_path="$1"
    local body_path="$2"
    local headers_path="$3"
    local status

    status="$(curl \
        --connect-timeout 2 \
        --dump-header "$headers_path" \
        --max-time 10 \
        --output "$body_path" \
        --silent \
        --show-error \
        --write-out '%{http_code}' \
        "$BASE_URL/$relative_path")" \
        || fail "request failed for /$relative_path"
    [ "$status" = "200" ] || fail "/$relative_path returned HTTP $status"
}

cache_control() {
    awk '
        tolower($1) == "cache-control:" {
            $1 = ""
            sub(/^[[:space:]]+/, "")
            sub(/\r$/, "")
            print
            exit
        }
    ' "$1"
}

for relative_path in "${ARTIFACTS[@]}"; do
    live_path="$LIVE_ROOT/$relative_path"
    headers_path="$TEMP_ROOT/artifact.headers"
    mkdir -p "$(dirname "$live_path")"
    fetch "$relative_path" "$live_path" "$headers_path"
    cmp -s "$WEB_ROOT/$relative_path" "$live_path" \
        || fail "served bytes differ for /$relative_path"
done

fetch "index.html" "$TEMP_ROOT/index.body" "$TEMP_ROOT/index.headers"
INDEX_CACHE="$(cache_control "$TEMP_ROOT/index.headers")"
[ "$INDEX_CACHE" = "no-cache" ] \
    || fail "/index.html Cache-Control is '$INDEX_CACHE', expected 'no-cache'"

fetch "$HASHED_ASSET" "$TEMP_ROOT/hashed.body" "$TEMP_ROOT/hashed.headers"
HASHED_CACHE="$(cache_control "$TEMP_ROOT/hashed.headers")"
[ "$HASHED_CACHE" = "public, max-age=31536000, immutable" ] \
    || fail "/$HASHED_ASSET Cache-Control is '$HASHED_CACHE'"

fetch "$UNHASHED_ASSET" "$TEMP_ROOT/unhashed.body" "$TEMP_ROOT/unhashed.headers"
UNHASHED_CACHE="$(cache_control "$TEMP_ROOT/unhashed.headers")"
case "$UNHASHED_CACHE" in
    *immutable*|*max-age=31536000*)
        fail "/$UNHASHED_ASSET unexpectedly has immutable one-year caching"
        ;;
esac

RUNNING="$(container inspect --format '{{.State.Running}}' "$CONTAINER_NAME")"
[ "$RUNNING" = "true" ] || fail "container stopped during artifact verification"

echo "[release-container] OK: engine=$ENGINE image=$IMAGE_ID container=${CONTAINER_ID:0:12} port=$HOST_PORT"
echo "[release-container] OK: ${#ARTIFACTS[@]} live artifacts match dist/web"
echo "[release-container] OK: index=no-cache hashed=$HASHED_ASSET immutable unversioned=$UNHASHED_ASSET not-immutable"
