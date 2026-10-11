#version 450
// Outer levels come from push constants exactly as Xenia's adaptive hull
// shader writes them; inner is the minimum, as Xenia sets it.
layout(vertices = 3) out;
layout(push_constant) uniform Levels { vec4 outer; } levels;
void main() {
  gl_out[gl_InvocationID].gl_Position = gl_in[gl_InvocationID].gl_Position;
  if (gl_InvocationID == 0) {
    gl_TessLevelOuter[0] = levels.outer.x;
    gl_TessLevelOuter[1] = levels.outer.y;
    gl_TessLevelOuter[2] = levels.outer.z;
    gl_TessLevelInner[0] = min(min(levels.outer.x, levels.outer.y), levels.outer.z);
  }
}
