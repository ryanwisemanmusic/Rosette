#version 450
// Three corners as Xenia supplies them; Rosette generates the fourth.
out gl_PerVertex { vec4 gl_Position; };
layout(location=0) out float lighting;
void main() {
  const vec2 positions[3] = vec2[3](vec2(-1,-1),vec2(1,-1),vec2(-1,1));
  // A one-unit change at a large offset exposes cancellation in a+b+c-f-f.
  const float light[3] = float[3](8388608.0,8388609.0,8388609.0);
  gl_Position=vec4(positions[gl_VertexIndex],0,1);
  lighting=light[gl_VertexIndex];
}
