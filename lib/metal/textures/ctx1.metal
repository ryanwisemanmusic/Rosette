#include "block_formats.h"
struct Ctx1Bounds { uint width; uint height; uint block_pitch; uint block_count; uint endian; };

// Linear 4x4 CTX1 blocks -> RG8Unorm. Endpoint layout is 0xRRGGrrgg;
// selectors 0,1,2,3 choose low,high,2:1,1:2, with integer truncation.
// ISO resource pages, guest tiling and packed mips must be resolved by the
// caller. This kernel does not guess resource addresses or reconstruct blue.
kernel void rosette_decode_ctx1(device const uint2* blocks [[buffer(0)]],
                               constant Ctx1Bounds& bounds [[buffer(1)]],
                               texture2d<float, access::write> output [[texture(0)]],
                               uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= bounds.width || pixel.y >= bounds.height ||
        pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    const ulong index = ulong(pixel.y / 4u) * bounds.block_pitch + pixel.x / 4u;
    if (index >= bounds.block_count || bounds.endian > 3u) { output.write(float4(0),pixel); return; }
    uint2 block = blocks[index];
    block = uint2(rosette_texture_endian(block.x,bounds.endian),rosette_texture_endian(block.y,bounds.endian));
    const uint2 rg = rosette_ctx1_pixel(block,(pixel.y & 3u)*4u + (pixel.x & 3u));
    output.write(float4(float2(rg)/255.0f,0,1),pixel);
}
