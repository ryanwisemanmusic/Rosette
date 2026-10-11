#include <metal_stdlib>
using namespace metal;
struct FsiRaster { float4 position [[position]]; };
struct FsiBounds { uint width; uint height; uint samples; uint words; uint value; };
vertex FsiRaster rosette_fsi_triangle(uint vertex_id [[vertex_id]]) {
    const float2 positions[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
    return {float4(positions[min(vertex_id,2u)],0,1)};
}

// Native ordered storage-buffer primitive. The recurrence is a contract probe,
// not Xbox blend/depth/stencil logic. It deliberately has no atomic substitute:
// the raster order group must retain overlapping fragment ordering.
fragment float4 rosette_fsi_order(FsiRaster in [[stage_in]],
    device uint* edram [[buffer(0), raster_order_group(0)]],
    constant FsiBounds& bounds [[buffer(1)]], uint sample [[sample_id]]) {
    const uint2 pixel = uint2(in.position.xy);
    if (pixel.x >= bounds.width || pixel.y >= bounds.height || sample >= bounds.samples) return float4(0);
    const ulong index = (ulong(pixel.y) * bounds.width + pixel.x) * bounds.samples + sample;
    if (index >= bounds.words) return float4(0);
    edram[index] = edram[index] * 3u + bounds.value;
    return float4(0,0,0,1);
}
