//! What instrumentation is allowed to cost.
//!
//! Diagnostics that run on the hot path have to be paid for out of the run's
//! wall clock, and a run that takes 962 seconds instead of 202 has not been
//! made more observable — it has been made unusable, and the failure it was
//! supposed to explain now happens somewhere else or not at all.
//!
//! The instinct that causes this is right in isolation: each observer wants to
//! see the whole run so it can say "this never happened anywhere". The mistake
//! is letting each observer decide that for itself, which is the same
//! duplicated-authority pattern this library exists to break — here spending a
//! shared resource (time) rather than a shared decision.
//!
//! A budget is an explicit allowance with an explicit end, and — the part that
//! matters — an observer that ran out says so. A count of zero from an observer
//! whose budget expired is not evidence of absence, and reporting it as though
//! it were is exactly the mistake this codebase keeps making with empty rings
//! and unset flags.

const std = @import("std");

pub const Budget = struct {
    /// Events this budget still permits.
    remaining: u64,
    /// Events that arrived after it ran out.
    declined: u64 = 0,
    /// Events permitted so far.
    spent: u64 = 0,

    pub fn init(allowance: u64) Budget {
        return .{ .remaining = allowance };
    }

    /// Take one event from the budget. The caller does the work only when this
    /// returns true.
    ///
    /// Written so the exhausted case is a single predictable branch: once the
    /// budget is gone this is one compare and a saturating increment, which is
    /// what keeps the path hot for the rest of the run.
    pub fn take(self: *Budget) bool {
        if (self.remaining == 0) {
            self.declined +|= 1;
            return false;
        }
        self.remaining -= 1;
        self.spent +|= 1;
        return true;
    }

    pub fn exhausted(self: *const Budget) bool {
        return self.remaining == 0;
    }

    /// True when the budget ran out *and* events kept arriving, so any count
    /// this observer produced covers only part of the run. Callers must report
    /// this alongside their findings: "never observed" and "never observed
    /// within budget" are different claims.
    pub fn truncated(self: *const Budget) bool {
        return self.remaining == 0 and self.declined != 0;
    }
};

test "a budget permits its allowance and then declines" {
    var budget = Budget.init(3);
    try std.testing.expect(budget.take());
    try std.testing.expect(budget.take());
    try std.testing.expect(budget.take());
    try std.testing.expect(!budget.take());
    try std.testing.expectEqual(@as(u64, 3), budget.spent);
    try std.testing.expectEqual(@as(u64, 1), budget.declined);
    try std.testing.expect(budget.exhausted());
}

test "truncation distinguishes a spent budget from an untested one" {
    // Spent exactly, nothing declined: the observer saw everything offered, so
    // its counts are complete.
    var complete = Budget.init(2);
    _ = complete.take();
    _ = complete.take();
    try std.testing.expect(complete.exhausted());
    try std.testing.expect(!complete.truncated());

    // Spent and then declined: the counts cover only part of the run and must
    // not be reported as whole-run evidence.
    _ = complete.take();
    try std.testing.expect(complete.truncated());
}

test "a zero allowance declines immediately without underflow" {
    var budget = Budget.init(0);
    try std.testing.expect(!budget.take());
    try std.testing.expectEqual(@as(u64, 0), budget.remaining);
    try std.testing.expectEqual(@as(u64, 1), budget.declined);
}
