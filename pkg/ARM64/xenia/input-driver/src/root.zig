//! ARM64 host-side facts for reading a host gamepad into guest state.
//!
//! The console-side layout — button bits, stick ranges, dead zones — is
//! `pkg/common/xenia/input-contract` and is the same everywhere. What is
//! route-local is how a freshly polled controller state becomes visible to the
//! guest thread that reads it.
//!
//! ## Why the publish width is a route fact
//!
//! Input is produced on a host polling thread and consumed by a guest thread
//! that may read it at any instant. `XINPUT_STATE` is sixteen bytes, and a
//! reader that catches a half-written one sees a button word from this poll
//! beside a stick position from the last. That is a torn read, and it presents
//! as input that occasionally "sticks" or fires twice — rare, unreproducible,
//! and almost never attributed to a memory-ordering problem.
//!
//! The widest atomic store the route offers decides whether the state can be
//! published in one operation or needs a sequence lock. Both routes here reach
//! sixteen bytes, so the whole `XINPUT_STATE` can be published atomically —
//! which is a fact worth stating, because the alternative design is much more
//! intricate and would be adopted needlessly if nobody checked.
//!
//! ## What this package is not
//!
//! * It is not an input system. It polls nothing; `lib/hid/` owns the host
//!   device, its callbacks, and the poll loop.
//! * It holds no controller state. A published snapshot is live state.
//! * It does not map buttons. Which host button is "A" depends on the pad that
//!   happens to be connected, which is a runtime observation.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_input_backend = "gamecontroller";

/// The widest value the route can store atomically in a single operation.
///
/// An LDXP/STXP pair gives a 16-byte atomic on AArch64. The pair
/// requires 16-byte alignment; an underaligned operand takes an alignment
/// fault.
pub const atomic_publish_bytes: u32 = 16;
pub const atomic_publish_primitive = "ldxp-stxp";

/// `XINPUT_STATE` is sixteen bytes: a `u32` packet number and a twelve-byte
/// gamepad. Restated here as the size that must be published, so the
/// comparison against `atomic_publish_bytes` is explicit.
pub const controller_state_bytes: u32 = 16;

/// Poll rate. Above the console's 60 Hz sampling so a button press is never
/// missed between guest reads, and low enough not to spin a core.
pub const poll_rate_hz: u32 = 120;

/// Whether a state of this size can be published without a sequence lock.
pub fn isAtomicallyPublishable(bytes: u32) bool {
    return bytes != 0 and bytes <= atomic_publish_bytes;
}

/// Whether an address is aligned for the route's widest atomic store.
///
/// A wide atomic on an underaligned address is not merely slow — on some
/// routes it is not atomic at all, which reintroduces the torn read the wide
/// store was chosen to prevent.
pub fn isAtomicallyAligned(address: u64) bool {
    return address % atomic_publish_bytes == 0;
}

test "package identity is the ARM64 input route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("ldxp-stxp", atomic_publish_primitive);
}

test "the whole controller state fits one atomic publish" {
    // The reason lib/hid does not need a sequence lock. If this ever fails,
    // the torn-read design question is reopened rather than silently wrong.
    try std.testing.expectEqual(@as(u32, 16), controller_state_bytes);
    try std.testing.expect(isAtomicallyPublishable(controller_state_bytes));
    try std.testing.expect(controller_state_bytes <= atomic_publish_bytes);
}

test "an oversized state is not atomically publishable" {
    try std.testing.expect(!isAtomicallyPublishable(0));
    try std.testing.expect(!isAtomicallyPublishable(atomic_publish_bytes + 1));
    try std.testing.expect(!isAtomicallyPublishable(32));
}

test "wide atomics require their own alignment" {
    try std.testing.expect(isAtomicallyAligned(0x1000));
    try std.testing.expect(isAtomicallyAligned(0x1010));
    try std.testing.expect(!isAtomicallyAligned(0x1008));
    try std.testing.expect(!isAtomicallyAligned(0x1004));
}

test "the poll rate outruns the console's sampling" {
    // 120 Hz against a 60 Hz guest read. Polling at or below the guest rate
    // lets a short press land entirely between two reads and vanish.
    try std.testing.expectEqual(@as(u32, 120), poll_rate_hz);
    try std.testing.expect(poll_rate_hz > 60);
}
