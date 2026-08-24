#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xenia-x86-startup-evidence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "xenia-x86-startup-evidence: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/global-cache" \
    "$package_dir/src/evidence.zig"

echo "xenia-x86-startup-evidence: native CLI compile"
"$zig_bin" build-exe \
    --cache-dir "$tmp_dir/cli-cache" \
    --global-cache-dir "$tmp_dir/cli-global-cache" \
    "$package_dir/src/main.zig" \
    -femit-bin="$tmp_dir/xenia-x86-startup-evidence"

if [[ "$#" -eq 2 ]]; then
    echo "xenia-x86-startup-evidence: supplied log pair"
    output="$($tmp_dir/xenia-x86-startup-evidence "$1" "$2")"
    printf '%s\n' "$output"
    printf '%s\n' "$output" | rg -q '^frontier=shader_storage_requested '
    printf '%s\n' "$output" | rg -q '^tracepoints=22/0 '
    printf '%s\n' "$output" | rg -q '^tracepoints=.* swap_tracepoints=.* swap_hits=0$'
    printf '%s\n' "$output" | rg -q '^verdict=graphics_owner_silent$'
fi

echo "xenia-x86-startup-evidence: PASS"
