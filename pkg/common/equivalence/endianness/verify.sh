#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$package_dir/../../../.." && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-endianness-equivalence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"$zig_bin" test \
    --cache-dir "$tmp_dir/cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    --dep x86_endianness --dep arm64_endianness --dep ppc_endianness \
    -Mroot="$package_dir/src/root.zig" \
    -Mx86_endianness="$repo_dir/pkg/x86/third_party/endianness/src/root.zig" \
    -Marm64_endianness="$repo_dir/pkg/ARM64/third_party/endianness/src/root.zig" \
    -Mppc_endianness="$repo_dir/pkg/PPC/third_party/endianness/src/root.zig"

echo "common-endianness-equivalence: PASS"
