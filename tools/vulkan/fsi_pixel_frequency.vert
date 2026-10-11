#version 450
void main() {
  const vec2 p[3] = vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));
  vec2 window = (p[gl_VertexIndex]+1.0)*8.0;
  gl_Position=vec4(p[gl_VertexIndex],0.125+window.x/64.0+window.y/128.0,1.0);
}
