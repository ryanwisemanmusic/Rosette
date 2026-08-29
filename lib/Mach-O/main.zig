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
const application_framework = @import("application_framework");
const application_framework_contract = application_framework.contract;
const xenia_launch_assist_contract = @import("xenia_launch_assist_contract");
const xenia_host_gpu_callback_contract = @import("xenia_host_gpu_callback_contract");

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

// The application framework follows the same root-export rule as the heap and
// PPC providers above. Xenia resolves these symbols with dlsym while it is
// hosted by this executable; exporting them from main keeps the ABI visible in
// the final Mach-O image rather than only in an imported Zig module.
pub export fn rosette_application_framework_abi_version() callconv(.c) u32 {
    return application_framework_contract.abi_version;
}

pub export fn rosette_application_framework_schema_version() callconv(.c) u16 {
    return application_framework_contract.schema_version;
}

pub export fn rosette_application_framework_handle() callconv(.c) *application_framework.Framework {
    return application_framework.defaultHandle();
}

pub export fn rosette_application_framework_configure(
    handle: *application_framework.Framework,
    config: *const application_framework_contract.Config,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(config) == 0) return 0;
    return @intFromBool(handle.configure(config.*));
}

pub export fn rosette_application_framework_register_adapter(
    handle: *application_framework.Framework,
    name: [*:0]const u8,
    capabilities: u64,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(name) == 0) return 0;
    return @intFromBool(handle.registerAdapter(std.mem.span(name), capabilities));
}

pub export fn rosette_application_framework_emit(
    handle: *application_framework.Framework,
    event: *const application_framework_contract.Event,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(event) == 0) return 0;
    if (!abiRecordIsCompatible(event.size, event.schema, @sizeOf(application_framework_contract.Event))) return 0;
    handle.emit(event.*);
    return @intFromBool(handle.isEnabled());
}

pub export fn rosette_application_framework_observe_function_enter(
    handle: *application_framework.Framework,
    owner_raw: u8,
    domain_raw: u8,
    name: [*:0]const u8,
    guest_step: u64,
    guest_rip: u64,
    thread_id: u64,
    host_pc: u64,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(name) == 0) return 0;
    const owner = enumFromRaw(application_framework_contract.Owner, owner_raw) orelse return 0;
    const domain = enumFromRaw(application_framework_contract.Domain, domain_raw) orelse return 0;
    handle.observeFunctionEnter(owner, domain, std.mem.span(name), guest_step, guest_rip, thread_id, host_pc);
    return 1;
}

pub export fn rosette_application_framework_observe_function_exit(
    handle: *application_framework.Framework,
    owner_raw: u8,
    domain_raw: u8,
    name: [*:0]const u8,
    guest_step: u64,
    guest_rip: u64,
    thread_id: u64,
    result: u64,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(name) == 0) return 0;
    const owner = enumFromRaw(application_framework_contract.Owner, owner_raw) orelse return 0;
    const domain = enumFromRaw(application_framework_contract.Domain, domain_raw) orelse return 0;
    handle.observeFunctionExit(owner, domain, std.mem.span(name), guest_step, guest_rip, thread_id, result);
    return 1;
}

pub export fn rosette_application_framework_observe_control_transfer(
    handle: *application_framework.Framework,
    owner_raw: u8,
    source: u64,
    target: u64,
    guest_step: u64,
    thread_id: u64,
    taken: u8,
    name: [*:0]const u8,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(name) == 0) return 0;
    const owner = enumFromRaw(application_framework_contract.Owner, owner_raw) orelse return 0;
    handle.observeControlTransfer(owner, source, target, guest_step, thread_id, taken != 0, std.mem.span(name));
    return 1;
}

pub export fn rosette_application_framework_observe_value(
    handle: *application_framework.Framework,
    owner_raw: u8,
    domain_raw: u8,
    subject: u64,
    actual: u64,
    guest_step: u64,
    guest_rip: u64,
    name: [*:0]const u8,
    detail: [*:0]const u8,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(name) == 0 or @intFromPtr(detail) == 0) return 0;
    const owner = enumFromRaw(application_framework_contract.Owner, owner_raw) orelse return 0;
    const domain = enumFromRaw(application_framework_contract.Domain, domain_raw) orelse return 0;
    handle.observeValue(owner, domain, subject, actual, guest_step, guest_rip, std.mem.span(name), std.mem.span(detail));
    return 1;
}

pub export fn rosette_application_framework_compare(
    handle: *application_framework.Framework,
    owner_raw: u8,
    domain_raw: u8,
    subject: u64,
    expected: u64,
    actual: u64,
    mask: u64,
    guest_step: u64,
    guest_rip: u64,
    name: [*:0]const u8,
) callconv(.c) u8 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(name) == 0) return @intFromEnum(application_framework_contract.Equivalence.unavailable);
    const owner = enumFromRaw(application_framework_contract.Owner, owner_raw) orelse return @intFromEnum(application_framework_contract.Equivalence.unavailable);
    const domain = enumFromRaw(application_framework_contract.Domain, domain_raw) orelse return @intFromEnum(application_framework_contract.Equivalence.unavailable);
    return @intFromEnum(handle.compareValue(owner, domain, subject, expected, actual, mask, guest_step, guest_rip, std.mem.span(name)));
}

pub export fn rosette_application_framework_request(
    handle: *application_framework.Framework,
    request: *const application_framework_contract.Request,
    result: *application_framework_contract.RequestResult,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(request) == 0 or @intFromPtr(result) == 0) return 0;
    if (!abiRecordIsCompatible(request.size, request.schema, @sizeOf(application_framework_contract.Request))) {
        result.* = .{ .status = @intFromEnum(application_framework_contract.RequestStatus.invalid) };
        return 0;
    }
    result.* = handle.request(request.*);
    return 1;
}

pub export fn rosette_application_framework_take_request(
    handle: *application_framework.Framework,
    request: *application_framework_contract.Request,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(request) == 0) return 0;
    return @intFromBool(handle.takePending(request));
}

pub export fn rosette_application_framework_complete_request(
    handle: *application_framework.Framework,
    request_id: u64,
    status_raw: u8,
    reason_code: u64,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0) return 0;
    const status = enumFromRaw(application_framework_contract.RequestStatus, status_raw) orelse return 0;
    return @intFromBool(handle.complete(request_id, status, reason_code));
}

pub export fn rosette_application_framework_read_event(
    handle: *application_framework.Framework,
    ordinal: u64,
    event: *application_framework_contract.Event,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(event) == 0 or ordinal > std.math.maxInt(usize)) return 0;
    return @intFromBool(handle.readEvent(@intCast(ordinal), event));
}

pub export fn rosette_application_framework_snapshot(
    handle: *application_framework.Framework,
    snapshot: *application_framework_contract.Snapshot,
) callconv(.c) i32 {
    if (@intFromPtr(handle) == 0 or @intFromPtr(snapshot) == 0) return 0;
    snapshot.* = handle.snapshot();
    return 1;
}

/// Rosette's Xenia adapter resolves this ABI with dlsym. The request is a
/// proof-bearing host-startup record; the response can authorize only the
/// package-defined host operations and never guest execution or GPU output.
pub export fn rosette_xenia_launch_assist_abi_version() callconv(.c) u32 {
    return xenia_launch_assist_contract.abi_version;
}

pub export fn rosette_xenia_launch_assist_schema_version() callconv(.c) u16 {
    return xenia_launch_assist_contract.schema_version;
}

pub export fn rosette_xenia_launch_assist_query(
    request: *const xenia_launch_assist_contract.Request,
    response: *xenia_launch_assist_contract.Response,
) callconv(.c) i32 {
    if (@intFromPtr(request) == 0 or @intFromPtr(response) == 0) return 0;
    response.* = application_framework.defaultHandle().queryXeniaLaunchAssist(request.*);
    return 1;
}

pub export fn rosette_xenia_launch_assist_report(
    request: *const xenia_launch_assist_contract.Request,
    response: *const xenia_launch_assist_contract.Response,
    applied_actions: u32,
    status_raw: u8,
) callconv(.c) i32 {
    if (@intFromPtr(request) == 0 or @intFromPtr(response) == 0) return 0;
    const status = enumFromRaw(xenia_launch_assist_contract.ApplyStatus, status_raw) orelse return 0;
    return @intFromBool(application_framework.defaultHandle().reportXeniaLaunchAssist(
        request.*,
        response.*,
        applied_actions,
        status,
    ));
}

/// Xenia resolves this optional provider with dlsym.  The response authorizes
/// only Xenia's own host callback trampoline; it cannot manufacture a guest
/// VdSet callback, PM4 packet, ring write, XE_SWAP, or presentation fact.
pub export fn rosette_xenia_host_gpu_callback_abi_version() callconv(.c) u32 {
    return xenia_host_gpu_callback_contract.abi_version;
}

pub export fn rosette_xenia_host_gpu_callback_schema_version() callconv(.c) u16 {
    return xenia_host_gpu_callback_contract.schema_version;
}

pub export fn rosette_xenia_host_gpu_callback_query(
    request: *const xenia_host_gpu_callback_contract.Request,
    response: *xenia_host_gpu_callback_contract.Response,
) callconv(.c) i32 {
    if (@intFromPtr(request) == 0 or @intFromPtr(response) == 0) return 0;
    response.* = application_framework.defaultHandle().queryXeniaHostGpuCallback(request.*);
    return 1;
}

pub export fn rosette_xenia_host_gpu_callback_report(
    request: *const xenia_host_gpu_callback_contract.Request,
    response: *const xenia_host_gpu_callback_contract.Response,
    applied_actions: u32,
    status_raw: u8,
) callconv(.c) i32 {
    if (@intFromPtr(request) == 0 or @intFromPtr(response) == 0) return 0;
    const status = enumFromRaw(xenia_host_gpu_callback_contract.ApplyStatus, status_raw) orelse return 0;
    return @intFromBool(application_framework.defaultHandle().reportXeniaHostGpuCallback(
        request.*,
        response.*,
        applied_actions,
        status,
    ));
}

fn abiRecordIsCompatible(size: u16, schema: u16, expected_size: usize) bool {
    if (schema != 0 and schema != application_framework_contract.schema_version) return false;
    if (size != 0 and size < expected_size) return false;
    return true;
}

fn enumFromRaw(comptime T: type, raw: u8) ?T {
    const fields = @typeInfo(T).@"enum".fields;
    if (raw >= fields.len) return null;
    return @enumFromInt(raw);
}

pub fn main(init: std.process.Init) !void {
    try process.main(init);
}
