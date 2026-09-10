#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dll-win32-library-inventory.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "dll-win32-library-inventory: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    "$package_dir/src/root.zig"

# Both routes compile the same file, so both are checked here. A package that
# only ever built for the host it was written on is how a route split starts.
for target in aarch64-freestanding x86_64-freestanding; do
    echo "dll-win32-library-inventory: $target compile-only check"
    output="$tmp_dir/$target.a"
    "$zig_bin" build-lib \
        --cache-dir "$tmp_dir/$target-cache" \
        --global-cache-dir "$tmp_dir/$target-global-cache" \
        -target "$target" \
        -O Debug \
        "$package_dir/src/root.zig" \
        -femit-bin="$output" \
        >/dev/null
    test -s "$output"
    echo "  verified $target"
done

echo "dll-win32-library-inventory: PASS"
