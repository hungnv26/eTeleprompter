#!/bin/bash
# Build a distributable macOS .dmg for eTeleprompter.
#
# Usage:  ./tools-make-dmg.sh [output.dmg]
#
# Signing: if a "Developer ID Application" certificate is present it is used and
# the result is suitable for distribution once notarized (see NOTARIZING below).
# Otherwise the script falls back to the first "Apple Development" identity, or
# to the ad-hoc signature from the build. Development-signed apps run fine on
# the machine that built them but Gatekeeper will refuse them elsewhere until
# they are Developer ID signed AND notarized.
#
# NOTARIZING (needs a paid Apple Developer Program membership):
#   xcrun notarytool store-credentials NOTARY --apple-id <id> --team-id <team> --password <app-specific-pw>
#   xcrun notarytool submit <dmg> --keychain-profile NOTARY --wait
#   xcrun stapler staple <dmg>
set -euo pipefail

cd "$(dirname "$0")"
OUT="${1:-$HOME/Downloads/eTeleprompter-1.0.dmg}"
VOLNAME="eTeleprompter 1.0"
DD="$(mktemp -d)/dd"
STAGE="$(mktemp -d)/stage"
trap 'rm -rf "$(dirname "$DD")" "$(dirname "$STAGE")"' EXIT

echo "==> Building Release (universal)"
xcodebuild -project eTeleprompter.xcodeproj -scheme eTeleprompter \
  -destination 'platform=macOS' -configuration Release \
  -derivedDataPath "$DD" build CODE_SIGNING_ALLOWED=NO \
  | grep -E "BUILD (SUCCEEDED|FAILED)|error:" || true

APP="$DD/Build/Products/Release/eTeleprompter.app"
[ -d "$APP" ] || { echo "Build produced no app bundle" >&2; exit 1; }

echo "==> Signing"
IDENTITY="$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
fi
if [ -n "$IDENTITY" ]; then
  echo "    using: $IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "    no identity found — keeping the ad-hoc signature"
fi
codesign --verify --strict "$APP" && echo "    signature verified"

echo "==> Staging"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<'TXT'
eTeleprompter 1.0
=============

To install: drag eTeleprompter to the Applications folder in this window.

First launch
------------
If this build is not Developer ID signed and notarized, macOS Gatekeeper will
warn you the first time you open it. To proceed:

  Right-click (or Control-click) eTeleprompter in Applications, choose "Open",
  then confirm.

You only need to do this once. If macOS blocks it outright, open
System Settings > Privacy & Security, scroll down, and click "Open Anyway".

Requirements: macOS 14 or later. Universal (Apple Silicon and Intel).

Keyboard shortcuts while presenting
-----------------------------------
  Space   play / pause
  Up      faster
  Down    slower
  Esc     exit the prompter

Source: https://github.com/hungnv26/eTeleprompter
TXT

echo "==> Creating $OUT"
rm -f "$OUT"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO \
  -fs HFS+ "$OUT" | tail -1

echo "==> Done: $(du -h "$OUT" | cut -f1)  $OUT"
