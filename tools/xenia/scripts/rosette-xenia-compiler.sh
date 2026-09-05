#!/usr/bin/env bash
# Rosette-owned compiler boundary for Xenia's C/GTK wrappers.
#
# The wrapper rejects a known incompatible provider path. It does not silently
# rewrite an ARM include tree into an x86 build or the reverse; that is the
# class of error the old wrappers made difficult to see.

set -euo pipefail

_rosette_xenia_compiler_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rosette_xenia_compiler_help() {
    cat <<'EOF'
Rosette Xenia compiler adapter

Configure the environment first, then set a build system's C/CXX compiler to
this file. The real compiler may be supplied with
ROSETTE_XENIA_REAL_COMPILER or ROSETTE_XENIA_REAL_CXX.

The adapter rejects provider paths that disagree with
ROSETTE_XENIA_SOURCE_ARCHITECTURE and optionally adds
ROSETTE_XENIA_GTK_INCLUDE_ROOT.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    rosette_xenia_compiler_help
    exit 0
fi

[[ "${ROSETTE_XENIA_CONFIGURED:-0}" == "1" ]] || {
    echo "ERROR: configure Rosette's Xenia environment before invoking the compiler adapter" >&2
    exit 1
}

rosette_xenia_compiler_is_cpp() {
    local next_is_language=0
    local arg
    for arg in "$@"; do
        if [[ "${next_is_language}" == 1 ]]; then
            [[ "${arg}" == "c++" || "${arg}" == "objective-c++" ]] && return 0
            next_is_language=0
            continue
        fi
        if [[ "${arg}" == "-x" ]]; then
            next_is_language=1
            continue
        fi
        case "${arg}" in
            *.cc|*.cpp|*.cxx|*.mm|*.mxx) return 0 ;;
        esac
    done
    return 1
}

rosette_xenia_compiler_check_path() {
    local path="${1:-}"
    case "${ROSETTE_XENIA_SOURCE_ARCHITECTURE}:${path}" in
        x86_64:/opt/homebrew|x86_64:/opt/homebrew/*|arm64:/usr/local/x86brew|arm64:/usr/local/x86brew/*)
            echo "ERROR: compiler invocation carries a provider incompatible with the source architecture: ${path}" >&2
            return 1
            ;;
    esac
}

rosette_xenia_compiler_check_args() {
    local arg
    for arg in "$@"; do
        rosette_xenia_compiler_check_path "${arg}"
    done
}

rosette_xenia_compiler_real_path() {
    local cpp=0
    rosette_xenia_compiler_is_cpp "$@" && cpp=1 || true
    local candidate=""
    if [[ "${cpp}" == 1 ]]; then
        candidate="${ROSETTE_XENIA_REAL_CXX:-${ROSETTE_CXX:-}}"
    else
        candidate="${ROSETTE_XENIA_REAL_COMPILER:-${ROSETTE_CC:-}}"
    fi
    if [[ -z "${candidate}" ]]; then
        if [[ "${cpp}" == 1 ]]; then
            candidate="/usr/bin/clang++"
        else
            candidate="/usr/bin/clang"
        fi
    fi
    case "${candidate}" in
        */rosette-xenia-compiler.sh)
            if [[ "${cpp}" == 1 ]]; then candidate="/usr/bin/clang++"; else candidate="/usr/bin/clang"; fi
            ;;
    esac
    [[ -x "${candidate}" ]] || {
        echo "ERROR: selected real compiler is not executable: ${candidate}" >&2
        return 1
    }
    rosette_xenia_compiler_check_path "${candidate}"
    printf '%s\n' "${candidate}"
}

rosette_xenia_compiler_check_args "$@"
compiler="$(rosette_xenia_compiler_real_path "$@")"
forwarded=("$@")

if [[ "${ROSETTE_XENIA_SOURCE_ARCHITECTURE}" == "x86_64" ]]; then
    has_arch=0
    previous=""
    for arg in "${forwarded[@]}"; do
        if [[ "${previous}" == "-arch" || "${arg}" == -arch=* ]]; then has_arch=1; fi
        previous="${arg}"
    done
    [[ "${has_arch}" == 1 ]] || forwarded+=("-arch" "x86_64")
fi

if [[ -n "${ROSETTE_XENIA_GTK_INCLUDE_ROOT:-}" ]]; then
    gtk_root="${ROSETTE_XENIA_GTK_INCLUDE_ROOT}"
    [[ -d "${gtk_root}" ]] || {
        echo "ERROR: configured GTK staging root does not exist: ${gtk_root}" >&2
        exit 1
    }
    forwarded+=("-I${gtk_root}" "-I${gtk_root}/gtk-3.0" "-I${gtk_root}/glib-2.0" "-I${gtk_root}/glib-2.0/include" "-I${gtk_root}/fontconfig")
fi

exec "${compiler}" "${forwarded[@]}"

