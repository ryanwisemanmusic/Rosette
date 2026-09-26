//! The last error and warning lines this processor wrote, kept for the exit
//! report.
//!
//! A terminal decision site that records a `TerminalEvent` says what stopped
//! the run; one that does not still usually logged why just before it set
//! the reason. The log itself holds that line, but hundreds of report lines
//! later and interleaved with every other thread's output. The exit report
//! now reprints the last few error and warning lines beside the stop, so the
//! answer to "what was Rosette complaining about when it stopped" is next to
//! the question.
//!
//! `Scoped` is a drop-in for `std.log.scoped`: `err` and `warn` are copied
//! into the ring before they are written, `info` and `debug` pass straight
//! through. Each call site records its first eight lines and then only its
//! power-of-two occurrences, so a site that fires every instruction cannot
//! spend the run formatting lines no one will read.

const std = @import("std");

pub const Level = enum(u8) { err, warn };

pub const Line = struct {
    level: Level = .err,
    sequence: u64 = 0,
    text_storage: [360]u8 = undefined,
    text_len: u16 = 0,

    pub fn text(self: *const Line) []const u8 {
        return self.text_storage[0..self.text_len];
    }
};

pub const capacity = 24;

const Ring = struct {
    lines: [capacity]Line = @splat(.{}),
    next: usize = 0,
    total: u64 = 0,
    lock: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

var ring: Ring = .{};

fn acquire() void {
    while (ring.lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}

fn release() void {
    ring.lock.store(false, .release);
}

fn admit(occurrence: u64) bool {
    return occurrence <= 8 or (occurrence & (occurrence - 1)) == 0;
}

pub fn remember(level: Level, comptime format: []const u8, args: anytype) void {
    const Site = struct {
        const site_format = format;
        var occurrences = std.atomic.Value(u64).init(0);
    };
    const occurrence = Site.occurrences.fetchAdd(1, .monotonic) +% 1;
    if (!admit(occurrence)) return;
    var text_buffer: [360]u8 = undefined;
    const formatted = std.fmt.bufPrint(&text_buffer, format, args) catch blk: {
        // Too long: keep the start, which is where every line says what it is.
        break :blk text_buffer[0..];
    };
    acquire();
    defer release();
    const line = &ring.lines[ring.next];
    line.level = level;
    ring.total +|= 1;
    line.sequence = ring.total;
    const count = @min(formatted.len, line.text_storage.len);
    @memcpy(line.text_storage[0..count], formatted[0..count]);
    line.text_len = @intCast(count);
    ring.next = (ring.next + 1) % capacity;
}

/// Copy the held lines, oldest first, into `destination`. Returns how many.
pub fn snapshot(destination: []Line) usize {
    acquire();
    defer release();
    const held: usize = @intCast(@min(ring.total, capacity));
    const first = if (ring.total <= capacity) 0 else ring.next;
    const count = @min(held, destination.len);
    // The newest `count` lines.
    const skip = held - count;
    for (0..count) |index| {
        destination[index] = ring.lines[(first + skip + index) % capacity];
    }
    return count;
}

pub fn totalRecorded() u64 {
    acquire();
    defer release();
    return ring.total;
}

/// Tests only.
pub fn resetForTest() void {
    ring = .{};
}

pub fn Scoped(comptime scope: @EnumLiteral()) type {
    return struct {
        const base = std.log.scoped(scope);

        pub fn err(comptime format: []const u8, args: anytype) void {
            remember(.err, format, args);
            base.err(format, args);
        }

        pub fn warn(comptime format: []const u8, args: anytype) void {
            remember(.warn, format, args);
            base.warn(format, args);
        }

        pub const info = base.info;
        pub const debug = base.debug;
    };
}

test "one call site keeps its first eight lines and then its powers of two" {
    resetForTest();
    defer resetForTest();
    for (0..40) |index| remember(.err, "line {d}", .{index});
    var lines: [capacity]Line = undefined;
    const count = snapshot(&lines);
    // Occurrences 1-8, 16 and 32 of this one site.
    try std.testing.expectEqual(@as(usize, 10), count);
    try std.testing.expectEqualStrings("line 0", lines[0].text());
    try std.testing.expectEqualStrings("line 7", lines[7].text());
    try std.testing.expectEqualStrings("line 15", lines[8].text());
    try std.testing.expectEqualStrings("line 31", lines[9].text());
    try std.testing.expect(lines[count - 1].sequence == totalRecorded());
}

test "the ring keeps the newest lines oldest first when it wraps" {
    resetForTest();
    defer resetForTest();
    // Distinct sites so no throttle applies.
    inline for (0..capacity + 5) |index| {
        remember(.warn, std.fmt.comptimePrint("site {d}", .{index}), .{});
    }
    var lines: [capacity]Line = undefined;
    const count = snapshot(&lines);
    try std.testing.expectEqual(@as(usize, capacity), count);
    try std.testing.expectEqualStrings("site 5", lines[0].text());
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("site {d}", .{capacity + 4}), lines[count - 1].text());
}

test "a partial snapshot returns the newest lines" {
    resetForTest();
    defer resetForTest();
    remember(.warn, "first", .{});
    remember(.err, "second {s}", .{"x"});
    remember(.err, "third", .{});
    var lines: [2]Line = undefined;
    try std.testing.expectEqual(@as(usize, 2), snapshot(&lines));
    try std.testing.expectEqualStrings("second x", lines[0].text());
    try std.testing.expectEqualStrings("third", lines[1].text());
    try std.testing.expectEqual(Level.err, lines[1].level);
}

test "a line longer than the slot keeps its start" {
    resetForTest();
    defer resetForTest();
    const long = [_]u8{'y'} ** 500;
    remember(.err, "{s}", .{&long});
    var lines: [1]Line = undefined;
    _ = snapshot(&lines);
    try std.testing.expectEqual(@as(usize, 360), lines[0].text().len);
}
