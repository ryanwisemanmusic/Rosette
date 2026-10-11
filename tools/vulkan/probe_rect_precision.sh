#!/bin/bash
# Safe native rendering parity gate. Uses only tiny synthetic shaders, never
# game shaders or Xenia. Compares the production rewrite with supplied corners.
# Usage: tools/vulkan/probe_rect_precision.sh [/absolute/libMoltenVK.dylib]
set -euo pipefail
probe_root="$(cd "$(dirname "$0")/../.." && pwd)"
probe_sdk="${VULKAN_SDK:-$HOME/VulkanSDK/vulkan/macOS}"
probe_output="${RECT_PRECISION_OUTPUT:-$probe_root/.rosette/diagnostics/rect-precision-probe}"
probe_driver="${1:-$probe_sdk/lib/libMoltenVK.dylib}"
mkdir -p "$probe_output/input" "$probe_output/expanded"
cd "$probe_root"
zig build-exe -O ReleaseFast -lc --dep rect --dep robust \
  -Mroot=tools/vulkan/prepare_rect_shaders.zig \
  -Mrect=lib/gpu/vulkan/rect_list_expand.zig \
  -Mrobust=lib/gpu/vulkan/robust_access.zig \
  -femit-bin="$probe_output/prepare"
/usr/bin/clang -arch arm64 -std=c11 -Wall -Wextra -Werror \
  -I"$probe_root/pkg/vendor/sources/vulkan-headers/1.4.313/include" \
  tools/vulkan/fsi_contract_probe.c -o "$probe_output/probe"
"$probe_sdk/bin/glslangValidator" -V tools/vulkan/rect_precision_guest.vert -o "$probe_output/input/vertex.spv"
"$probe_sdk/bin/glslangValidator" -V tools/vulkan/rect_precision_oracle.vert -o "$probe_output/oracle.spv"
"$probe_sdk/bin/glslangValidator" -V tools/vulkan/rect_precision.frag -o "$probe_output/fragment.spv"
"$probe_output/prepare" "$probe_output/input" "$probe_output/expanded"
for probe_shader in "$probe_output/expanded/vertex.spv" "$probe_output/oracle.spv" "$probe_output/fragment.spv"; do
  "$probe_sdk/bin/spirv-val" --target-env vulkan1.2 "$probe_shader"
done
env -u FSI_PROBE_RECTANGLE_TAG FSI_PROBE_ISOLATE_SAMPLES=1 \
  FSI_PROBE_RECTANGLE_RECORD="$probe_output/oracle.bin" \
  "$probe_output/probe" "$probe_driver" "$probe_output/oracle.spv" "$probe_output/fragment.spv" \
  > "$probe_output/oracle.log" 2>&1
FSI_PROBE_ISOLATE_SAMPLES=1 FSI_PROBE_RECTANGLE_TAG=1 \
  FSI_PROBE_RECTANGLE_RECORD="$probe_output/expanded.bin" \
  "$probe_output/probe" "$probe_driver" "$probe_output/expanded/vertex.spv" "$probe_output/fragment.spv" \
  > "$probe_output/expanded.log" 2>&1
python3 - "$probe_output" <<'PY'
from pathlib import Path
import json, struct, sys
root = Path(sys.argv[1])
oracle = (root / 'oracle.bin').read_bytes()
expanded = (root / 'expanded.bin').read_bytes()
if len(oracle) != 40960 or len(expanded) != 40960:
    raise SystemExit('Incomplete ten-case sample recording')
a = struct.unpack('<10240I', oracle)
b = struct.unpack('<10240I', expanded)
if any(not any(a[i*1024:(i+1)*1024]) for i in range(10)):
    raise SystemExit('Oracle produced an empty sample buffer')
counts = [sum(x != y for x, y in zip(a[i*1024:(i+1)*1024], b[i*1024:(i+1)*1024])) for i in range(10)]
result = {'cases': 10, 'mismatched_sample_words': sum(counts), 'per_case': counts}
(root / 'parity.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
if any(counts):
    raise SystemExit('Rectangle interpolation differs from independent corners')
print(f'Rectangle precision parity: 10/10. Evidence: {root}')
PY
