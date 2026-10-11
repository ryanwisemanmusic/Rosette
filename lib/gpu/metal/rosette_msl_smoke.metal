#include <metal_stdlib>

using namespace metal;

// Small offline compiler/caching probe. The production Vulkan route does not
// call this kernel; compiling it proves that Rosette can produce a native AIR
// object and metallib for the selected Apple SDK and target.
kernel void rosette_msl_copy_probe(
    device const uint* source [[buffer(0)]],
    device uint* destination [[buffer(1)]],
    constant uint& element_count [[buffer(2)]],
    uint index [[thread_position_in_grid]])
{
    if (index < element_count) {
        destination[index] = source[index];
    }
}
