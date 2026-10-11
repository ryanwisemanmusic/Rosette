#include <metal_stdlib>
using namespace metal;
// Independent numeric oracle for finite Xenos EDRAM, before resolve exponent
// bias. This contract probe is standalone; the live path uses hdr_resolve.zig.
inline float rosette_resolve_decode(uint code) {
    uint e=(code>>10u)&31u, m=code&1023u;
    float magnitude=e ? ldexp(1.0f+float(m)/1024.0f,int(e)-15)
                      : float(m)/16777216.0f;
    return copysign(magnitude,code&32768u ? -1.0f : 1.0f);
}
// Same entry name/record ABI as the bounded generic HDR contract harness.
kernel void rosette_hdr_resolve(device const uint4* input [[buffer(0)]],
                               device uint4* output [[buffer(1)]],
                               constant uint& rows [[buffer(2)]],
                               uint index [[thread_position_in_grid]]) {
    if(index>=rows)return;
    uint4 v=input[index];
    float2 decoded=float2(rosette_resolve_decode(v.x&65535u),rosette_resolve_decode(v.x>>16u));
    output[index]=uint4(as_type<uint2>(decoded),as_type<uint2>(decoded*as_type<float>(v.y)));
}
