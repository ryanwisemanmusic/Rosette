#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${package_dir}/../../../.." && pwd)"
manifest="${package_dir}/source-scripts.txt"
xenia_root="${ROSETTE_XENIA_ROOT:-${XENIA_ROOT:-}}"

zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-console-rosette-script-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"${zig_bin}" test \
    --cache-dir "${tmp_dir}/native-cache" \
    --global-cache-dir "${tmp_dir}/native-global-cache" \
    "${package_dir}/src/root.zig"

for target in aarch64-freestanding x86_64-freestanding; do
    output="${tmp_dir}/${target}.a"
    "${zig_bin}" build-lib "${package_dir}/src/root.zig" \
        --cache-dir "${tmp_dir}/${target}-cache" \
        --global-cache-dir "${tmp_dir}/${target}-global-cache" \
        -target "${target}" -O Debug -femit-bin="${output}" >/dev/null
    test -s "${output}"
done

for adapter in \
    rosette-guest-environment.sh \
    rosette-guest-toolchain.sh \
    rosette-guest-gtk.sh \
    rosette-guest-compiler.sh \
    rosette-guest-linker.sh \
    rosette-guest-dxil.sh \
    rosette-guest-vulkan.sh \
    rosette-guest-diagnostics.sh \
    rosette-guest-orchestration.sh \
    rosette-guest-project.sh \
    rosette-guest-signing.sh \
    rosette-guest-windows.sh \
    rosette-guest-script.sh; do
    test -f "${repo_root}/tools/guest_runtime/scripts/${adapter}"
    bash -n "${repo_root}/tools/guest_runtime/scripts/${adapter}"
done

windows_template_dir="${repo_root}/tools/guest_runtime/windows"
for template in \
    CMakeLists.windows.in \
    windows-toolchain.cmake.in \
    clang-c-wrapper.sh.in \
    clang-cxx-wrapper.sh.in \
    windres-wrapper.sh.in \
    wine.in \
    guest_windows_compat.h \
    guest_cxx_compat.h.in \
    intrin.h.in \
    mm3dnow.h \
    libusb-config.h \
    DXProgrammableCapture.h \
    ShlObj_core.h \
    README.md; do
    test -f "${windows_template_dir}/${template}"
done
for template in "${windows_template_dir}"/*.sh.in; do
    bash -n "${template}"
done
bash "${repo_root}/tools/guest_runtime/scripts/rosette-guest-windows.sh" --help >/dev/null
if rg -n '/tmp/xenia-canary|/Users/ryanwiseman|/Volumes/2023 Drive' \
    "${windows_template_dir}" \
    "${repo_root}/tools/guest_runtime/scripts/rosette-guest-windows.sh"; then
    echo "ERROR: Windows build capsule contains disposable or machine-specific paths" >&2
    exit 1
fi
portability_sources=(
    "${repo_root}/build/Makefile"
    "${repo_root}/build.zig"
    "${repo_root}/src/tooling/exe_parser/native_windows_graphics.zig"
    "${repo_root}/tools/build_identity_manifest.py"
    "${repo_root}/tools/check_vendor_libraries.py"
    "${repo_root}/gen_batch13.py"
    "${repo_root}/update_batch13.py"
    "${repo_root}/tools/gen_abi_gap_batch.py"
    "${repo_root}/tools/vulkan/check_hdr_float16.py"
    "${repo_root}/tools/guest_runtime/scripts/rosette-guest-run.sh"
)
if rg -n '/Users/ryanwiseman|/Volumes/2023 Drive|/Applications/Xcode\.app|/opt/homebrew/opt/llvm' "${portability_sources[@]}"; then
    echo "ERROR: Rosette build/runtime inputs contain a machine-specific development path" >&2
    exit 1
fi
echo "Rosette and Xenia path portability: machine-specific path scan PASS"
echo "rosette Xenia Windows build capsule: template coverage PASS"

# The macOS compatibility entrypoints are shipped beside Xenia and resolve
# Rosette through its install registry. Check them whenever an external Xenia
# checkout is available, without making source-only Rosetta checks depend on
# the removable checkout.
if [[ -n "$xenia_root" && -d "$xenia_root/macos" ]]; then
    for adapter in build-async.sh build-scratch-async.sh rosette-root.sh; do
        test -f "${xenia_root}/macos/${adapter}"
        bash -n "${xenia_root}/macos/${adapter}"
    done
    if rg -n '/Users/ryanwiseman|/Volumes/2023 Drive' \
        "${xenia_root}/macos/build-async.sh" \
        "${xenia_root}/macos/build-scratch-async.sh" \
        "${xenia_root}/macos/rosette-root.sh"; then
        echo "ERROR: Xenia macOS adapters contain machine-specific paths" >&2
        exit 1
    fi
    fixture_home="${tmp_dir}/root-discovery-home"
    fixture_root="${tmp_dir}/rosette-checkout"
    mkdir -p "${fixture_home}/.rosette" "${fixture_root}/tools/guest_runtime/scripts"
    : > "${fixture_root}/tools/guest_runtime/scripts/rosette-guest-run.sh"
    chmod +x "${fixture_root}/tools/guest_runtime/scripts/rosette-guest-run.sh"
    printf '%s\n' "${fixture_root}" > "${fixture_home}/.rosette/source-root"
    resolved_root="$(env -i HOME="${fixture_home}" PATH="${PATH}" bash -c \
        'source "$1"; rosette_resolve_root' _ "${xenia_root}/macos/rosette-root.sh")"
    test "${resolved_root}" = "${fixture_root}"
    echo "Xenia macOS Rosette-root discovery: install registry PASS"
fi

# The Xenia adapter must publish the same canonical architecture fact as the
# generic source adapter before it delegates to the shared verifier. Keep this
# smoke test host-independent: an explicit ARM64 source-tree configuration
# needs no package-manager binaries or Xenia checkout.
arm_environment_output="${tmp_dir}/arm-environment.txt"
env -i PATH="${PATH}" HOME="${HOME:-/tmp}" \
    bash "${repo_root}/tools/guest_runtime/scripts/rosette-guest-environment.sh" \
    --source-architecture arm64 --verify --print > "${arm_environment_output}"
grep -q '^ROSETTE_XENIA_SOURCE_ARCHITECTURE=arm64$' "${arm_environment_output}"
grep -q '^ROSETTE_XENIA_LIBRARY_ARCHITECTURE=arm64$' "${arm_environment_output}"
if grep -q '/usr/local/x86brew' "${arm_environment_output}"; then
    echo "ERROR: ARM64 Xenia environment retained an x86brew path" >&2
    exit 1
fi
echo "rosette Xenia environment: clean ARM64 verification PASS"

python3 - "${manifest}" "${repo_root}" "${xenia_root}" <<'PY'
import pathlib
import subprocess
import sys

manifest = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])
xenia_root = pathlib.Path(sys.argv[3]) if sys.argv[3] else None
rows = []
for line in manifest.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    fields = line.split("\t")
    if len(fields) != 3 or any(not field for field in fields):
        raise SystemExit(f"invalid manifest row: {line!r}")
    source, category, packaged = fields
    rows.append((source, category, packaged))

if len(rows) != 28:
    raise SystemExit(f"expected 28 source scripts, found {len(rows)}")
if len({source for source, _, _ in rows}) != len(rows):
    raise SystemExit("duplicate source script in manifest")
if len({packaged for _, _, packaged in rows}) < 8:
    raise SystemExit("manifest collapsed the script surface too aggressively")

for source, category, packaged in rows:
    if not source.startswith("src/xenia/scripts/"):
        raise SystemExit(f"source is outside the requested Xenia scripts folder: {source}")
    if not packaged.startswith("tools/guest_runtime/scripts/"):
        raise SystemExit(f"packaged adapter is outside Rosette tools: {packaged}")
    if not (repo_root / packaged).is_file():
        raise SystemExit(f"packaged adapter is missing: {packaged}")

if xenia_root is not None and xenia_root.is_dir():
    actual = sorted(
        path.relative_to(xenia_root).as_posix()
        for path in (xenia_root / "src/xenia/scripts").glob("*.sh")
    )
    expected = sorted(source for source, _, _ in rows)
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise SystemExit(f"Xenia script inventory drift: missing={missing} extra={extra}")
    for source, _, _ in rows:
        source_path = xenia_root / source
        result = subprocess.run(["bash", "-n", str(source_path)], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"source syntax warning (reference retained; Rosette adapter is authoritative): {source}")
else:
    print("rosette script contract: external Xenia tree not present; source inventory deferred")

print("rosette script contract: manifest and adapter coverage PASS")
PY

if rg -n -i \
    'brew[[:space:]]+(update|install|upgrade|uninstall)|sudo[[:space:]]+rm|rm[[:space:]]+-rf|git[[:space:]]+clone' \
    "${repo_root}/tools/guest_runtime/scripts"; then
    echo "ERROR: Rosette Xenia adapters contain provisioning, destructive, or hard-coded ARM-provider behavior" >&2
    exit 1
fi

echo "common-console-rosette-script-contract: PASS"
