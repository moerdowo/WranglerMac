#!/usr/bin/env bash
# Build, ad-hoc sign, DMG, and Sparkle-sign a WranglerMac release, then print the
# appcast <item> to paste into appcast.xml. Requires the EdDSA private key in the
# login keychain (generated once via Sparkle's generate_keys).
#
# Usage: scripts/release.sh <version>   e.g. scripts/release.sh 1.2.0
set -euo pipefail
VERSION="${1:?usage: release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate >/dev/null
echo "==> Building Release $VERSION"
xcodebuild -project WranglerMac.xcodeproj -scheme WranglerMac -configuration Release \
  -derivedDataPath build-release build >/dev/null
APP="build-release/Build/Products/Release/WranglerMac.app"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify "$APP"

echo "==> Building DMG"
STAGE="$(mktemp -d)"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG="WranglerMac-${VERSION}.dmg"; rm -f "$DMG"
hdiutil create -volname "WranglerMac ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

SIGN="$(find build build-release -name sign_update -type f 2>/dev/null | head -1)"
echo "==> Sparkle signature:"
"$SIGN" "$DMG"
echo
echo "DMG: $DMG ($(stat -f%z "$DMG") bytes)"
echo "Now: add an <item> to appcast.xml with the edSignature/length above and the enclosure URL"
echo "     https://github.com/moerdowo/WranglerMac/releases/download/v${VERSION}/${DMG}"
echo "Then: gh release create v${VERSION} \"$DMG\" --repo moerdowo/WranglerMac --title \"WranglerMac ${VERSION}\""
