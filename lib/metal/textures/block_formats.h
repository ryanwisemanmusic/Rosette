#ifndef ROSETTE_METAL_BLOCK_FORMATS_H
#define ROSETTE_METAL_BLOCK_FORMATS_H
#include <metal_stdlib>
using namespace metal;
inline uint rosette_texture_endian(uint word, uint mode) {
    if (mode == 1u) return ((word & 0x00ff00ffu) << 8u) | ((word & 0xff00ff00u) >> 8u);
    if (mode == 2u) return ((word & 0xffu) << 24u) | ((word & 0xff00u) << 8u) |
                           ((word >> 8u) & 0xff00u) | (word >> 24u);
    if (mode == 3u) return (word << 16u) | (word >> 16u);
    return word;
}
inline uint3 rosette_color565(uint value) {
    const uint r = (value >> 11u) & 31u, g = (value >> 5u) & 63u, b = value & 31u;
    return uint3((r << 3u) | (r >> 2u), (g << 2u) | (g >> 4u), (b << 3u) | (b >> 2u));
}
inline uint4 rosette_dxt_pixel(uint4 block, uint format, uint texel) {
    const uint endpoints = format == 1u ? block.x : block.z;
    const uint selectors = format == 1u ? block.y : block.w;
    const uint selector = (selectors >> (2u*texel)) & 3u;
    const uint c0 = endpoints & 65535u, c1 = endpoints >> 16u;
    const uint3 color0 = rosette_color565(c0), color1 = rosette_color565(c1);
    uint3 color; uint alpha = 255u;
    if (selector == 0u) color = color0;
    else if (selector == 1u) color = color1;
    else if (format == 1u && c0 <= c1) {
        color = selector == 2u ? (color0+color1)/2u : uint3(0);
        if (selector == 3u) alpha = 0u;
    } else color = selector == 2u ? (2u*color0+color1)/3u : (color0+2u*color1)/3u;
    if (format == 3u) {
        const uint alpha_word = texel < 8u ? block.x : block.y;
        alpha = ((alpha_word >> (4u*(texel & 7u))) & 15u)*17u;
    } else if (format == 5u) {
        const uint a0 = block.x & 255u, a1 = (block.x >> 8u) & 255u;
        const ulong codes = (ulong(block.y) << 16u) | (ulong(block.x) >> 16u);
        const uint a = uint((codes >> (3u*texel)) & 7u);
        if (a == 0u) alpha = a0;
        else if (a == 1u) alpha = a1;
        else if (a0 > a1) alpha = ((8u-a)*a0+(a-1u)*a1)/7u;
        else if (a < 6u) alpha = ((6u-a)*a0+(a-1u)*a1)/5u;
        else alpha = a == 6u ? 0u : 255u;
    }
    return uint4(color,alpha);
}
inline uint2 rosette_ctx1_pixel(uint2 block, uint texel) {
    const uint selector=(block.y >> (2u*texel)) & 3u;
    const uint2 low=uint2((block.x>>8u)&255u,block.x&255u);
    const uint2 high=uint2(block.x>>24u,(block.x>>16u)&255u);
    if (selector==0u) return low;
    if (selector==1u) return high;
    return selector==2u ? (2u*low+high)/3u : (low+2u*high)/3u;
}
#endif
