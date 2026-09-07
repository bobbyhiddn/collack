#!/usr/bin/env bash
# Keep this launcher beside the bundled LÖVE runtime and game archive.
set -euo pipefail
LAUNCH_ROOT="$(cd "$(dirname "$0")" && pwd)"
# Extraction works on distributions without FUSE. The AppImage cleans up its
# own temporary runtime when the game exits.
export APPIMAGE_EXTRACT_AND_RUN=1
# Give extraction a private directory, avoiding stale shared-/tmp caches
# created by another account or an interrupted previous run.
COLLACK_RUNTIME_TMP="$(mktemp -d "${TMPDIR:-/tmp}/collack-runtime.XXXXXX")"
trap 'rm -rf -- "$COLLACK_RUNTIME_TMP"' EXIT
export TMPDIR="$COLLACK_RUNTIME_TMP"
"$LAUNCH_ROOT/love-11.5-x86_64.AppImage" "$LAUNCH_ROOT/collack-spike.love" "$@"
