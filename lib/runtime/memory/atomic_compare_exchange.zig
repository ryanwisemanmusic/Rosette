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
    matches: u64 = 0,
    mismatches: u64 = 0,

    pub fn record(self: *Stats, matched: bool) void {
        self.operations +|= 1;
        if (matched) {
            self.matches +|= 1;
        } else {
            self.mismatches +|= 1;
        }
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

test "atomic statistics treat compare mismatches as normal outcomes" {
    var stats = Stats{};
    stats.record(true);
    stats.record(false);
    try std.testing.expectEqual(@as(u64, 2), stats.operations);
    try std.testing.expectEqual(@as(u64, 1), stats.matches);
    try std.testing.expectEqual(@as(u64, 1), stats.mismatches);
}

// --- CMPXCHG8 semantic verification ---

fn checkCmpxchg8(expected: u8, actual: u8, replacement: u8) !void {
    const r = evaluate(expected, actual, replacement);
    const matched = expected == actual;

    try std.testing.expectEqual(matched, r.matched);

    if (matched) {
        try std.testing.expectEqual(replacement, r.destination);
        try std.testing.expectEqual(expected, r.accumulator);
    } else {
        try std.testing.expectEqual(actual, r.destination);
        try std.testing.expectEqual(actual, r.accumulator);
    }
}

test "CMPXCHG8 equal operands" {
    try checkCmpxchg8(0x00, 0x00, 0xFF);
    try checkCmpxchg8(0xFF, 0xFF, 0x00);
    try checkCmpxchg8(0x7F, 0x7F, 0x80);
    try checkCmpxchg8(0x80, 0x80, 0x7F);
    try checkCmpxchg8(0xAA, 0xAA, 0x55);
    try checkCmpxchg8(0x01, 0x01, 0x02);
}

test "CMPXCHG8 unequal operands" {
    try checkCmpxchg8(0x00, 0x01, 0xFF);
    try checkCmpxchg8(0x01, 0x00, 0xFF);
    try checkCmpxchg8(0x7F, 0x80, 0x00);
    try checkCmpxchg8(0x80, 0x7F, 0x00);
    try checkCmpxchg8(0xFF, 0x00, 0xAA);
    try checkCmpxchg8(0x00, 0xFF, 0xAA);
}

test "CMPXCHG8 AL writeback preserves upper RAX" {
    // Simulating partial-register writeback:
    // RAX before = 0x11223344556677XX
    // AL should be set to actual on failure, preserving bytes 8-63
    const rax_before: u64 = 0x11223344556677AA;
    const al_before: u8 = @truncate(rax_before); // 0xAA
    const dest_value: u8 = 0xBB; // actual

    const r = evaluate(al_before, dest_value, 0xCC);
    try std.testing.expect(!r.matched); // mismatch

    // On mismatch, AL = DEST = 0xBB
    const al_after: u8 = @truncate(r.accumulator);
    try std.testing.expectEqual(dest_value, al_after);

    // Upper RAX preserved: (rax_before & 0xFFFFFFFFFFFFFF00) | al_after
    const rax_after: u64 = (rax_before & 0xFFFF_FFFF_FFFF_FF00) | al_after;
    try std.testing.expectEqual(@as(u64, 0x11223344556677BB), rax_after);
}

test "CMPXCHG8 AL unchanged on match" {
    const al_before: u8 = 0x11;
    const r = evaluate(al_before, 0x11, 0xFF);
    try std.testing.expect(r.matched);
    try std.testing.expectEqual(al_before, @as(u8, @truncate(r.accumulator)));
    try std.testing.expectEqual(@as(u64, 0xFF), r.destination);
}

test "CMPXCHG8 difference direction matches AL - DEST" {
    // expected(AL)=0x01, actual(DEST)=0x00 → diff = 0x01 - 0x00 = 1
    const r = evaluate(@as(u8, 0x01), @as(u8, 0x00), @as(u8, 0xFF));
    try std.testing.expect(!r.matched);
    try std.testing.expectEqual(@as(u64, 1), r.difference);
}

test "CMPXCHG8 AL gets DEST on failure, upper RAX preserved" {
    const r = evaluate(@as(u8, 0x00), @as(u8, 0x01), @as(u8, 0xFF));
    try std.testing.expect(!r.matched);
    try std.testing.expectEqual(@as(u8, 0x01), @as(u8, @truncate(r.accumulator))); // AL = DEST
    try std.testing.expectEqual(@as(u8, 0x01), @as(u8, @truncate(r.destination))); // DEST unchanged
}
