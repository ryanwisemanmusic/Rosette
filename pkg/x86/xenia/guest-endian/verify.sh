#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xenia-x86-guest-endian.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"$zig_bin" test "$package_dir/src/root.zig" \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache"
for target_name in x86_64-freestanding aarch64-freestanding powerpc64-freestanding; do
    output="$tmp_dir/${target_name}.a"
    "$zig_bin" build-lib "$package_dir/src/root.zig" \
        -target "$target_name" -O Debug \
        --cache-dir "$tmp_dir/${target_name}-cache" \
        --global-cache-dir "$tmp_dir/${target_name}-global-cache" \
        -femit-bin="$output" >/dev/null
    test -s "$output"
done
printf '%s\n' 'xenia-x86-guest-endian: PASS'
