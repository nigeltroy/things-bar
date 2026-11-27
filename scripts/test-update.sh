#!/bin/zsh
# End-to-end test of the in-app update (Sparkle): an old ThingsBar finds a newer one in a
# local appcast, downloads it, checks its EdDSA signature, quits, is replaced and reopens.
#
#   scripts/test-update.sh            expects the update to install
#   TAMPER=1 scripts/test-update.sh   changes the DMG after signing: expects no install
#
# Both copies get their own bundle ID, no URL scheme and a memory-only token store, so your
# installed ThingsBar, its settings, its Keychain token and Things are untouched. Needs the Sparkle signing
# key: SPARKLE_KEY_FILE, or the "things-bar" key in your login Keychain.
set -euo pipefail
cd "${0:A:h}/.."

TEST_ID="local.thingsbar.ThingsBar.updatetest"
WORK="$(mktemp -d)"
KEY="$WORK/key"
PORT=$(( 20000 + RANDOM % 20000 ))
FEED="http://127.0.0.1:$PORT"
SERVER=""
cleanup() {
  [[ -n "$SERVER" ]] && kill "$SERVER" 2>/dev/null || true
  pkill -f "$WORK/install/ThingsBar.app/Contents/MacOS/ThingsBar" 2>/dev/null || true
  rm -f "$KEY"
  [[ -n "${KEEP:-}" ]] && { echo "kept $WORK"; return; }
  defaults delete "$TEST_ID" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/install" "$WORK/feed"

BIN=.build/artifacts/sparkle/Sparkle/bin
if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then cp "$SPARKLE_KEY_FILE" "$KEY"
else (umask 077; "$BIN/generate_keys" --account things-bar -x "$KEY" >/dev/null); fi

# Builds a copy at $3 with version $1 (build number $2) and the test identity.
make_copy() {
  VERSION="$1" BUILD="$2" ./scripts/build-app.sh >/dev/null
  local plist=build/ThingsBar.app/Contents/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $TEST_ID" -c "Delete :CFBundleURLTypes" \
    -c "Add :LSEnvironment dict" -c "Add :LSEnvironment:THINGSBAR_UPDATE_TEST string 1" \
    -c "Add :LSEnvironment:THINGSBAR_FEED_URL string $FEED/appcast.xml" \
    -c "Add :SUAllowsAutomaticUpdates bool true" \
    -c "Add :NSAppTransportSecurity dict" -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$plist"
  codesign --force --deep --sign - build/ThingsBar.app 2>/dev/null
  rm -rf "$3"; ditto build/ThingsBar.app "$3"
}

make_copy 9.0.0 900 "$WORK/new.app"
rm -rf build/ThingsBar.app; ditto "$WORK/new.app" build/ThingsBar.app
./scripts/make-dmg.sh "$WORK/feed/ThingsBar-9.0.0.dmg" >/dev/null
"$BIN/generate_appcast" --ed-key-file "$KEY" --download-url-prefix "$FEED/" \
  -o "$WORK/feed/appcast.xml" "$WORK/feed" >/dev/null
grep -q 'sparkle:edSignature' "$WORK/feed/appcast.xml"
if [[ -n "${TAMPER:-}" ]]; then
  # Same size (the appcast's length still matches), one byte different: only the signature catches it.
  python3 -I - "$WORK/feed/ThingsBar-9.0.0.dmg" <<'PY'
import sys
with open(sys.argv[1], "r+b") as f:
    f.seek(4096); b = f.read(1); f.seek(4096); f.write(bytes([b[0] ^ 0xFF]))
PY
fi

make_copy 0.0.1 1 "$WORK/install/ThingsBar.app"
OLD="$WORK/install/ThingsBar.app"
echo "Installed $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD/Contents/Info.plist"); feed offers 9.0.0"

# Sparkle only downloads over http(s): serve the feed locally.
python3 -I -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/feed" >/dev/null 2>&1 &
SERVER=$!
for _ in {1..20}; do curl -fsS "$FEED/appcast.xml" >/dev/null 2>&1 && break; sleep 0.25; done

# LSEnvironment (above) makes it a test run: a memory token store, so no Keychain prompt.
open -n "$OLD"

if [[ -n "${TAMPER:-}" ]]; then
  sleep 30
  v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD/Contents/Info.plist")
  [[ "$v" == "0.0.1" ]] && echo "PASS: tampered update rejected, still 0.0.1" && exit 0
  echo "FAIL: tampered update installed ($v)" >&2; exit 1
fi

for _ in {1..90}; do
  sleep 1
  v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$v" == "9.0.0" ]]; then
    for _ in {1..20}; do pgrep -f "$OLD/Contents/MacOS/ThingsBar" >/dev/null && break; sleep 0.5; done
    codesign --verify --strict --deep "$OLD"
    pgrep -f "$OLD/Contents/MacOS/ThingsBar" >/dev/null \
      && echo "PASS: replaced with 9.0.0 and relaunched" && exit 0
    echo "FAIL: replaced with 9.0.0 but not relaunched" >&2; exit 1
  fi
done
echo "FAIL: not updated after 90 s" >&2
exit 1
