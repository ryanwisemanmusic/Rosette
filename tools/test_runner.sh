#!/usr/bin/env bash
# =============================================================================
#  tools/test_runner.sh — Rosette Test Prodder
#
#  A pseudo-kernel that lets you selectively build and run test suites.
#  The menu grows automatically as you add folders under test/ and app_testing/.
#
#  Usage:
#    bash tools/test_runner.sh              # interactive menu
#    bash tools/test_runner.sh --all        # run every suite non-interactively
#    bash tools/test_runner.sh --suite win32        # run one suite by name
#    bash tools/test_runner.sh --list               # list discovered suites
#
#  Suite discovery roots:
#    test/<category>/        → Unit / ABI Tests
#    app_testing/<app>/      → App Tests
#    third_party/<lib>/test/ → Third-Party Tests  (reserved for future use)
#
#  Per-suite tuning: place a suite.cfg file inside the suite directory.
#  See app_testing/basic_snake/suite.cfg for the full option reference.
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve project root (works whether called as tools/test_runner.sh or via
# make from the repo root, or as a git submodule path)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Build settings (mirrors Makefile)
# ---------------------------------------------------------------------------
INCLUDE_DIR="${ROOT_DIR}/include"
SHIM_WIN32_DIR="${INCLUDE_DIR}/shims/win32"
SHIM_MACOS_DIR="${INCLUDE_DIR}/shims/macos"
ZIG_LIB="${ROOT_DIR}/zig-out/lib/librosette_zig.a"

DEFAULT_CC="clang"
DEFAULT_CXX="clang++"
DEFAULT_CFLAGS="-Wall -Wextra -Wno-ignored-attributes"

# macOS shim prepend (mirrors Makefile logic)
if [[ "$(uname -s)" == "Darwin" ]]; then
    MACOS_SHIM_INC="-I${SHIM_MACOS_DIR}"
else
    MACOS_SHIM_INC=""
fi

COMMON_INCLUDES="${MACOS_SHIM_INC} -I${SHIM_WIN32_DIR} -I${INCLUDE_DIR}"

# ---------------------------------------------------------------------------
# Terminal colours (gracefully degrade if not a colour terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_CYAN="\033[36m"
    C_GREEN="\033[32m"
    C_RED="\033[31m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_MAGENTA="\033[35m"
else
    C_RESET="" C_BOLD="" C_DIM="" C_CYAN="" C_GREEN=""
    C_RED="" C_YELLOW="" C_BLUE="" C_MAGENTA=""
fi

# ---------------------------------------------------------------------------
# Suite data structures
# suite_names[]  — display name
# suite_paths[]  — absolute path to the suite directory
# suite_groups[] — group label (Unit Tests / App Tests / Third-Party Tests)
# ---------------------------------------------------------------------------
declare -a suite_names=()
declare -a suite_paths=()
declare -a suite_groups=()

# ---------------------------------------------------------------------------
# discover_suites — populate the arrays above
# ---------------------------------------------------------------------------
discover_suites() {
    # --- Unit / ABI Tests: test/<category>/ ---
    if [[ -d "${ROOT_DIR}/test" ]]; then
        while IFS= read -r -d '' dir; do
            local name
            name="$(basename "${dir}")"
            # Only include directories that actually contain source files
            if find "${dir}" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) | grep -q .; then
                suite_names+=("${name}")
                suite_paths+=("${dir}")
                suite_groups+=("Unit / ABI Tests")
            fi
        done < <(find "${ROOT_DIR}/test" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi

    # --- App Tests: app_testing/<app>/ ---
    if [[ -d "${ROOT_DIR}/app_testing" ]]; then
        while IFS= read -r -d '' dir; do
            local name
            name="$(basename "${dir}")"
            if find "${dir}" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) | grep -q .; then
                suite_names+=("${name}")
                suite_paths+=("${dir}")
                suite_groups+=("App Tests")
            fi
        done < <(find "${ROOT_DIR}/app_testing" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi

    # --- Third-Party Tests: third_party/<lib>/test/ and .rosette/third_party/<lib>/test/ ---
    local tp_root tp_label
    for tp_root in "${ROOT_DIR}/third_party" "${ROOT_DIR}/.rosette/third_party"; do
        [[ -d "${tp_root}" ]] || continue
        if [[ "${tp_root}" == *".rosette"* ]]; then tp_label="ref:"; else tp_label=""; fi
        while IFS= read -r -d '' dir; do
            local name
            name="${tp_label}$(basename "$(dirname "${dir}")") /test"
            if find "${dir}" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) | grep -q .; then
                suite_names+=("${name}")
                suite_paths+=("${dir}")
                suite_groups+=("Third-Party Tests")
            fi
        done < <(find "${tp_root}" -mindepth 2 -maxdepth 2 -type d -name "test" -print0 2>/dev/null | sort -z)
    done
}

# ---------------------------------------------------------------------------
# print_banner
# ---------------------------------------------------------------------------
print_banner() {
    echo ""
    printf "${C_CYAN}${C_BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║      Rosette — Test Prodder            ║"
    echo "  ╚══════════════════════════════════════════╝"
    printf "${C_RESET}"
    echo ""
}

# ---------------------------------------------------------------------------
# print_menu — numbered list grouped by category
# ---------------------------------------------------------------------------
print_menu() {
    local current_group=""
    local idx=1

    for i in "${!suite_names[@]}"; do
        if [[ "${suite_groups[$i]}" != "${current_group}" ]]; then
            current_group="${suite_groups[$i]}"
            printf "\n  ${C_BOLD}${C_YELLOW}%s${C_RESET}\n" "${current_group}"
        fi
        printf "    ${C_CYAN}[%d]${C_RESET} %s\n" "${idx}" "${suite_names[$i]}"
        (( idx++ ))
    done

    echo ""
    printf "    ${C_CYAN}[0]${C_RESET} Run ALL suites\n"
    printf "    ${C_DIM}[q]${C_RESET} Quit\n"
    echo ""
}

# ---------------------------------------------------------------------------
# load_suite_cfg — parse suite.cfg if present, reset defaults first
# ---------------------------------------------------------------------------
load_suite_cfg() {
    local suite_dir="$1"
    # Defaults (overridable by suite.cfg)
    SUITE_CC=""          # empty = auto (clang/.cpp → clang++)
    SUITE_CFLAGS=""
    SUITE_LDFLAGS=""
    SUITE_LINK_ZIG=auto  # auto | yes | no
    SUITE_INTERACTIVE=no # yes = skip auto-run in --all mode

    local cfg="${suite_dir}/suite.cfg"
    if [[ -f "${cfg}" ]]; then
        local line key value
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line="${line%$'\r'}"
            line="${line%%#*}"
            [[ "${line}" == *"="* ]] || continue
            key="${line%%=*}"
            value="${line#*=}"
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            case "${key}" in
                SUITE_CC) SUITE_CC="${value}" ;;
                SUITE_CFLAGS) SUITE_CFLAGS="${value}" ;;
                SUITE_LDFLAGS) SUITE_LDFLAGS="${value}" ;;
                SUITE_LINK_ZIG) SUITE_LINK_ZIG="${value}" ;;
                SUITE_INTERACTIVE) SUITE_INTERACTIVE="${value}" ;;
            esac
        done < "${cfg}"
    fi
}

# ---------------------------------------------------------------------------
# ensure_zig_lib — build the Zig static library if it's missing
# ---------------------------------------------------------------------------
ensure_zig_lib() {
    if [[ ! -f "${ZIG_LIB}" ]]; then
        printf "  ${C_DIM}→ Zig library not found, building…${C_RESET}\n"
        if ! command -v zig &>/dev/null; then
            printf "  ${C_RED}✗ zig not found in PATH — cannot build ${ZIG_LIB}${C_RESET}\n"
            return 1
        fi
        (
            cd "${ROOT_DIR}" &&
                env \
                    ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-build/.zig-cache}" \
                    ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-build/.zig-cache/global}" \
                    zig build --build-file build/build.zig install
        ) || return 1
    fi
}

# ---------------------------------------------------------------------------
# run_suite — build and run all sources in a suite directory
# Returns 0 on overall pass, 1 on any failure
# ---------------------------------------------------------------------------
run_suite() {
    local suite_name="$1"
    local suite_dir="$2"
    local non_interactive="${3:-no}"  # "yes" in --all / --suite CI modes

    load_suite_cfg "${suite_dir}"

    local pass=0 fail=0 skip=0
    local start_ts end_ts elapsed

    start_ts=$(date +%s)

    printf "\n  ${C_BOLD}Suite: %s${C_RESET}  ${C_DIM}(%s)${C_RESET}\n" \
        "${suite_name}" "${suite_dir}"
    printf "  %s\n" "$(printf '─%.0s' {1..60})"

    if [[ "${suite_dir}" == "${ROOT_DIR}/app_testing/"* ]]; then
        local tmp_dir=""
        tmp_dir="$(mktemp -d /tmp/r3prodder.XXXXXX)"
        trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN
        local build_err="${tmp_dir}/build.err"
        local binary="${tmp_dir}/${suite_name}.host"

        printf "  ${C_DIM}build${C_RESET}  %-40s … " "${suite_name}"
        if bash "${ROOT_DIR}/tools/build_suite_binary.sh" "${suite_name}" "${binary}" >"${build_err}" 2>&1; then
            printf "${C_GREEN}OK${C_RESET}\n"

            if [[ "${SUITE_INTERACTIVE}" == "yes" && "${non_interactive}" == "yes" ]]; then
                printf "  ${C_DIM}run${C_RESET}    %-40s … ${C_YELLOW}SKIPPED (interactive)${C_RESET}\n" "${suite_name}"
                (( skip++ )) || true
            else
                printf "  ${C_DIM}run${C_RESET}    %-40s … " "${suite_name}"
                if "${binary}" >"${tmp_dir}/stdout.txt" 2>"${tmp_dir}/stderr.txt"; then
                    printf "${C_GREEN}PASS${C_RESET}\n"
                    (( pass++ )) || true
                else
                    printf "${C_RED}FAIL${C_RESET}\n"
                    sed 's/^/    /' "${tmp_dir}/stderr.txt" | head -n 8
                    (( fail++ )) || true
                fi
            fi
        else
            printf "${C_RED}BUILD FAIL${C_RESET}\n"
            head -n 8 "${build_err}" | sed 's/^/    /'
            (( fail++ )) || true
        fi

        end_ts=$(date +%s)
        elapsed=$(( end_ts - start_ts ))
        printf "  %s\n" "$(printf '─%.0s' {1..60})"
        printf "  ${C_DIM}elapsed: %ds   pass: %s   fail: %s   skip: %s${C_RESET}\n\n" \
            "${elapsed}" \
            "${C_GREEN}${pass}${C_RESET}${C_DIM}" \
            "${C_RED}${fail}${C_RESET}${C_DIM}" \
            "${C_YELLOW}${skip}${C_RESET}${C_DIM}"

        [[ "${fail}" -eq 0 ]]
        return
    fi

    # Should we link the Zig library?
    local link_zig="${SUITE_LINK_ZIG}"
    if [[ "${link_zig}" == "auto" ]]; then
        # Auto-detect: link if any source in this suite references zig_bridge.h
        # AND the library has been built.
        if [[ -f "${ZIG_LIB}" ]] && grep -rl 'zig_bridge' "${suite_dir}" --include='*.c' --include='*.cpp' &>/dev/null; then
            link_zig="yes"
        else
            link_zig="no"
        fi
    fi
    if [[ "${link_zig}" == "yes" ]]; then
        ensure_zig_lib || link_zig="no"
    fi

    # Gather source files
    local sources=()
    while IFS= read -r -d '' f; do
        sources+=("$f")
    done < <(find "${suite_dir}" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) -print0 | sort -z)

    if [[ ${#sources[@]} -eq 0 ]]; then
        printf "  ${C_YELLOW}⚠ No source files found in suite.${C_RESET}\n"
        return 0
    fi

    local tmp_dir=""
    tmp_dir="$(mktemp -d /tmp/r3prodder.XXXXXX)"
    trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN
    local build_err="${tmp_dir}/build.err"

    for src in "${sources[@]}"; do
        local base ext cc binary rc

        base="$(basename "${src}")"
        ext="${src##*.}"
        binary="${tmp_dir}/${base%.*}"

        # Choose compiler
        if [[ -n "${SUITE_CC}" ]]; then
            cc="${SUITE_CC}"
        elif [[ "${ext}" == "cpp" ]]; then
            cc="${DEFAULT_CXX}"
        else
            cc="${DEFAULT_CC}"
        fi

        # Build command as an array — correctly handles paths with spaces
        local cmd=("${cc}")
        # Split DEFAULT_CFLAGS on whitespace into individual flags
        read -ra _flags <<< "${DEFAULT_CFLAGS}"
        cmd+=("${_flags[@]}")
        # Include paths — each as its own quoted token
        [[ -n "${MACOS_SHIM_INC}" ]] && cmd+=("-I${SHIM_MACOS_DIR}")
        cmd+=("-I${SHIM_WIN32_DIR}" "-I${INCLUDE_DIR}")
        # Suite-level extra flags (word-split intentional here — user-controlled)
        [[ -n "${SUITE_CFLAGS}" ]] && read -ra _sf <<< "${SUITE_CFLAGS}" && cmd+=("${_sf[@]}")
        cmd+=("${src}" "-o" "${binary}")
        [[ "${link_zig}" == "yes" ]] && cmd+=("${ZIG_LIB}")
        [[ -n "${SUITE_LDFLAGS}" ]] && read -ra _lf <<< "${SUITE_LDFLAGS}" && cmd+=("${_lf[@]}")

        printf "  ${C_DIM}build${C_RESET}  %-40s … " "${base}"

        if "${cmd[@]}" 2>"${build_err}"; then
            printf "${C_GREEN}OK${C_RESET}\n"

            # Run — skip if interactive and we are in non-interactive mode
            if [[ "${SUITE_INTERACTIVE}" == "yes" && "${non_interactive}" == "yes" ]]; then
                printf "  ${C_DIM}run${C_RESET}    %-40s … ${C_YELLOW}SKIPPED (interactive)${C_RESET}\n" "${base}"
                (( skip++ )) || true
                continue
            fi

            printf "  ${C_DIM}run${C_RESET}    %-40s … " "${base}"
            if "${binary}"; then
                printf "${C_GREEN}PASS${C_RESET}\n"
                (( pass++ )) || true
            else
                rc=$?
                printf "${C_RED}FAIL (exit %d)${C_RESET}\n" "${rc}"
                (( fail++ )) || true
            fi
        else
            printf "${C_RED}BUILD FAIL${C_RESET}\n"
            # Print first few lines of compiler error, indented
            head -n 8 "${build_err}" | sed 's/^/    /'
            (( fail++ )) || true
        fi
    done

    end_ts=$(date +%s)
    elapsed=$(( end_ts - start_ts ))

    printf "  %s\n" "$(printf '─%.0s' {1..60})"
    printf "  ${C_DIM}elapsed: %ds   pass: %s   fail: %s   skip: %s${C_RESET}\n\n" \
        "${elapsed}" \
        "${C_GREEN}${pass}${C_RESET}${C_DIM}" \
        "${C_RED}${fail}${C_RESET}${C_DIM}" \
        "${C_YELLOW}${skip}${C_RESET}${C_DIM}"

    [[ "${fail}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# print_summary — final table after running one or more suites
# ---------------------------------------------------------------------------
declare -a summary_names=()
declare -a summary_results=()
declare -a summary_elapsed=()

record_result() {
    summary_names+=("$1")
    summary_results+=("$2")   # PASS | FAIL | SKIP
    summary_elapsed+=("$3")
}

print_summary() {
    local total=${#summary_names[@]}
    [[ "${total}" -eq 0 ]] && return

    printf "\n${C_BOLD}  Summary${C_RESET}\n"
    printf "  %s\n" "$(printf '─%.0s' {1..60})"
    printf "  ${C_BOLD}%-30s %-10s %s${C_RESET}\n" "Suite" "Result" "Time"
    printf "  %s\n" "$(printf '─%.0s' {1..60})"

    local overall_pass=0 overall_fail=0

    for i in "${!summary_names[@]}"; do
        local res="${summary_results[$i]}"
        local col="${C_GREEN}"
        [[ "${res}" == "FAIL" ]] && { col="${C_RED}"; (( overall_fail++ )); } || (( overall_pass++ ))
        [[ "${res}" == "SKIP" ]] && col="${C_YELLOW}"
        printf "  %-30s ${col}%-10s${C_RESET} %ss\n" \
            "${summary_names[$i]}" "${res}" "${summary_elapsed[$i]}"
    done

    printf "  %s\n" "$(printf '─%.0s' {1..60})"
    if [[ "${overall_fail}" -eq 0 ]]; then
        printf "  ${C_GREEN}${C_BOLD}All %d suite(s) passed.${C_RESET}\n\n" "${overall_pass}"
    else
        printf "  ${C_RED}${C_BOLD}%d suite(s) failed.${C_RESET}  ${C_GREEN}%d passed.${C_RESET}\n\n" \
            "${overall_fail}" "${overall_pass}"
    fi
}

# ---------------------------------------------------------------------------
# run_suite_by_index — wrapper that records into summary
# ---------------------------------------------------------------------------
run_suite_by_index() {
    local idx="$1"
    local non_interactive="${2:-no}"
    local name="${suite_names[$idx]}"
    local path="${suite_paths[$idx]}"
    local ts_start ts_end

    ts_start=$(date +%s)
    local result="PASS"
    run_suite "${name}" "${path}" "${non_interactive}" || result="FAIL"
    ts_end=$(date +%s)

    record_result "${name}" "${result}" "$(( ts_end - ts_start ))"
    [[ "${result}" == "PASS" ]]
}

# ---------------------------------------------------------------------------
# interactive_menu — prompt loop
# ---------------------------------------------------------------------------
interactive_menu() {
    local count=${#suite_names[@]}

    if [[ "${count}" -eq 0 ]]; then
        printf "${C_YELLOW}  No test suites discovered.${C_RESET}\n\n"
        printf "  Add source files to test/<category>/ or app_testing/<app>/ to get started.\n\n"
        exit 0
    fi

    while true; do
        print_banner
        print_menu

        printf "  ${C_BOLD}Select${C_RESET} > "
        read -r choice

        case "${choice}" in
            q|Q|quit|exit)
                echo ""
                exit 0
                ;;
            0)
                local overall_rc=0
                for i in "${!suite_names[@]}"; do
                    run_suite_by_index "${i}" "no" || overall_rc=1
                done
                print_summary
                printf "  Press ENTER to return to menu…"
                read -r
                summary_names=(); summary_results=(); summary_elapsed=()
                ;;
            ''|*[!0-9]*)
                printf "  ${C_RED}Invalid choice.${C_RESET}\n\n"
                sleep 0.5
                ;;
            *)
                local sel=$(( choice ))
                if (( sel >= 1 && sel <= count )); then
                    run_suite_by_index $(( sel - 1 )) "no"
                    print_summary
                    printf "  Press ENTER to return to menu…"
                    read -r
                    summary_names=(); summary_results=(); summary_elapsed=()
                else
                    printf "  ${C_RED}Choice out of range (1–%d).${C_RESET}\n\n" "${count}"
                    sleep 0.5
                fi
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# main — parse args and dispatch
# ---------------------------------------------------------------------------
MODE="menu"    # menu | all | suite | list
TARGET_SUITE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)       MODE="all";   shift ;;
        --list)      MODE="list";  shift ;;
        --suite)
            MODE="suite"
            TARGET_SUITE="${2:-}"
            [[ -z "${TARGET_SUITE}" ]] && { echo "error: --suite requires a name" >&2; exit 1; }
            shift 2
            ;;
        -h|--help)
            sed -n '/^#  Usage/,/^# ====/p' "$0" | grep '^#' | sed 's/^#  \{0,2\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

discover_suites

case "${MODE}" in
    list)
        printf "\nDiscovered suites:\n"
        for i in "${!suite_names[@]}"; do
            printf "  [%s] %s  (%s)\n" "${suite_groups[$i]}" "${suite_names[$i]}" "${suite_paths[$i]}"
        done
        echo ""
        exit 0
        ;;

    all)
        print_banner
        printf "  ${C_BOLD}Running all %d suite(s) non-interactively…${C_RESET}\n" "${#suite_names[@]}"
        overall_rc=0
        for i in "${!suite_names[@]}"; do
            run_suite_by_index "${i}" "yes" || overall_rc=1
        done
        print_summary
        exit "${overall_rc}"
        ;;

    suite)
        found=0
        for i in "${!suite_names[@]}"; do
            if [[ "${suite_names[$i]}" == "${TARGET_SUITE}" ]]; then
                print_banner
                run_suite_by_index "${i}" "yes"
                rc=$?
                print_summary
                exit "${rc}"
            fi
        done
        printf "${C_RED}error: suite '%s' not found.${C_RESET}\n" "${TARGET_SUITE}" >&2
        printf "Run with --list to see available suites.\n" >&2
        exit 1
        ;;

    menu)
        interactive_menu
        ;;
esac
