#!/usr/bin/env bash
# Rosette-owned macOS environment for translated x86-64 builds.
#
# Source this file before configuring a Xenia/Rosette build:
#   source tools/rosette-macos-env.sh
#   rosette_verify_macos_host
#
# This is intentionally non-destructive. It never installs Homebrew, changes
# shell startup files, removes a CMake cache, or deletes a failed prefix. A
# Rosette-managed provider is preferred; /usr/local/x86brew remains a visible
# migration fallback until its dependencies have been moved into the managed
# layout.

set -euo pipefail

# The normal entry point is Bash, but macOS users commonly source this file
# from zsh. BASH_SOURCE is not defined by zsh, so use zsh's current-source
# token there instead of making the environment adapter unusable interactively.
if [[ -n "${BASH_VERSION:-}" ]]; then
    _rosette_macos_env_source_path="${BASH_SOURCE[0]}"
    _rosette_macos_env_run_directly=false
    [[ "${BASH_SOURCE[0]}" == "${0}" ]] && _rosette_macos_env_run_directly=true
else
    _rosette_macos_env_source_path="${(%):-%x}"
    _rosette_macos_env_run_directly=false
    [[ "${_rosette_macos_env_source_path}" == "${0}" ]] && _rosette_macos_env_run_directly=true
fi
_rosette_macos_env_script_dir="$(cd "$(dirname "${_rosette_macos_env_source_path}")" && pwd)"
_rosette_macos_env_repo_root="$(cd "${_rosette_macos_env_script_dir}/.." && pwd)"

if [[ -z "${ROSETTE_MACOS_HOST_ROOT:-}" ]]; then
    export ROSETTE_MACOS_HOST_ROOT="${_rosette_macos_env_repo_root}/.rosette/macos-host"
fi

_rosette_macos_sanitize_path() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        setopt localoptions shwordsplit
    fi
    local value="${1:-}"
    local entry
    local result=""
    local old_ifs="${IFS}"
    IFS=':'
    for entry in ${value}; do
        [[ -z "${entry}" ]] && continue
        case "${entry}" in
            /opt/homebrew|/opt/homebrew/*) continue ;;
        esac
        if [[ -z "${result}" ]]; then
            result="${entry}"
        else
            result="${result}:${entry}"
        fi
    done
    IFS="${old_ifs}"
    printf '%s' "${result}"
}

_rosette_macos_sanitize_flags() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        setopt localoptions shwordsplit
    fi
    local value="${1:-}"
    local token
    local result=""
    # Build flags are conventionally whitespace-delimited. Drop any token
    # that carries an ARM Homebrew path, including combined linker options
    # such as -Wl,-rpath,/opt/homebrew/lib. This prevents an inherited host
    # shell from reintroducing ARM headers or libraries after PATH filtering.
    for token in ${value}; do
        case "${token}" in
            */opt/homebrew|*/opt/homebrew/*|/opt/homebrew|/opt/homebrew/*) continue ;;
        esac
        if [[ -z "${result}" ]]; then
            result="${token}"
        else
            result="${result} ${token}"
        fi
    done
    printf '%s' "${result}"
}

_rosette_macos_is_arm_homebrew_path() {
    case "${1:-}" in
        /opt/homebrew|/opt/homebrew/*) return 0 ;;
        *) return 1 ;;
    esac
}

_rosette_macos_assert_no_arm_path() {
    local name="$1"
    local value="${2:-}"
    case "${value}" in
        */opt/homebrew*|/opt/homebrew*)
            echo "ERROR: ${name} still references ARM Homebrew: ${value}" >&2
            return 1
            ;;
    esac
}

_rosette_macos_xcode_tool() {
    local name="$1"
    local result=""
    if command -v xcrun >/dev/null 2>&1; then
        result="$(xcrun -find "${name}" 2>/dev/null || true)"
    fi
    if [[ -n "${result}" ]]; then
        printf '%s' "${result}"
    else
        printf '%s' "/usr/bin/${name}"
    fi
}

_rosette_macos_select_prefix() {
    if [[ -n "${ROSETTE_HOST_PREFIX:-}" ]]; then
        if _rosette_macos_is_arm_homebrew_path "${ROSETTE_HOST_PREFIX}"; then
            echo "ERROR: ROSETTE_HOST_PREFIX resolves to ARM Homebrew: ${ROSETTE_HOST_PREFIX}" >&2
            return 1
        fi
        printf '%s' "${ROSETTE_HOST_PREFIX}"
        return 0
    fi
    if [[ -d "${ROSETTE_MACOS_HOST_ROOT}/x86_64" ]]; then
        _rosette_macos_managed_x86_prefix="${ROSETTE_MACOS_HOST_ROOT}/x86_64"
        if _rosette_macos_is_arm_homebrew_path "${_rosette_macos_managed_x86_prefix}"; then
            echo "ERROR: managed x86 prefix resolves to ARM Homebrew: ${_rosette_macos_managed_x86_prefix}" >&2
            return 1
        fi
        printf '%s' "${_rosette_macos_managed_x86_prefix}"
        return 0
    fi
    # Compatibility only. This branch is deliberately reported so a later
    # migration can prove that no build still depends on x86brew.
    if [[ -d "/usr/local/x86brew" ]]; then
        printf '%s' "/usr/local/x86brew"
        return 0
    fi
    if [[ -x "/usr/local/bin/brew" ]]; then
        printf '%s' "/usr/local"
        return 0
    fi
    printf '%s' ''
}

_rosette_macos_x86_prefix="$(_rosette_macos_select_prefix)"
if [[ -n "${_rosette_macos_x86_prefix}" ]]; then
    export ROSETTE_HOST_PREFIX="${_rosette_macos_x86_prefix}"
fi

_rosette_macos_xcode_clang="$(_rosette_macos_xcode_tool clang)"
_rosette_macos_xcode_clangxx="$(_rosette_macos_xcode_tool clang++)"
_rosette_macos_requested_cc="${ROSETTE_CC:-${CC:-}}"
_rosette_macos_requested_cxx="${ROSETTE_CXX:-${CXX:-}}"
_rosette_macos_requested_pkg_config="${PKG_CONFIG:-}"
if [[ -z "${_rosette_macos_requested_cc}" || "${_rosette_macos_requested_cc}" == /opt/homebrew || "${_rosette_macos_requested_cc}" == /opt/homebrew/* ]]; then
    export CC="${_rosette_macos_xcode_clang}"
else
    export CC="${_rosette_macos_requested_cc}"
fi
if [[ -z "${_rosette_macos_requested_cxx}" || "${_rosette_macos_requested_cxx}" == /opt/homebrew || "${_rosette_macos_requested_cxx}" == /opt/homebrew/* ]]; then
    export CXX="${_rosette_macos_xcode_clangxx}"
else
    export CXX="${_rosette_macos_requested_cxx}"
fi

# ARM Homebrew is a native-host provider, but it is the wrong toolchain for an
# x86-64 Xenia build. Keep it out of PATH while leaving it available for the
# native Vulkan loader lookup performed by the runtime.
_rosette_macos_path_prefix=""
if [[ -n "${ROSETTE_HOST_PREFIX:-}" ]]; then
    _rosette_macos_path_prefix="${ROSETTE_HOST_PREFIX}/bin:${ROSETTE_HOST_PREFIX}/sbin"
fi
export PATH="${_rosette_macos_path_prefix}:/usr/bin:/bin:/usr/sbin:/sbin:$(_rosette_macos_sanitize_path "${PATH:-}")"

# Sanitize inherited search paths before prepending the selected provider.
# PATH alone is insufficient: CMake, pkg-config, and the linker can each
# select ARM Homebrew independently of executable lookup.
_rosette_macos_inherited_pkg_config_path="$(_rosette_macos_sanitize_path "${PKG_CONFIG_PATH:-}")"
_rosette_macos_inherited_cmake_prefix_path="$(_rosette_macos_sanitize_path "${CMAKE_PREFIX_PATH:-}")"
_rosette_macos_inherited_dyld_library_path="$(_rosette_macos_sanitize_path "${DYLD_LIBRARY_PATH:-}")"
_rosette_macos_inherited_ldflags="$(_rosette_macos_sanitize_flags "${LDFLAGS:-}")"
_rosette_macos_inherited_cppflags="$(_rosette_macos_sanitize_flags "${CPPFLAGS:-}")"

if [[ -n "${ROSETTE_HOST_PREFIX:-}" ]]; then
    export PKG_CONFIG_PATH="${ROSETTE_HOST_PREFIX}/lib/pkgconfig${_rosette_macos_inherited_pkg_config_path:+:${_rosette_macos_inherited_pkg_config_path}}"
    if [[ -x "${ROSETTE_HOST_PREFIX}/bin/pkg-config" ]]; then
        export PKG_CONFIG="${ROSETTE_HOST_PREFIX}/bin/pkg-config"
    elif _rosette_macos_is_arm_homebrew_path "${_rosette_macos_requested_pkg_config}"; then
        unset PKG_CONFIG
    fi
    export CMAKE_PREFIX_PATH="${ROSETTE_HOST_PREFIX}${_rosette_macos_inherited_cmake_prefix_path:+:${_rosette_macos_inherited_cmake_prefix_path}}"
    export LDFLAGS="-L${ROSETTE_HOST_PREFIX}/lib${_rosette_macos_inherited_ldflags:+ ${_rosette_macos_inherited_ldflags}}"
    export CPPFLAGS="-I${ROSETTE_HOST_PREFIX}/include${_rosette_macos_inherited_cppflags:+ ${_rosette_macos_inherited_cppflags}}"
    export DYLD_LIBRARY_PATH="${ROSETTE_HOST_PREFIX}/lib${_rosette_macos_inherited_dyld_library_path:+:${_rosette_macos_inherited_dyld_library_path}}"
else
    export PKG_CONFIG_PATH="${_rosette_macos_inherited_pkg_config_path}"
    export CMAKE_PREFIX_PATH="${_rosette_macos_inherited_cmake_prefix_path}"
    export LDFLAGS="${_rosette_macos_inherited_ldflags}"
    export CPPFLAGS="${_rosette_macos_inherited_cppflags}"
    export DYLD_LIBRARY_PATH="${_rosette_macos_inherited_dyld_library_path}"
    if _rosette_macos_is_arm_homebrew_path "${_rosette_macos_requested_pkg_config}"; then
        unset PKG_CONFIG
    fi
fi

export CMAKE_OSX_ARCHITECTURES="x86_64"
export ROSETTE_X86_64_TARGET="x86_64"

rosette_run_x86_64() {
    if command -v arch >/dev/null 2>&1; then
        arch -x86_64 "$@"
    else
        "$@"
    fi
}

rosette_find_tool() {
    local tool="$1"
    if [[ -n "${ROSETTE_HOST_PREFIX:-}" && -x "${ROSETTE_HOST_PREFIX}/bin/${tool}" ]]; then
        printf '%s' "${ROSETTE_HOST_PREFIX}/bin/${tool}"
        return 0
    fi
    command -v "${tool}" 2>/dev/null || return 1
}

rosette_verify_macos_host() {
    local system
    system="$(uname -s 2>/dev/null || true)"
    echo "Rosette macOS host contract"
    echo "  repository:       ${_rosette_macos_env_repo_root}"
    echo "  system:           ${system:-<unknown>}"
    echo "  target:           ${CMAKE_OSX_ARCHITECTURES}"
    echo "  managed root:     ${ROSETTE_MACOS_HOST_ROOT}"
    echo "  build prefix:     ${ROSETTE_HOST_PREFIX:-<none>}"
    echo "  compiler:         ${CC}"
    echo "  cxx compiler:     ${CXX}"

    [[ "${CMAKE_OSX_ARCHITECTURES}" == "x86_64" ]] || {
        echo "ERROR: CMAKE_OSX_ARCHITECTURES is not x86_64" >&2
        return 1
    }
    case "${CC}" in
        /opt/homebrew|/opt/homebrew/*)
            echo "ERROR: CC resolves to ARM Homebrew: ${CC}" >&2
            return 1
            ;;
    esac
    case "${CXX}" in
        /opt/homebrew|/opt/homebrew/*)
            echo "ERROR: CXX resolves to ARM Homebrew: ${CXX}" >&2
            return 1
            ;;
    esac
    _rosette_macos_assert_no_arm_path "PATH" "${PATH}" || return 1
    _rosette_macos_assert_no_arm_path "PKG_CONFIG_PATH" "${PKG_CONFIG_PATH}" || return 1
    _rosette_macos_assert_no_arm_path "CMAKE_PREFIX_PATH" "${CMAKE_PREFIX_PATH}" || return 1
    _rosette_macos_assert_no_arm_path "DYLD_LIBRARY_PATH" "${DYLD_LIBRARY_PATH}" || return 1
    _rosette_macos_assert_no_arm_path "LDFLAGS" "${LDFLAGS}" || return 1
    _rosette_macos_assert_no_arm_path "CPPFLAGS" "${CPPFLAGS}" || return 1
    _rosette_macos_assert_no_arm_path "PKG_CONFIG" "${PKG_CONFIG:-}" || return 1
    if [[ -n "${ROSETTE_HOST_PREFIX:-}" ]]; then
        case "${ROSETTE_HOST_PREFIX}" in
            /opt/homebrew|/opt/homebrew/*)
                echo "ERROR: x86 build prefix resolves to ARM Homebrew: ${ROSETTE_HOST_PREFIX}" >&2
                return 1
                ;;
        esac
        if [[ "${ROSETTE_HOST_PREFIX}" == /usr/local/x86brew || "${ROSETTE_HOST_PREFIX}" == /usr/local/x86brew/* ]]; then
            echo "  provider:         legacy-x86brew (migration fallback)"
        elif [[ "${ROSETTE_HOST_PREFIX}" == "${ROSETTE_MACOS_HOST_ROOT}" || "${ROSETTE_HOST_PREFIX}" == "${ROSETTE_MACOS_HOST_ROOT}"/* ]]; then
            echo "  provider:         rosette-managed"
        else
            echo "  provider:         explicit-compatible-prefix"
        fi
    else
        echo "  provider:         <unprovisioned>"
        echo "WARNING: no Rosette-managed or legacy x86 dependency prefix was found" >&2
    fi

    local required_tool
    for required_tool in clang clang++ cmake nasm pkg-config; do
        if ! command -v "${required_tool}" >/dev/null 2>&1; then
            echo "ERROR: required host tool is missing: ${required_tool}" >&2
            return 1
        fi
    done
    echo "  status:            PASS (non-destructive environment and architecture checks)"
}

if [[ "${_rosette_macos_env_run_directly}" == true ]]; then
    rosette_verify_macos_host
fi
