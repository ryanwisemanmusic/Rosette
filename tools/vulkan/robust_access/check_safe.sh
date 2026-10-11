#!/usr/bin/env bash
# Bounds/zero-result regression. Never executes an original game shader.
set -euo pipefail
safe_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
safe_sdk="${VULKAN_SDK:-$HOME/VulkanSDK/vulkan/macOS}"
safe_output="${ROSETTE_ROBUST_CHECK_OUTPUT:-$safe_root/.rosette/diagnostics/robust-access-safe}"
mkdir -p "$safe_output"
zig test "$safe_root/lib/gpu/vulkan/robust_access.zig" > "$safe_output/unit.log" 2>&1
zig build-exe -O ReleaseFast -lc --dep robust \
    "-Mroot=$safe_root/tools/vulkan/robust_access/harden.zig" \
    "-Mrobust=$safe_root/lib/gpu/vulkan/robust_access.zig" \
    "-femit-bin=$safe_output/harden"
/usr/bin/clang -arch arm64 -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$safe_sdk/include" "$safe_root/tools/vulkan/robust_access/probe.c" \
    -o "$safe_output/probe"
"$safe_sdk/bin/glslangValidator" -V \
    "$safe_root/tools/vulkan/robust_access/relative_constant.comp" \
    -o "$safe_output/relative_constant.spv"
"$safe_output/harden" "$safe_output/relative_constant.spv" \
    "$safe_output/relative_constant.hardened.spv" > "$safe_output/harden.log" 2>&1
"$safe_sdk/bin/spirv-val" --target-env vulkan1.0 "$safe_output/relative_constant.hardened.spv"
if [[ $# == 0 ]]; then set -- "$safe_sdk/lib/libMoltenVK.dylib"; fi
safe_index=0
for safe_driver in "$@"; do
    safe_index=$((safe_index + 1))
    "$safe_output/probe" uniform-zero "$safe_driver" "$safe_output" \
        > "$safe_output/driver-$safe_index.log" 2>&1
    cat "$safe_output/driver-$safe_index.log"
done
echo "Safe robust-access check passed. Evidence: $safe_output"
