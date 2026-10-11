#include "block_formats.h"
struct DxtBounds { uint width; uint height; uint block_pitch; uint word_count; uint endian; uint format; };

// Linear Xbox DXT1/3/5 blocks -> RGBA8Unorm. format is 1,3,5, not a Halo
// cache enum. 565 endpoints use bit replication; interpolation truncates as
// in Xenia's pixel_formats.xesli. DXT1 chooses punchthrough on c0<=c1;
// DXT3/5 always use four RGB colours, regardless of endpoint ordering.
// Guest resource pages, tiling, packed mips and gamma are caller contracts.
kernel void rosette_decode_dxt(device const uint* words [[buffer(0)]],
    constant DxtBounds& bounds [[buffer(1)]], texture2d<float, access::write> output [[texture(0)]],
    uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= bounds.width || pixel.y >= bounds.height ||
        pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    const uint stride = bounds.format == 1u ? 2u : 4u;
    const ulong offset = (ulong(pixel.y / 4u) * bounds.block_pitch + pixel.x / 4u) * stride;
    if (bounds.endian > 3u || (bounds.format != 1u && bounds.format != 3u && bounds.format != 5u) ||
        offset + stride > bounds.word_count) { output.write(float4(0),pixel); return; }
    // Each read occurs after the whole block range is checked.
    uint4 block = uint4(0);
    block.x = rosette_texture_endian(words[offset],bounds.endian);
    block.y = rosette_texture_endian(words[offset+1u],bounds.endian);
    if (stride == 4u) {
        block.z = rosette_texture_endian(words[offset+2u],bounds.endian);
        block.w = rosette_texture_endian(words[offset+3u],bounds.endian);
    }
    const uint4 rgba = rosette_dxt_pixel(block,bounds.format,(pixel.y & 3u)*4u + (pixel.x & 3u));
    output.write(float4(rgba)/255.0f,pixel);
}
