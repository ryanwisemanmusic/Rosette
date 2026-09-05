#!/usr/bin/env bash
# Rosette-owned read-only boundary for Xenia's wrapper/status scripts.
#
# Build and run execution remain explicit user actions in Xenia. This adapter
# provides status and points those actions at the Rosette-selected environment
# without silently invoking either operation.

set -euo pipefail

rosette_xenia_orchestration_help() {
    cat <<'EOF'
Rosette Xenia orchestration adapter

  rosette-xenia-orchestration.sh --status --xenia-root path
  rosette-xenia-orchestration.sh --source-architecture x86_64 --status

This command is intentionally read-only. Configure with the toolchain adapter,
then invoke Xenia's build/run command yourself.
EOF
}

xenia_root="${ROSETTE_XENIA_ROOT:-}"
source_image=""
source_architecture=""
status=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --xenia-root)
            [[ $# -ge 2 ]] || { echo "ERROR: --xenia-root requires a path" >&2; exit 2; }
            xenia_root="$2"
            shift 2
            ;;
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
        --status) status=1; shift ;;
        --help|-h) rosette_xenia_orchestration_help; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; rosette_xenia_orchestration_help >&2; exit 2 ;;
    esac
done

if [[ -n "${source_image}" || -n "${source_architecture}" ]]; then
    # shellcheck source=tools/xenia/scripts/rosette-xenia-environment.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rosette-xenia-environment.sh"
    [[ -n "${source_image}" ]] && export ROSETTE_XENIA_SOURCE_IMAGE="${source_image}"
    [[ -n "${source_architecture}" ]] && export ROSETTE_XENIA_SOURCE_ARCHITECTURE="${source_architecture}"
    if [[ -n "${source_image}" ]]; then
        rosette_xenia_configure_environment "${source_image}"
    else
        rosette_xenia_configure_environment
    fi
    rosette_xenia_verify_environment
    printf 'rosette Xenia orchestration: provider=%s target=%s\n' "$(rosette_xenia_provider_kind)" "${CMAKE_OSX_ARCHITECTURES}"
fi

if [[ "${status}" == 1 ]]; then
    [[ -n "${xenia_root}" && -d "${xenia_root}" ]] || {
        echo "ERROR: --status requires an existing --xenia-root or ROSETTE_XENIA_ROOT" >&2
        exit 1
    }
    printf 'xenia root: %s\n' "${xenia_root}"
    [[ -x "${xenia_root}/xb" ]] && printf 'xb: present\n' || printf 'xb: absent\n'
    [[ -d "${xenia_root}/build" ]] && printf 'build directory: present\n' || printf 'build directory: absent\n'
    [[ -d "${xenia_root}/src/xenia/scripts" ]] && printf 'source scripts: present\n' || printf 'source scripts: absent\n'
else
    rosette_xenia_orchestration_help
fi

