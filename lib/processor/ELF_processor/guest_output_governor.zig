//! Keeps a guest's standard output from flooding the host.
//!
//! Xenia's logger writes every line through the guest CRT to stdout, and
//! Rosette writes those bytes to the host descriptor the launcher pipes into
//! the run log. Nothing between the guest and the host disk bounded that
//! stream. On the 2026-09-13 run one line - `ResolvePath(WavesLibDLL) failed
//! - device not found` - arrived 322 times in a few seconds; it was bounded
//! only because the title stopped asking. A title that retries a missing
//! module in a loop, or a warning inside a per-frame path, repeats one line
//! for as long as the run lasts, and the run log lives on the host's disk.
//!
//! ## The rule
//!
//! * Every exact line is written the first `repeat_allowance` times.
//! * After that it is withheld, and written again only when its count
//!   reaches a power of two, as a notice that carries the line and its count.
//!   A line repeated a million times costs twenty notices.
//! * Independently, once `byte_budget` bytes of guest output have been
//!   written, every further guest line is withheld and counted; a notice is
//!   written at each power of two of the withheld count.
//!
//! The guest is always told its write succeeded, and Rosette's own classifier
//! still sees every byte: this bounds what reaches the log, never what the
//! guest did or what Rosette learned from it. Every withheld line is counted,
//! and the most repeated ones are kept as examples for the exit report.
//!
//! ## What this does not do
//!
//! It does not collapse lines that differ only in a number. Two lines naming
//! different registers are different facts, and withholding the second
//! because it resembles the first would hide exactly the line a reader needs.
//! Lines that differ every time are what the byte budget is for.

const std = @import("std");

pub const repeat_allowance: u64 = 16;
/// Power of two; the table is addressed by the low bits of the line hash.
pub const tracked_line_capacity: usize = 1024;
pub const default_byte_budget: u64 = 64 * 1024 * 1024;
pub const pending_capacity: usize = 4096;
pub const example_capacity: usize = 8;
pub const example_bytes: usize = 160;
/// How far a hash probes before the line is treated as untracked. Untracked
/// lines are always admitted, so a full table degrades to the byte budget
/// rather than to withholding lines it cannot count.
const probe_limit: usize = 16;
const notice_line_bytes: usize = 200;

pub const Example = struct {
    hash: u64 = 0,
    count: u64 = 0,
    text: [example_bytes]u8 = [_]u8{0} ** example_bytes,
    text_len: u8 = 0,

    pub fn textSlice(self: *const Example) []const u8 {
        return self.text[0..self.text_len];
    }
};

const Slot = struct {
    hash: u64 = 0,
    count: u64 = 0,
};

pub const Governor = struct {
    slots: [tracked_line_capacity]Slot = [_]Slot{.{}} ** tracked_line_capacity,
    examples: [example_capacity]Example = [_]Example{.{}} ** example_capacity,
    pending: [pending_capacity]u8 = [_]u8{0} ** pending_capacity,
    pending_len: usize = 0,
    byte_budget: u64 = default_byte_budget,

    lines: u64 = 0,
    passed_lines: u64 = 0,
    passed_bytes: u64 = 0,
    withheld_repeat_lines: u64 = 0,
    withheld_budget_lines: u64 = 0,
    withheld_bytes: u64 = 0,
    notices: u64 = 0,
    untracked_lines: u64 = 0,
    distinct_tracked: u64 = 0,

    /// Feed guest bytes. `sink.emit(bytes)` receives what reaches the host.
    pub fn feed(self: *Governor, bytes: []const u8, sink: anytype) void {
        var rest = bytes;
        while (rest.len != 0) {
            const newline = std.mem.indexOfScalar(u8, rest, '\n');
            const chunk_end = newline orelse rest.len;
            const room = pending_capacity - self.pending_len;
            const take = @min(chunk_end, room);
            @memcpy(self.pending[self.pending_len..][0..take], rest[0..take]);
            self.pending_len += take;
            rest = rest[take..];
            if (take < chunk_end) {
                // Longer than the assembler holds: decide on what is here and
                // carry on with the remainder as a continuation.
                self.finishLine(false, sink);
                continue;
            }
            if (newline != null) {
                rest = rest[1..];
                self.finishLine(true, sink);
            }
        }
    }

    /// Decide on a trailing partial line, at exit.
    pub fn flush(self: *Governor, sink: anytype) void {
        if (self.pending_len != 0) self.finishLine(false, sink);
    }

    pub fn withheldLines(self: *const Governor) u64 {
        return self.withheld_repeat_lines +| self.withheld_budget_lines;
    }

    fn finishLine(self: *Governor, terminated: bool, sink: anytype) void {
        const line = self.pending[0..self.pending_len];
        defer self.pending_len = 0;
        self.lines +|= 1;
        const line_bytes: u64 = line.len + @intFromBool(terminated);

        const hash = fnv1a(line);
        const count = self.countLine(hash);

        if (self.passed_bytes +| line_bytes > self.byte_budget) {
            self.withheld_budget_lines +|= 1;
            self.withheld_bytes +|= line_bytes;
            if (isPowerOfTwo(self.withheld_budget_lines)) {
                var buffer: [256]u8 = undefined;
                const notice = std.fmt.bufPrint(&buffer, "[rosette] guest output governor: {d} guest line(s) withheld since guest output reached its {d} MiB budget; PE64 GUEST OUTPUT GOVERNOR at exit counts the rest\n", .{
                    self.withheld_budget_lines,
                    self.byte_budget / (1024 * 1024),
                }) catch return;
                self.emitNotice(notice, sink);
            }
            return;
        }

        if (count <= repeat_allowance) {
            sink.emit(line);
            if (terminated) sink.emit("\n");
            self.passed_lines +|= 1;
            self.passed_bytes +|= line_bytes;
            return;
        }

        self.withheld_repeat_lines +|= 1;
        self.withheld_bytes +|= line_bytes;
        self.recordExample(hash, count, line);
        if (isPowerOfTwo(count)) {
            var buffer: [notice_line_bytes + 256]u8 = undefined;
            const shown = line[0..@min(line.len, notice_line_bytes)];
            const notice = std.fmt.bufPrint(&buffer, "[rosette] guest output governor: repeat {d} of this line withheld (each exact line is written {d} times, then only at powers of two): {s}\n", .{
                count,
                repeat_allowance,
                shown,
            }) catch return;
            self.emitNotice(notice, sink);
        }
    }

    fn emitNotice(self: *Governor, notice: []const u8, sink: anytype) void {
        self.notices +|= 1;
        sink.emit(notice);
    }

    /// The occurrence number of this line, counting this one. A line the
    /// table cannot place is reported as new.
    fn countLine(self: *Governor, hash: u64) u64 {
        const mask = tracked_line_capacity - 1;
        var probe: usize = 0;
        while (probe < probe_limit) : (probe += 1) {
            const slot = &self.slots[(@as(usize, @truncate(hash)) +% probe) & mask];
            if (slot.count == 0) {
                slot.* = .{ .hash = hash, .count = 1 };
                self.distinct_tracked +|= 1;
                return 1;
            }
            if (slot.hash == hash) {
                slot.count +|= 1;
                return slot.count;
            }
        }
        self.untracked_lines +|= 1;
        return 1;
    }

    fn recordExample(self: *Governor, hash: u64, count: u64, line: []const u8) void {
        var smallest: usize = 0;
        for (&self.examples, 0..) |*example, index| {
            if (example.count != 0 and example.hash == hash) {
                example.count = count;
                return;
            }
            if (example.count < self.examples[smallest].count) smallest = index;
        }
        const target = &self.examples[smallest];
        if (target.count != 0 and target.count >= count) return;
        const length = @min(line.len, example_bytes);
        target.* = .{ .hash = hash, .count = count };
        @memcpy(target.text[0..length], line[0..length]);
        target.text_len = @intCast(length);
    }
};

fn fnv1a(bytes: []const u8) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 0x0000_0100_0000_01b3;
    }
    return hash;
}

fn isPowerOfTwo(value: u64) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

const Capture = struct {
    data: [16384]u8 = undefined,
    len: usize = 0,

    fn emit(self: *Capture, bytes: []const u8) void {
        const room = self.data.len - self.len;
        const take = @min(room, bytes.len);
        @memcpy(self.data[self.len..][0..take], bytes[0..take]);
        self.len += take;
    }

    fn text(self: *const Capture) []const u8 {
        return self.data[0..self.len];
    }

    fn count(self: *const Capture, needle: []const u8) usize {
        return std.mem.count(u8, self.text(), needle);
    }
};

test "distinct lines pass through untouched" {
    var governor = Governor{};
    var capture = Capture{};
    governor.feed("w> 01 first\nw> 01 second\n", &capture);
    try std.testing.expectEqualStrings("w> 01 first\nw> 01 second\n", capture.text());
    try std.testing.expectEqual(@as(u64, 2), governor.passed_lines);
    try std.testing.expectEqual(@as(u64, 0), governor.withheldLines());
}

test "a repeated line is written its allowance, then only at powers of two" {
    var governor = Governor{};
    var capture = Capture{};
    const line = "!> F8000014 ResolvePath(WavesLibDLL) failed - device not found\n";
    for (0..1000) |_| governor.feed(line, &capture);
    // Sixteen verbatim copies, and notices at 32, 64, 128, 256 and 512.
    try std.testing.expectEqual(@as(usize, 16 + 5), capture.count("ResolvePath(WavesLibDLL)"));
    try std.testing.expectEqual(@as(usize, 5), capture.count("guest output governor: repeat"));
    try std.testing.expectEqual(@as(u64, 1000 - 16), governor.withheld_repeat_lines);
    try std.testing.expectEqual(@as(u64, 1000), governor.examples[0].count);
    try std.testing.expect(std.mem.indexOf(u8, governor.examples[0].textSlice(), "WavesLibDLL") != null);
}

test "a line split across writes is assembled before it is judged" {
    var governor = Governor{};
    var capture = Capture{};
    governor.feed("w> 01 hal", &capture);
    try std.testing.expectEqual(@as(usize, 0), capture.len);
    governor.feed("f a line\nw> 01 next", &capture);
    try std.testing.expectEqualStrings("w> 01 half a line\n", capture.text());
    governor.flush(&capture);
    try std.testing.expectEqualStrings("w> 01 half a line\nw> 01 next", capture.text());
}

test "the byte budget withholds every further line and says so sparsely" {
    var governor = Governor{ .byte_budget = 64 };
    var capture = Capture{};
    var buffer: [32]u8 = undefined;
    for (0..40) |index| {
        const line = std.fmt.bufPrint(&buffer, "w> 01 distinct {d}\n", .{index}) catch unreachable;
        governor.feed(line, &capture);
    }
    try std.testing.expect(governor.passed_bytes <= 64);
    try std.testing.expect(governor.withheld_budget_lines > 30);
    // Notices at 1, 2, 4, 8, 16 and 32 withheld lines at most.
    try std.testing.expect(capture.count("guest output governor:") <= 6);
    try std.testing.expectEqual(@as(u64, 40), governor.lines);
}

test "a line longer than the assembler still reaches the host" {
    var governor = Governor{};
    var capture = Capture{};
    var long: [pending_capacity + 100]u8 = undefined;
    @memset(&long, 'x');
    governor.feed(&long, &capture);
    governor.feed("\n", &capture);
    try std.testing.expectEqual(@as(usize, pending_capacity + 101), capture.len);
}
