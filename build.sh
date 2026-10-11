#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
BUILD_DIR="$PROJECT_DIR/.build"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
OUTPUT_DIR="${OUTPUT_DIR:A}"
APP_DIR="$OUTPUT_DIR/Memory Glass.app"
# Prefer the known-compatible SDK; fall back to the active Xcode/CLT SDK.
# SDKROOT may be either an SDK name or an absolute SDK directory.
if [[ -n "${SDKROOT:-}" ]]; then
  SDK_PATH="$(xcrun --sdk "$SDKROOT" --show-sdk-path)"
elif SDK_PATH="$(xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null)"; then
  :
else
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi
STAGING_DIR="$(mktemp -d "$BUILD_DIR/app.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/Memory Glass.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
xcrun clang -O2 -Wall -Wextra -target arm64-apple-macosx14.0 -isysroot "$SDK_PATH" \
  -c "$PROJECT_DIR/Sources/CMemory.c" -o "$BUILD_DIR/CMemory.o"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  -import-objc-header "$PROJECT_DIR/Sources/CMemory.h" \
  "$PROJECT_DIR"/Sources/*.swift "$BUILD_DIR/CMemory.o" \
  -framework AppKit -framework SwiftUI -framework Charts -framework ServiceManagement \
  -o "$STAGED_APP/Contents/MacOS/MemoryGlass"
cp "$PROJECT_DIR/Info.plist" "$STAGED_APP/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --sign - "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"
# Publish a complete bundle only after compilation and signature verification.
rm -rf -- "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"
echo "$APP_DIR"
