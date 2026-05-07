#!/usr/bin/env bash
# build-ios.sh — wrap the love.js web bundle in a Capacitor iOS project.
#
# Steps performed locally (Linux-safe):
#   1. Run build-web.sh to produce dist/web/.
#   2. Copy dist/web/ → capacitor/dist/ (Capacitor's webDir).
#   3. Install npm deps under capacitor/.
#   4. If capacitor/ios/ does not exist, copy the iOS template from capacitor/ios-template/.
#      (Generating the iOS native project from scratch requires CocoaPods + macOS;
#       the GHA macos-latest job re-runs `npx cap add ios` cleanly. Locally we mirror
#       the capacitor-asteroids reference iOS scaffold.)
#   5. Run `npx cap sync ios` — copies web assets into ios/App/App/public/.
#
# After this script:
#   - capacitor/dist/        : web bundle Capacitor will ship
#   - capacitor/ios/         : Xcode project (App.xcworkspace, App.xcodeproj, fastlane/, Podfile)
#   - GHA pipeline (.github/workflows/build.yml) does the .ipa build via Fastlane Match.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_OUT="$ROOT/dist/web"
CAP="$ROOT/capacitor"

# 1. Ensure web bundle exists.
if [ ! -f "$WEB_OUT/index.html" ]; then
    echo "[ios] running build-web.sh first..."
    "$ROOT/scripts/build-web.sh"
fi

# 2. Mirror web bundle into capacitor/dist (Capacitor webDir).
mkdir -p "$CAP/dist"
rm -rf "$CAP/dist"/*
cp -r "$WEB_OUT/." "$CAP/dist/"
echo "[ios] copied web bundle to $CAP/dist"

# 3. Install Capacitor deps.
pushd "$CAP" >/dev/null
if [ ! -d node_modules ]; then
    npm install --no-audit --no-fund --silent
fi
popd >/dev/null

# 4. Copy iOS scaffold from template if not present.
if [ ! -d "$CAP/ios" ]; then
    if [ -d "$CAP/ios-template" ]; then
        cp -r "$CAP/ios-template" "$CAP/ios"
        echo "[ios] seeded $CAP/ios from ios-template/"
    else
        echo "[ios] WARN: no $CAP/ios and no ios-template. On macOS, run: cd capacitor && npx cap add ios"
    fi
fi

# 5. cap sync — copies web assets into ios/App/App/public.
pushd "$CAP" >/dev/null
if [ -d ios ]; then
    npx cap sync ios || {
        echo "[ios] cap sync ios failed (likely missing CocoaPods on Linux). Project files are still staged."
        echo "[ios] In the GHA macos-latest job this step succeeds automatically."
    }
else
    echo "[ios] no ios/ directory yet — skipping cap sync."
fi
popd >/dev/null

echo "[ios] OK. Capacitor project at $CAP — open with Xcode on macOS."
