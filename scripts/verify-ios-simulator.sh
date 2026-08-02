#!/usr/bin/env bash
# Build the current love.js output, sync it into the tracked Capacitor wrapper,
# then build, install, and launch an unsigned app on an available iOS Simulator.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAP_ROOT="$ROOT/capacitor"
APP_ROOT="$CAP_ROOT/ios/App"
EVIDENCE_ROOT="${CALLACK_IOS_EVIDENCE_DIR:-$ROOT/dist/ios-simulator-smoke}"
DERIVED_DATA="$EVIDENCE_ROOT/DerivedData"
BUILD_LOG="$EVIDENCE_ROOT/xcodebuild.log"
LAUNCH_LOG="$EVIDENCE_ROOT/app-launch.log"
SIMULATOR_LIST="$EVIDENCE_ROOT/simulators.json"
APP_SCREENSHOT="$EVIDENCE_ROOT/app-launched.png"
BOOTED_BY_SCRIPT=false

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[ios-smoke] ERROR: required command is unavailable: $1" >&2
        exit 1
    }
}

cleanup() {
    if [ "$BOOTED_BY_SCRIPT" = true ] && [ -n "${SIMULATOR_UDID:-}" ]; then
        xcrun simctl shutdown "$SIMULATOR_UDID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if [ "$(uname -s)" != "Darwin" ]; then
    echo "[ios-smoke] ERROR: the Simulator smoke path requires macOS" >&2
    exit 1
fi

for command_name in git node npm pod xcodebuild xcrun shasum; do
    require_command "$command_name"
done

rm -rf "$EVIDENCE_ROOT"
mkdir -p "$EVIDENCE_ROOT"

echo "[ios-smoke] building the current love.js output"
"$ROOT/scripts/build-web.sh" 2>&1 | tee "$EVIDENCE_ROOT/build-web.log"

echo "[ios-smoke] syncing the web output into Capacitor"
"$ROOT/scripts/build-ios.sh" 2>&1 | tee "$EVIDENCE_ROOT/capacitor-sync.log"

test -f "$APP_ROOT/App.xcworkspace/contents.xcworkspacedata"
test -f "$APP_ROOT/App/public/index.html"

SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
SOURCE_TREE="$(git -C "$ROOT" rev-parse 'HEAD^{tree}')"
EXPECTED_BUNDLE_ID="$(node -p "require('$CAP_ROOT/capacitor.config.json').appId")"
XCODE_VERSION="$(xcodebuild -version | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
SIMULATOR_SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
SIMULATOR_SDK_BUILD="$(xcrun --sdk iphonesimulator --show-sdk-build-version)"

echo "[ios-smoke] building unsigned app with $XCODE_VERSION (Simulator SDK $SIMULATOR_SDK_VERSION)"
set -o pipefail
xcodebuild \
    -workspace "$APP_ROOT/App.xcworkspace" \
    -scheme App \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    build 2>&1 | tee "$BUILD_LOG"

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/App.app"
INFO_PLIST="$APP_PATH/Info.plist"
test -d "$APP_PATH"
test -f "$INFO_PLIST"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
APP_BINARY="$APP_PATH/$EXECUTABLE_NAME"
test -x "$APP_BINARY"

if [ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
    echo "[ios-smoke] ERROR: built bundle id $BUNDLE_ID does not match Capacitor appId $EXPECTED_BUNDLE_ID" >&2
    exit 1
fi

xcrun simctl list devices available --json > "$SIMULATOR_LIST"
if [ -n "${CALLACK_SIMULATOR_UDID:-}" ]; then
    SIMULATOR_RECORD="$(node -e '
      const fs = require("fs");
      const wanted = process.argv[2];
      const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      for (const [runtime, devices] of Object.entries(data.devices)) {
        const device = devices.find((entry) => entry.udid === wanted && entry.isAvailable);
        if (device) {
          process.stdout.write([runtime, device.name, device.udid, device.state].join("\t"));
          process.exit(0);
        }
      }
      process.exit(1);
    ' "$SIMULATOR_LIST" "$CALLACK_SIMULATOR_UDID")"
else
    SIMULATOR_RECORD="$(node -e '
      const fs = require("fs");
      const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const candidates = [];
      for (const [runtime, devices] of Object.entries(data.devices)) {
        for (const device of devices) {
          if (device.isAvailable && device.name.startsWith("iPhone")) {
            candidates.push({ runtime, ...device });
          }
        }
      }
      candidates.sort((left, right) =>
        right.runtime.localeCompare(left.runtime, undefined, { numeric: true })
          || left.name.localeCompare(right.name)
          || left.udid.localeCompare(right.udid));
      if (!candidates.length) process.exit(1);
      const selected = candidates[0];
      process.stdout.write([
        selected.runtime, selected.name, selected.udid, selected.state,
      ].join("\t"));
    ' "$SIMULATOR_LIST")"
fi

IFS=$'\t' read -r SIMULATOR_RUNTIME SIMULATOR_NAME SIMULATOR_UDID SIMULATOR_STATE <<< "$SIMULATOR_RECORD"
if [ -z "$SIMULATOR_UDID" ]; then
    echo "[ios-smoke] ERROR: no available iPhone Simulator was found" >&2
    exit 1
fi

echo "[ios-smoke] selected $SIMULATOR_NAME ($SIMULATOR_RUNTIME, $SIMULATOR_UDID)"
if [ "$SIMULATOR_STATE" = "Booted" ]; then
    xcrun simctl shutdown "$SIMULATOR_UDID"
fi
xcrun simctl erase "$SIMULATOR_UDID"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
BOOTED_BY_SCRIPT=true

echo "[ios-smoke] installing $APP_PATH"
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
INSTALLED_APP_PATH="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" app)"
test -d "$INSTALLED_APP_PATH"

echo "[ios-smoke] launching $BUNDLE_ID"
LAUNCH_OUTPUT="$(xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" "$BUNDLE_ID")"
printf '%s\n' "$LAUNCH_OUTPUT" | tee "$EVIDENCE_ROOT/simctl-launch.txt"
APP_PID="$(printf '%s\n' "$LAUNCH_OUTPUT" | awk -F ': ' -v bundle="$BUNDLE_ID" '$1 == bundle { print $2 }')"
case "$APP_PID" in
    ''|*[!0-9]*)
        echo "[ios-smoke] ERROR: simctl did not return an app process id: $LAUNCH_OUTPUT" >&2
        exit 1
        ;;
esac

sleep 10
xcrun simctl io "$SIMULATOR_UDID" screenshot "$APP_SCREENSHOT"
test -s "$APP_SCREENSHOT"
xcrun simctl spawn "$SIMULATOR_UDID" log show \
    --last 5m \
    --style compact \
    --predicate 'eventMessage CONTAINS "CALLACK_IOS_SMOKE app-did-launch"' \
    2>&1 | tee "$LAUNCH_LOG"

LAUNCH_MARKER="CALLACK_IOS_SMOKE app-did-launch bundle=$BUNDLE_ID"
grep -Fq "$LAUNCH_MARKER" "$LAUNCH_LOG" || {
    echo "[ios-smoke] ERROR: launched process $APP_PID did not emit $LAUNCH_MARKER" >&2
    exit 1
}

(cd "$ROOT/dist/web" && find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
done) > "$EVIDENCE_ROOT/web-assets.sha256"

APP_BINARY_SHA256="$(shasum -a 256 "$APP_BINARY" | awk '{print $1}')"
SCREENSHOT_SHA256="$(shasum -a 256 "$APP_SCREENSHOT" | awk '{print $1}')"
cat > "$EVIDENCE_ROOT/evidence.txt" <<EOF
schema=callack-ios-simulator-smoke-v1
source_commit=$SOURCE_COMMIT
source_tree=$SOURCE_TREE
xcode=$XCODE_VERSION
simulator_sdk_version=$SIMULATOR_SDK_VERSION
simulator_sdk_build=$SIMULATOR_SDK_BUILD
simulator_name=$SIMULATOR_NAME
simulator_runtime=$SIMULATOR_RUNTIME
simulator_udid=$SIMULATOR_UDID
app_path=$APP_PATH
installed_app_path=$INSTALLED_APP_PATH
bundle_id=$BUNDLE_ID
app_version=$APP_VERSION
app_build=$APP_BUILD
app_executable=$EXECUTABLE_NAME
app_binary_sha256=$APP_BINARY_SHA256
launch_pid=$APP_PID
launch_marker=$LAUNCH_MARKER
screenshot_sha256=$SCREENSHOT_SHA256
signing_allowed=NO
EOF

cat "$EVIDENCE_ROOT/evidence.txt"
echo "[ios-smoke] OK: unsigned $BUNDLE_ID launched as pid $APP_PID on $SIMULATOR_NAME"
