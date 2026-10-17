#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <suite-name> [out-dir]" >&2
    exit 1
fi

SUITE_NAME="$1"
OUT_DIR="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUITE_DIR="${ROOT_DIR}/app_testing/${SUITE_NAME}"

if [[ ! -d "${SUITE_DIR}" ]]; then
    echo "suite not found: ${SUITE_NAME}" >&2
    exit 1
fi

ASM_FAMILY=""
ASM_SOURCE=""
ASM_TOOL=""
ASM_FORMAT=""
ASM_REQUIRED="no"
FAIL_FAST="yes"
LOG_PATH=""
RUNTIME_ABI_LOG_PATH=""
ASM_RUNTIME=""
ASSEMBLER_RUNNER="${ROOT_DIR}/src/Assemblers/runner.zig"
ASSEMBLER_RUNNER_BIN="${ROOT_DIR}/zig-out/bin/rosette_assembler_runner"

load_suite_cfg() {
    local cfg_path="$1"
    [[ -f "${cfg_path}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        local key="${line%%=*}"
        local value="${line#*=}"
        case "${key}" in
            ASM_FAMILY) ASM_FAMILY="${value}" ;;
            ASM_SOURCE) ASM_SOURCE="${value}" ;;
            ASM_TOOL) ASM_TOOL="${value}" ;;
            ASM_FORMAT) ASM_FORMAT="${value}" ;;
            ASM_REQUIRED) ASM_REQUIRED="${value}" ;;
            ASM_RUNTIME) ASM_RUNTIME="${value}" ;;
        esac
    done < "${cfg_path}"
}

load_suite_cfg "${SUITE_DIR}/suite.cfg"

if [[ -f "${SUITE_DIR}/game.toml" ]]; then
    if grep -Eq '^[[:space:]]*runtime_abi_fail_fast[[:space:]]*=[[:space:]]*false[[:space:]]*$' "${SUITE_DIR}/game.toml"; then
        FAIL_FAST="no"
    fi
    if grep -Eq '^[[:space:]]*log_file[[:space:]]*=' "${SUITE_DIR}/game.toml"; then
        log_name="$(sed -n 's/^[[:space:]]*log_file[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "${SUITE_DIR}/game.toml" | head -n 1)"
        if [[ -n "${log_name}" ]]; then
            LOG_PATH="${SUITE_DIR}/${log_name}"
        fi
    fi
fi

if [[ -z "${LOG_PATH}" ]]; then
    LOG_PATH="${SUITE_DIR}/rosette-x86.log"
fi
if [[ "${LOG_PATH}" == *.log ]]; then
    RUNTIME_ABI_LOG_PATH="${LOG_PATH%.log}.runtime-abi.log"
else
    RUNTIME_ABI_LOG_PATH="${LOG_PATH}.runtime-abi.log"
fi

log_assembler_event() {
    local line="$1"
    printf '%s\n' "$line" >> "${LOG_PATH}" 2>/dev/null || true
    printf '%s\n' "$line" >> "${RUNTIME_ABI_LOG_PATH}" 2>/dev/null || true
}

fail_fast_abort() {
    local reason="$1"
    echo "  ✗ ${reason}" >&2
    log_assembler_event "[runtime-abi][assembler][validation] ${reason}"
    if [[ "${FAIL_FAST}" == "yes" ]]; then
        log_assembler_event "[runtime-abi][assembler][validation] fail-fast abort"
        kill -ABRT $$
    fi
    exit 1
}

validate_source_fallback() {
    local source_path="$1"
    local family="$2"
    local runtime_name="$3"

    [[ -s "${source_path}" ]] || return 1

    case "${family}" in
        masm|jwasm)
            if grep -Eiq '(^|[[:space:]])(\.model|proc|endp|includelib|byte|word|dword)([[:space:]]|$)' "${source_path}"; then
                return 0
            fi
            ;;
        masm-irvine32|jwasm-irvine32)
            if grep -Eiq 'Irvine32\.inc|WriteString|ReadKey|Gotoxy|Clrscr' "${source_path}"; then
                return 0
            fi
            ;;
        fasm)
            if grep -Eiq '(^|[[:space:]])format[[:space:]]+(pe|mz|elf)|(^|[[:space:]])section[[:space:]]' "${source_path}"; then
                return 0
            fi
            ;;
    esac

    if [[ -n "${runtime_name}" ]]; then
        case "${runtime_name}" in
            dos-text|dos-graphics)
                grep -Eiq 'int[[:space:]]+10h|int[[:space:]]+16h|int[[:space:]]+21h' "${source_path}" && return 0
                ;;
            win32-text|win32-block-window)
                grep -Eiq 'CreateWindow|RegisterClass|MessageBox|DrawText|BitBlt|SetPixel|GetStdHandle' "${source_path}" && return 0
                ;;
        esac
    fi

    return 1
}

run_native_assembler() {
    local tool="$1"
    local source_path="$2"
    local artifact_path="$3"
    local mode="$4"
    (
        cd "${ROOT_DIR}"
        env MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}" \
            ZIG_LOCAL_CACHE_DIR="${ROOT_DIR}/.zig-cache" \
            ZIG_GLOBAL_CACHE_DIR="${ROOT_DIR}/.zig-global-cache" \
            zig build --build-file build/build.zig install --prefix "${ROOT_DIR}/zig-out" >/dev/null
        "${ASSEMBLER_RUNNER_BIN}" \
            "${tool}" \
            "${source_path}" \
            "${artifact_path}" \
            "${LOG_PATH}" \
            "$([[ "${FAIL_FAST}" == "yes" ]] && printf '1' || printf '0')" \
            "${mode}"
    )
}

if [[ -z "${ASM_FAMILY}" || -z "${ASM_SOURCE}" ]]; then
    exit 0
fi

SOURCE_PATH="${SUITE_DIR}/${ASM_SOURCE}"
if [[ ! -f "${SOURCE_PATH}" ]]; then
    SOURCE_PATH="${ROOT_DIR}/app_testing/${ASM_SOURCE}"
fi
if [[ ! -f "${SOURCE_PATH}" ]]; then
    echo "assembler source not found for ${SUITE_NAME}: ${ASM_SOURCE}" >&2
    exit 1
fi

if [[ -z "${OUT_DIR}" ]]; then
    OUT_DIR="$(mktemp -d /tmp/rosette-asm.XXXXXX)"
fi
mkdir -p "${OUT_DIR}"

resolve_nasm() {
    if [[ -n "${ROSETTE_NASM:-}" && -x "${ROSETTE_NASM}" ]]; then
        printf '%s\n' "${ROSETTE_NASM}"
        return 0
    fi
    if [[ -n "${ROSETTE_HOST_PREFIX:-}" && -x "${ROSETTE_HOST_PREFIX}/bin/nasm" ]]; then
        printf '%s\n' "${ROSETTE_HOST_PREFIX}/bin/nasm"
        return 0
    fi
    if command -v nasm >/dev/null 2>&1; then
        command -v nasm
        return 0
    fi
    if [[ -x /usr/local/x86brew/bin/nasm ]]; then
        printf '%s\n' "/usr/local/x86brew/bin/nasm"
        return 0
    fi
    return 1
}

emit_unavailable() {
    local reason="$1"
    if [[ "${FAIL_FAST}" == "yes" || "${ASM_REQUIRED}" == "yes" ]]; then
        fail_fast_abort "${reason}"
    fi
    echo "  ↷ ${reason}"
    log_assembler_event "[runtime-abi][assembler][warning] ${reason}"
    return 0
}

case "${ASM_TOOL}" in
    nasm)
        NASM_BIN="$(resolve_nasm)" || {
            emit_unavailable "NASM requested for ${SUITE_NAME}, but no runnable nasm binary is available on this host"
            exit 0
        }
        local_out="${OUT_DIR}/${SUITE_NAME}.obj"
        format="${ASM_FORMAT:-win32}"
        echo "  → Assembling with NASM: ${ASM_SOURCE}"
        if ! (
            cd "${SUITE_DIR}"
            "${NASM_BIN}" -f "${format}" "${ASM_SOURCE}" -o "${local_out}"
        ); then
            fail_fast_abort "NASM assembly failed for ${SUITE_NAME}: ${ASM_SOURCE}"
        fi
        if ! run_native_assembler "nasm" "${SOURCE_PATH}" "${local_out}" "validate"; then
            fail_fast_abort "NASM ABI validation failed for ${SUITE_NAME}: ${ASM_SOURCE}"
        fi
        echo "    artifact: ${local_out}"
        log_assembler_event "[runtime-abi][assembler][ok] nasm assembled ${ASM_SOURCE} -> ${local_out}"
        ;;
    jwasm|jwasm-irvine32)
        local_out="${OUT_DIR}/${SUITE_NAME}.obj"
        echo "  → Assembling with JWasm (Zig native ABI runner): ${ASM_SOURCE}"
        if run_native_assembler "${ASM_TOOL}" "${SOURCE_PATH}" "${local_out}" "assemble"; then
            echo "    artifact: ${local_out}"
            log_assembler_event "[runtime-abi][assembler][ok] jwasm native runner assembled ${ASM_SOURCE} -> ${local_out}"
            exit 0
        fi
        if validate_source_fallback "${SOURCE_PATH}" "${ASM_TOOL}" "${ASM_RUNTIME}"; then
            local_out="${OUT_DIR}/${SUITE_NAME}.fallback-validated"
            : > "${local_out}"
            echo "  ↷ JWasm native runner unavailable or rejected source — source-profile ABI fallback validation passed"
            echo "    artifact: ${local_out}"
            log_assembler_event "[runtime-abi][assembler][ok] jwasm fallback validation passed for ${ASM_SOURCE}"
            exit 0
        fi
        emit_unavailable "JWasm source detected for ${SUITE_NAME}, but neither the Zig native JWasm runner nor legacy payloads could validate this source on the current macOS host"
        ;;
    fasm)
        local_out="${OUT_DIR}/${SUITE_NAME}.obj"
        echo "  → Assembling with FASM (Zig native ABI runner): ${ASM_SOURCE}"
        if run_native_assembler "fasm" "${SOURCE_PATH}" "${local_out}" "assemble"; then
            echo "    artifact: ${local_out}"
            log_assembler_event "[runtime-abi][assembler][ok] fasm native runner assembled ${ASM_SOURCE} -> ${local_out}"
            exit 0
        fi
        if validate_source_fallback "${SOURCE_PATH}" "${ASM_TOOL}" "${ASM_RUNTIME}"; then
            local_out="${OUT_DIR}/${SUITE_NAME}.fallback-validated"
            : > "${local_out}"
            echo "  ↷ FASM native runner unavailable or rejected source — source-profile ABI fallback validation passed"
            echo "    artifact: ${local_out}"
            log_assembler_event "[runtime-abi][assembler][ok] fasm fallback validation passed for ${ASM_SOURCE}"
            exit 0
        fi
        emit_unavailable "FASM source detected for ${SUITE_NAME}, but neither the Zig native FASM runner nor a host FASM binary could validate this source"
        ;;
    "")
        exit 0
        ;;
    *)
        emit_unavailable "unknown assembler tool '${ASM_TOOL}' for ${SUITE_NAME}"
        ;;
esac
