#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 || ! -f "$1" ]]; then
    echo 'usage: bash tools/inspect_vulkan_capture.sh input.png output-directory' >&2
    exit 2
fi
inspection_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inspection_tmp="$(mktemp -d "${TMPDIR:-/tmp}/rosette-capture-inspection.XXXXXX")"
trap 'rm -rf "$inspection_tmp"' EXIT
xcrun clang -fobjc-arc -fno-modules -Wall -Wextra -Werror \
    -Wno-deprecated-declarations -Wno-incompatible-pointer-types-discards-qualifiers \
    "$inspection_repo/tools/inspect_vulkan_capture.m" \
    "$inspection_repo/lib/Mach-O/native_window_bridge.m" \
    "$inspection_repo/lib/Mach-O/native_window_toolbar.m" \
    "$inspection_repo/lib/Mach-O/input_controller_bridge.m" \
    -framework AppKit -framework AVFoundation -framework CoreGraphics -framework CoreMedia \
    -framework CoreVideo -framework Metal \
    -framework QuartzCore -framework GameController -framework ScreenCaptureKit \
    -framework UniformTypeIdentifiers \
    -o "$inspection_tmp/inspect-capture"
"$inspection_tmp/inspect-capture" "$1" "$2"
