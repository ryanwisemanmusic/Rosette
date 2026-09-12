#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-xenia-warning-severity-map.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# The shared character-set filter is a sibling package, so it has to be mapped
# as a module. Without this the script fails with "no module named
# 'phrase_filter'" and the package's tests never run at all — which is what it
# did before, silently, because nothing else executes this file.
filter_src="$package_dir/../../text/phrase-filter/src/root.zig"

echo "common-xenia-warning-severity-map: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    --dep phrase_filter \
    -Mroot="$package_dir/src/root.zig" \
    -Mphrase_filter="$filter_src"

# Both routes compile the same file, so both are checked here rather than in a
# mirrored copy. A package that only ever built for the host it was written on
# is how a route split starts.
for target in aarch64-freestanding x86_64-freestanding; do
    echo "common-xenia-warning-severity-map: $target compile-only check"
    output="$tmp_dir/$target.a"
    "$zig_bin" build-lib \
        --cache-dir "$tmp_dir/$target-cache" \
        --global-cache-dir "$tmp_dir/$target-global-cache" \
        -target "$target" \
        -O Debug \
        --dep phrase_filter \
        -Mroot="$package_dir/src/root.zig" \
        -Mphrase_filter="$filter_src" \
        -femit-bin="$output" \
        >/dev/null
    test -s "$output"
    echo "  verified $target"
done

echo "common-xenia-warning-severity-map: PASS"
