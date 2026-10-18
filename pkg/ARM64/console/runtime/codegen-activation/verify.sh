#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/host-arm64-codegen-activation-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "host-arm64-codegen-activation-contract: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    "$package_dir/src/root.zig"

echo "host-arm64-codegen-activation-contract: arm64 compile-only check"
output="$tmp_dir/aarch64-freestanding.a"
"$zig_bin" build-lib "$package_dir/src/root.zig" \
    --cache-dir "$tmp_dir/target-cache" \
    --global-cache-dir "$tmp_dir/target-global-cache" \
    -target aarch64-freestanding \
    -O Debug \
    -femit-bin="$output" \
    >/dev/null
test -s "$output"
echo "  verified aarch64-freestanding"

echo "host-arm64-codegen-activation-contract: PASS"
