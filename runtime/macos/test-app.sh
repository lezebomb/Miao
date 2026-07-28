#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
APP_PATH="${MIAOMIAO_APP_PATH:-$SCRIPT_DIR/dist/Miaomiao.app}"
EXECUTABLE="$APP_PATH/Contents/MacOS/Miaomiao"
TEST_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/miaomiao-macos-test.XXXXXX")"

cleanup() {
    if [[ -n "${FIRST_PID:-}" ]] && kill -0 "$FIRST_PID" 2>/dev/null; then
        kill "$FIRST_PID" 2>/dev/null || true
    fi
    rm -rf -- "$TEST_DIRECTORY"
}
trap cleanup EXIT

swift test --package-path "$SCRIPT_DIR"
"$SCRIPT_DIR/build-app.sh"
"$EXECUTABLE" --check-only

"$EXECUTABLE" --test-auto-exit-ms 3000 \
    >"$TEST_DIRECTORY/first.stdout" \
    2>"$TEST_DIRECTORY/first.stderr" &
FIRST_PID=$!
sleep 1
"$EXECUTABLE" --test-auto-exit-ms 1000 \
    >"$TEST_DIRECTORY/second.stdout" \
    2>"$TEST_DIRECTORY/second.stderr"
grep -q "already running" "$TEST_DIRECTORY/second.stderr"
wait "$FIRST_PID"
FIRST_PID=""

echo "macOS app smoke test passed: JSON, frames, playback window, scaling, exit, and single instance."
