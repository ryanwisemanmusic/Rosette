//! Collapsing a guest that repeats itself.
//!
//! A translated program's log is the program's, not the runtime's: Rosette
//! mirrors it and has no say in what it contains. When the guest enters a loop
//! that logs, the mirror faithfully reproduces every iteration — one observed
//! run produced 64,470 near-identical lines from a single call, 92% of the whole
//! file, and the one line that mattered was somewhere underneath.
//!
//! Fixing the guest is the right repair when the guest's source is available.
//! It usually is not, and a runtime whose diagnostics become unusable whenever
//! the workload misbehaves has made the workload's bug into its own.
//!
//! So the mirror collapses runs. A line identical to the one before it is
//! counted rather than written, and the count is emitted when the run ends —
//! which is strictly more informative than the repetitions, because "this
//! repeated 64,470 times" is the finding and the 64,470 copies are not.
//!
//! Two things are deliberately preserved:
//!
//!   * **The first occurrence is always written**, immediately. Collapsing
//!     starts at the second, so nothing is delayed and no line is ever lost to
//!     buffering.
//!   * **Only *consecutive* repeats collapse.** Two interleaved loops produce
//!     alternating lines, and treating those as repeats would hide the
//!     interleaving, which is usually the interesting part.
//!
//! Comparison is over the whole line and exact. A near-identical line carrying
//! an incrementing counter is a different line, and deciding that two lines are
//! "the same apart from the number" requires knowing which number is noise —
//! that is the caller's knowledge, not this module's.

const std = @import("std");

/// Longest line compared verbatim. Beyond this, the prefix is compared and the
/// suffix ignored, which can only ever merge lines that share a long prefix —
/// acceptable, and reported through `truncated_comparisons` so the report never
/// implies more precision than it has.
pub const max_compared: usize = 256;

/// What the caller should do with the line it just handed over.
pub const Action = union(enum) {
    /// Write it.
    emit,
    /// Do not write it; it repeats the previous line. The count is carried.
    suppress,
    /// Write it, but first write a summary of the run that just ended.
    /// `repeats` counts the *suppressed* lines, not including the original.
    emit_after_run: u64,
};

pub const Collapser = struct {
    previous: [max_compared]u8 = undefined,
    previous_len: usize = 0,
    /// Consecutive suppressed repeats of `previous`.
    run_length: u64 = 0,
    has_previous: bool = false,

    /// Lines the caller was told to suppress, over the whole run.
    suppressed: u64 = 0,
    /// Runs that ended, i.e. how many collapse summaries were emitted.
    runs: u64 = 0,
    /// Longest run seen. A single enormous run and many small ones are
    /// different findings.
    longest_run: u64 = 0,
    /// Lines longer than `max_compared`, compared on their prefix only.
    truncated_comparisons: u64 = 0,

    pub fn observe(self: *Collapser, line: []const u8) Action {
        const compared_len = @min(line.len, max_compared);
        if (line.len > max_compared) self.truncated_comparisons +|= 1;

        const same = self.has_previous and
            self.previous_len == compared_len and
            std.mem.eql(u8, self.previous[0..self.previous_len], line[0..compared_len]);

        if (same) {
            self.run_length +|= 1;
            self.suppressed +|= 1;
            return .suppress;
        }

        const ended = self.run_length;
        @memcpy(self.previous[0..compared_len], line[0..compared_len]);
        self.previous_len = compared_len;
        self.has_previous = true;
        self.run_length = 0;

        if (ended != 0) {
            self.runs +|= 1;
            if (ended > self.longest_run) self.longest_run = ended;
            return .{ .emit_after_run = ended };
        }
        return .emit;
    }

    /// Close out a run in progress, for end-of-stream. Returns the count when
    /// one was open, so the final repetitions are never silently dropped.
    pub fn finish(self: *Collapser) ?u64 {
        if (self.run_length == 0) return null;
        const ended = self.run_length;
        self.runs +|= 1;
        if (ended > self.longest_run) self.longest_run = ended;
        self.run_length = 0;
        return ended;
    }

    pub fn active(self: *const Collapser) bool {
        return self.suppressed != 0;
    }
};

test "the first occurrence is always emitted and repeats are suppressed" {
    var collapser = Collapser{};
    try std.testing.expectEqual(Action.emit, collapser.observe("same"));
    try std.testing.expectEqual(Action.suppress, collapser.observe("same"));
    try std.testing.expectEqual(Action.suppress, collapser.observe("same"));
    try std.testing.expectEqual(@as(u64, 2), collapser.suppressed);

    const action = collapser.observe("different");
    switch (action) {
        .emit_after_run => |repeats| try std.testing.expectEqual(@as(u64, 2), repeats),
        else => return error.TestFailed,
    }
    try std.testing.expectEqual(@as(u64, 1), collapser.runs);
    try std.testing.expectEqual(@as(u64, 2), collapser.longest_run);
}

// The interleaving is usually the interesting part, so alternating lines must
// not collapse into each other.
test "only consecutive repeats collapse" {
    var collapser = Collapser{};
    try std.testing.expectEqual(Action.emit, collapser.observe("a"));
    try std.testing.expectEqual(Action.emit, collapser.observe("b"));
    try std.testing.expectEqual(Action.emit, collapser.observe("a"));
    try std.testing.expectEqual(Action.emit, collapser.observe("b"));
    try std.testing.expectEqual(@as(u64, 0), collapser.suppressed);
    try std.testing.expectEqual(@as(u64, 0), collapser.runs);
}

test "a run open at end of stream is reported, not dropped" {
    var collapser = Collapser{};
    _ = collapser.observe("x");
    _ = collapser.observe("x");
    _ = collapser.observe("x");
    const remaining = collapser.finish() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 2), remaining);
    try std.testing.expect(collapser.finish() == null);
}

test "a line that differs only in its tail is a different line" {
    var collapser = Collapser{};
    try std.testing.expectEqual(Action.emit, collapser.observe("iter=1 result=x"));
    // An incrementing counter makes this a genuinely different line; deciding
    // otherwise needs to know which number is noise, which is not knowable here.
    try std.testing.expectEqual(Action.emit, collapser.observe("iter=2 result=x"));
    try std.testing.expectEqual(@as(u64, 0), collapser.suppressed);
}

test "lines beyond the comparison window are counted as truncated" {
    var collapser = Collapser{};
    const long = "z" ** (max_compared + 32);
    _ = collapser.observe(long);
    _ = collapser.observe(long);
    try std.testing.expectEqual(@as(u64, 2), collapser.truncated_comparisons);
    try std.testing.expectEqual(@as(u64, 1), collapser.suppressed);
}

// The observed shape: one enormous run, which must be reported as one run of
// 64,470 rather than as many small ones.
test "an enormous run is one run, and its length is retained" {
    var collapser = Collapser{};
    _ = collapser.observe("DBG: ResolveSymLink iter spinning");
    var index: usize = 0;
    while (index < 64_470) : (index += 1) {
        try std.testing.expectEqual(Action.suppress, collapser.observe("DBG: ResolveSymLink iter spinning"));
    }
    const remaining = collapser.finish() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 64_470), remaining);
    try std.testing.expectEqual(@as(u64, 1), collapser.runs);
    try std.testing.expectEqual(@as(u64, 64_470), collapser.longest_run);
    try std.testing.expectEqual(@as(u64, 64_470), collapser.suppressed);
}

test "an empty line is handled like any other" {
    var collapser = Collapser{};
    try std.testing.expectEqual(Action.emit, collapser.observe(""));
    try std.testing.expectEqual(Action.suppress, collapser.observe(""));
    // The line that ends the run reports it; a run of blank lines is still a
    // run, and swallowing its count would be the same defect at a smaller size.
    switch (collapser.observe("x")) {
        .emit_after_run => |repeats| try std.testing.expectEqual(@as(u64, 1), repeats),
        else => return error.TestFailed,
    }
}
