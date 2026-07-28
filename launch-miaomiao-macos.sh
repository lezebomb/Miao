#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/runtime/macos/build-app.sh"
APP_PATH="$SCRIPT_DIR/runtime/macos/dist/Miaomiao.app"
FOLLOW_ARGUMENTS=()
FORCE_BUILD=false

for argument in "$@"; do
    case "$argument" in
        --follow-chatgpt|--follow-codex)
            FOLLOW_ARGUMENTS=(--args --follow-chatgpt)
            ;;
        --build)
            FORCE_BUILD=true
            ;;
        *)
            echo "Usage: ./launch-miaomiao-macos.sh [--follow-chatgpt] [--build]" >&2
            exit 2
            ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This launcher requires macOS." >&2
    exit 1
fi

if [[ "$FORCE_BUILD" == true || ! -x "$APP_PATH/Contents/MacOS/Miaomiao" ]]; then
    "$BUILD_SCRIPT"
fi

open "$APP_PATH" "${FOLLOW_ARGUMENTS[@]}"
