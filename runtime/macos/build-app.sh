#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
BUILD_ROOT="${MIAOMIAO_BUILD_ROOT:-$SCRIPT_DIR/.build-app}"
APP_PATH="${MIAOMIAO_APP_PATH:-$SCRIPT_DIR/dist/Miaomiao.app}"
PACKAGE_PATH="$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "build-app.sh must be run on macOS." >&2
    exit 1
fi

rm -rf -- "$BUILD_ROOT"
mkdir -p -- "$BUILD_ROOT" "$(dirname -- "$APP_PATH")"

ARCHITECTURES=(arm64 x86_64)
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
    scratch="$BUILD_ROOT/$architecture"
    swift build \
        --package-path "$PACKAGE_PATH" \
        --configuration release \
        --arch "$architecture" \
        --scratch-path "$scratch"
    bin_dir="$(swift build \
        --package-path "$PACKAGE_PATH" \
        --configuration release \
        --arch "$architecture" \
        --scratch-path "$scratch" \
        --show-bin-path)"
    BINARIES+=("$bin_dir/Miaomiao")
done

rm -rf -- "$APP_PATH"
mkdir -p -- \
    "$APP_PATH/Contents/MacOS" \
    "$APP_PATH/Contents/Resources/pet/miaomiao"

lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/Miaomiao"
chmod 755 "$APP_PATH/Contents/MacOS/Miaomiao"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$REPOSITORY_ROOT/miaomiao.config.json" "$APP_PATH/Contents/Resources/miaomiao.config.json"
cp "$REPOSITORY_ROOT/pet/miaomiao/behavior.json" \
    "$APP_PATH/Contents/Resources/pet/miaomiao/behavior.json"
ditto "$REPOSITORY_ROOT/pet/miaomiao/actions" \
    "$APP_PATH/Contents/Resources/pet/miaomiao/actions"

codesign --force --deep --sign - "$APP_PATH"
"$APP_PATH/Contents/MacOS/Miaomiao" --check-only
lipo -archs "$APP_PATH/Contents/MacOS/Miaomiao"
echo "Built $APP_PATH"
