#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${package_dir}/../../../.." && pwd)"
manifest="${package_dir}/source-scripts.txt"
xenia_root="${ROSETTE_XENIA_ROOT:-/Volumes/2023 Drive/xenia/xenia}"

zig_bin="${ZIG:-zig}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/common-xenia-rosette-script-contract.XXXXXX")"
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
    rosette-xenia-environment.sh \
    rosette-xenia-toolchain.sh \
    rosette-xenia-gtk.sh \
    rosette-xenia-compiler.sh \
    rosette-xenia-linker.sh \
    rosette-xenia-dxil.sh \
    rosette-xenia-vulkan.sh \
    rosette-xenia-diagnostics.sh \
    rosette-xenia-orchestration.sh \
    rosette-xenia-project.sh \
    rosette-xenia-signing.sh \
    rosette-xenia-script.sh; do
    test -f "${repo_root}/tools/xenia/scripts/${adapter}"
    bash -n "${repo_root}/tools/xenia/scripts/${adapter}"
done

# The Xenia adapter must publish the same canonical architecture fact as the
# generic source adapter before it delegates to the shared verifier. Keep this
# smoke test host-independent: an explicit ARM64 source-tree configuration
# needs no package-manager binaries or Xenia checkout.
arm_environment_output="${tmp_dir}/arm-environment.txt"
env -i PATH="${PATH}" HOME="${HOME:-/tmp}" \
    bash "${repo_root}/tools/xenia/scripts/rosette-xenia-environment.sh" \
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
xenia_root = pathlib.Path(sys.argv[3])
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
    if not packaged.startswith("tools/xenia/scripts/"):
        raise SystemExit(f"packaged adapter is outside Rosette tools: {packaged}")
    if not (repo_root / packaged).is_file():
        raise SystemExit(f"packaged adapter is missing: {packaged}")

if xenia_root.is_dir():
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
    "${repo_root}/tools/xenia/scripts"; then
    echo "ERROR: Rosette Xenia adapters contain provisioning, destructive, or hard-coded ARM-provider behavior" >&2
    exit 1
fi

echo "common-xenia-rosette-script-contract: PASS"
