#version 450
#extension GL_ARB_fragment_shader_interlock : require
layout(sample_interlock_ordered) in;
layout(set=0,binding=0,std430) coherent buffer Pixels { uvec4 sample_data[1024]; uint invocations[256]; } output_data;
void main() {
  uint x=uint(gl_FragCoord.x), y=uint(gl_FragCoord.y);
  uint coverage=uint(gl_SampleMaskIn[0]);
  beginInvocationInterlockARB();
  bool live_lane=x<16u && y<16u && !gl_HelperInvocation;
  if(live_lane) atomicAdd(output_data.invocations[y*16u+x],1u);
  for(uint s=0u;s<4u;++s) {
    if(live_lane && (coverage&(1u<<s))!=0u) {
      uint i=(y*16u+x)*4u+s;
      output_data.sample_data[i]=uvec4(floatBitsToUint(gl_FragCoord.xyz),output_data.sample_data[i].w+1u);
    }
  }
  endInvocationInterlockARB();
}
