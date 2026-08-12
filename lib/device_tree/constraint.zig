//! Hardware facts as things the runtime can be checked against.
//!
//! A device tree that only records numbers is documentation. What makes the
//! Linux model useful is that the *consumer* asks the tree instead of assuming,
//! so a wrong assumption becomes a refused question rather than a fault
//! discovered three subsystems later.
//!
//! That is the difference this module exists to make. Every constraint here
//! corresponds to something the runtime previously learned by hitting it: a
//! guest page smaller than the host's, a reserved range the guest protects on
//! purpose, physical views that alias the same RAM, an address space narrower
//! than the host's pointers. Each was found as a fault, and each is a fact that
//! could have been asked for.
//!
//! Deliberately conservative. A constraint is stated only where the hardware
//! genuinely fixes the answer; anything the emulated platform is free to choose
//! is absent rather than guessed, because a confidently wrong constraint is
//! worse than none — it would refuse operations that are actually legal.

const std = @import("std");

/// The answer to "may the runtime do this".
pub const Ruling = enum(u8) {
    /// The hardware fixes this and the operation agrees with it.
    permitted,
    /// The hardware fixes this and the operation contradicts it. Doing it
    /// anyway produces behaviour the guest cannot account for.
    violates_hardware,
    /// The hardware does not fix this. Not permission — absence of a rule, and
    /// the caller must not read it as approval.
    unconstrained,

    pub fn allowed(self: Ruling) bool {
        return self != .violates_hardware;
    }
};

pub const Check = struct {
    ruling: Ruling = .unconstrained,
    /// Short name of the constraint, for reporting.
    rule: []const u8 = "",
    detail: []const u8 = "",
};

pub const permitted_check = Check{ .ruling = .permitted };

pub fn violation(rule: []const u8, detail: []const u8) Check {
    return .{ .ruling = .violates_hardware, .rule = rule, .detail = detail };
}

pub fn unconstrained(rule: []const u8) Check {
    return .{ .ruling = .unconstrained, .rule = rule };
}

pub fn permitted(rule: []const u8) Check {
    return .{ .ruling = .permitted, .rule = rule };
}

test "unconstrained is not permission" {
    const check = unconstrained("page-size");
    try std.testing.expectEqual(Ruling.unconstrained, check.ruling);
    // It does not block the operation...
    try std.testing.expect(check.ruling.allowed());
    // ...but it is distinguishable from an affirmative answer, which is the
    // whole point: a caller that treats "no rule" as "approved" has learned
    // nothing from asking.
    try std.testing.expect(check.ruling != .permitted);
}

test "a violation is reportable with its rule name" {
    const check = violation("reserved-range", "the guest reserves this range");
    try std.testing.expect(!check.ruling.allowed());
    try std.testing.expectEqualStrings("reserved-range", check.rule);
}
