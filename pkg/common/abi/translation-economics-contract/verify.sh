#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$package_dir/../../../.." && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-abi-translation-economics-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "common-abi-translation-economics-contract: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    --dep rosette_translation_cache_contract \
    -Mroot="$package_dir/src/root.zig" \
    -Mrosette_translation_cache_contract="$repo_dir/pkg/common/rosette/translation-cache-contract/src/root.zig"

# Both routes compile the same file, so both are checked here rather than in a
# mirrored copy. A package that only ever built for the host it was written on
# is how a route split starts.
for target in aarch64-freestanding x86_64-freestanding; do
    echo "common-abi-translation-economics-contract: $target compile-only check"
    output="$tmp_dir/$target.a"
    "$zig_bin" build-lib \
        --cache-dir "$tmp_dir/$target-cache" \
        --global-cache-dir "$tmp_dir/$target-global-cache" \
        --dep rosette_translation_cache_contract \
        -Mroot="$package_dir/src/root.zig" \
        -Mrosette_translation_cache_contract="$repo_dir/pkg/common/rosette/translation-cache-contract/src/root.zig" \
        -target "$target" \
        -O Debug \
        -femit-bin="$output" \
        >/dev/null
    test -s "$output"
    echo "  verified $target"
done

echo "common-abi-translation-economics-contract: PASS"
