#include "contracts.h"

// Bounded compiler/GPU contract entry; helpers above can be included by future
// translated render shaders. No game microcode is dispatched by its tests.
kernel void rosette_color_7e3(device uint4* output [[buffer(0)]],
                             constant uint& count [[buffer(1)]],
                             uint index [[thread_position_in_grid]]) {
    if (index >= count || index >= 1024u) return;
    float decoded = rosette_unpack_7e3(index);
    float next = rosette_unpack_7e3(min(index + 1u, 1023u));
    output[index] = uint4(as_type<uint>(decoded), rosette_pack_7e3_preclamped(decoded),
                         rosette_pack_7e3_preclamped((decoded + next) * 0.5f), 0u);
}
