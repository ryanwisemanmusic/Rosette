// Compiled to LLVM IR / GNU COFF, never executed. The source shapes below
// are passed through the opt-in ABI profile in test_windows_cpp_profile.sh.
#include <windows.h>
#include <cstdio>
#include <string>
#include <ctime>
#include <cstdint>

static_assert(sizeof(void*) == 8 && sizeof(long) == 4);
static_assert(sizeof(time_t) == 8 && sizeof(FARPROC) == 8);

namespace {
__attribute__((format(printf, 3, 4)))
void MicroProfilePrintf(void*, void*, const char*, ...) {}
void dump_time(void* CB, void* Handle, time_t CaptureTime) {
  MicroProfilePrintf(CB, Handle, "var DumpUtcCaptureTime = %ld;\n", CaptureTime);
}
struct Base { virtual void set_name(std::string) = 0; };
struct Thread : Base {
  void set_name(std::string name) override {
    if (&name == nullptr) { return; }
    (void)name;
  }
};
struct Dpi {
  UINT (WINAPI* get_dpi_for_window)(HWND) = nullptr;
} per_monitor_dpi_v2_api_;
bool resolve(HMODULE user32_module_) {
  return (*reinterpret_cast<void**>(&per_monitor_dpi_v2_api_.get_dpi_for_window) =
          GetProcAddress(user32_module_, "GetDpiForWindow")) != nullptr;
}
void* XInputEnable_;
void resolve_xinput(FARPROC xie) { XInputEnable_ = xie; }
bool dos_magic(void* base) {
  return *reinterpret_cast<unsigned short*>(base) == 'ZM';
}
}  // namespace

extern void rosette_note_cpu_check();
extern void rosette_note_default_init();
struct StartupCpuFeatureCheck { StartupCpuFeatureCheck() { rosette_note_cpu_check(); } };
#pragma init_seg(lib)
static StartupCpuFeatureCheck gStartupAvxCheck;
struct DefaultCheck { DefaultCheck() { rosette_note_default_init(); } };
static DefaultCheck gDefaultCheck;

#define XE_FORCEINLINE __forceinline
namespace xe {
struct RingBuffer;
namespace gpu {
struct CommandProcessor {
  XE_FORCEINLINE virtual void WriteRegistersFromMem(uint32_t start_index,
                                                   uint32_t* base, uint32_t num_registers);
  XE_FORCEINLINE virtual void WriteRegisterRangeFromRing(xe::RingBuffer* ring,
                                                        uint32_t base, uint32_t num_registers);
};
}  // namespace gpu
}  // namespace xe
// Force references outside the definitions' translation unit. The profile
// must keep ordinary external virtual declarations, not header-wide no-inline.
void call_commands(xe::gpu::CommandProcessor& processor) {
  processor.WriteRegistersFromMem(0, nullptr, 0);
  processor.WriteRegisterRangeFromRing(nullptr, 0, 0);
}

#define XE_MSVC_OPTIMIZE_SMALL() __pragma(optimize("s", on))
#define XE_MSVC_OPTIMIZE_REVERT() __pragma(optimize("", on))
XE_MSVC_OPTIMIZE_SMALL()
bool GetResolveInfo(int value) { return value != 0; }
XE_MSVC_OPTIMIZE_REVERT()
bool ordinary_function(int value) { return value != 0; }
