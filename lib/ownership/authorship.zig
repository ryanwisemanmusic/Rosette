//! Who authored a piece of guest state.
//!
//! Rosette writes to guest memory and guest registers while repairing faults.
//! Provenance records the *faulting guest RIP* as the writer, because that is
//! what the register file holds when a recovery runs. Nothing downstream could
//! tell the difference, so every consumer — most visibly the near-null
//! causality chain — would confidently attribute Rosette's own store to a guest
//! symbol, and any conclusion drawn from that is about the emulator rather than
//! the program.
//!
//! This is an ownership question about *data*: for a given slot, who owns the
//! value that is there. One definition, so a repair can never be mistaken for
//! guest behaviour.

const std = @import("std");

pub const Author = enum {
    /// The guest executed a store.
    guest,
    /// Rosette wrote this while repairing a fault.
    host_repair,

    pub fn isHost(self: Author) bool {
        return self == .host_repair;
    }

    /// Conclusions about guest behaviour may only be drawn from guest writes.
    pub fn supportsGuestInference(self: Author) bool {
        return self == .guest;
    }
};

/// Scoped marker for "a repair is writing right now".
///
/// Nesting is supported because a repair may call a helper that writes again;
/// the scope restores the previous state rather than clearing unconditionally,
/// so an inner scope cannot end an outer one early.
pub const Scope = struct {
    flag: *bool,
    previous: bool,

    pub fn begin(flag: *bool) Scope {
        const previous = flag.*;
        flag.* = true;
        return .{ .flag = flag, .previous = previous };
    }

    pub fn end(self: Scope) void {
        self.flag.* = self.previous;
    }
};

/// Classify a write given whether a repair scope is active.
pub fn authorOf(repair_in_flight: bool) Author {
    return if (repair_in_flight) .host_repair else .guest;
}

test "a repair scope marks writes and restores on exit" {
    var in_flight = false;
    try std.testing.expectEqual(Author.guest, authorOf(in_flight));

    const scope = Scope.begin(&in_flight);
    try std.testing.expectEqual(Author.host_repair, authorOf(in_flight));
    scope.end();
    try std.testing.expectEqual(Author.guest, authorOf(in_flight));
}

test "nested scopes do not end the outer one early" {
    var in_flight = false;
    const outer = Scope.begin(&in_flight);
    const inner = Scope.begin(&in_flight);
    inner.end();
    // Still inside the outer repair.
    try std.testing.expect(in_flight);
    outer.end();
    try std.testing.expect(!in_flight);
}

test "host writes never support guest inference" {
    try std.testing.expect(Author.guest.supportsGuestInference());
    try std.testing.expect(!Author.host_repair.supportsGuestInference());
    try std.testing.expect(Author.host_repair.isHost());
}
