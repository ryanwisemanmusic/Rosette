#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xenia-arm64-wait-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "xenia-arm64-wait-contract: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    "$package_dir/src/root.zig"

echo "xenia-arm64-wait-contract: compile-only target matrix"
for target_name in x86_64-freestanding powerpc64-freestanding aarch64-freestanding; do
    output="$tmp_dir/${target_name}.a"
    "$zig_bin" build-lib "$package_dir/src/root.zig" \
        --cache-dir "$tmp_dir/${target_name}-cache" \
        --global-cache-dir "$tmp_dir/${target_name}-global-cache" \
        -target "$target_name" \
        -O Debug \
        -femit-bin="$output" \
        >/dev/null
    test -s "$output"
    echo "  verified $target_name"
done

echo "xenia-arm64-wait-contract: PASS"
