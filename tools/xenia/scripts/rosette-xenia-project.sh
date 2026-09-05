#!/usr/bin/env bash
# Rosette-owned project preflight for the Xenia script surface.
#
# Project generation is kept out of Rosette's runtime. This command verifies
# the intended source root and prints the selected configuration without
# rewriting an Xcode project.

set -euo pipefail

rosette_xenia_project_help() {
    cat <<'EOF'
Rosette Xenia project adapter

  rosette-xenia-project.sh --xenia-root path --print

The adapter is a non-destructive project preflight. Include the generated
Rosette toolchain/GTK fragments from the consuming build system instead of
rewriting project files in place.
EOF
}

xenia_root="${ROSETTE_XENIA_ROOT:-}"
print=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --xenia-root)
            [[ $# -ge 2 ]] || { echo "ERROR: --xenia-root requires a path" >&2; exit 2; }
            xenia_root="$2"
            shift 2
            ;;
        --print) print=1; shift ;;
        --help|-h) rosette_xenia_project_help; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; rosette_xenia_project_help >&2; exit 2 ;;
    esac
done
[[ -n "${xenia_root}" && -d "${xenia_root}" ]] || {
    echo "ERROR: an existing Xenia root is required" >&2
    exit 1
}
[[ -f "${xenia_root}/CMakeLists.txt" || -f "${xenia_root}/premake.lua" ]] || {
    echo "ERROR: Xenia root does not contain a recognized project definition: ${xenia_root}" >&2
    exit 1
}
if [[ "${print}" == 1 ]]; then
    printf 'rosette Xenia project preflight: root=%s\n' "${xenia_root}"
    printf 'project mutation: disabled\n'
fi

