#include "contracts.h"
struct UniformBounds { uint rows; uint requests; };
kernel void rosette_uniform_gather(device const float4* values [[buffer(0)]],
                                  device const int* indices [[buffer(1)]],
                                  device float4* output [[buffer(2)]],
                                  constant UniformBounds& bounds [[buffer(3)]],
                                  uint index [[thread_position_in_grid]]) {
    if (index >= bounds.requests) return;
    output[index] = rosette_uniform4(values, indices[index], bounds.rows);
}
