const std = @import("std");
const common = @import("../common.zig");
const types = @import("types.zig");

pub const AccessKind = enum { read, write, fetch };
pub const HostState = types.HostState;
pub const HostCallingConvention = types.HostCallingConvention;
pub const HostSignalKind = types.HostSignalKind;

pub fn init() void {
    common.acquire();
}

pub fn deinit() void {
    common.release();
}

pub fn validateMemoryAccess(kind: AccessKind, addr: u64, width: usize, permissions: u8, aligned: bool, null_page: bool, guard_page: bool, stack_access: bool) void {
    common.noteValidation();
    if (null_page)
        common.violation("arm64", "null_page", "{s} at 0x{x} touched null page", .{ @tagName(kind), addr });
    if (guard_page)
        common.violation("arm64", "guard_page", "{s} at 0x{x} touched guard page", .{ @tagName(kind), addr });
    if (!aligned)
        common.violation("arm64", "unaligned_access", "{s} at 0x{x} width {d} unaligned", .{ @tagName(kind), addr, width });
    const need_bit: u8 = switch (kind) {
        .read => 1 << 0,
        .write => 1 << 1,
        .fetch => 1 << 2,
    };
    if ((permissions & need_bit) == 0)
        common.violation("arm64", "page_permissions", "{s} at 0x{x} width {d} denied by perms 0x{x}", .{ @tagName(kind), addr, width, permissions });
    _ = stack_access;
}

pub fn validateHostState(phase: []const u8, state: *const HostState) void {
    common.noteValidation();
    if ((state.sp & 0xF) != 0)
        common.violation("arm64", "sp_alignment", "{s}: SP 0x{x} is not 16-byte aligned", .{ phase, state.sp });
    if (state.pc == 0)
        common.violation("arm64", "pc_zero", "{s}: PC is zero", .{phase});
    if ((state.nzcv & 0x0FFF_FFFF) != 0)
        common.violation("arm64", "nzcv_layout", "{s}: NZCV lower bits should be zero, saw 0x{x}", .{ phase, state.nzcv });
    if (state.page_size < 4096 or !std.math.isPowerOfTwo(state.page_size))
        common.violation("arm64", "page_size", "{s}: host page size {d} invalid", .{ phase, state.page_size });
    if (state.call_boundary and state.x[30] == 0)
        common.violation("arm64", "lr_zero", "{s}: LR/X30 is zero at a host call boundary", .{phase});
    if (state.generated_code_dirty and !state.cache_coherent)
        common.violation("arm64", "cache_coherency", "{s}: generated code is dirty without cache coherency", .{phase});
    if (state.call_boundary and state.calling_convention != .darwin_aapcs64 and state.calling_convention != .lowered_guest and state.calling_convention != .windows_arm64ec)
        common.violation("arm64", "calling_convention", "{s}: unsupported host calling convention tag", .{phase});
    validateSignalDelivery(phase, state.signal_kind, state.signal_mapped_exception);
}

pub fn validateCallBoundary(phase: []const u8, state: *const HostState) void {
    common.noteValidation();
    if (!state.call_boundary) return;
    if ((state.sp & 0xF) != 0)
        common.violation("arm64", "call_boundary_sp", "{s}: call boundary SP 0x{x} is misaligned", .{ phase, state.sp });
    if (state.calling_convention == .darwin_aapcs64 and state.x[18] != 0)
        common.violation("arm64", "platform_register", "{s}: Darwin host boundary expects X18 unused/reserved, saw 0x{x}", .{ phase, state.x[18] });
}

pub fn validateSignalDelivery(phase: []const u8, signal_kind: HostSignalKind, mapped_exception: u32) void {
    common.noteValidation();
    switch (signal_kind) {
        .none => {},
        .sigill, .sigtrap, .sigabort, .sigfpe, .sigbus, .sigsegv => {
            if (mapped_exception == 0)
                common.violation("arm64", "signal_mapping", "{s}: signal {s} missing mapped exception code", .{ phase, @tagName(signal_kind) });
        },
        else => {},
    }
}

test "arm64 host state validation accepts sane darwin boundary" {
    var state: HostState = .{};
    state.sp = 0x4000;
    state.pc = 0x1000;
    state.x[29] = 0x4100;
    state.x[30] = 0x4200;
    state.nzcv = 0xA0000000;
    state.call_boundary = true;
    validateHostState("arm64-runtime-test", &state);
    validateCallBoundary("arm64-runtime-test", &state);
}
