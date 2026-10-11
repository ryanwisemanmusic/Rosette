#include <metal_stdlib>
using namespace metal;

// Xenos extended float16 has a finite exponent 31, unlike IEEE half.
// Integer/numeric conversions avoid Metal half's Inf/NaN interpretation.
// Standalone contract foundation; not wired into the live FSI pipeline.
inline float rosette_hdr_unpack16(uint h) {
    uint sign=(h & 0x8000u)<<16u, e=(h>>10u)&31u, m=h&1023u;
    float magnitude=e==0u ? float(m)*(1.0f/16777216.0f)
                          : as_type<float>(((e+112u)<<23u)|(m<<13u));
    return as_type<float>(as_type<uint>(magnitude)|sign);
}
inline uint rosette_hdr_pack16(float value) {
    uint bits=as_type<uint>(value), a=bits&0x7fffffffu, sign=(bits>>16u)&0x8000u;
    if(a>0x7f800000u)return 0u; // Xenos has no NaN; flush to +zero.
    a=min(a,0x47ffe000u); // Saturate infinity/overflow at 131008.
    if(a<0x33000000u)return sign;
    if(a<0x38800000u) {
        uint shift=126u-(a>>23u), mantissa=(a&0x7fffffu)|0x800000u;
        uint integral=mantissa>>shift, residue=mantissa&((1u<<shift)-1u);
        uint halfway=1u<<(shift-1u);
        return sign|(integral+uint(residue>halfway || (residue==halfway && (integral&1u)!=0u)));
    }
    uint biased=a-0x38000000u;
    return sign|((biased+0xfffu+((biased>>13u)&1u))>>13u);
}
kernel void rosette_hdr_float16(device const uint4* input [[buffer(0)]],
                               device uint4* output [[buffer(1)]],
                               constant uint& rows [[buffer(2)]],
                               uint index [[thread_position_in_grid]]) {
    if(index>=rows)return;
    uint4 v=input[index];
    float x=rosette_hdr_unpack16(v.x&65535u), y=rosette_hdr_unpack16(v.x>>16u);
    output[index]=uint4(as_type<uint>(x),as_type<uint>(y),
        rosette_hdr_pack16(as_type<float>(v.y))|(rosette_hdr_pack16(as_type<float>(v.z))<<16u),
        rosette_hdr_pack16(x)|(rosette_hdr_pack16(y)<<16u));
}
