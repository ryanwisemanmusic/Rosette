#!/usr/bin/env bash
# Resolve Rosette for Xenia without a machine-specific checkout path.
#
# `auto` prefers an imported source tree at third_party/rosette, then falls
# back to a registered global Rosette checkout. This makes a local import the
# default test target while preserving a dynamic route for users who have not
# imported Rosette. Force either route with ROSETTE_XENIA_ROSETTE_MODE. Static
# means a vendored source tree and its standalone runner binary; it is not a
# dylib dependency.

rosette_is_source_root() {
    [[ -n "${1:-}" && -x "$1/tools/guest_runtime/scripts/rosette-guest-run.sh" ]]
}

rosette_registered_global_root() {
    local candidate="${ROSETTE_ROOT:-}"
    local registry=""
    if [[ -n "$candidate" ]]; then
        rosette_is_source_root "$candidate" || return 1
        (cd "$candidate" && pwd)
        return
    fi

    if [[ -n "${ROSETTE_HOME:-}" ]]; then
        registry="${ROSETTE_HOME}/source-root"
    elif [[ -n "${HOME:-}" ]]; then
        registry="${HOME}/.rosette/source-root"
    fi
    [[ -r "$registry" ]] || return 1
    IFS= read -r candidate < "$registry" || true
    rosette_is_source_root "$candidate" || return 1
    (cd "$candidate" && pwd)
}

rosette_resolve_root() {
    local xenia_root="${1:-${ROSETTE_XENIA_ROOT:-}}"
    local mode="${2:-${ROSETTE_XENIA_ROSETTE_MODE:-auto}}"
    local local_root=""
    local global_root=""

    if [[ -n "$xenia_root" ]]; then
        xenia_root="$(cd "$xenia_root" 2>/dev/null && pwd)" || {
            echo "Xenia source root does not exist: ${1:-$xenia_root}" >&2
            return 1
        }
        local_root="${xenia_root}/third_party/rosette"
    fi
    global_root="$(rosette_registered_global_root 2>/dev/null || true)"

    case "$mode" in
        static)
            rosette_is_source_root "$local_root" || {
                echo "Static Rosette source import is missing: ${local_root:-<Xenia root required>}" >&2
                return 1
            }
            (cd "$local_root" && pwd)
            ;;
        dynamic)
            [[ -n "$global_root" ]] || {
                echo "No registered global Rosette checkout found; set ROSETTE_ROOT or install Rosette with make shell-update" >&2
                return 1
            }
            printf '%s\n' "$global_root"
            ;;
        auto)
            if rosette_is_source_root "$local_root"; then
                (cd "$local_root" && pwd)
            elif [[ -n "$global_root" ]]; then
                printf '%s\n' "$global_root"
            else
                echo "Rosette not found. Install/register a global checkout or import source with macos/vendor-rosette.sh." >&2
                return 1
            fi
            ;;
        *)
            echo "ROSETTE_XENIA_ROSETTE_MODE must be auto, static, or dynamic (got: $mode)" >&2
            return 2
            ;;
    esac
}
