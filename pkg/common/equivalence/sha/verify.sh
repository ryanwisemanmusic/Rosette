#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$package_dir/../../../.." && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-sha-equivalence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"$zig_bin" test \
    --cache-dir "$tmp_dir/cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    --dep x86_sha --dep arm64_sha --dep ppc_sha \
    -Mroot="$package_dir/src/root.zig" \
    -Mx86_sha="$repo_dir/pkg/x86/third_party/crypto/sha/src/root.zig" \
    -Marm64_sha="$repo_dir/pkg/ARM64/third_party/crypto/sha/src/root.zig" \
    -Mppc_sha="$repo_dir/pkg/PPC/third_party/crypto/sha/src/root.zig"

echo "common-sha-equivalence: PASS"
