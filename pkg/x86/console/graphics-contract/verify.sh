#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")" && pwd)"
zig_bin=zig
tmp_dir="$(mktemp -d "/tmp/xenia-x86-graphics-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "xenia-x86-graphics-contract: native tests"
"$zig_bin" test --cache-dir "$tmp_dir/native-cache" --global-cache-dir "$tmp_dir/global-cache" "$package_dir/src/root.zig"

echo "xenia-x86-graphics-contract: x86_64 compile-only check"
output="$tmp_dir/x86_64-freestanding.a"
"$zig_bin" build-lib "$package_dir/src/root.zig" --cache-dir "$tmp_dir/target-cache" --global-cache-dir "$tmp_dir/target-global-cache" -target x86_64-freestanding -O Debug -femit-bin="$output" >/dev/null
test -s "$output"

echo "xenia-x86-graphics-contract: PASS"
