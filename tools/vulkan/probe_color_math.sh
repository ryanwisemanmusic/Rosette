#!/usr/bin/env bash
# Bounded HDR color conversion gate. No Xenia or game shaders are executed.
set -euo pipefail
color_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
color_sdk="${VULKAN_SDK:-$HOME/VulkanSDK/vulkan/macOS}"
color_output="${ROSETTE_COLOR_MATH_OUTPUT:-$color_root/.rosette/diagnostics/color-math-safe}"
mkdir -p "$color_output"
zig build-exe -O ReleaseFast -lc --dep robust \
    "-Mroot=$color_root/tools/vulkan/robust_access/harden.zig" \
    "-Mrobust=$color_root/lib/gpu/vulkan/robust_access.zig" \
    "-femit-bin=$color_output/harden"
/usr/bin/clang -arch arm64 -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$color_sdk/include" "$color_root/tools/vulkan/robust_access/probe.c" \
    -o "$color_output/probe"
"$color_sdk/bin/glslangValidator" -V \
    "$color_root/tools/vulkan/robust_access/color_math.comp" -o "$color_output/color_math.spv"
"$color_output/harden" "$color_output/color_math.spv" \
    "$color_output/color_math.hardened.spv" > "$color_output/harden.log" 2>&1
for color_shader in "$color_output/color_math.spv" "$color_output/color_math.hardened.spv"; do
    "$color_sdk/bin/spirv-val" --target-env vulkan1.2 "$color_shader"
done
if [[ $# == 0 ]]; then set -- "$color_sdk/lib/libMoltenVK.dylib"; fi
color_index=0
for color_driver in "$@"; do
    color_index=$((color_index + 1))
    "$color_output/probe" color-math "$color_driver" "$color_output" \
        > "$color_output/driver-$color_index.log" 2>&1
    cat "$color_output/driver-$color_index.log"
done
echo "Safe HDR color-math check passed. Evidence: $color_output"
