#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    echo "native readback capture: SKIP (requires AppKit codec)"
    exit 0
fi
capture_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture_tmp="$(mktemp -d "${TMPDIR:-/tmp}/rosette-readback-test.XXXXXX")"
trap 'rm -rf "$capture_tmp"' EXIT
xcrun clang -fobjc-arc -fno-modules -Wall -Wextra -Werror \
    -Wno-deprecated-declarations -Wno-incompatible-pointer-types-discards-qualifiers \
    "$capture_repo/tools/native_readback_capture_test.m" \
    "$capture_repo/lib/Mach-O/native_window_bridge.m" \
    "$capture_repo/lib/Mach-O/native_window_toolbar.m" \
    "$capture_repo/lib/Mach-O/input_controller_bridge.m" \
    -framework AppKit -framework AVFoundation -framework AudioToolbox -framework CoreGraphics -framework CoreMedia \
    -framework CoreVideo -framework Metal \
    -framework QuartzCore -framework GameController -framework ScreenCaptureKit \
    -framework UniformTypeIdentifiers \
    -o "$capture_tmp/capture-test"
"$capture_tmp/capture-test" "$capture_tmp/frames" "$@"
