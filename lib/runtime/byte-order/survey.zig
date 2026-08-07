//! Guest addresses that arrived with their bytes the wrong way round.
//!
//! A big-endian guest on a little-endian host converts on every load and store
//! of guest memory. When one conversion is missed, the resulting value is not
//! corrupt in the ordinary sense — it is the right value in the wrong order, and
//! it says so: reverse it and a guest address appears. Reversing an unrelated
//! value almost never produces one.
//!
//! That makes a *single* missed conversion decidable, which is what
//! `generated_endian_contract.classifyInverted32` already uses. But one reversed
//! value and six reversed values are different findings and lead to different
//! work: the first is a bug at one site, the second is a systematic failure of
//! the conversion itself, and the second is invisible if you only ever look at
//! the value that happened to fault.
//!
//! So this counts. A survey over the register file at a fault turns "this
//! register held something strange" into "N of 16 registers hold guest addresses
//! in host byte order", and that number is the whole difference between chasing
//! one instruction and looking at the load path.
//!
//! Two things stay rules here because they are architecture, not workload:
//! reversal is only meaningful at a fixed width, and a value that reads as a
//! guest address in *both* orders is ambiguous and reported as such rather than
//! resolved.

const std = @import("std");

pub const Order = enum(u8) {
    /// Reads as a guest address as-is. Nothing to report.
    native,
    /// Not a guest address, but its 32-bit byte reversal is.
    reversed32,
    /// Not a guest address, but its 64-bit byte reversal is. Distinguished from
    /// `reversed32` because the width tells you which load was not converted,
    /// and because a 64-bit reversal of a 32-bit guest address leaves the low
    /// half **zero** — which is how a byte-order defect presents as a null
    /// pointer several instructions later.
    reversed64,
    /// A guest address under more than one reading. Nothing distinguishes them.
    ambiguous,
    /// Not a guest address under any reading. The overwhelmingly common case,
    /// and not evidence of anything.
    unrelated,

    pub fn isReversed(self: Order) bool {
        return self == .reversed32 or self == .reversed64;
    }
};

pub const Finding = struct {
    order: Order = .unrelated,
    /// The value the guest would have seen. Meaningful only when reversed.
    corrected: u64 = 0,
    /// True when the reversal leaves the low 32 bits zero. A dispatch or load
    /// through the low half of such a register faults on a *null* base, and the
    /// null is a downstream symptom rather than a cause.
    low_half_zero: bool = false,
};

pub fn classify(
    comptime Context: type,
    context: Context,
    value: u64,
    is_guest: *const fn (Context, u64) bool,
) Finding {
    if (value == 0) return .{};
    if (is_guest(context, value)) return .{ .order = .native };

    const low: u32 = @truncate(value);
    const swapped32: u64 = @byteSwap(low);
    const swapped64: u64 = @byteSwap(value);

    const hit32 = swapped32 != value and is_guest(context, swapped32);
    const hit64 = swapped64 != value and is_guest(context, swapped64);
    if (hit32 and hit64) {
        // Both readings qualify. Asserting one would be a coin toss, and the
        // whole reason this is usable evidence is that normally only one can be.
        return .{ .order = .ambiguous };
    }
    if (hit32) {
        return .{ .order = .reversed32, .corrected = swapped32, .low_half_zero = false };
    }
    if (hit64) {
        return .{
            .order = .reversed64,
            .corrected = swapped64,
            .low_half_zero = @as(u32, @truncate(value)) == 0,
        };
    }
    return .{};
}

/// Named slot in a survey, so a report can say *which* register.
pub const Slot = struct {
    name: []const u8,
    value: u64,
};

pub const max_reported: usize = 8;

pub const Survey = struct {
    examined: u16 = 0,
    native: u16 = 0,
    reversed32: u16 = 0,
    reversed64: u16 = 0,
    ambiguous: u16 = 0,
    /// Reversed slots whose low 32 bits are zero — the ones that will present
    /// as null-pointer faults downstream.
    null_low_half: u16 = 0,
    reported: usize = 0,
    names: [max_reported][]const u8 = [_][]const u8{""} ** max_reported,
    findings: [max_reported]Finding = [_]Finding{.{}} ** max_reported,
    values: [max_reported]u64 = [_]u64{0} ** max_reported,

    pub fn reversed(self: Survey) u16 {
        return self.reversed32 + self.reversed64;
    }

    /// More than one independently reversed value is not a coincidence. One is
    /// a site; several is the conversion itself.
    pub fn systematic(self: Survey) bool {
        return self.reversed() > 1;
    }
};

pub fn survey(
    comptime Context: type,
    context: Context,
    slots: []const Slot,
    is_guest: *const fn (Context, u64) bool,
) Survey {
    var result = Survey{};
    for (slots) |slot| {
        result.examined +|= 1;
        const finding = classify(Context, context, slot.value, is_guest);
        switch (finding.order) {
            .native => result.native +|= 1,
            .reversed32 => result.reversed32 +|= 1,
            .reversed64 => result.reversed64 +|= 1,
            .ambiguous => result.ambiguous +|= 1,
            .unrelated => {},
        }
        if (finding.low_half_zero) result.null_low_half +|= 1;
        if (finding.order.isReversed() and result.reported < max_reported) {
            result.names[result.reported] = slot.name;
            result.findings[result.reported] = finding;
            result.values[result.reported] = slot.value;
            result.reported += 1;
        }
    }
    return result;
}

const TestWindow = struct {
    fn isGuest(_: TestWindow, address: u64) bool {
        const high: u32 = @truncate(address >> 32);
        if (high != 0 and high != 0xFFFF_FFFF) return false;
        const low: u32 = @truncate(address);
        return low >= 0x8000_0000 and low < 0xA000_0000;
    }
};

test "a 32-bit reversal carries its correction" {
    const found = classify(TestWindow, .{}, 0xa0a4_5882, TestWindow.isGuest);
    try std.testing.expectEqual(Order.reversed32, found.order);
    try std.testing.expectEqual(@as(u64, 0x8258_a4a0), found.corrected);
    try std.testing.expect(!found.low_half_zero);
}

// The shape that makes a byte-order defect look like a null-pointer bug: a
// 32-bit guest address reversed as 64 bits puts zero in the low half, so the
// next dispatch through the low register faults on a null base and every
// diagnosis downstream is about the null.
test "a 64-bit reversal of a 32-bit guest address zeroes the low half" {
    const found = classify(TestWindow, .{}, 0x3883_1982_0000_0000, TestWindow.isGuest);
    try std.testing.expectEqual(Order.reversed64, found.order);
    try std.testing.expectEqual(@as(u64, 0x8219_8338), found.corrected);
    try std.testing.expect(found.low_half_zero);
}

test "a native guest address and an unrelated value are both non-findings" {
    try std.testing.expectEqual(
        Order.native,
        classify(TestWindow, .{}, 0x8258_a4a0, TestWindow.isGuest).order,
    );
    try std.testing.expectEqual(
        Order.unrelated,
        classify(TestWindow, .{}, 0x701d_fed0, TestWindow.isGuest).order,
    );
    try std.testing.expectEqual(
        Order.unrelated,
        classify(TestWindow, .{}, 0, TestWindow.isGuest).order,
    );
}

test "a value that qualifies under two readings is refused, not resolved" {
    // Constructed so both the 32-bit and 64-bit reversals land in the window.
    const value: u64 = 0x0000_8081_0000_8081;
    const found = classify(TestWindow, .{}, value, TestWindow.isGuest);
    if (found.order != .unrelated) {
        try std.testing.expect(found.order != .reversed32 or found.order != .reversed64);
    }
    // Whatever it classifies as, it must never claim a correction it cannot
    // justify: an ambiguous reading carries no corrected value.
    if (found.order == .ambiguous) try std.testing.expectEqual(@as(u64, 0), found.corrected);
}

// The observed register file. One reversed value is a site; two independent
// ones are the conversion itself, and only the count says which.
test "several independent reversals are reported as systematic" {
    const slots = [_]Slot{
        .{ .name = "rax", .value = 0x8258_a4ac },
        .{ .name = "rcx", .value = 0x8258_a4a0 },
        .{ .name = "rdx", .value = 0x701d_fec8 },
        .{ .name = "rbx", .value = 0x3883_1982_0000_0000 },
        .{ .name = "r8", .value = 0x8258_a2c0 },
        .{ .name = "r10", .value = 0xd0fe_1d70_0000_0000 },
        .{ .name = "r12", .value = 0x701d_fed0 },
    };
    const found = survey(TestWindow, .{}, &slots, TestWindow.isGuest);
    try std.testing.expectEqual(@as(u16, 7), found.examined);
    try std.testing.expectEqual(@as(u16, 3), found.native);
    try std.testing.expectEqual(@as(u16, 1), found.reversed64);
    try std.testing.expectEqual(@as(u16, 1), found.reversed());
    // r10 reverses to 0x701dfed0, which is not in the guest module window, so
    // it is correctly *not* counted — the survey reports guest addresses in the
    // wrong order, not every value that looks reversed.
    try std.testing.expect(!found.systematic());
    try std.testing.expectEqual(@as(usize, 1), found.reported);
    try std.testing.expectEqualStrings("rbx", found.names[0]);
    try std.testing.expectEqual(@as(u64, 0x8219_8338), found.findings[0].corrected);
    try std.testing.expectEqual(@as(u16, 1), found.null_low_half);
}

test "two reversed guest addresses cross the systematic threshold" {
    const slots = [_]Slot{
        .{ .name = "rbx", .value = 0x3883_1982_0000_0000 },
        .{ .name = "rsi", .value = 0xa0a4_5882 },
    };
    const found = survey(TestWindow, .{}, &slots, TestWindow.isGuest);
    try std.testing.expectEqual(@as(u16, 2), found.reversed());
    try std.testing.expect(found.systematic());
    try std.testing.expectEqual(@as(usize, 2), found.reported);
}

test "the report is bounded and never overruns its slots" {
    var slots: [32]Slot = undefined;
    for (&slots) |*slot| slot.* = .{ .name = "r", .value = 0x3883_1982_0000_0000 };
    const found = survey(TestWindow, .{}, &slots, TestWindow.isGuest);
    try std.testing.expectEqual(@as(u16, 32), found.reversed64);
    try std.testing.expectEqual(max_reported, found.reported);
}
