#!/bin/zsh
# Builds ThingsBar and wraps the SwiftPM executable in a .app bundle.
#
#   scripts/build-app.sh                 release build for this Mac's architecture
#   scripts/build-app.sh --universal     release build for Apple silicon + Intel
#   scripts/build-app.sh debug           debug build
#
# Optional environment:
#   VERSION=1.2.0   sets CFBundleShortVersionString (default: value in Info.plist)
#   BUILD=42        sets CFBundleVersion (default: value in Info.plist)
set -euo pipefail
cd "${0:A:h}/.."

CONFIG="release"
ARCH_FLAGS=()
for arg in "$@"; do
  case "$arg" in
    --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    debug|release) CONFIG="$arg" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/ThingsBar"

APP="build/ThingsBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ThingsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

PLIST="$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
if [[ -n "${BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
fi

# Ad-hoc sign so macOS keeps a stable identity for the Automation (TCC) grant.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/ThingsBar"), version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST"))"
