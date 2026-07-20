const std = @import("std");

/// Pure CMPXCHG state transition. Memory/register access and architectural
/// flag materialization stay in the interpreter; keeping the transition here
/// makes byte-atomic behavior independently testable.
pub const Result = struct {
    matched: bool,
    destination: u64,
    accumulator: u64,
    difference: u64,
};

pub fn evaluate(expected: u64, actual: u64, replacement: u64) Result {
    const matched = expected == actual;
    return .{
        .matched = matched,
        .destination = if (matched) replacement else actual,
        .accumulator = if (matched) expected else actual,
        .difference = expected -% actual,
    };
}

pub const Stats = struct {
    operations: u64 = 0,
    successes: u64 = 0,
    failures: u64 = 0,

    pub fn record(self: *Stats, matched: bool) void {
        self.operations +|= 1;
        if (matched) {
            self.successes +|= 1;
        } else {
            self.failures +|= 1;
        }
    }

    /// Repeated recovery of a compare-exchange failure branch without a
    /// single decoded byte CAS is decoder/interpreter evidence, not evidence
    /// that the guest application's atomic invariant is wrong.
    pub fn indicatesDecoderGap(self: Stats, classified_ud2_recoveries: u64) bool {
        return classified_ud2_recoveries != 0 and self.operations == 0;
    }
};

test "compare exchange success replaces the destination" {
    const result = evaluate(0, 0, 1);
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(u64, 1), result.destination);
    try std.testing.expectEqual(@as(u64, 0), result.accumulator);
    try std.testing.expectEqual(@as(u64, 0), result.difference);
}

test "compare exchange failure preserves destination and loads accumulator" {
    const result = evaluate(0, 3, 1);
    try std.testing.expect(!result.matched);
    try std.testing.expectEqual(@as(u64, 3), result.destination);
    try std.testing.expectEqual(@as(u64, 3), result.accumulator);
    try std.testing.expectEqual(std.math.maxInt(u64) - 2, result.difference);
}

test "atomic statistics identify a missing decoder path" {
    var stats = Stats{};
    try std.testing.expect(stats.indicatesDecoderGap(240));
    stats.record(true);
    try std.testing.expect(!stats.indicatesDecoderGap(240));
    try std.testing.expectEqual(@as(u64, 1), stats.successes);
}
