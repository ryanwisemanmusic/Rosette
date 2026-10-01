//! Access-class policy for the hybrid TSO memory paths.
//!
//! Guest image and ordinary mapped RAM may use the executor's store buffer.
//! Device aliases and accesses whose Windows protection routes through the
//! guest exception handler must reach their backing/handler immediately and
//! use the coordinated scalar access path. A non-temporal store is an
//! instruction class rather than an address class; callers explicitly bypass
//! buffering and name that boundary when issuing it. The instruction class
//! overrides ordinary RAM buffering even when the destination itself is RAM.

const std = @import("std");

pub const MemoryClass = enum {
    ordinary_ram,
    device_backed,
    fault_routed,
};

pub fn classify(device_backed: bool, fault_routed: bool) MemoryClass {
    if (fault_routed) return .fault_routed;
    if (device_backed) return .device_backed;
    return .ordinary_ram;
}

pub fn bypassStoreBuffer(class: MemoryClass) bool {
    return class != .ordinary_ram;
}

/// A non-temporal instruction must bypass the ordinary temporal queue even
/// when its destination is ordinary RAM. Device and fault-routed classes keep
/// their more specific synchronous boundary in the caller.
pub fn bypassStoreBufferForStore(class: MemoryClass, non_temporal: bool) bool {
    return non_temporal or bypassStoreBuffer(class);
}

/// Parallel accesses always coordinate. Device and fault-routed accesses
/// also coordinate in serial mode so that their ordering and helper behavior
/// do not depend on whether the executor currently has peer guest threads.
pub fn requiresCoordinator(class: MemoryClass, parallel: bool) bool {
    return parallel or class != .ordinary_ram;
}

test "ordinary RAM is the only class admitted to the guest store buffer" {
    try std.testing.expect(!bypassStoreBuffer(.ordinary_ram));
    try std.testing.expect(bypassStoreBuffer(.device_backed));
    try std.testing.expect(bypassStoreBuffer(.fault_routed));
    try std.testing.expect(requiresCoordinator(.ordinary_ram, true));
    try std.testing.expect(!requiresCoordinator(.ordinary_ram, false));
    try std.testing.expect(requiresCoordinator(.device_backed, false));
    try std.testing.expect(requiresCoordinator(.fault_routed, false));
}

test "fault routing takes precedence when a protected page is device-backed" {
    try std.testing.expectEqual(MemoryClass.fault_routed, classify(true, true));
    try std.testing.expectEqual(MemoryClass.device_backed, classify(true, false));
    try std.testing.expectEqual(MemoryClass.ordinary_ram, classify(false, false));
}

test "non-temporal stores bypass ordinary buffering for every destination class" {
    try std.testing.expect(bypassStoreBufferForStore(.ordinary_ram, true));
    try std.testing.expect(bypassStoreBufferForStore(.device_backed, true));
    try std.testing.expect(bypassStoreBufferForStore(.fault_routed, true));
    try std.testing.expect(!bypassStoreBufferForStore(.ordinary_ram, false));
    try std.testing.expect(bypassStoreBufferForStore(.device_backed, false));
    try std.testing.expect(bypassStoreBufferForStore(.fault_routed, false));
}
