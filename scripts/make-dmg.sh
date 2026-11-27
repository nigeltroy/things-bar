#!/bin/zsh
# Packages build/ThingsBar.app into a drag-to-install disk image.
#
#   scripts/make-dmg.sh [output.dmg]     default: build/ThingsBar.dmg
#
# Run scripts/build-app.sh first.
set -euo pipefail
cd "${0:A:h}/.."

APP="build/ThingsBar.app"
OUT="${1:-build/ThingsBar.dmg}"
[[ -d "$APP" ]] || { echo "missing $APP: run scripts/build-app.sh first" >&2; exit 1; }
codesign --verify --strict "$APP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ThingsBar.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "ThingsBar" -srcfolder "$STAGE" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null
echo "Built $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"
