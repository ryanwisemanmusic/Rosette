#!/bin/sh
# Compile a self-contained MSL source through AIR into a content/toolchain-
# keyed metallib cache. Outputs stay outside the source tree by default.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
source_path=${1:-"$repo_root/lib/gpu/metal/rosette_msl_smoke.metal"}
cache_root=${2:-"${TMPDIR:-/tmp}/rosette-metal-cache"}
sdk_name=${3:-macosx}

if [ ! -f "$source_path" ]; then
    echo "rosette-metal-cache: source file not found: $source_path" >&2
    exit 2
fi

source_dir=$(CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P)
source_path="$source_dir/$(basename -- "$source_path")"
mkdir -p "$cache_root"
cache_root=$(CDPATH= cd -- "$cache_root" && pwd -P)

metal=$(xcrun --sdk "$sdk_name" -f metal)
metallib=$(xcrun --sdk "$sdk_name" -f metallib)
sdk_version=$(xcrun --sdk "$sdk_name" --show-sdk-version)
sdk_build=$(xcrun --sdk "$sdk_name" --show-sdk-build-version)
metal_identity=$("$metal" --version 2>&1 | sed -n '1p;2p' | tr '\n' ' ')
metallib_identity=$("$metallib" --version 2>&1 | sed -n '1p')
architecture=$(uname -m)
source_sha256=$(LC_ALL=C shasum -a 256 "$source_path" | awk '{print $1}')
identity=$(printf '%s\n' \
    "schema=rosette-metal-artifact-v1" \
    "source=$source_path" \
    "source_sha256=$source_sha256" \
    "metal=$metal_identity" \
    "metallib=$metallib_identity" \
    "sdk=$sdk_name/$sdk_version/$sdk_build" \
    "host_arch=$architecture")
cache_key=$(printf '%s\n' "$identity" | LC_ALL=C shasum -a 256 | awk '{print $1}')
artifact_dir="$cache_root/$cache_key"

if [ -s "$artifact_dir/rosette_msl_smoke.air" ] &&
    [ -s "$artifact_dir/rosette_msl_smoke.metallib" ] &&
    [ -f "$artifact_dir/manifest.txt" ] &&
    [ "$(cat "$artifact_dir/manifest.txt")" = "$identity" ]; then
    printf 'rosette-metal-cache: hit key=%s\nair=%s\nmetallib=%s\n' \
        "$cache_key" "$artifact_dir/rosette_msl_smoke.air" "$artifact_dir/rosette_msl_smoke.metallib"
    exit 0
fi

temporary_dir=$(mktemp -d "$cache_root/.metal-build.XXXXXX")
cleanup() {
    rm -rf "$temporary_dir"
}
trap cleanup EXIT HUP INT TERM

"$metal" -c "$source_path" -o "$temporary_dir/rosette_msl_smoke.air"
"$metallib" "$temporary_dir/rosette_msl_smoke.air" -o "$temporary_dir/rosette_msl_smoke.metallib"
test -s "$temporary_dir/rosette_msl_smoke.air"
test -s "$temporary_dir/rosette_msl_smoke.metallib"
printf '%s\n' "$identity" > "$temporary_dir/manifest.txt"

mkdir -p "$artifact_dir"
mv -f "$temporary_dir/rosette_msl_smoke.air" "$artifact_dir/rosette_msl_smoke.air"
mv -f "$temporary_dir/rosette_msl_smoke.metallib" "$artifact_dir/rosette_msl_smoke.metallib"
mv -f "$temporary_dir/manifest.txt" "$artifact_dir/manifest.txt"
printf 'rosette-metal-cache: compiled key=%s\nair=%s\nmetallib=%s\n' \
    "$cache_key" "$artifact_dir/rosette_msl_smoke.air" "$artifact_dir/rosette_msl_smoke.metallib"
