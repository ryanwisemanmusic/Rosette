#version 450
// Feeds Xenia's FSI pixel shaders every interpolator slot they can declare.
layout(location = 0) out vec4 xe_interpolators[16];
void main() {
  const vec2 corners[3] = vec2[3](vec2(-1, -1), vec2(3, -1), vec2(-1, 3));
  vec2 position = corners[gl_VertexIndex];
  gl_Position = vec4(position, 0.5, 1);
  vec4 uv = vec4(position * 0.5 + 0.5, 0.25, 1);
  for (int i = 0; i < 16; ++i) xe_interpolators[i] = uv * (1.0 + float(i) * 0.125) + vec4(float(i) * 0.0625);
}
