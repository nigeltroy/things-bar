#!/bin/zsh
# Builds ThingsBar and wraps the SwiftPM executable in a .app bundle.
set -euo pipefail
cd "${0:A:h}/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ThingsBar"
APP="build/ThingsBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ThingsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc sign so macOS keeps a stable identity for the Automation (TCC) grant.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
