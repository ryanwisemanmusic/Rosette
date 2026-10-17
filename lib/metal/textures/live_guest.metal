#ifndef ROSETTE_METAL_BLOCK_FORMATS_H
#include "block_formats.h"
#endif
// Rosette-owned unscaled 2D texture loaders. The ten scalar words are the
// Xenia texture-load push contract (uint3 would introduce MSL padding).
// Included after block_formats.h by live_source.zig / the probe builder.
struct RosetteXeniaLoad {
    uint flags, guest_offset, guest_pitch, guest_z_rows;
    uint blocks_x, blocks_y, blocks_z, host_offset, host_pitch, height;
};

// Xenos macro/micro tile bit addressing, using 64-bit intermediates so a
// malformed pitch/offset cannot wrap an out-of-range address back in range.
inline ulong rosette_tiled_2d(uint x, uint y, uint pitch, uint log_bpb) {
    const ulong outer = (ulong(y >> 5u)*(pitch >> 5u)+(x >> 5u)) << 6u;
    const ulong inner = (((y >> 1u)&7u) << 3u) | (x&7u);
    const ulong oi = (outer+inner) << log_bpb;
    const ulong bank = (y >> 4u)&1u;
    const ulong pipe = ((x >> 3u)&3u)^(((y >> 3u)&1u) << 1u);
    return ((ulong(y)&1u) << 4u) | (pipe << 6u) | (bank << 11u) |
           (oi&15u) | (((oi >> 4u)&1u) << 5u) |
           (((oi >> 5u)&7u) << 8u) | ((oi >> 8u) << 12u);
}

inline void rosette_live_load(constant RosetteXeniaLoad& p, device uchar* dest,
    device const uint* source, uint dest_bytes, uint source_bytes,
    uint3 invocation, uint format) {
    // Scaled and 3D paths deliberately remain with the hardened SPIR-V loader.
    const uint scale=p.flags&~15u;
    if ((scale!=0u && scale!=0x90u) || (p.flags&2u) || p.blocks_z != 1u || invocation.z != 0u ||
        p.blocks_x > 1024u || p.blocks_y > 1024u || p.height > p.blocks_y*4u ||
        p.guest_pitch < p.blocks_x || p.host_pitch < p.blocks_x*4u*(format==0u?2u:4u) ||
        (p.guest_offset&3u) || (p.host_offset&3u)) return;
    const uint block_y=invocation.y;
    if (block_y >= p.blocks_y) return;
    const uint log_bpb=(format==0u || format==1u)?3u:4u;
    const uint bytes_per_block=1u << log_bpb;
    const uint bytes_per_pixel=format==0u?2u:4u;
    const uint endian=(p.flags >> 2u)&3u;
    for (uint local_block=0u; local_block<4u; ++local_block) {
        const ulong bx=ulong(invocation.x)*4u+local_block;
        if (bx >= p.blocks_x) break;
        const ulong guest=p.guest_offset+((p.flags&1u)?
            rosette_tiled_2d(uint(bx),block_y,p.guest_pitch,log_bpb):
            (ulong(block_y)*p.guest_pitch+bx)*bytes_per_block);
        uint4 block=uint4(0);
        if (guest <= source_bytes && bytes_per_block <= ulong(source_bytes)-guest) {
            for (uint word=0; word<bytes_per_block/4u; ++word)
                block[word]=rosette_texture_endian(source[guest/4u+word],endian);
        }
        for (uint y=0u; y<4u; ++y) {
            const uint py=block_y*4u+y;
            if (py >= p.height) break;
            for (uint x=0u; x<4u; ++x) {
                const ulong output=ulong(p.host_offset)+ulong(py)*p.host_pitch+(bx*4u+x)*bytes_per_pixel;
                if (output > dest_bytes || bytes_per_pixel > ulong(dest_bytes)-output) continue;
                const uint4 rgba=format==0u?uint4(rosette_ctx1_pixel(block.xy,y*4u+x),0u,255u):
                    rosette_dxt_pixel(block,format,y*4u+x);
                for (uint c=0; c<bytes_per_pixel; ++c) dest[output+c]=uchar(rgba[c]);
            }
        }
    }
}

// Pinned MoltenVK 1.2.7 discrete binding ABI: push buffer 0; destination
// set0/binding0 -> 1; source set1/binding0 -> 2; two private bounds UBOs -> 3,4.
// Each bounds UBO has a real 16-byte descriptor. No driver robustness assumed.
#define ROSETTE_LIVE_LOADER(name,format) \
kernel void name(constant RosetteXeniaLoad& p [[buffer(0)]], \
    device uchar* dest [[buffer(1)]], device const uint* source [[buffer(2)]], \
    constant uint4& db [[buffer(3)]], constant uint4& sb [[buffer(4)]], \
    uint3 id [[thread_position_in_grid]]) { rosette_live_load(p,dest,source,db.x,sb.x,id,format); }
ROSETTE_LIVE_LOADER(rosette_live_ctx1,0u)
ROSETTE_LIVE_LOADER(rosette_live_dxt1,1u)
ROSETTE_LIVE_LOADER(rosette_live_dxt3,3u)
ROSETTE_LIVE_LOADER(rosette_live_dxt5,5u)
