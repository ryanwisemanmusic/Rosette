#version 450
#extension GL_ARB_fragment_shader_interlock : require
// An interlocked EDRAM-style store whose index runs past the bound range, the
// way any FSI shader's would if its address arithmetic were given an
// out-of-range base. Run under the same sample interlock (Metal raster order
// group) as Xenia's FSI shaders.
layout(sample_interlock_ordered) in;
layout(set = 0, binding = 0, std430) coherent restrict buffer XeEdram { uint edram[]; };
layout(push_constant) uniform Push { int base_dwords; uint marker; } push;
void main() {
  int index = push.base_dwords + int(uint(gl_FragCoord.y) * 80u + uint(gl_FragCoord.x));
  beginInvocationInterlockARB();
  edram[index] = push.marker;
  endInvocationInterlockARB();
}
