//! Local Xenia cross-architecture ABI package root.
//!
//! The ABI facts below are the same on every route: the guest is a 32-bit
//! big-endian Xenon value space regardless of which host build of Rosette is
//! reading it. Only the route identity differs between the two copies.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";

pub const target = @import("target.zig");
pub const contract = @import("contract.zig");
pub const assembly = @import("assembly.zig");

/// The route this package build speaks for, expressed in the package's own
/// architecture vocabulary rather than as a bare string.
pub const host_route: target.Architecture = .x86_64;

test "package identity is the x86 Xbyak route" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
    try std.testing.expectEqualStrings(host_architecture, host_route.label());
}

test {
    _ = target;
    _ = contract;
    _ = assembly;
}
