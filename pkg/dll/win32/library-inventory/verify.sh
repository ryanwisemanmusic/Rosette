#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
win32_dir="$(cd "$package_dir/.." && pwd)"
zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dll-win32-library-inventory.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# The inventory delegates name ownership to the catalogue, which in turn maps
# one module per DLL package. Without those mappings this script fails at
# "no module named 'dll_win32_catalogue'" and the package's tests never run at
# all -- which is what it did, silently, because nothing else executes this
# file. Build the module list from the sibling directories so a new per-DLL
# package is picked up rather than quietly left out.
build_module_args() {
    module_args=(--dep dll_win32_catalogue)
    module_args+=(-Mroot="$package_dir/src/root.zig")

    local catalogue_deps=()
    local dir stem module
    for dir in "$win32_dir"/*/; do
        stem="$(basename "$dir")"
        [[ "$stem" == "catalogue" || "$stem" == "library-inventory" ]] && continue
        [[ -f "$dir/src/root.zig" ]] || continue
        module="dll_win32_${stem//-/_}"
        catalogue_deps+=(--dep "$module")
    done

    module_args+=("${catalogue_deps[@]}")
    module_args+=(-Mdll_win32_catalogue="$win32_dir/catalogue/src/root.zig")

    for dir in "$win32_dir"/*/; do
        stem="$(basename "$dir")"
        [[ "$stem" == "catalogue" || "$stem" == "library-inventory" ]] && continue
        [[ -f "$dir/src/root.zig" ]] || continue
        module="dll_win32_${stem//-/_}"
        module_args+=(-M"$module=$dir/src/root.zig")
    done
}

build_module_args

echo "dll-win32-library-inventory: native tests"
"$zig_bin" test \
    --cache-dir "$tmp_dir/native-cache" \
    --global-cache-dir "$tmp_dir/native-global-cache" \
    "${module_args[@]}"

# Both routes compile the same file, so both are checked here. A package that
# only ever built for the host it was written on is how a route split starts.
for target in aarch64-freestanding x86_64-freestanding; do
    echo "dll-win32-library-inventory: $target compile-only check"
    output="$tmp_dir/$target.a"
    "$zig_bin" build-lib \
        --cache-dir "$tmp_dir/$target-cache" \
        --global-cache-dir "$tmp_dir/$target-global-cache" \
        -target "$target" \
        -O Debug \
        "${module_args[@]}" \
        -femit-bin="$output" \
        >/dev/null
    test -s "$output"
    echo "  verified $target"
done

echo "dll-win32-library-inventory: PASS"
