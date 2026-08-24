const std = @import("std");
const process = @import("process.zig");
const xenia_heap_range = @import("xenia_heap_range");
const _ = @import("sha1_tracer");
const _constants = @import("macho_core").constants;
const _types = @import("macho_core").types;
const _decoder = @import("macho_core").decoder;
const _core = @import("process_core");
const ppc_runtime = @import("ppc_runtime");
const ppc_host_abi = ppc_runtime.host_abi;

// Xenia resolves this optional provider with dlsym while it is hosted by the
// Mach-O processor. Keeping the wrappers in the executable's root module is
// intentional: exports from a merely imported child module are not guaranteed
// to become dynamic symbols in the final process image.
pub export fn rosette_xenia_heap_allocator_abi_version() callconv(.c) u32 {
    return xenia_heap_range.abiVersion();
}

pub export fn rosette_xenia_heap_select(
    entries: [*]const u64,
    total_page_count: u32,
    low_page: u32,
    high_page: u32,
    allocation_pages: u32,
    alignment_pages: u32,
    top_down: u32,
    hint_page: u32,
) callconv(.c) u32 {
    return xenia_heap_range.selectC(
        entries,
        total_page_count,
        low_page,
        high_page,
        allocation_pages,
        alignment_pages,
        top_down,
        hint_page,
    );
}

// Xenia's direct PowerPC backend resolves this optional provider with dlsym
// while it is hosted by the Mach-O processor. Keep these forwarding exports in
// the executable root for the same reason as the heap ABI above: a child
// module's exported declarations are not a reliable dynamic-symbol boundary.
pub export fn rosette_ppc_host_available() callconv(.c) i32 {
    return ppc_host_abi.rosette_ppc_host_available();
}

pub export fn rosette_ppc_host_identity() callconv(.c) [*:0]const u8 {
    return ppc_host_abi.rosette_ppc_host_identity();
}

pub export fn rosette_ppc_bind_context(
    guest: *const ppc_host_abi.GuestState,
) callconv(.c) i32 {
    return ppc_host_abi.rosette_ppc_bind_context(guest);
}

pub export fn rosette_ppc_release_context(host_context: *anyopaque) callconv(.c) void {
    ppc_host_abi.rosette_ppc_release_context(host_context);
}

pub export fn rosette_ppc_set_recompiler_enabled(enabled: i32) callconv(.c) i32 {
    return ppc_host_abi.rosette_ppc_set_recompiler_enabled(enabled);
}

pub export fn rosette_ppc_recompiler_stats(
    host_context: *anyopaque,
    out_blocks: *u64,
    out_instructions: *u64,
) callconv(.c) i32 {
    return ppc_host_abi.rosette_ppc_recompiler_stats(
        host_context,
        out_blocks,
        out_instructions,
    );
}

pub export fn rosette_ppc_invalidate_range(guest_low: u32, guest_high: u32) callconv(.c) void {
    ppc_host_abi.rosette_ppc_invalidate_range(guest_low, guest_high);
}

pub export fn rosette_ppc_execute(
    host_context: *anyopaque,
    address: u32,
    return_address: u32,
    out_result: *ppc_host_abi.RunResult,
) callconv(.c) void {
    ppc_host_abi.rosette_ppc_execute(host_context, address, return_address, out_result);
}

pub fn main(init: std.process.Init) !void {
    try process.main(init);
}
