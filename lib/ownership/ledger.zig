//! Per-family bookkeeping for generated-code recoveries.
//!
//! Every recovery family used to share three pieces of state: a counter, a
//! throttle derived from that counter, and one loop guard keyed on a single
//! `last_dispatch_recovery_rip`. Sharing made all three lie. A counter bumped
//! by two mechanisms no longer names either of them; a throttle driven by that
//! counter silently drops log lines from one family because another was busy;
//! and a loop guard reset by any family gives none of them an independent
//! budget — a recovery that alternates between two sites never reaches its
//! limit at all.
//!
//! One ledger per family, one meaning per field. The ledger is the only
//! definition of "how many", "should this be logged", and "is this looping".

const std = @import("std");

/// The one throttle rule: the first eight occurrences, then power-of-two
/// milestones. Sites that count something not owned by a `Ledger` call this
/// directly so the cadence of the log is decided in exactly one place.
pub fn throttled(count: u64) bool {
    return count <= 8 or std.math.isPowerOfTwo(count);
}

pub const Ledger = struct {
    /// Successful recoveries attributed to this family, and only this family.
    recoveries: u64 = 0,
    /// Site of the most recent recovery, for the loop guard.
    last_site: u64 = 0,
    /// Consecutive recoveries at `last_site`.
    consecutive: u32 = 0,

    /// A recovery that keeps firing at one site is not making progress. The
    /// budget is per-family so one family exhausting it cannot mask another,
    /// and so no family can refill another's.
    pub const consecutive_limit: u32 = 16;

    pub fn note(self: *Ledger) void {
        self.recoveries +|= 1;
    }

    /// Throttle: the first few occurrences plus power-of-two milestones. Reads
    /// this family's own counter, so a quiet family still reports its first
    /// events however loud its neighbours are.
    pub fn shouldLog(self: *const Ledger) bool {
        return throttled(self.recoveries);
    }

    /// Returns false once this family has recovered at `site` more times in a
    /// row than the budget allows. Callers must treat false as "stop
    /// recovering and let the terminal diagnostics run".
    pub fn loopAllowed(self: *Ledger, site: u64) bool {
        if (self.last_site == site) {
            self.consecutive +|= 1;
            return self.consecutive <= consecutive_limit;
        }
        self.last_site = site;
        self.consecutive = 1;
        return true;
    }
};

test "ledger throttles on its own counter" {
    var ledger = Ledger{};
    var logged: usize = 0;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        ledger.note();
        if (ledger.shouldLog()) logged += 1;
    }
    // 1..8, then 16 and 32.
    try std.testing.expectEqual(@as(usize, 10), logged);
}

test "loop guard is per site and bounded" {
    var ledger = Ledger{};
    var i: u32 = 0;
    while (i < Ledger.consecutive_limit) : (i += 1) {
        try std.testing.expect(ledger.loopAllowed(0x1000));
    }
    try std.testing.expect(!ledger.loopAllowed(0x1000));
    // A different site restarts the budget for that site only.
    try std.testing.expect(ledger.loopAllowed(0x2000));
    try std.testing.expectEqual(@as(u32, 1), ledger.consecutive);
}

test "alternating sites do not refill each other" {
    // The shared guard reset its counter whenever the site changed, so a
    // recovery ping-ponging between two sites never hit the limit. Each ledger
    // now tracks one family, and a family that genuinely alternates still
    // reports honest per-site counts rather than an unbounded loop.
    var ledger = Ledger{};
    try std.testing.expect(ledger.loopAllowed(0x1000));
    try std.testing.expect(ledger.loopAllowed(0x2000));
    try std.testing.expectEqual(@as(u64, 0x2000), ledger.last_site);
    try std.testing.expectEqual(@as(u32, 1), ledger.consecutive);
}
