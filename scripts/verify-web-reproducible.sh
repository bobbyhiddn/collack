#!/usr/bin/env bash
# Build two isolated source snapshots with deliberately different paths, mtimes,
# modes, timezones, and umasks, then compare every production web artifact.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LC_ALL=C

SOURCE_REVISION="$(git -C "$ROOT" rev-parse HEAD)"
SOURCE_TREE="$(git -C "$ROOT" rev-parse 'HEAD^{tree}')"

fail() {
    echo "[web-repro] FAIL: $*" >&2
    exit 1
}

mkdir -p "$ROOT/dist"
TEMP_ROOT="$(mktemp -d "$ROOT/dist/.web-repro.XXXXXX")"
cleanup() {
    if [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
}
trap cleanup EXIT

SOURCE_A="$TEMP_ROOT/source-a"
SOURCE_B="$TEMP_ROOT/source-b-with-a-different-path"
mkdir -p "$SOURCE_A" "$SOURCE_B"
[ "$SOURCE_A" != "$SOURCE_B" ] || fail "independent build roots unexpectedly match"

copy_tracked_tree() {
    local destination="$1"
    git -C "$ROOT" ls-files -z \
        | tar -C "$ROOT" --null -T - -cf - \
        | tar -C "$destination" -xf -
}

copy_tracked_tree "$SOURCE_A"
copy_tracked_tree "$SOURCE_B"

# A deterministic archive must ignore checkout mtime and mode differences.
find "$SOURCE_A/src" "$SOURCE_A/battle" -exec touch -t 200101010101.02 {} +
find "$SOURCE_B/src" "$SOURCE_B/battle" -exec touch -t 203012312359.58 {} +
find "$SOURCE_A/src" "$SOURCE_A/battle" -type f -exec chmod 0644 {} +
find "$SOURCE_B/src" "$SOURCE_B/battle" -type f -exec chmod 0600 {} +

if [ -x "$ROOT/.node_cache/node_modules/.bin/love.js" ]; then
    NODE_CACHE="$ROOT/.node_cache"
else
    NODE_CACHE="$TEMP_ROOT/node-cache"
fi

echo "[web-repro] build A: short path, old mtimes, mode 0644, restrictive umask"
(
    umask 077
    TZ=Pacific/Honolulu CALLACK_NODE_CACHE_DIR="$NODE_CACHE" \
        CALLACK_ALLOW_EXTERNAL_BUILD_IDENTITY=1 \
        CALLACK_BUILD_REVISION="$SOURCE_REVISION" \
        CALLACK_BUILD_TREE="$SOURCE_TREE" \
        bash "$SOURCE_A/scripts/build-web.sh"
)

echo "[web-repro] build B: different path, new mtimes, mode 0600, permissive umask"
(
    umask 002
    TZ=Etc/GMT-14 CALLACK_NODE_CACHE_DIR="$NODE_CACHE" \
        CALLACK_ALLOW_EXTERNAL_BUILD_IDENTITY=1 \
        CALLACK_BUILD_REVISION="$SOURCE_REVISION" \
        CALLACK_BUILD_TREE="$SOURCE_TREE" \
        bash "$SOURCE_B/scripts/build-web.sh"
)

NAMES_A="$TEMP_ROOT/names-a.txt"
NAMES_B="$TEMP_ROOT/names-b.txt"
HASHES_A="$TEMP_ROOT/hashes-a.txt"
HASHES_B="$TEMP_ROOT/hashes-b.txt"

create_manifest() {
    local source_root="$1"
    local names_path="$2"
    local hashes_path="$3"
    local web_root="$source_root/dist/web"
    local relative_path

    (
        cd "$web_root"
        find . -type f -print | sort | sed 's|^\./||'
    ) > "$names_path"

    : > "$hashes_path"
    printf '%s  %s\n' \
        "$(shasum -a 256 "$source_root/dist/collack-spike.love" | awk '{print $1}')" \
        "collack-spike.love" >> "$hashes_path"
    while IFS= read -r relative_path; do
        printf '%s  %s\n' \
            "$(shasum -a 256 "$web_root/$relative_path" | awk '{print $1}')" \
            "$relative_path" >> "$hashes_path"
    done < "$names_path"
}

create_manifest "$SOURCE_A" "$NAMES_A" "$HASHES_A"
create_manifest "$SOURCE_B" "$NAMES_B" "$HASHES_B"

DIFFERENT=0
if ! diff -u "$NAMES_A" "$NAMES_B"; then
    echo "[web-repro] generated asset filenames differ" >&2
    DIFFERENT=1
fi
if ! diff -u "$HASHES_A" "$HASHES_B"; then
    echo "[web-repro] generated artifact bytes differ" >&2
    DIFFERENT=1
fi
[ "$DIFFERENT" -eq 0 ] || fail "independent clean builds are not reproducible"

echo "[web-repro] build A hashes:"
sed 's/^/[web-repro]   /' "$HASHES_A"
echo "[web-repro] build B hashes:"
sed 's/^/[web-repro]   /' "$HASHES_B"
echo "[web-repro] OK: independent clean builds have identical filenames and bytes"
