#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$package_dir/../../../.." && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-half-equivalence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"$zig_bin" test \
    --cache-dir "$tmp_dir/cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    --dep x86_half --dep arm64_half --dep ppc_half \
    -Mroot="$package_dir/src/root.zig" \
    -Mx86_half="$repo_dir/pkg/x86/third_party/half/src/root.zig" \
    -Marm64_half="$repo_dir/pkg/ARM64/third_party/half/src/root.zig" \
    -Mppc_half="$repo_dir/pkg/PPC/third_party/half/src/root.zig"

echo "common-half-equivalence: PASS"
