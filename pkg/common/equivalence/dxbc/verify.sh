#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$package_dir/../../../.." && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-dxbc-equivalence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"$zig_bin" test \
    --cache-dir "$tmp_dir/cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    --dep x86_dxbc --dep arm64_dxbc --dep ppc_dxbc \
    -Mroot="$package_dir/src/root.zig" \
    -Mx86_dxbc="$repo_dir/pkg/x86/third_party/dxbc/src/root.zig" \
    -Marm64_dxbc="$repo_dir/pkg/ARM64/third_party/dxbc/src/root.zig" \
    -Mppc_dxbc="$repo_dir/pkg/PPC/third_party/dxbc/src/root.zig"

echo "common-dxbc-equivalence: PASS"
