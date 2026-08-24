#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xenia-x86-heap-range.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "xenia-x86-heap-range: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    "$package_dir/src/root.zig"

echo "xenia-x86-heap-range: x86_64 compile-only check"
output="$tmp_dir/x86_64-freestanding.a"
"$zig_bin" build-lib "$package_dir/src/root.zig" \
    --cache-dir "$tmp_dir/target-cache" \
    --global-cache-dir "$tmp_dir/target-global-cache" \
    -target x86_64-freestanding \
    -O Debug \
    -femit-bin="$output" \
    >/dev/null
test -s "$output"
echo "  verified x86_64-freestanding"
echo "xenia-x86-heap-range: PASS"
