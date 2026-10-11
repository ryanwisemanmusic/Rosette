#!/usr/bin/env bash
# Offline GPU check of Xenia's FSI occlusion counter. For every unique fragment-interlock module in a
# saved shader archive it applies Rosette's production rewrite (rectangle + coordinate + robust), then
# runs that module through the attachment-less FSI pass on MoltenVK the way Xenia drives a query:
# stale counter contents, vkCmdFillBuffer, a barrier, one full-screen draw. The counter must equal the
# number of covered samples. Only the production-rewritten modules are dispatched, never an original
# game shader, and no Xenia, Rosette guest or window is involved.
#
#   probe_zpd_count.sh SHADER_ARCHIVE_DIR [OUTPUT_DIR]
#
# SHADER_ARCHIVE_DIR is a run's vulkan-shaders directory (module-*-HASH.guest.spv files).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sdk="${VULKAN_SDK:-$HOME/VulkanSDK/vulkan/macOS}"
archive="${1:?usage: probe_zpd_count.sh SHADER_ARCHIVE_DIR [OUTPUT_DIR]}"
out="${2:-$root/.rosette/diagnostics/zpd-count}"
mkdir -p "$out/original"
python3 - "$archive" "$out/original" <<'PY'
import os, shutil, struct, sys
source, target = sys.argv[1:3]
seen, kept = set(), 0
for name in sorted(os.listdir(source)):
    if not name.endswith(".guest.spv"):
        continue
    digest = name.split("-")[-1].split(".")[0]
    if digest in seen:
        continue
    seen.add(digest)
    words = struct.unpack("<%dI" % (os.path.getsize(os.path.join(source, name)) // 4),
                          open(os.path.join(source, name), "rb").read()[: os.path.getsize(os.path.join(source, name)) // 4 * 4])
    index, interlock, fragment = 5, False, False
    while index < len(words):
        count, op = words[index] >> 16, words[index] & 0xFFFF
        if count == 0 or op == 54:
            break
        interlock |= op == 17 and words[index + 1] in (5363, 5378, 5379)
        fragment |= op == 15 and words[index + 1] == 4
        index += count
    if interlock and fragment:
        shutil.copy(os.path.join(source, name), os.path.join(target, digest + ".spv"))
        kept += 1
print("unique fragment-interlock modules:", kept)
PY
zig build-exe -O ReleaseFast -lc --dep rect --dep robust --dep sampling \
    "-Mroot=$root/tools/vulkan/prepare_fsi_shaders.zig" \
    "-Mrect=$root/lib/gpu/vulkan/rect_list_expand.zig" \
    "-Mrobust=$root/lib/gpu/vulkan/robust_access.zig" \
    "-Msampling=$root/lib/gpu/vulkan/fsi/pixel_frequency.zig" \
    "-femit-bin=$out/prepare_fsi"
"$out/prepare_fsi" "$out/original" "$out/production" > "$out/prepare.log" 2>&1
/usr/bin/clang -arch arm64 -std=c11 -O2 -Wall -Wextra -Werror -I "$sdk/include" \
    "$root/tools/vulkan/robust_access/probe.c" -o "$out/probe"
"$sdk/bin/glslangValidator" -V "$root/tools/vulkan/robust_access/interpolators.vert" -o "$out/interpolators.spv" > /dev/null
export MVK_CONFIG_RESUME_LOST_DEVICE=0 MVK_CONFIG_FAST_MATH_ENABLED=0
status=0
"$out/probe" zpd-count "${ROSETTE_PROBE_DRIVER:-$sdk/lib/libMoltenVK.dylib}" "$out/original" "$out/production" \
    "$out/interpolators.spv" > "$out/zpd.log" 2>&1 || status=$?
python3 - "$out/zpd.log" <<'PY'
import re, sys
rows = re.findall(r"^ZPD (\S+) msaa=(\d)x depth=(\d) counter=(\d+) covered_samples=(\d+)", open(sys.argv[1]).read(), re.M)
for config in sorted({r[1] for r in rows}):
    chosen = [r for r in rows if r[1] == config]
    exact = sum(int(r[3]) == int(r[4]) for r in chosen)
    zero = sum(int(r[3]) == 0 for r in chosen)
    over = sum(int(r[3]) > int(r[4]) for r in chosen)
    print(f"msaa={config}x: {len(chosen)} modules, {exact} exact, {zero} counted nothing, {over} over-counted")
PY
echo "zpd-count exit status $status. Evidence: $out"
exit "$status"
