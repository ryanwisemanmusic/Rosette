#version 450
#extension GL_ARB_fragment_shader_interlock : require
layout(sample_interlock_ordered) in;
layout(location=0) in float lighting;
layout(set=0,binding=0,std430) coherent buffer Edram { uvec4 pixels[]; } edram;
layout(push_constant) uniform Push { uint amount; } push;
void main() {
  // The probe's fixed 16x16 scissor keeps every index inside 256 uvec4s.
  uint pixel=uint(gl_FragCoord.y)*16+uint(gl_FragCoord.x);
  uint coverage=uint(gl_SampleMaskIn[0]);
  beginInvocationInterlockARB();
  for(uint slot=0;slot<4;++slot)
    if((coverage&(1u<<slot))!=0)
      edram.pixels[pixel][slot]+=floatBitsToUint(lighting);
  endInvocationInterlockARB();
}
