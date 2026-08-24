#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xenia-x86-input-driver.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "xenia-x86-input-driver: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    "$package_dir/src/root.zig"

# Both routes compile the same file, so both are checked here rather than in a
# mirrored copy. A package that only ever built for the host it was written on
# is how a route split starts.
for target in aarch64-freestanding x86_64-freestanding; do
    echo "xenia-x86-input-driver: $target compile-only check"
    output="$tmp_dir/$target.a"
    "$zig_bin" build-lib "$package_dir/src/root.zig" \
        --cache-dir "$tmp_dir/$target-cache" \
        --global-cache-dir "$tmp_dir/$target-global-cache" \
        -target "$target" \
        -O Debug \
        -femit-bin="$output" \
        >/dev/null
    test -s "$output"
    echo "  verified $target"
done

echo "xenia-x86-input-driver: PASS"
