#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build/tests"
mkdir -p "$BUILD_DIR"
if [[ -n "${SDKROOT:-}" ]]; then
  SDK_PATH="$(xcrun --sdk "$SDKROOT" --show-sdk-path)"
elif SDK_PATH="$(xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null)"; then
  :
else
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi
xcrun clang -O2 -Wall -Wextra -target arm64-apple-macosx14.0 -isysroot "$SDK_PATH" \
  -c "$PROJECT_DIR/Sources/CMemory.c" -o "$BUILD_DIR/CMemory.o"
xcrun swiftc -O -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  -import-objc-header "$PROJECT_DIR/Sources/CMemory.h" \
  "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/MemoryCollector.swift" \
  "$PROJECT_DIR/Tests/CollectorTests.swift" "$BUILD_DIR/CMemory.o" \
  -o "$BUILD_DIR/collector-tests"
xcrun swiftc -O -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  -import-objc-header "$PROJECT_DIR/Sources/CMemory.h" \
  "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/ProcessTerminator.swift" \
  "$PROJECT_DIR/Tests/TerminatorTests.swift" "$BUILD_DIR/CMemory.o" \
  -o "$BUILD_DIR/terminator-tests"
xcrun swiftc -O -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  "$PROJECT_DIR/Sources/LoginItemManager.swift" "$PROJECT_DIR/Tests/LoginItemTests.swift" \
  -framework ServiceManagement -o "$BUILD_DIR/login-item-tests"
UI_SOURCES=()
for SOURCE_FILE in "$PROJECT_DIR"/Sources/*.swift; do
  if [[ "${SOURCE_FILE:t}" != MemoryPanelApp.swift ]]; then
    UI_SOURCES+=("$SOURCE_FILE")
  fi
done
xcrun swiftc -O -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  -import-objc-header "$PROJECT_DIR/Sources/CMemory.h" \
  "${UI_SOURCES[@]}" "$PROJECT_DIR/Tests/MenuBarTests.swift" "$BUILD_DIR/CMemory.o" \
  -framework AppKit -framework SwiftUI -framework Charts -framework ServiceManagement \
  -o "$BUILD_DIR/menu-bar-tests"
"$BUILD_DIR/collector-tests"
"$BUILD_DIR/terminator-tests"
"$BUILD_DIR/login-item-tests"
"$BUILD_DIR/menu-bar-tests"
