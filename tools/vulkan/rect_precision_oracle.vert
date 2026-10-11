#version 450
// Independent four-corner input: no Rosette rectangle rewrite.
out gl_PerVertex { vec4 gl_Position; };
layout(location=0) out float lighting;
void main() {
  const vec2 positions[4] = vec2[4](vec2(-1,-1),vec2(1,-1),vec2(-1,1),vec2(1,1));
  // Xenia's precise (second-first)+third yields 8388610 at corner four.
  const float light[4] = float[4](8388608.0,8388609.0,8388609.0,8388610.0);
  gl_Position=vec4(positions[gl_VertexIndex],0,1);
  lighting=light[gl_VertexIndex];
}
