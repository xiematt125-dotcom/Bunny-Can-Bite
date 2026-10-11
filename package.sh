#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
mkdir -p "$OUTPUT_DIR" "$PROJECT_DIR/.build"
OUTPUT_DIR="${OUTPUT_DIR:A}"
if [[ $# -ge 2 ]]; then
  APP_DIR="${2:A}"
else
  "$PROJECT_DIR/build.sh" "$OUTPUT_DIR"
  APP_DIR="$OUTPUT_DIR/Memory Glass.app"
fi
PLIST="$APP_DIR/Contents/Info.plist"
if [[ ! -f "$PLIST" || ! -x "$APP_DIR/Contents/MacOS/MemoryGlass" ]]; then
  print -u2 -- "Expected a complete Memory Glass.app bundle: $APP_DIR"
  exit 1
fi
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [[ "$IDENTIFIER" != "local.memoryglass.monitor" || ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 -- 'Unexpected bundle identifier or version.'
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/.build/package.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
mkdir -p "$STAGING_DIR/root" "$STAGING_DIR/dmg"
/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/root/Memory Glass.app"
/usr/bin/pkgbuild --analyze --root "$STAGING_DIR/root" "$STAGING_DIR/components.plist"
# Always install/upgrade in /Applications, never relocate to a development copy.
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$STAGING_DIR/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsVersionChecked true' "$STAGING_DIR/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleHasStrictIdentifier true' "$STAGING_DIR/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleOverwriteAction upgrade' "$STAGING_DIR/components.plist"
PACKAGE_PATH="$OUTPUT_DIR/MemoryGlass-$VERSION-arm64.pkg"
/usr/bin/pkgbuild --root "$STAGING_DIR/root" \
  --component-plist "$STAGING_DIR/components.plist" \
  --identifier "$IDENTIFIER.pkg" --version "$VERSION" \
  --install-location /Applications --ownership recommended \
  "$STAGING_DIR/MemoryGlass.pkg"
mv -f "$STAGING_DIR/MemoryGlass.pkg" "$PACKAGE_PATH"
/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/dmg/Memory Glass.app"
ln -s /Applications "$STAGING_DIR/dmg/Applications"
cp "$PROJECT_DIR/docs/安装说明.txt" "$STAGING_DIR/dmg/安装说明.txt"
DMG_PATH="$OUTPUT_DIR/MemoryGlass-$VERSION-arm64.dmg"
/usr/bin/hdiutil create -ov -quiet -format UDZO \
  -volname "Memory Glass $VERSION" -srcfolder "$STAGING_DIR/dmg" \
  "$STAGING_DIR/MemoryGlass.dmg"
mv -f "$STAGING_DIR/MemoryGlass.dmg" "$DMG_PATH"
/usr/bin/hdiutil verify -quiet "$DMG_PATH"
print -- "$PACKAGE_PATH"
print -- "$DMG_PATH"
