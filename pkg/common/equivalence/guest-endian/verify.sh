#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$package_dir/../../../.." && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-guest-endian-equivalence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"$zig_bin" test \
    --cache-dir "$tmp_dir/cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    --dep x86_guest_endian --dep arm64_guest_endian --dep ppc_guest_endian \
    -Mroot="$package_dir/src/root.zig" \
    -Mx86_guest_endian="$repo_dir/pkg/x86/console/guest-endian/src/root.zig" \
    -Marm64_guest_endian="$repo_dir/pkg/ARM64/console/guest-endian/src/root.zig" \
    -Mppc_guest_endian="$repo_dir/pkg/PPC/console/guest-endian/src/root.zig"

echo "common-guest-endian-equivalence: PASS"
