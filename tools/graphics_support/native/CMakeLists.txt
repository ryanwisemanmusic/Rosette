cmake_minimum_required(VERSION 3.20)
project(rosette_iso_shader_translator LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT EXISTS "${XENIA_SOURCE}/src/xenia/gpu/spirv_shader_translator.cc")
  message(FATAL_ERROR "Pass -DXENIA_SOURCE=<read-only Xenia source directory>")
endif()
add_executable(iso_shader_profile profile.c)
target_include_directories(iso_shader_profile PRIVATE "${XENIA_SOURCE}/third_party/Vulkan-Headers/include")
set(GPU "${XENIA_SOURCE}/src/xenia/gpu")
set(SPV "${XENIA_SOURCE}/third_party/glslang/SPIRV")
add_executable(iso_shader_translate
  translate.cc support.cc
  "${XENIA_SOURCE}/src/xenia/base/string_buffer.cc"
  "${GPU}/shader.cc" "${GPU}/shader_translator.cc"
  "${GPU}/shader_translator_disasm.cc" "${GPU}/spirv_builder.cc"
  "${GPU}/spirv_shader.cc" "${GPU}/ucode.cc" "${GPU}/draw_util.cc"
  "${GPU}/spirv_shader_translator.cc" "${GPU}/spirv_shader_translator_alu.cc"
  "${GPU}/spirv_shader_translator_fetch.cc" "${GPU}/spirv_shader_translator_memexport.cc"
  "${GPU}/spirv_shader_translator_rb.cc"
  "${SPV}/SpvBuilder.cpp" "${SPV}/SpvPostProcess.cpp" "${SPV}/Logger.cpp"
  "${SPV}/InReadableOrder.cpp")
# Only console configuration/IO integration is supplied by this harness.
# Shader translation and its SPIR-V builder compile directly from Xenia.
target_include_directories(iso_shader_translate PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/integration" "${XENIA_SOURCE}/src" "${XENIA_SOURCE}"
  "${XENIA_SOURCE}/third_party/Vulkan-Headers/include" "${XENIA_SOURCE}/third_party/glslang")
target_compile_definitions(iso_shader_translate PRIVATE FMT_HEADER_ONLY VULKAN_HPP_NO_TO_STRING)
target_compile_options(iso_shader_translate PRIVATE -O2 -UNDEBUG)
if(APPLE)
  target_link_options(iso_shader_translate PRIVATE -Wl,-dead_strip)
endif()
