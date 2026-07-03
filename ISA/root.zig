const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");

pub const x86 = @import("x86/Zig/root.zig");
pub const neon = @import("NEON/Zig/root.zig");
pub const math = @import("Math/root.zig");

pub fn validateAll() void {
    runtime_abi.isa.init();
    defer runtime_abi.isa.deinit();

    x86.validateAll();
    neon.validateAll();
    math.validateAll();
}

test "ISA registry validates x86 tables and NEON mirrors" {
    try std.testing.expectEqual(x86.tableCount(), neon.tableCount());
    validateAll();
    try math.exerciseAll();
}
