#!/usr/bin/env bash
# Clean-capsule counterpart to macos/build-async.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xenia_root="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/rosette-root.sh"

if [[ -z "${ROSETTE_XENIA_ROSETTE_MODE+x}" && -t 0 ]]; then
    echo "Choose Rosette route for this scratch build:"
    echo "  1) static import in third_party/rosette"
    echo "  2) registered global shell checkout (dynamic selection)"
    echo "  3) auto (global checkout first, then static import)"
    read -r -p "Route [3]: " route_choice
    case "$route_choice" in
        1) export ROSETTE_XENIA_ROSETTE_MODE=static ;;
        2) export ROSETTE_XENIA_ROSETTE_MODE=dynamic ;;
        ''|3) export ROSETTE_XENIA_ROSETTE_MODE=auto ;;
        *) echo "Invalid route choice: $route_choice" >&2; exit 2 ;;
    esac
fi

export ROSETTE_XENIA_WINDOWS_BUILD_DIR="${ROSETTE_XENIA_WINDOWS_SCRATCH_BUILD_DIR:-${xenia_root}/build/xenia-windows-scratch}"
export ROSETTE_XENIA_WINDOWS_BUNDLE_DIR="${ROSETTE_XENIA_WINDOWS_SCRATCH_BUNDLE_DIR:-${ROSETTE_XENIA_WINDOWS_BUILD_DIR}/bundle}"
export ROSETTE_XENIA_REBUILD=1

exec "${script_dir}/build-async.sh" "$@"
