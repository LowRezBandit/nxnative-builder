#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_OUT="${APP_OUT:-$SCRIPT_DIR/dist/NXNative Builder.app}"

mkdir -p "$APP_OUT/Contents/MacOS" "$APP_OUT/Contents/Resources"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_OUT/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_OUT/Contents/Resources/AppIcon.icns"

SWIFT_FILES=()
while IFS= read -r -d '' file; do
  SWIFT_FILES+=("$file")
done < <(find "$SCRIPT_DIR/Sources" -name '*.swift' -print0 | sort -z)

swiftc -O -parse-as-library -framework SwiftUI -framework AppKit \
  "${SWIFT_FILES[@]}" \
  -o "$APP_OUT/Contents/MacOS/NXNativeBuilder"

touch "$APP_OUT"
echo "Built $APP_OUT"
