#!/usr/bin/env bash
# Select Rosette's library provider from the source image, not from the
# architecture of the Rosette host process.
#
#   source tools/rosette-source-architecture.sh
#   rosette_configure_source_environment path/to/title.exe
#
# A universal Mach-O containing an x86_64 slice selects the x86 provider,
# because that slice is executable source for the translator. Unknown input
# is treated as native ARM64 by policy; callers that require an x86 image
# should pass --source-image and verify the returned class.

set -euo pipefail

if [[ -n "${BASH_VERSION:-}" ]]; then
    _rosette_source_arch_source_path="${BASH_SOURCE[0]}"
else
    _rosette_source_arch_source_path="${(%):-%x}"
fi
_rosette_source_arch_script_dir="$(cd "$(dirname "${_rosette_source_arch_source_path}")" && pwd)"
_rosette_source_arch_repo_root="$(cd "${_rosette_source_arch_script_dir}/.." && pwd)"

rosette_detect_source_architecture() {
    local source_path="${1:?source image is required}"
    [[ -f "${source_path}" ]] || {
        echo "ERROR: source image does not exist: ${source_path}" >&2
        return 1
    }
    local description
    description="$(file -b -- "${source_path}" 2>/dev/null || true)"
    case "${description}" in
        *x86_64*|*x86-64*|*amd64*|*X86_64*)
            printf '%s\n' "x86_64"
            ;;
        *arm64*|*aarch64*|*ARM64*)
            printf '%s\n' "arm64"
            ;;
        *)
            printf '%s\n' "unknown"
            ;;
    esac
}

rosette_source_library_architecture() {
    local detected="${1:?detected source architecture is required}"
    if [[ "${detected}" == "x86_64" ]]; then
        printf '%s\n' "x86_64"
    else
        # ARM64 is the native provider and the safe fallback for an unknown
        # container. It avoids accidentally treating an arbitrary data file
        # as permission to inject the legacy x86 provider.
        printf '%s\n' "arm64"
    fi
}

rosette_source_provider_for_architecture() {
    local architecture="${1:?library architecture is required}"
    local managed_root="${ROSETTE_MACOS_HOST_ROOT:-${_rosette_source_arch_repo_root}/build/rosette-support/macos-host}"
    if [[ "${architecture}" == "x86_64" ]]; then
        if [[ -d "${managed_root}/x86_64" ]]; then
            printf '%s\n' "${managed_root}/x86_64"
        elif [[ -d "/usr/local/x86brew" ]]; then
            printf '%s\n' "/usr/local/x86brew"
        elif [[ -d "/usr/local" ]]; then
            printf '%s\n' "/usr/local"
        else
            printf '%s\n' ""
        fi
    else
        if [[ -d "${managed_root}/arm64" ]]; then
            printf '%s\n' "${managed_root}/arm64"
        elif [[ -d "/opt/homebrew" ]]; then
            printf '%s\n' "/opt/homebrew"
        else
            # System frameworks and Xcode are native providers even without a
            # Homebrew prefix. Do not substitute /usr/local here: on this host
            # it is the historical x86brew location.
            printf '%s\n' ""
        fi
    fi
}

_rosette_source_arch_sanitize_path() {
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
            /usr/local/x86brew|/usr/local/x86brew/*) continue ;;
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

_rosette_source_arch_sanitize_flags() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        setopt localoptions shwordsplit
    fi
    local value="${1:-}"
    local token
    local result=""
    for token in ${value}; do
        case "${token}" in
            */usr/local/x86brew|*/usr/local/x86brew/*|/usr/local/x86brew|/usr/local/x86brew/*) continue ;;
        esac
        if [[ -z "${result}" ]]; then
            result="${token}"
        else
            result="${result} ${token}"
        fi
    done
    printf '%s' "${result}"
}

rosette_configure_arm64_environment() {
    local managed_root="${ROSETTE_MACOS_HOST_ROOT:-${_rosette_source_arch_repo_root}/build/rosette-support/macos-host}"
    local prefix="${ROSETTE_ARM64_HOST_PREFIX:-}"
    if [[ -z "${prefix}" && -d "${managed_root}/arm64" ]]; then
        prefix="${managed_root}/arm64"
    fi
    if [[ -z "${prefix}" && -d "/opt/homebrew" ]]; then
        prefix="/opt/homebrew"
    fi
    case "${prefix}" in
        /usr/local/x86brew|/usr/local/x86brew/*)
            echo "ERROR: ARM64 source cannot use the x86brew provider: ${prefix}" >&2
            return 1
            ;;
    esac

    export ROSETTE_HOST_PREFIX="${prefix}"
    export ROSETTE_LIBRARY_PROVIDER="${prefix:-system-native}"
    export CMAKE_OSX_ARCHITECTURES="arm64"
    export ROSETTE_ARM64_TARGET="arm64"
    unset ROSETTE_X86_64_TARGET

    local xcode_clang="/usr/bin/clang"
    local xcode_clangxx="/usr/bin/clang++"
    if command -v xcrun >/dev/null 2>&1; then
        xcode_clang="$(xcrun -find clang 2>/dev/null || printf '%s' "${xcode_clang}")"
        xcode_clangxx="$(xcrun -find clang++ 2>/dev/null || printf '%s' "${xcode_clangxx}")"
    fi
    local requested_cc="${ROSETTE_CC:-${CC:-}}"
    local requested_cxx="${ROSETTE_CXX:-${CXX:-}}"
    case "${requested_cc}" in
        /usr/local/x86brew|/usr/local/x86brew/*)
            echo "ERROR: ARM64 source cannot use the x86brew compiler: ${requested_cc}" >&2
            return 1
            ;;
    esac
    case "${requested_cxx}" in
        /usr/local/x86brew|/usr/local/x86brew/*)
            echo "ERROR: ARM64 source cannot use the x86brew C++ compiler: ${requested_cxx}" >&2
            return 1
            ;;
    esac
    export CC="${requested_cc:-${xcode_clang}}"
    export CXX="${requested_cxx:-${xcode_clangxx}}"
    local sanitized_path
    sanitized_path="$(_rosette_source_arch_sanitize_path "${PATH:-}")"
    local prefix_path=""
    if [[ -n "${prefix}" ]]; then
        prefix_path="${prefix}/bin:${prefix}/sbin:"
    fi
    export PATH="${prefix_path}/usr/bin:/bin:/usr/sbin:/sbin:${sanitized_path}"
    local sanitized_pkg_config_path
    local sanitized_cmake_prefix_path
    local sanitized_dyld_library_path
    local sanitized_ldflags
    local sanitized_cppflags
    sanitized_pkg_config_path="$(_rosette_source_arch_sanitize_path "${PKG_CONFIG_PATH:-}")"
    sanitized_cmake_prefix_path="$(_rosette_source_arch_sanitize_path "${CMAKE_PREFIX_PATH:-}")"
    sanitized_dyld_library_path="$(_rosette_source_arch_sanitize_path "${DYLD_LIBRARY_PATH:-}")"
    sanitized_ldflags="$(_rosette_source_arch_sanitize_flags "${LDFLAGS:-}")"
    sanitized_cppflags="$(_rosette_source_arch_sanitize_flags "${CPPFLAGS:-}")"
    export PKG_CONFIG_PATH="${sanitized_pkg_config_path}"
    export CMAKE_PREFIX_PATH="${sanitized_cmake_prefix_path}"
    export LDFLAGS="${sanitized_ldflags}"
    export CPPFLAGS="${sanitized_cppflags}"
    export DYLD_LIBRARY_PATH="${sanitized_dyld_library_path}"
    case "${PKG_CONFIG:-}" in
        /usr/local/x86brew|/usr/local/x86brew/*) unset PKG_CONFIG ;;
    esac
    case "${ROSETTE_CMAKE:-}" in
        /usr/local/x86brew|/usr/local/x86brew/*)
            echo "ERROR: ARM64 source cannot use the x86brew CMake: ${ROSETTE_CMAKE}" >&2
            return 1
            ;;
    esac
    if [[ -n "${prefix}" ]]; then
        export PKG_CONFIG_PATH="${prefix}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
        if [[ -x "${prefix}/bin/pkg-config" ]]; then export PKG_CONFIG="${prefix}/bin/pkg-config"; fi
        export CMAKE_PREFIX_PATH="${prefix}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
        export LDFLAGS="-L${prefix}/lib ${LDFLAGS:-}"
        export CPPFLAGS="-I${prefix}/include ${CPPFLAGS:-}"
        export DYLD_LIBRARY_PATH="${prefix}/lib${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
    fi
}

rosette_configure_source_environment() {
    local source_path="${1:-}"
    local detected="unknown"
    if [[ -n "${source_path}" ]]; then
        detected="$(rosette_detect_source_architecture "${source_path}")"
    fi
    local library_architecture
    library_architecture="$(rosette_source_library_architecture "${detected}")"
    export ROSETTE_SOURCE_ARCHITECTURE="${detected}"
    export ROSETTE_LIBRARY_ARCHITECTURE="${library_architecture}"
    if [[ -n "${source_path}" ]]; then
        export ROSETTE_SOURCE_CONTAINER="$(file -b -- "${source_path}" 2>/dev/null || true)"
    else
        export ROSETTE_SOURCE_CONTAINER="source-tree"
    fi

    if [[ "${library_architecture}" == "x86_64" ]]; then
        # The x86 adapter owns all toolchain-path sanitization and keeps the
        # legacy prefix visible as a migration fallback.
        # shellcheck source=tools/rosette-macos-env.sh
        source "${_rosette_source_arch_repo_root}/tools/rosette-macos-env.sh"
        export ROSETTE_LIBRARY_PROVIDER="${ROSETTE_HOST_PREFIX:-system-x86}"
    else
        rosette_configure_arm64_environment
    fi
    export ROSETTE_SOURCE_PROVIDER="${ROSETTE_HOST_PREFIX:-system-native}"
    printf 'rosette source environment: source_architecture=%s library_architecture=%s provider=%s\n' \
        "${ROSETTE_SOURCE_ARCHITECTURE}" "${ROSETTE_LIBRARY_ARCHITECTURE}" "${ROSETTE_SOURCE_PROVIDER}"
}

rosette_verify_source_environment() {
    local architecture="${ROSETTE_LIBRARY_ARCHITECTURE:-}"
    case "${architecture}" in
        x86_64)
            [[ "${CMAKE_OSX_ARCHITECTURES:-}" == "x86_64" ]] || {
                echo "ERROR: x86 source selected, but CMAKE_OSX_ARCHITECTURES is not x86_64" >&2
                return 1
            }
            case "${PATH:-}:${PKG_CONFIG_PATH:-}:${CMAKE_PREFIX_PATH:-}:${LDFLAGS:-}:${CPPFLAGS:-}:${DYLD_LIBRARY_PATH:-}" in
                */opt/homebrew*|*/opt/homebrew/*)
                    echo "ERROR: x86 source environment still references an incompatible provider" >&2
                    return 1
                    ;;
            esac
            case "${CC:-}:${CXX:-}:${PKG_CONFIG:-}:${ROSETTE_CMAKE:-}" in
                */opt/homebrew*|*/opt/homebrew/*)
                    echo "ERROR: x86 source environment still references an incompatible tool" >&2
                    return 1
                    ;;
            esac
            ;;
        arm64)
            [[ "${CMAKE_OSX_ARCHITECTURES:-}" == "arm64" ]] || {
                echo "ERROR: native source selected, but CMAKE_OSX_ARCHITECTURES is not arm64" >&2
                return 1
            }
            case "${ROSETTE_HOST_PREFIX:-}" in
                /usr/local/x86brew|/usr/local/x86brew/*)
                    echo "ERROR: native source selected x86brew: ${ROSETTE_HOST_PREFIX}" >&2
                    return 1
                    ;;
            esac
            case "${PATH:-}:${PKG_CONFIG_PATH:-}:${CMAKE_PREFIX_PATH:-}:${LDFLAGS:-}:${CPPFLAGS:-}:${DYLD_LIBRARY_PATH:-}:${CC:-}:${CXX:-}:${PKG_CONFIG:-}:${ROSETTE_CMAKE:-}:${VULKAN_SDK:-}" in
                */usr/local/x86brew*|*/usr/local/x86brew/*)
                    echo "ERROR: native source environment still references x86brew" >&2
                    return 1
                    ;;
            esac
            ;;
        *)
            echo "ERROR: source library architecture has not been configured" >&2
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    if [[ "${1:-}" == "--detect" ]]; then
        shift
        rosette_detect_source_architecture "${1:?source image is required}"
    elif [[ "${1:-}" == "--provider" ]]; then
        shift
        rosette_source_provider_for_architecture "${1:?library architecture is required}"
    else
        rosette_configure_source_environment "${1:-}"
        rosette_verify_source_environment
    fi
fi
