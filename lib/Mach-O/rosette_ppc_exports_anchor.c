#include <stdint.h>

typedef struct RosettePpcGuestState RosettePpcGuestState;
typedef struct RosettePpcRunResult RosettePpcRunResult;

typedef int32_t (*rosette_ppc_host_available_fn)(void);
typedef const char* (*rosette_ppc_host_identity_fn)(void);
typedef int32_t (*rosette_ppc_bind_context_fn)(const RosettePpcGuestState*);
typedef void (*rosette_ppc_release_context_fn)(void*);
typedef void (*rosette_ppc_execute_fn)(void*, uint32_t, uint32_t,
                                       RosettePpcRunResult*);
typedef void (*rosette_ppc_invalidate_range_fn)(uint32_t, uint32_t);
typedef int32_t (*rosette_ppc_set_recompiler_enabled_fn)(int32_t);
typedef int32_t (*rosette_ppc_recompiler_stats_fn)(void*, uint64_t*, uint64_t*);

extern int32_t rosette_ppc_host_available(void);
extern const char* rosette_ppc_host_identity(void);
extern int32_t rosette_ppc_bind_context(const RosettePpcGuestState*);
extern void rosette_ppc_release_context(void*);
extern void rosette_ppc_execute(void*, uint32_t, uint32_t,
                                RosettePpcRunResult*);
extern void rosette_ppc_invalidate_range(uint32_t, uint32_t);
extern int32_t rosette_ppc_set_recompiler_enabled(int32_t);
extern int32_t rosette_ppc_recompiler_stats(void*, uint64_t*, uint64_t*);

// ReleaseFast enables dead stripping. These typed, retained references make
// every optional PPC provider entry point a real link dependency so Xenia's
// dlsym(RTLD_DEFAULT, ...) can resolve it from the Mach-O process image.
__attribute__((used, retain)) static const struct {
  rosette_ppc_host_available_fn host_available;
  rosette_ppc_host_identity_fn host_identity;
  rosette_ppc_bind_context_fn bind_context;
  rosette_ppc_release_context_fn release_context;
  rosette_ppc_execute_fn execute;
  rosette_ppc_invalidate_range_fn invalidate_range;
  rosette_ppc_set_recompiler_enabled_fn set_recompiler_enabled;
  rosette_ppc_recompiler_stats_fn recompiler_stats;
} rosette_ppc_exports_anchor = {
    rosette_ppc_host_available,
    rosette_ppc_host_identity,
    rosette_ppc_bind_context,
    rosette_ppc_release_context,
    rosette_ppc_execute,
    rosette_ppc_invalidate_range,
    rosette_ppc_set_recompiler_enabled,
    rosette_ppc_recompiler_stats,
};
