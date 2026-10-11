#ifndef ROSETTE_METAL_CONTRACTS_H
#define ROSETTE_METAL_CONTRACTS_H
#include <metal_stdlib>
using namespace metal;

// Counts describe the bound range, never the enclosing allocation. The host
// support API verifies them against actual buffers before encoding commands.
inline float4 rosette_uniform4(device const float4* values, int index, uint count) {
    if (index < 0 || uint(index) >= count) return float4(0.0f);
    return values[uint(index)];
}

// Unsigned Xenos 7-mantissa / 3-exponent encoding, not 10-bit UNORM.
inline float rosette_unpack_7e3(uint code) {
    code &= 1023u;
    const uint exponent = code >> 7u, mantissa = code & 127u;
    if (exponent == 0u) return float(mantissa) * (1.0f / 512.0f);
    return as_type<float>(((exponent + 124u) << 23u) | (mantissa << 16u));
}

// Contract: finite input already clamped to [0,31.875]. Round nearest, ties
// even, matching the Xenos render-target conversion. No exposure/gamma policy.
inline uint rosette_pack_7e3_preclamped(float value) {
    const uint bits = as_type<uint>(value);
    const uint denormal = ((bits & 0x7fffffu) | 0x800000u) >> min(125u - (bits >> 23u), 24u);
    const uint normal = bits - (124u << 23u);
    const uint biased = bits < 0x3e800000u ? denormal : normal;
    return ((biased + 0x7fffu + ((biased >> 16u) & 1u)) >> 16u) & 1023u;
}
#endif
