#!/usr/bin/env bash
# Rosette-owned adapter for the diagnostic scripts in Xenia's scripts folder.
#
# Rosette already owns the runtime ledgers. This entrypoint keeps the old
# diagnostic names discoverable while making log inspection read-only and
# architecture-aware; it never starts Xenia or a debugger.

set -euo pipefail

rosette_xenia_diagnostics_list() {
    cat <<'EOF'
analyze-memory-patterns.sh
avx-and-compat-test.sh
capstone-search-pattern-for-arm64.sh
monitor-memory-live.sh
run-all-diagnostics.sh
shader-compilation-diagnostic.sh
startup-starvation-triage.sh
validate_jit.sh
vmx-detection-diagnostic.sh
x86-display-diagnostics.sh
EOF
}

rosette_xenia_diagnostics_scan_log() {
    local log="${1:?log path is required}"
    [[ -f "${log}" ]] || { echo "ERROR: diagnostic log does not exist: ${log}" >&2; return 1; }
    local pattern
    local count
    for pattern in \
        'XENIA JIT HEALTH.*(FAULT|faulted|COMPILE_FAILURE|CODE_CACHE_FAILURE|PUBLICATION_FAILURE)' \
        'READY COMPILER.*(BLOCKED|COMPILE_CHECK_FAILED)' \
        'cache-pressure' \
        'TRANSLATION ECONOMICS.*(conflict=[1-9]|stale|flush)' \
        'Vulkan.*(missing_required|degraded|fatal|failed)' \
        'provider.*(mismatch|incompatible|legacy-x86brew)'; do
        count="$(grep -E -i -c "${pattern}" "${log}" 2>/dev/null || true)"
        printf 'rosette diagnostic: matches=%s pattern=%s\n' "${count}" "${pattern}"
    done
    printf 'rosette diagnostic: log=%s\n' "${log}"
}

rosette_xenia_diagnostics_help() {
    cat <<'EOF'
Rosette Xenia diagnostics adapter

  rosette-xenia-diagnostics.sh --list
  rosette-xenia-diagnostics.sh --log path/to/rosette.log

The scan is read-only. For live runtime evidence, use Rosette's own log and
runtime gates; this adapter does not run Xenia-specific probes.
EOF
}

log=""
source_script=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list) rosette_xenia_diagnostics_list; exit 0 ;;
        --log)
            [[ $# -ge 2 ]] || { echo "ERROR: --log requires a path" >&2; exit 2; }
            log="$2"
            shift 2
            ;;
        --source-script)
            [[ $# -ge 2 ]] || { echo "ERROR: --source-script requires a name" >&2; exit 2; }
            source_script="$2"
            shift 2
            ;;
        --help|-h) rosette_xenia_diagnostics_help; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; rosette_xenia_diagnostics_help >&2; exit 2 ;;
    esac
done

if [[ -n "${source_script}" ]]; then
    case "$(basename "${source_script}")" in
        analyze-memory-patterns.sh|avx-and-compat-test.sh|capstone-search-pattern-for-arm64.sh|monitor-memory-live.sh|run-all-diagnostics.sh|shader-compilation-diagnostic.sh|startup-starvation-triage.sh|validate_jit.sh|vmx-detection-diagnostic.sh|x86-display-diagnostics.sh)
            ;;
        *) echo "ERROR: diagnostic source script is not in the declared inventory: ${source_script}" >&2; exit 1 ;;
    esac
fi
if [[ -n "${log}" ]]; then
    rosette_xenia_diagnostics_scan_log "${log}"
elif [[ -z "${source_script}" ]]; then
    rosette_xenia_diagnostics_help
fi

