#!/bin/zsh
# Builds ThingsBar and wraps the SwiftPM executable in a .app bundle.
#
#   scripts/build-app.sh                 release build for this Mac's architecture
#   scripts/build-app.sh --universal     release build for Apple silicon + Intel
#   scripts/build-app.sh debug           debug build
#
# Optional environment:
#   VERSION=1.2.0   sets CFBundleShortVersionString (default: value in Info.plist)
#   BUILD=42        sets CFBundleVersion (default: value in Info.plist); Sparkle compares it
#   SIGN_IDENTITY="Developer ID Application: …"
#                   signs for distribution (hardened runtime, timestamp) instead of ad-hoc
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
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/ThingsBar"

APP="build/ThingsBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/ThingsBar"
# Sparkle (in-app updates); the binary looks for it via @executable_path/../Frameworks.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"

PLIST="$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
if [[ -n "${BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  # Ad-hoc: no Developer ID yet. macOS asks "Open Anyway" on first launch.
  codesign --force --deep --sign - "$APP" >/dev/null
else
  # Developer ID, inside out, the way Sparkle documents it. The hardened runtime needs the
  # Apple Events entitlement for reading and updating Things.
  SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
  "${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
  "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SPARKLE/Autoupdate"
  "${SIGN[@]}" "$SPARKLE/Updater.app"
  "${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
  "${SIGN[@]}" --entitlements Resources/ThingsBar.entitlements "$APP"
fi
codesign --verify --strict --deep "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/ThingsBar"), version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST"))"
