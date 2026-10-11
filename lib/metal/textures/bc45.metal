#include "block_formats.h"
struct Bc45Bounds { uint width; uint height; uint block_pitch; uint word_count; uint endian; uint format; };

// Linear Xbox DXT5A (single 8-bit channel), DXN (two 8-bit channels) and
// DXT3A (4-bit explicit alpha) blocks. Sources were checked against the
// read-only Xenia references texture_load_dxt5a_r8, texture_load_dxn_rg8,
// texture_load_dxt3a and pixel_formats.xesli (XeDXT5RowToA8 family). They
// share Xenia's Xenos endian handling: whole 32-bit words are swapped before a
// block is interpreted, so word 0 holds endpoint 0 in bits 0..7, endpoint 1 in
// bits 8..15 and the first 16 selector bits above them.
//
// 8-step mode (e0 > e1) uses (8-c)*e0+(c-1)*e1 over 7 for codes 2..7; the
// 6-step mode (e0 <= e1) uses 6-c / c-1 over 5 for codes 2..5 and the
// constants 0 and 255 for codes 6 and 7. All interpolation truncates, exactly
// as in the integer Xenia helpers. Guest resource pages, tiling, packed mips,
// signed interpretation and channel swizzles remain caller contracts.
inline uint rosette_bc4_value(uint2 half_block, uint texel) {
    const uint e0 = half_block.x & 255u, e1 = (half_block.x >> 8u) & 255u;
    const ulong codes = (ulong(half_block.y) << 16u) | (ulong(half_block.x) >> 16u);
    const uint c = uint((codes >> (3u*texel)) & 7u);
    if (c == 0u) return e0;
    if (c == 1u) return e1;
    if (e0 > e1) return ((8u-c)*e0 + (c-1u)*e1) / 7u;
    if (c < 6u) return ((6u-c)*e0 + (c-1u)*e1) / 5u;
    return c == 6u ? 0u : 255u;
}

inline uint rosette_dxt3a_value(uint2 half_block, uint texel) {
    const uint word = texel < 8u ? half_block.x : half_block.y;
    return ((word >> (4u*(texel & 7u))) & 15u) * 17u;
}

// stride is the number of 32-bit source words per 4x4 block.
inline bool rosette_bc45_block(device const uint* words, constant Bc45Bounds& bounds,
                               uint stride, uint2 pixel, thread uint4& block) {
    if (pixel.x >= bounds.width || pixel.y >= bounds.height) return false;
    const ulong offset = (ulong(pixel.y / 4u) * bounds.block_pitch + pixel.x / 4u) * stride;
    if (bounds.endian > 3u || offset + stride > bounds.word_count) return false;
    // Each read occurs after the whole block range is checked.
    block = uint4(0);
    for (uint i = 0u; i < stride; ++i) block[i] = rosette_texture_endian(words[offset+i], bounds.endian);
    return true;
}

kernel void rosette_decode_dxt5a(device const uint* words [[buffer(0)]],
    constant Bc45Bounds& bounds [[buffer(1)]], texture2d<float, access::write> output [[texture(0)]],
    uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    uint4 block;
    if (bounds.format != 1u || !rosette_bc45_block(words, bounds, 2u, pixel, block)) { output.write(float4(0), pixel); return; }
    const uint value = rosette_bc4_value(block.xy, (pixel.y & 3u)*4u + (pixel.x & 3u));
    output.write(float4(float(value)/255.0f, 0.0f, 0.0f, 0.0f), pixel);
}

kernel void rosette_decode_dxt3a(device const uint* words [[buffer(0)]],
    constant Bc45Bounds& bounds [[buffer(1)]], texture2d<float, access::write> output [[texture(0)]],
    uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    uint4 block;
    if (bounds.format != 3u || !rosette_bc45_block(words, bounds, 2u, pixel, block)) { output.write(float4(0), pixel); return; }
    const uint value = rosette_dxt3a_value(block.xy, (pixel.y & 3u)*4u + (pixel.x & 3u));
    output.write(float4(float(value)/255.0f, 0.0f, 0.0f, 0.0f), pixel);
}

// The first eight bytes are the first output channel, the next eight the
// second, as in Xenia's DXN loader (low byte, then high byte of each texel).
kernel void rosette_decode_dxn(device const uint* words [[buffer(0)]],
    constant Bc45Bounds& bounds [[buffer(1)]], texture2d<float, access::write> output [[texture(0)]],
    uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    uint4 block;
    if (bounds.format != 2u || !rosette_bc45_block(words, bounds, 4u, pixel, block)) { output.write(float4(0), pixel); return; }
    const uint texel = (pixel.y & 3u)*4u + (pixel.x & 3u);
    const uint r = rosette_bc4_value(block.xy, texel), g = rosette_bc4_value(block.zw, texel);
    output.write(float4(float(r)/255.0f, float(g)/255.0f, 0.0f, 0.0f), pixel);
}
