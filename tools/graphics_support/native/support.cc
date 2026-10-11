#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include "xenia/base/logging.h"
#include "xenia/base/memory.h"
namespace cvars {
std::filesystem::path dump_shaders;
bool draw_resolution_scaled_texture_offsets = true;
}
namespace xe::logging {
bool ShouldLog(LogLevel, uint32_t) { return true; }
namespace internal {
thread_local char buffer[65536];
uint32_t GetLogLevel() { return uint32_t(LogLevel::Trace); }
std::pair<char*, size_t> GetThreadBuffer() { return {buffer, sizeof(buffer)}; }
void AppendLogLine(LogLevel, char prefix, size_t written) {
  std::fprintf(stderr, "%c ", prefix);
  std::fwrite(buffer, 1, std::min(written, sizeof(buffer)), stderr);
  std::fputc('\n', stderr);
}
}
}
namespace xe {
void copy_and_swap_32_aligned(void* dest, const void* src, size_t count) {
  auto* d = static_cast<uint32_t*>(dest);
  const auto* s = static_cast<const uint32_t*>(src);
  for (size_t i = 0; i < count; ++i) d[i] = __builtin_bswap32(s[i]);
}
void copy_and_swap_32_unaligned(void* dest, const void* src, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    uint32_t word;
    std::memcpy(&word, static_cast<const char*>(src) + i * 4, 4);
    word = __builtin_bswap32(word);
    std::memcpy(static_cast<char*>(dest) + i * 4, &word, 4);
  }
}
[[noreturn]] void FatalError(std::string_view message) {
  std::fprintf(stderr, "%.*s\n", int(message.size()), message.data());
  std::abort();
}
namespace filesystem {
FILE* OpenFile(const std::filesystem::path& path, std::string_view mode) {
  return std::fopen(path.c_str(), std::string(mode).c_str());
}
}
}
