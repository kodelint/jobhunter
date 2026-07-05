#!/usr/bin/env bash
# Builds JobHunter.app (universal), signs it, and packages a DMG.
# - No secrets  -> ad-hoc signature (opens via right-click on other Macs)
# - DEVELOPER_ID set -> Developer ID + hardened runtime (notarizable)
# - Notary creds set -> submits to Apple notary service and staples
set -euo pipefail

APP_NAME="JobHunter"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Sources"
APPRES="$ROOT/App"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/$APP_NAME.app"

# --- version from git tag (vX.Y.Z) or override via env ---
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUM="${BUILD_NUM:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
echo "==> Building $APP_NAME $VERSION (build $BUILD_NUM)"

rm -rf "$BUILD" "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

SDK="$(xcrun --show-sdk-path)"
echo "==> Compiling universal binary (arm64 + x86_64)"
swiftc -O -parse-as-library -target arm64-apple-macos14.0  -sdk "$SDK" "$SRC"/*.swift -o "$BUILD/jh-arm64"
swiftc -O -parse-as-library -target x86_64-apple-macos14.0 -sdk "$SDK" "$SRC"/*.swift -o "$BUILD/jh-x86_64"
lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "$BUILD/jh-arm64" "$BUILD/jh-x86_64"
rm -f "$BUILD/jh-arm64" "$BUILD/jh-x86_64"

echo "==> Assembling bundle"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUM/g" "$APPRES/Info.plist" > "$APP/Contents/Info.plist"
cp "$APPRES/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  # Notarizable: hardened runtime, secure timestamp, NO sandbox (app needs shell env + curl).
  # No --deep (deprecated by Apple): the bundle is a single binary + icon, so sign it directly.
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
  echo "    signed with Developer ID: $DEVELOPER_ID"
else
  codesign --force --sign - "$APP"
  echo "    ad-hoc signed (set DEVELOPER_ID to produce a notarizable build)"
fi

echo "==> Packaging DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$APP_NAME-v$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "    created $DMG"

# --- optional notarization ---
if [[ -n "${DEVELOPER_ID:-}" && ( -n "${NOTARY_PROFILE:-}" || -n "${AC_PASSWORD:-}" ) ]]; then
  echo "==> Notarizing (this can take a few minutes)"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$DMG" --apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_PASSWORD" --wait
  fi
  xcrun stapler staple "$DMG"
  echo "    notarized & stapled"
else
  echo "==> Skipping notarization (no notary credentials set)"
fi

echo "==> DONE: $DMG"
