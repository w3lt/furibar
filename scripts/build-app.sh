#!/bin/zsh
# Builds build/Furibar.app (and build/Furibar.zip for copying to another Mac).
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
swift build -c "$CONFIG" --product Furibar
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Furibar"

APP=build/Furibar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Furibar"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run on your own Mac. The entitlements turn on the App Sandbox
# with Bluetooth and nothing else (no network).
codesign --force --sign - --options runtime --entitlements Support/Furibar.entitlements "$APP"

rm -f build/Furibar.zip
ditto -c -k --keepParent "$APP" build/Furibar.zip

echo "Built $PWD/$APP"
echo "Zipped $PWD/build/Furibar.zip"
