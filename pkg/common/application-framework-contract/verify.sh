#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-application-framework-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "common-application-framework-contract: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    "$package_dir/src/root.zig"

# The ABI is intentionally route-independent. Compile the exact same contract
# for both supported host directions so a new field or enum cannot silently
# become architecture-specific.
for target in aarch64-freestanding x86_64-freestanding; do
    echo "common-application-framework-contract: $target compile-only check"
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

echo "common-application-framework-contract: PASS"
