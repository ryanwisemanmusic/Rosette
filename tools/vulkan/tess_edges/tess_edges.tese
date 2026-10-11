#version 450
// Record every generated domain point. The CPU counts the distinct points on
// each edge (u = 0, v = 0, w = 0): with equal spacing an edge of level N has
// N + 1 points, so the counts say which outer level drove which edge.
layout(triangles, equal_spacing, cw) in;
layout(std430, binding = 0) buffer Points { uint count; uint pad[3]; vec4 points[]; } points;
void main() {
  uint slot = atomicAdd(points.count, 1u);
  if (slot < 4096u) points.points[slot] = vec4(gl_TessCoord, 0.0);
  gl_Position = vec4(gl_TessCoord, 1.0);
}
