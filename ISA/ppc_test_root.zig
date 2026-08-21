//! Standalone harness for the PowerPC ISA tables and their ARM64/NEON mirrors.
//!
//! It lives at the ISA root, not under ISA/ppc/, because it spans two trees:
//! a Zig module may only import files under its own root directory, and the
//! PPC source tables (ISA/ppc) and their ARM64 mirrors (ISA/NEON/PPC) are
//! siblings.
//!
//! The registry validators report shape violations through the runtime ABI
//! handshake rather than returning errors, so this harness turns fail-fast on:
//! any PPC table or mirror that drops part of its contract aborts the test
//! instead of being written to a log nobody reads.

const std = @import("std");

pub const ppc = @import("ppc/Zig/root.zig");
pub const neon = @import("NEON/PPC/Zig/root.zig");

pub export fn rosette_debug_enabled() c_int {
    return 0;
}

pub export fn rosette_debug_log_path() [*:0]const u8 {
    return "".ptr;
}

pub export fn rosette_runtime_abi_fail_fast_enabled() c_int {
    return 1;
}

test "PPC ISA tables validate under fail-fast ABI checking" {
    ppc.validateAll();
}

test "PPC ARM64/NEON mirrors validate under fail-fast ABI checking" {
    neon.validateAll();
}

test "PPC tables and mirrors cover the same instruction set" {
    try std.testing.expectEqual(ppc.tableCount(), neon.tableCount());
    for (ppc.tables) |table| {
        try std.testing.expect(neon.findMirror(table.path) != null);
    }
}

test {
    _ = ppc;
    _ = neon;
}
