#include <stdint.h>

typedef uint32_t (*rosette_xenia_heap_abi_version_fn)(void);
typedef uint32_t (*rosette_xenia_heap_select_fn)(
    const uint64_t* entries, uint32_t total_page_count, uint32_t low_page,
    uint32_t high_page, uint32_t allocation_pages, uint32_t alignment_pages,
    uint32_t top_down, uint32_t hint_page);

extern uint32_t rosette_xenia_heap_allocator_abi_version(void);
extern uint32_t rosette_xenia_heap_select(
    const uint64_t* entries, uint32_t total_page_count, uint32_t low_page,
    uint32_t high_page, uint32_t allocation_pages, uint32_t alignment_pages,
    uint32_t top_down, uint32_t hint_page);

// The executable is normally linked with dead-stripping enabled. Keeping a
// typed anchor in a C translation unit makes the optional ABI an actual link
// dependency, so ReleaseFast cannot erase the symbols Xenia resolves with
// dlsym. The anchor is never called; the function pointers are the contract.
__attribute__((used, retain))
static const rosette_xenia_heap_abi_version_fn
    rosette_xenia_heap_abi_version_anchor =
        rosette_xenia_heap_allocator_abi_version;

__attribute__((used, retain))
static const rosette_xenia_heap_select_fn rosette_xenia_heap_select_anchor =
    rosette_xenia_heap_select;
