const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");

pub const x86 = @import("x86/Zig/root.zig");
pub const neon = @import("NEON/Zig/root.zig");
pub const ppc = @import("ppc/Zig/root.zig");
pub const ppc_neon = @import("NEON/PPC/Zig/root.zig");
pub const math = @import("Math/root.zig");

pub fn validateAll() void {
    runtime_abi.isa.init();
    defer runtime_abi.isa.deinit();

    x86.validateAll();
    neon.validateAll();
    ppc.validateAll();
    ppc_neon.validateAll();
    math.validateAll();
}

test "ISA registry validates x86 tables and NEON mirrors" {
    try std.testing.expectEqual(x86.tableCount(), neon.tableCount());
    validateAll();
    try math.exerciseAll();
}

test "ISA registry validates PPC tables and their ARM64 mirrors" {
    // The PPC source tables and their ARM64/NEON lowerings mirror one another
    // the same way the x86 tables and ISA/NEON do, and the two source ISAs stay
    // in separate trees so neither count constrains the other.
    try std.testing.expectEqual(ppc.tableCount(), ppc_neon.tableCount());
    try std.testing.expect(ppc.tableCount() > 0);
    try std.testing.expect(ppc.findByName("addx") != null);
    try std.testing.expect(ppc.findByName("lwzx") != null);
    try std.testing.expect(ppc.findByName("vaddubm") != null);
}
