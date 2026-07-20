const std = @import("std");

pub const Kind = enum(u8) {
    guest_assertion,
    classified_ud2_recovery,
    lazy_import_dispatch,
};

pub const Disposition = enum {
    /// First observation of this symbol/case pair: print full context.
    detail,
    /// A power-of-ten occurrence: print one compact liveness checkpoint.
    checkpoint,
    /// Repeated context that is already represented by a detail/checkpoint.
    suppress,
};

pub const Observation = struct {
    disposition: Disposition,
    occurrence: u64,
    suppressed_since_emit: u64,
};

const capacity = 256;

const Entry = struct {
    occupied: bool = false,
    kind: Kind = .guest_assertion,
    symbol: u64 = 0,
    variant: u64 = 0,
    occurrences: u64 = 0,
    last_emitted_occurrence: u64 = 0,
};

pub const Summary = struct {
    observed: u64,
    unique: u64,
    detailed: u64,
    checkpoints: u64,
    suppressed: u64,
    capacity_overflows: u64,
};

/// Bounded, allocation-free throttling for diagnostics reached from hot guest
/// paths. Keys are deliberately symbol-oriented so a new caller or a new case
/// within the same caller always receives a full diagnostic.
pub const Tracker = struct {
    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    observed: u64 = 0,
    unique: u64 = 0,
    detailed: u64 = 0,
    checkpoints: u64 = 0,
    suppressed: u64 = 0,
    capacity_overflows: u64 = 0,

    pub fn observe(self: *Tracker, kind: Kind, symbol: u64, variant: u64) Observation {
        self.observed +|= 1;
        const start: usize = @truncate(hash(kind, symbol, variant));
        for (0..capacity) |probe| {
            const index = (start + probe) & (capacity - 1);
            const entry = &self.entries[index];
            if (!entry.occupied) {
                entry.* = .{
                    .occupied = true,
                    .kind = kind,
                    .symbol = symbol,
                    .variant = variant,
                    .occurrences = 1,
                    .last_emitted_occurrence = 1,
                };
                self.unique +|= 1;
                self.detailed +|= 1;
                return .{ .disposition = .detail, .occurrence = 1, .suppressed_since_emit = 0 };
            }
            if (entry.kind != kind or entry.symbol != symbol or entry.variant != variant) continue;

            entry.occurrences +|= 1;
            if (isPowerOfTen(entry.occurrences)) {
                const since = entry.occurrences -| entry.last_emitted_occurrence -| 1;
                entry.last_emitted_occurrence = entry.occurrences;
                self.checkpoints +|= 1;
                return .{
                    .disposition = .checkpoint,
                    .occurrence = entry.occurrences,
                    .suppressed_since_emit = since,
                };
            }
            self.suppressed +|= 1;
            return .{
                .disposition = .suppress,
                .occurrence = entry.occurrences,
                .suppressed_since_emit = entry.occurrences -| entry.last_emitted_occurrence,
            };
        }

        // Never hide a genuinely new case merely because the bounded catalog
        // filled. This should be exceptional and remains visible in summary.
        self.capacity_overflows +|= 1;
        self.detailed +|= 1;
        return .{ .disposition = .detail, .occurrence = 1, .suppressed_since_emit = 0 };
    }

    pub fn summary(self: *const Tracker) Summary {
        return .{
            .observed = self.observed,
            .unique = self.unique,
            .detailed = self.detailed,
            .checkpoints = self.checkpoints,
            .suppressed = self.suppressed,
            .capacity_overflows = self.capacity_overflows,
        };
    }

    pub fn logSummary(self: *const Tracker) void {
        const totals = self.summary();
        if (totals.observed == 0) return;
        std.debug.print(
            "macho-processor: repetitive diagnostic throttle: observed={d} unique_symbol_cases={d} detailed={d} checkpoints={d} suppressed={d} capacity_overflows={d}\n",
            .{ totals.observed, totals.unique, totals.detailed, totals.checkpoints, totals.suppressed, totals.capacity_overflows },
        );
    }
};

fn hash(kind: Kind, symbol: u64, variant: u64) u64 {
    var value = symbol ^ (variant *% 0x9E37_79B9_7F4A_7C15) ^ @intFromEnum(kind);
    value ^= value >> 30;
    value *%= 0xBF58_476D_1CE4_E5B9;
    value ^= value >> 27;
    value *%= 0x94D0_49BB_1331_11EB;
    return value ^ (value >> 31);
}

fn isPowerOfTen(value: u64) bool {
    if (value < 10) return false;
    var remaining = value;
    while (remaining % 10 == 0) remaining /= 10;
    return remaining == 1;
}

test "new symbol cases are detailed and repeats are sparse" {
    var tracker = Tracker{};
    try std.testing.expectEqual(Disposition.detail, tracker.observe(.guest_assertion, 0x1000, 7).disposition);
    for (2..10) |_| {
        try std.testing.expectEqual(Disposition.suppress, tracker.observe(.guest_assertion, 0x1000, 7).disposition);
    }
    const tenth = tracker.observe(.guest_assertion, 0x1000, 7);
    try std.testing.expectEqual(Disposition.checkpoint, tenth.disposition);
    try std.testing.expectEqual(@as(u64, 10), tenth.occurrence);
    try std.testing.expectEqual(@as(u64, 8), tenth.suppressed_since_emit);

    try std.testing.expectEqual(Disposition.detail, tracker.observe(.guest_assertion, 0x2000, 7).disposition);
    try std.testing.expectEqual(Disposition.detail, tracker.observe(.guest_assertion, 0x1000, 8).disposition);
    const totals = tracker.summary();
    try std.testing.expectEqual(@as(u64, 3), totals.unique);
    try std.testing.expectEqual(@as(u64, 8), totals.suppressed);
}

test "power-of-ten checkpoints remain logarithmic" {
    var tracker = Tracker{};
    var emitted: u64 = 0;
    for (1..50_001) |_| {
        const observation = tracker.observe(.classified_ud2_recovery, 0x19f2f0, 1);
        if (observation.disposition != .suppress) emitted += 1;
    }
    // Detail plus checkpoints at 10, 100, 1,000 and 10,000.
    try std.testing.expectEqual(@as(u64, 5), emitted);
    try std.testing.expectEqual(@as(u64, 4), tracker.summary().checkpoints);
}
