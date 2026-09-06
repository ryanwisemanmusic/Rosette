#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-xenia-gpu-observation-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "common-xenia-gpu-observation-contract: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    "$package_dir/src/root.zig"

for target in aarch64-freestanding x86_64-freestanding; do
    echo "common-xenia-gpu-observation-contract: $target compile-only check"
    output="$tmp_dir/$target.a"
    "$zig_bin" build-lib "$package_dir/src/root.zig" \
        --cache-dir "$tmp_dir/$target-cache" \
        --global-cache-dir "$tmp_dir/$target-global-cache" \
        -target "$target" \
        -O Debug \
        -femit-bin="$output" \
        >/dev/null
    test -s "$output"
done

echo "common-xenia-gpu-observation-contract: PASS"
