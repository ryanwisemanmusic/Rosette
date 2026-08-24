#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xenia-arm64-startup-evidence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "xenia-arm64-startup-evidence: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    "$package_dir/src/evidence.zig"

echo "xenia-arm64-startup-evidence: native CLI compile"
"$zig_bin" build-exe \
    --cache-dir "$tmp_dir/cli-cache" \
    --global-cache-dir "$tmp_dir/cli-global-cache" \
    "$package_dir/src/main.zig" \
    -femit-bin="$tmp_dir/xenia-arm64-startup-evidence"

if [[ "$#" -eq 2 ]]; then
    echo "xenia-arm64-startup-evidence: supplied log pair"
    output="$($tmp_dir/xenia-arm64-startup-evidence "$1" "$2")"
    printf '%s\n' "$output"
    # Deliberately no expected frontier, tracepoint count, or verdict here.
    # The x86 package asserts the values its own run produced; asserting them
    # for this route would be the cross-load the README refuses. Only the
    # report's shape is checked, so a parser that stopped emitting a field
    # still fails.
    printf '%s\n' "$output" | rg -q '^frontier=[^ ]+ '
    printf '%s\n' "$output" | rg -q '^tracepoints=[0-9]+/[0-9]+ swap_tracepoints=[0-9]+ swap_hits=[0-9]+$'
    printf '%s\n' "$output" | rg -q '^verdict=[a-z_]+$'
fi

echo "xenia-arm64-startup-evidence: PASS"
