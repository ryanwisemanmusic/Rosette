// Compiled, never executed: validates the Rosette Clang/MinGW header contract.
#include <winsock2.h>
#include <windows.h>
#include <intrin.h>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <vector>
#include "xenia/base/platform.h"
#include "third_party/date/include/date/date.h"
#include "third_party/imgui/imgui.h"
#include "xenia/ui/immediate_drawer.h"
#include <cstddef>

static_assert(sizeof(void*) == 8 && sizeof(long) == 4 && sizeof(size_t) == 8);
static_assert(sizeof(SOCKET) == 8);
static_assert(std::atomic<uint32_t>::is_always_lock_free);
static_assert(std::atomic<uint64_t>::is_always_lock_free);
static_assert(__GNUC__ == 4 && __GNUC_MINOR__ == 2);
static_assert(sizeof(FARPROC) == sizeof(void*));
// Read-only UI instrumentation uses public Windows x64 structures only.
static_assert(sizeof(ImDrawData) == 64);
static_assert(offsetof(ImDrawData, Valid) == 0);
static_assert(offsetof(ImDrawData, CmdListsCount) == 4);
static_assert(offsetof(ImDrawData, TotalIdxCount) == 8);
static_assert(offsetof(ImDrawData, TotalVtxCount) == 12);
static_assert(offsetof(ImDrawData, DisplaySize) == 40);
static_assert(offsetof(xe::ui::ImmediateDraw, primitive_type) == 0);
static_assert(offsetof(xe::ui::ImmediateDraw, count) == 4);
static_assert(offsetof(xe::ui::ImmediateDraw, texture) == 16);
static_assert(offsetof(xe::ui::ImmediateDraw, scissor) == 24);
static_assert(offsetof(xe::ui::ImmediateDraw, scissor_left) == 28);
static_assert(offsetof(xe::ui::ImmediateDraw, scissor_bottom) == 40);

__m128i rosette_header_contract(uint64_t value) {
  std::vector<uint64_t> values{value};
  return _mm_cvtsi64_si128(values.front());
}
