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

/// A guest stuck in a loop that logs more than one distinct line.
pub const Cycle = struct {
    /// Distinct lines in the repeating unit.
    period: usize,
    /// Confirmed repetitions of that unit.
    iterations: u64,
};

/// Names a guest that is repeating a *cycle* of lines rather than one line.
///
/// `Collapser` deliberately only collapses consecutive duplicates, because
/// interleaving is usually the interesting part. That leaves the commonest
/// stuck-guest shape unreported: a handshake between two contexts emits a fixed
/// rotation of several different lines, forever. No line ever equals the one
/// before it, so nothing collapses, the mirror grows without bound, and the
/// reader has to notice the pattern by eye — which is exactly the failure that
/// looks like "no indication of a problem" while the run makes no progress.
///
/// This detector never suppresses. Suppressing would destroy the interleaving
/// the collapser is careful to preserve. It only *reports*: the guest has
/// repeated an N-line cycle M times. A cycle repeating thousands of times with
/// no new content is a livelock, and saying so is the whole job.
///
/// Comparison is by hash of the same prefix `Collapser` compares, so the two
/// agree on what "the same line" means.
pub const CycleDetector = struct {
    /// Ring depth. The longest detectable period is half of it: confirming a
    /// period needs two consecutive copies of the unit.
    pub const window: usize = 32;
    pub const max_period: usize = window / 2;

    /// Repetitions before the first report, then the reporting stride. Bounded
    /// on purpose: a detector that reports a livelock once per line is itself
    /// the flood it exists to describe.
    pub const first_report: u64 = 8;
    pub const report_stride: u64 = 512;

    hashes: [window]u64 = [_]u64{0} ** window,
    observed: u64 = 0,
    period: usize = 0,
    iterations: u64 = 0,

    reports: u64 = 0,
    longest_period: usize = 0,
    most_iterations: u64 = 0,

    fn at(self: *const CycleDetector, back: usize) u64 {
        // `back` = 0 is the most recent line.
        const index = (self.observed -% (back + 1)) % window;
        return self.hashes[@intCast(index)];
    }

    fn repeatsWithPeriod(self: *const CycleDetector, period: usize) bool {
        if (self.observed < 2 * period) return false;
        var i: usize = 0;
        while (i < period) : (i += 1) {
            if (self.at(i) != self.at(i + period)) return false;
        }
        return true;
    }

    /// Observe one line. Returns a cycle when a reporting threshold is crossed.
    pub fn observe(self: *CycleDetector, line: []const u8) ?Cycle {
        const compared = line[0..@min(line.len, max_compared)];
        self.hashes[@intCast(self.observed % window)] = std.hash.Wyhash.hash(0, compared);
        self.observed +%= 1;

        // An established period continues as long as the line matches the one
        // one period back. Re-verifying the whole unit every line would cost
        // more and decide the same thing.
        if (self.period != 0) {
            if (self.observed > self.period and self.at(0) == self.at(self.period)) {
                self.iterations +|= 1;
                if (self.iterations > self.most_iterations) self.most_iterations = self.iterations;
                const due = self.iterations == first_report or
                    (self.iterations > first_report and
                        (self.iterations - first_report) % report_stride == 0);
                if (!due) return null;
                self.reports +|= 1;
                return .{ .period = self.period, .iterations = self.iterations };
            }
            self.period = 0;
            self.iterations = 0;
        }

        // Look for the shortest period first: a 2-line handshake repeated four
        // times also satisfies period 4, and the shortest one is the honest
        // description of the loop.
        var period: usize = 2;
        while (period <= max_period) : (period += 1) {
            if (!self.repeatsWithPeriod(period)) continue;
            self.period = period;
            self.iterations = 1;
            if (period > self.longest_period) self.longest_period = period;
            if (self.iterations > self.most_iterations) self.most_iterations = self.iterations;
            return null;
        }
        return null;
    }

    /// Whether a *confirmed* cycle is still the current stream suffix.
    ///
    /// `reports` is historical evidence: once a cycle has been observed it
    /// remains useful in the final audit.  It is not a liveness bit.  Using it
    /// as one made a short-lived allocator/initialisation repetition at 10B
    /// steps poison every later SWAP HEALTH checkpoint, even after a new line
    /// broke the cycle.  A current cycle must still have its period and must
    /// have crossed the reporting threshold.
    pub fn active(self: *const CycleDetector) bool {
        return self.period != 0 and self.iterations >= first_report;
    }

    /// Whether this run ever produced a cycle report.  This is intentionally
    /// separate from `active`: historical reports belong in the final audit,
    /// while only an active suffix may classify the current producer as
    /// livelocked.
    pub fn hasHistory(self: *const CycleDetector) bool {
        return self.reports != 0;
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

// The shape that made a run look healthy while it made no progress: a
// four-line rotation between two guest contexts, repeated indefinitely. No
// line ever equals the one before it, so `Collapser` correctly stays silent —
// and nothing else said anything at all.
test "a repeating cycle of distinct lines is reported, not collapsed" {
    var collapser = Collapser{};
    var detector = CycleDetector{};
    const cycle = [_][]const u8{
        "xeKeSetEvent: ptr=827CEC38 handle=F800015C",
        "KeReleaseSemaphore(827CEC14, 1, 1, 0)",
        "KeWaitForSingleObject result=00000000",
        "xeKeSetEvent: ptr=827CEC28 handle=F8000160",
    };

    var reported: ?Cycle = null;
    var emitted: usize = 0;
    for (0..40) |i| {
        const line = cycle[i % cycle.len];
        // The collapser must never suppress any of these: they interleave.
        try std.testing.expectEqual(Action.emit, collapser.observe(line));
        emitted += 1;
        if (detector.observe(line)) |found| reported = found;
    }
    try std.testing.expectEqual(@as(u64, 0), collapser.suppressed);
    try std.testing.expectEqual(@as(usize, 40), emitted);

    const found = reported orelse return error.TestFailed;
    try std.testing.expectEqual(@as(usize, 4), found.period);
    try std.testing.expectEqual(CycleDetector.first_report, found.iterations);
    try std.testing.expect(detector.active());
}

test "a cycle detector reports the shortest honest period" {
    var detector = CycleDetector{};
    var reported: ?Cycle = null;
    // A two-line handshake also satisfies period 4, 6, 8 ... describing it as
    // anything but 2 would overstate the size of the loop.
    for (0..30) |i| {
        const line: []const u8 = if (i % 2 == 0) "ping" else "pong";
        if (detector.observe(line)) |found| reported = found;
    }
    const found = reported orelse return error.TestFailed;
    try std.testing.expectEqual(@as(usize, 2), found.period);
}

test "progress breaks a cycle and nothing is reported" {
    var detector = CycleDetector{};
    var buffer: [64]u8 = undefined;
    // A guest that is actually advancing emits new content; the counter in the
    // line makes every line distinct, which is what forward progress looks
    // like from here.
    for (0..200) |i| {
        const line = std.fmt.bufPrint(&buffer, "step {d} completed", .{i}) catch unreachable;
        try std.testing.expectEqual(@as(?Cycle, null), detector.observe(line));
    }
    try std.testing.expect(!detector.active());
    try std.testing.expectEqual(@as(u64, 0), detector.reports);
}

test "a cycle that stops is not credited with later repetitions" {
    var detector = CycleDetector{};
    for (0..24) |i| {
        _ = detector.observe(if (i % 3 == 0) "a" else if (i % 3 == 1) "b" else "c");
    }
    try std.testing.expectEqual(@as(usize, 3), detector.period);
    const during = detector.iterations;
    try std.testing.expect(during > 0);

    _ = detector.observe("something genuinely new");
    try std.testing.expectEqual(@as(usize, 0), detector.period);
    try std.testing.expect(!detector.active());
    try std.testing.expect(detector.hasHistory());
    try std.testing.expectEqual(@as(u64, 0), detector.iterations);
    // The high-water mark survives, so the run summary can still report it.
    try std.testing.expectEqual(during, detector.most_iterations);
}
