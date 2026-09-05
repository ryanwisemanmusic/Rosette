#!/usr/bin/env bash
# Compatibility dispatcher for the source names in Xenia's scripts folder.
# The dispatcher keeps the source filename visible while the implementation
# lives in the Rosette-owned adapter for that behavior.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rosette_xenia_script_help() {
    cat <<'EOF'
Rosette Xenia script dispatcher

  rosette-xenia-script.sh setup-x86brew.sh --source-architecture x86_64 --preflight
  rosette-xenia-script.sh build-xenia-macos.sh --source-architecture x86_64 --print
  rosette-xenia-script.sh validate_jit.sh --log path/to/rosette.log

The first argument is one of the source names from Xenia's
src/xenia/scripts/ directory. No source script is edited or executed by this
dispatcher.
EOF
}

[[ $# -gt 0 ]] || { rosette_xenia_script_help >&2; exit 2; }
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    rosette_xenia_script_help
    exit 0
fi
source_script="${1##*/}"
shift

case "${source_script}" in
    setup-x86brew.sh)
        exec "${script_dir}/rosette-xenia-environment.sh" "$@"
        ;;
    build-xenia-macos.sh|xcode_build_wrapper.sh)
        exec "${script_dir}/rosette-xenia-toolchain.sh" "$@"
        ;;
    setup_xcode_gtk.sh|configure_xcode_gtk.sh)
        exec "${script_dir}/rosette-xenia-gtk.sh" "$@"
        ;;
    clang_gtk_wrapper.sh|xcode_compiler_wrapper.sh)
        exec "${script_dir}/rosette-xenia-compiler.sh" "$@"
        ;;
    xenia-linker-macos.sh)
        exec "${script_dir}/rosette-xenia-linker.sh" "$@"
        ;;
    setup_dxil_cmake_deps.sh)
        exec "${script_dir}/rosette-xenia-dxil.sh" "$@"
        ;;
    moltenvk-vulkan-diagnostic.sh|shader-compilation-diagnostic.sh|validate-moltenvk-env.sh)
        exec "${script_dir}/rosette-xenia-vulkan.sh" "$@"
        ;;
    check_entitlements.sh|entitlements_fix_3840.sh|sign-xenia-macos.sh)
        exec "${script_dir}/rosette-xenia-signing.sh" "$@"
        ;;
    create_clean_project.sh)
        exec "${script_dir}/rosette-xenia-project.sh" "$@"
        ;;
    build-wrapper.sh|run-wrapper.sh|status-wrapper.sh)
        exec "${script_dir}/rosette-xenia-orchestration.sh" "$@"
        ;;
    analyze-memory-patterns.sh|avx-and-compat-test.sh|capstone-search-pattern-for-arm64.sh|monitor-memory-live.sh|run-all-diagnostics.sh|startup-starvation-triage.sh|validate_jit.sh|vmx-detection-diagnostic.sh|x86-display-diagnostics.sh)
        exec "${script_dir}/rosette-xenia-diagnostics.sh" --source-script "${source_script}" "$@"
        ;;
    *)
        echo "ERROR: source script is not in Rosette's declared Xenia script contract: ${source_script}" >&2
        exit 1
        ;;
esac
