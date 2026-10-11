#!/bin/bash
# Native, tiny FSI contract check; never launches or modifies Xenia.
# Usage: tools/vulkan/probe_fsi_contract.sh [/absolute/libMoltenVK.dylib ...]
set -euo pipefail
probe_root="$(cd "$(dirname "$0")/../.." && pwd)"
probe_sdk="${VULKAN_SDK:-$HOME/VulkanSDK/vulkan/macOS}"
probe_compiler="${GLSLANG_VALIDATOR:-$probe_sdk/bin/glslangValidator}"
probe_output="${FSI_PROBE_OUTPUT:-$probe_root/.rosette/diagnostics/fsi-contract-probe}"
mkdir -p "$probe_output"
if [[ ! -x "$probe_compiler" ]]; then
  probe_compiler="$(command -v glslangValidator || true)"
fi
if [[ ! -x "$probe_compiler" ]]; then
  echo "Set GLSLANG_VALIDATOR to the SDK's glslangValidator executable." >&2
  exit 2
fi
/usr/bin/clang -arch arm64 -std=c11 -Wall -Wextra -Werror \
  -I"$probe_root/pkg/vendor/sources/vulkan-headers/1.4.313/include" \
  "$probe_root/tools/vulkan/fsi_contract_probe.c" -o "$probe_output/probe"
"$probe_compiler" -V "$probe_root/tools/vulkan/fsi_probe.vert" -o "$probe_output/vert.spv"
"$probe_compiler" -V "$probe_root/tools/vulkan/fsi_probe.frag" -o "$probe_output/frag.spv"
if [[ $# == 0 ]]; then set -- "$probe_sdk/lib/libMoltenVK.dylib"; fi
probe_driver_index=0
for probe_driver in "$@"; do
  probe_driver_index=$((probe_driver_index + 1))
  probe_status=0
  # Baseline mismatches are evidence, not a setup failure. A corrected future
  # driver may pass the baseline, which is also a useful result.
  env -u FSI_PROBE_ISOLATE_SAMPLES -u FSI_PROBE_RECTANGLE_RECORD -u FSI_PROBE_RECTANGLE_TAG \
    "$probe_output/probe" "$probe_driver" \
    "$probe_output/vert.spv" "$probe_output/frag.spv" \
    > "$probe_output/driver-$probe_driver_index-baseline.log" 2>&1 || probe_status=$?
  cat "$probe_output/driver-$probe_driver_index-baseline.log"
  if [[ $probe_status -gt 1 ]]; then exit "$probe_status"; fi
  env -u FSI_PROBE_RECTANGLE_RECORD -u FSI_PROBE_RECTANGLE_TAG FSI_PROBE_ISOLATE_SAMPLES=1 \
    "$probe_output/probe" "$probe_driver" \
    "$probe_output/vert.spv" "$probe_output/frag.spv" \
    > "$probe_output/driver-$probe_driver_index-adapted.log" 2>&1
  cat "$probe_output/driver-$probe_driver_index-adapted.log"
done
echo "Adapted FSI contract passed. Evidence: $probe_output"
