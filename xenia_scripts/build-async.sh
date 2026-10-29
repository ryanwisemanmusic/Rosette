#!/usr/bin/env bash
# Keep the established macOS entry point while pinning the Canary source revision.
#
# The upstream checkout is intentionally left free of Rosette's emulator
# patches.  The actual build and PE launch live in Rosette's isolated capsule;
# this thin adapter keeps the command users already have in muscle memory.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xenia_root="$(cd "${script_dir}/.." && pwd)"
"${script_dir}/ensure-canary-revision.sh"
source "${script_dir}/rosette-root.sh"
xenia_root="$(cd "${script_dir}/.." && pwd)"
rosette_mode="${ROSETTE_XENIA_ROSETTE_MODE:-auto}"
rosette_root="$(rosette_resolve_root "$xenia_root" "$rosette_mode")" || exit 66
local_rosette_root="${xenia_root}/third_party/rosette"
if [[ "$rosette_root" == "$local_rosette_root" ]]; then
    resolved_mode=static
else
    resolved_mode=dynamic
fi
export ROSETTE_ROOT="$rosette_root"
export ROSETTE_XENIA_ROSETTE_MODE_RESOLVED="$resolved_mode"
runner="${rosette_root}/tools/guest_runtime/scripts/rosette-guest-run.sh"

[[ -x "$runner" ]] || {
    echo "build-async.sh: Rosette launcher not found: $runner" >&2
    echo "Set ROSETTE_ROOT to the Rosetta 3 checkout." >&2
    exit 66
}

if [[ "$resolved_mode" == static && ! -x "${rosette_root}/zig-out/bin/rosette_exe_runner" && ! -x "${rosette_root}/app/bundling/zig-out/bin/rosette_exe_runner" ]]; then
    echo "build-async.sh: static Rosette source is present but its standalone runner is missing." >&2
    echo "Import/build a runner with macos/vendor-rosette.sh --build-runner, or select a registered global checkout with ROSETTE_XENIA_ROSETTE_MODE=dynamic." >&2
    exit 66
fi

export ROSETTE_ASYNC_LOG="${ROSETTE_ASYNC_LOG:-1}"
export ROSETTE_INPUT_HASH_STALL_SECONDS="${ROSETTE_INPUT_HASH_STALL_SECONDS:-0}"
# Arm a one-frame GFXReconstruct capture before Xenia creates its Vulkan
# instance. Nothing is written until F10 is pressed; set ROSETTE_VULKAN_GFXR=off
# for a run that should not load the capture layer.
export ROSETTE_VULKAN_GFXR="${ROSETTE_VULKAN_GFXR:-1}"
# The build-async entry point is the long-lived bring-up path. Keep fatal
# findings in the evidence log so decode/cache and other diagnostics cannot
# terminate the process before the first Cocoa present. A caller that owns a
# deliberate strict-failure run may still override this before invocation.
export ROSETTE_XENIA_FATAL_POINT_TERMINATE="${ROSETTE_XENIA_FATAL_POINT_TERMINATE:-0}"
export ROSETTE_XENIA_ROOT="$xenia_root"
# Keep generated Xenia build products with this checkout, whether Rosette is
# selected from a global install or imported under third_party/rosette.
export ROSETTE_XENIA_WINDOWS_BUILD_DIR="${ROSETTE_XENIA_WINDOWS_BUILD_DIR:-${xenia_root}/build/xenia-windows-clean}"
export ROSETTE_XENIA_WINDOWS_BUNDLE_DIR="${ROSETTE_XENIA_WINDOWS_BUNDLE_DIR:-${ROSETTE_XENIA_WINDOWS_BUILD_DIR}/bundle}"
export ROSETTE_XENIA_CPP_TOOL_PREFIX="${ROSETTE_XENIA_CPP_TOOL_PREFIX:-${xenia_root}/build/rosette-support/windows-cpp-tool}"
export ROSETTE_MACOS_HOST_ROOT="${ROSETTE_MACOS_HOST_ROOT:-${xenia_root}/build/rosette-support/macos-host}"
# Keep the run ledger with the Xenia checkout. The dedicated child directory
# prevents the Rosetta launcher cleanup from touching other Xenia `.rosette`
# metadata while making the log discoverable at the only approved location.
export ROSETTE_XENIA_ROSETTE_DIR="${ROSETTE_XENIA_ROSETTE_DIR:-${xenia_root}/.rosette/xenia-runs}"

args=(--source-root "$xenia_root" --build-if-missing)
if [[ "${ROSETTE_XENIA_REBUILD:-0}" == 1 ]]; then
    args+=(--rebuild)
fi

if [[ "${ROSETTE_XENIA_TRACE_RESOLUTION:-0}" == 1 ]]; then
    echo "Xenia Rosette route: ${resolved_mode} (${rosette_root})"
fi

# Keep the verified Halo 3 input discoverable without copying a multi-gigabyte
# image into the source checkout. Callers can override this explicitly. The
# old backup-volume path was not stable and could select a different title;
# the Rosetta repository is the media authority for this adapter.
if [[ -z "${ROSETTE_XENIA_MEDIA_IMAGE:-}" ]]; then
    shopt -s nullglob
    halo3_media_candidates=("${rosette_root}"/ISO_FILE/8CEB1ABA7AC20BDAF62EEA16699E0227*.iso)
    shopt -u nullglob
    if [[ "${#halo3_media_candidates[@]}" == 1 ]]; then
        export ROSETTE_XENIA_MEDIA_IMAGE="${halo3_media_candidates[0]}"
    fi
fi

# Do not `exec` here. Replacing the caller is surprising for an interactive
# shell and terminates the caller outright when this file is sourced. Run the
# Rosetta launcher as a child, retain its status, and return/exit only from
# this script's own scope.
runner_status=0
"$runner" "${args[@]}" "$@" || runner_status=$?

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    exit "$runner_status"
fi
return "$runner_status"
