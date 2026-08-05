#!/usr/bin/env bash
# build-ios.sh — wrap the love.js web bundle in a Capacitor iOS project.
#
# Steps performed locally (Linux-safe):
#   1. Rebuild the candidate-owned paddle target into dist/paddle-web/.
#   2. Copy dist/paddle-web/ → capacitor/dist/ (Capacitor's webDir).
#   3. Install the lockfile-pinned npm deps under capacitor/.
#   4. Re-seed capacitor/ios/ from the tracked template so stale generated files
#      cannot influence a build.
#   5. Run `npx cap sync ios` — copies web assets into ios/App/App/public/.
#
# After this script:
#   - capacitor/dist/        : web bundle Capacitor will ship
#   - capacitor/ios/         : Xcode project (App.xcworkspace, App.xcodeproj, fastlane/, Podfile)
#   - The unsigned smoke workflow builds and launches this project in Simulator.
#   - The separately gated signed job can still build an .ipa via Fastlane Match.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_OUT="$ROOT/dist/paddle-web"
CAP="$ROOT/capacitor"

# 1. Always regenerate the trusted paddle package. A stale or caller-selected
# bundle must never enter the native wrapper.
echo "[ios] rebuilding candidate-owned paddle web target"
"$ROOT/scripts/build-paddle-web.sh"

# 2. Mirror web bundle into capacitor/dist (Capacitor webDir).
mkdir -p "$CAP/dist"
rm -rf "$CAP/dist"/*
cp -r "$WEB_OUT/." "$CAP/dist/"
node "$ROOT/scripts/verify-paddle-package.mjs" "$CAP/dist"
echo "[ios] copied candidate paddle bundle to $CAP/dist"

# 3. Install the exact Capacitor dependency graph.
pushd "$CAP" >/dev/null
npm ci --no-audit --no-fund --silent
popd >/dev/null

# 4. Re-seed the generated project from the tracked source of truth.
if [ ! -d "$CAP/ios-template" ]; then
    echo "[ios] ERROR: tracked iOS template is missing: $CAP/ios-template" >&2
    exit 1
fi
rm -rf "$CAP/ios"
cp -R "$CAP/ios-template" "$CAP/ios"
echo "[ios] seeded $CAP/ios from ios-template/"

# 5. cap sync — copies web assets into ios/App/App/public.
pushd "$CAP" >/dev/null
npx cap sync ios
popd >/dev/null

test -f "$CAP/ios/App/App/public/index.html"
node "$ROOT/scripts/verify-paddle-package.mjs" "$CAP/ios/App/App/public" --allow-extra-files
echo "[ios] OK. Synced Capacitor project at $CAP/ios/App."
