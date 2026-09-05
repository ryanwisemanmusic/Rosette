#!/usr/bin/env bash
# Rosette-owned replacement for Xenia's x86brew setup script.
#
# This file is sourceable. It selects a provider and exports an environment;
# it never installs a provider, changes a shell profile, or deletes a failed
# installation. The source image is authoritative. A Xenia source tree has no
# executable header to inspect, so it must pass --source-architecture.

set -euo pipefail

if [[ -n "${BASH_VERSION:-}" ]]; then
    _rosette_xenia_env_source_path="${BASH_SOURCE[0]}"
    _rosette_xenia_env_direct=false
    [[ "${BASH_SOURCE[0]}" == "${0}" ]] && _rosette_xenia_env_direct=true
else
    _rosette_xenia_env_source_path="${(%):-%x}"
    _rosette_xenia_env_direct=false
fi
_rosette_xenia_env_script_dir="$(cd "$(dirname "${_rosette_xenia_env_source_path}")" && pwd)"
_rosette_xenia_env_repo_root="$(cd "${_rosette_xenia_env_script_dir}/../../.." && pwd)"

# shellcheck source=tools/rosette-source-architecture.sh
source "${_rosette_xenia_env_repo_root}/tools/rosette-source-architecture.sh"

rosette_xenia_configure_environment() {
    local source_image="${ROSETTE_XENIA_SOURCE_IMAGE:-}"
    local requested_architecture="${ROSETTE_XENIA_SOURCE_ARCHITECTURE:-}"
    local detected_architecture=""

    if [[ "${1:-}" == "--source-image" ]]; then
        [[ $# -ge 2 ]] || { echo "ERROR: --source-image requires a path" >&2; return 2; }
        source_image="$2"
    elif [[ "${1:-}" == "--source-architecture" ]]; then
        [[ $# -ge 2 ]] || { echo "ERROR: --source-architecture requires a value" >&2; return 2; }
        requested_architecture="$2"
    elif [[ $# -gt 0 ]]; then
        source_image="$1"
    fi

    if [[ -n "${source_image}" ]]; then
        detected_architecture="$(rosette_detect_source_architecture "${source_image}")"
        if [[ "${detected_architecture}" == "unknown" ]]; then
            echo "ERROR: source image has no recognized x86-64 or ARM64 identity: ${source_image}" >&2
            return 1
        fi
        requested_architecture="${detected_architecture}"
    fi

    case "${requested_architecture}" in
        x86_64|arm64)
            ;;
        "")
            echo "ERROR: source architecture is required; pass --source-image or --source-architecture" >&2
            return 1
            ;;
        *)
            echo "ERROR: unsupported source architecture: ${requested_architecture}" >&2
            return 1
            ;;
    esac

    if [[ "${requested_architecture}" == "x86_64" ]]; then
        # This is the existing Rosette-owned x86 toolchain adapter. Its only
        # compatibility fallback is the visible legacy prefix; it does not
        # provision that prefix.
        # shellcheck source=tools/rosette-macos-env.sh
        source "${_rosette_xenia_env_repo_root}/tools/rosette-macos-env.sh"
        export ROSETTE_XENIA_LIBRARY_ARCHITECTURE="x86_64"
    else
        # The public source adapter owns ARM path sanitization. It deliberately
        # removes inherited x86brew references before adding a native prefix.
        rosette_configure_arm64_environment
        export ROSETTE_XENIA_LIBRARY_ARCHITECTURE="arm64"
    fi

    # Keep the shared source-environment verifier authoritative even when the
    # caller supplied a Xenia source-tree architecture instead of a source
    # image. The generic adapter normally establishes these two variables
    # before delegating to the same verifier; Xenia must publish the equivalent
    # facts explicitly so an ARM64 preflight cannot pass through an unbound
    # architecture state.
    export ROSETTE_SOURCE_ARCHITECTURE="${requested_architecture}"
    export ROSETTE_LIBRARY_ARCHITECTURE="${ROSETTE_XENIA_LIBRARY_ARCHITECTURE}"
    export ROSETTE_XENIA_SOURCE_ARCHITECTURE="${requested_architecture}"
    export ROSETTE_XENIA_SOURCE_IMAGE="${source_image}"
    export ROSETTE_XENIA_SOURCE_CONTAINER="${ROSETTE_SOURCE_CONTAINER:-source-tree}"
    export ROSETTE_XENIA_PROVIDER_ROOT="${ROSETTE_HOST_PREFIX:-}"
    export ROSETTE_XENIA_TARGET_ARCHITECTURE="${ROSETTE_XENIA_LIBRARY_ARCHITECTURE}"

    case "${ROSETTE_XENIA_SOURCE_ARCHITECTURE}:${ROSETTE_XENIA_PROVIDER_ROOT}" in
        x86_64:/opt/homebrew|x86_64:/opt/homebrew/*)
            echo "ERROR: x86 source selected the ARM64 provider: ${ROSETTE_XENIA_PROVIDER_ROOT}" >&2
            return 1
            ;;
        arm64:/usr/local/x86brew|arm64:/usr/local/x86brew/*)
            echo "ERROR: ARM64 source selected the legacy x86brew provider: ${ROSETTE_XENIA_PROVIDER_ROOT}" >&2
            return 1
            ;;
    esac

    export CMAKE_OSX_ARCHITECTURES="${ROSETTE_XENIA_TARGET_ARCHITECTURE}"
    export ROSETTE_XENIA_CONFIGURED=1
    printf 'rosette Xenia environment: source=%s libraries=%s provider=%s\n' \
        "${ROSETTE_XENIA_SOURCE_ARCHITECTURE}" \
        "${ROSETTE_XENIA_LIBRARY_ARCHITECTURE}" \
        "${ROSETTE_XENIA_PROVIDER_ROOT:-system-native}"
}

rosette_xenia_provider_kind() {
    local provider="${ROSETTE_XENIA_PROVIDER_ROOT:-}"
    local managed_root="${ROSETTE_MACOS_HOST_ROOT:-${_rosette_xenia_env_repo_root}/.rosette/macos-host}"
    case "${provider}" in
        "${managed_root}"|"${managed_root}"/*)
            printf '%s\n' "rosette-managed"
            ;;
        /usr/local/x86brew|/usr/local/x86brew/*)
            printf '%s\n' "legacy-x86brew-migration-fallback"
            ;;
        /usr/local|/usr/local/*)
            printf '%s\n' "system-x86"
            ;;
        /opt/homebrew|/opt/homebrew/*)
            printf '%s\n' "native-arm64"
            ;;
        "")
            printf '%s\n' "system-native"
            ;;
        *)
            printf '%s\n' "explicit-provider"
            ;;
    esac
}

rosette_xenia_verify_environment() {
    [[ "${ROSETTE_XENIA_CONFIGURED:-0}" == "1" ]] || {
        echo "ERROR: Rosette Xenia environment has not been configured" >&2
        return 1
    }
    [[ "${ROSETTE_XENIA_SOURCE_ARCHITECTURE:-}" == "x86_64" ||
        "${ROSETTE_XENIA_SOURCE_ARCHITECTURE:-}" == "arm64" ]] || {
        echo "ERROR: configured source architecture is not concrete" >&2
        return 1
    }
    [[ "${ROSETTE_XENIA_LIBRARY_ARCHITECTURE:-}" == "${CMAKE_OSX_ARCHITECTURES:-}" ]] || {
        echo "ERROR: library and CMake architectures disagree" >&2
        return 1
    }

    case "${ROSETTE_XENIA_SOURCE_ARCHITECTURE}:${ROSETTE_XENIA_PROVIDER_ROOT:-}" in
        x86_64:/opt/homebrew|x86_64:/opt/homebrew/*|arm64:/usr/local/x86brew|arm64:/usr/local/x86brew/*)
            echo "ERROR: selected provider is incompatible with the source architecture" >&2
            return 1
            ;;
    esac

    if [[ "${ROSETTE_XENIA_SOURCE_ARCHITECTURE}" == "x86_64" ]]; then
        rosette_verify_macos_host
    else
        rosette_verify_source_environment
    fi

    printf 'rosette Xenia environment: verified provider_kind=%s target=%s\n' \
        "$(rosette_xenia_provider_kind)" "${CMAKE_OSX_ARCHITECTURES}"
}

rosette_xenia_print_environment() {
    printf 'ROSETTE_XENIA_SOURCE_ARCHITECTURE=%s\n' "${ROSETTE_XENIA_SOURCE_ARCHITECTURE:-}"
    printf 'ROSETTE_XENIA_LIBRARY_ARCHITECTURE=%s\n' "${ROSETTE_XENIA_LIBRARY_ARCHITECTURE:-}"
    printf 'ROSETTE_XENIA_PROVIDER_ROOT=%s\n' "${ROSETTE_XENIA_PROVIDER_ROOT:-}"
    printf 'ROSETTE_XENIA_PROVIDER_KIND=%s\n' "$(rosette_xenia_provider_kind)"
    printf 'CMAKE_OSX_ARCHITECTURES=%s\n' "${CMAKE_OSX_ARCHITECTURES:-}"
    printf 'CC=%s\n' "${CC:-}"
    printf 'CXX=%s\n' "${CXX:-}"
    printf 'PKG_CONFIG=%s\n' "${PKG_CONFIG:-}"
    printf 'PKG_CONFIG_PATH=%s\n' "${PKG_CONFIG_PATH:-}"
    printf 'CMAKE_PREFIX_PATH=%s\n' "${CMAKE_PREFIX_PATH:-}"
    printf 'LDFLAGS=%s\n' "${LDFLAGS:-}"
    printf 'CPPFLAGS=%s\n' "${CPPFLAGS:-}"
}

rosette_xenia_environment_help() {
    cat <<'EOF'
Rosette Xenia environment

Source this file and configure it with a concrete source image or source
architecture. The selected provider is exported for the other Rosette-owned
script adapters.

  source tools/xenia/scripts/rosette-xenia-environment.sh
  rosette_xenia_configure_environment --source-image title.exe
  rosette_xenia_verify_environment

For a Xenia source tree, where there is no executable header:

  rosette_xenia_configure_environment --source-architecture x86_64

The adapter is a preflight/configuration boundary. It does not provision a
package manager and it does not build or run Xenia.
EOF
}

if [[ "${_rosette_xenia_env_direct}" == true ]]; then
    source_image=""
    source_architecture=""
    verify=0
    print=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source-image)
                [[ $# -ge 2 ]] || { echo "ERROR: --source-image requires a path" >&2; exit 2; }
                source_image="$2"
                shift 2
                ;;
            --source-architecture)
                [[ $# -ge 2 ]] || { echo "ERROR: --source-architecture requires a value" >&2; exit 2; }
                source_architecture="$2"
                shift 2
                ;;
            --verify) verify=1; shift ;;
            --print) print=1; shift ;;
            --help|-h) rosette_xenia_environment_help; exit 0 ;;
            *) echo "ERROR: unknown argument: $1" >&2; rosette_xenia_environment_help >&2; exit 2 ;;
        esac
    done
    [[ -n "${source_image}" ]] && export ROSETTE_XENIA_SOURCE_IMAGE="${source_image}"
    [[ -n "${source_architecture}" ]] && export ROSETTE_XENIA_SOURCE_ARCHITECTURE="${source_architecture}"
    if [[ -n "${source_image}" ]]; then
        rosette_xenia_configure_environment "${source_image}"
    else
        rosette_xenia_configure_environment
    fi
    [[ "${verify}" == 1 ]] && rosette_xenia_verify_environment
    [[ "${print}" == 1 ]] && rosette_xenia_print_environment
fi
