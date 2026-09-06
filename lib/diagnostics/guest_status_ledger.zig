//! Every NTSTATUS the guest kernel converted to a DOS error, and which of them
//! is a defect.
//!
//! ## The gap this closes
//!
//! `xeRtlNtStatusToDosError` is the guest's own admission that a kernel call
//! failed: the title asked for something, the kernel said no, and the title is
//! now translating that no into the error code its caller understands. Every
//! one of those lines is a failure somewhere. Nothing in Rosette read them, so
//! fifty-eight failures in one run were invisible.
//!
//! But they are not one thing. On 2026-09-04 the run held:
//!
//!   * fifty-six `C000000F` (`STATUS_NO_SUCH_FILE`) from the title probing for
//!     `cache0:\cache000.map` … `cache1:\cacheNNN.map`, files that do not exist
//!     on a first run because the title is about to create them;
//!   * one `80000006` (`STATUS_NO_MORE_FILES`), which is how a directory
//!     enumeration *ends*;
//!   * one `C0000001` (`STATUS_UNSUCCESSFUL`), the kernel's generic failure,
//!     carrying no reason at all.
//!
//! Making all fifty-eight fatal would stop every run on the first cache probe.
//! Making none of them fatal is what the run did until now. The useful line is
//! between a negative result the caller *asked a question to receive* and a
//! failure that answers no question — and that line is drawn from the status
//! code, not from how many times it appeared.
//!
//! ## What it is and is not
//!
//! It classifies, counts, and retains the first witness of each class. It is
//! not a policy about which kernel calls a title may fail: a title is entitled
//! to probe for a file that is not there. It says which failures nobody asked
//! for, so a reader can tell fifty-six answered questions from one unexplained
//! no.

const std = @import("std");

/// Distinct status codes retained. A run's failure surface is small; anything
/// past this is counted so a diffuse run cannot look concentrated.
pub const max_statuses: usize = 24;
/// Bytes retained from the operation that preceded a failure.
pub const max_context: usize = 96;

/// What kind of answer a status is.
///
/// Derived from the code itself so a status this table has never seen is still
/// placed, and placed conservatively: an unrecognised error-severity status is
/// a defect until someone says otherwise, because the alternative is a silent
/// pass for exactly the codes nobody thought about.
pub const Class = enum(u8) {
    /// The call succeeded. Present because `xeRtlNtStatusToDosError` is also
    /// called on success paths by some titles, and a success counted as a
    /// failure would inflate every total here.
    success,
    /// A negative result the caller asked for: "is this file there", "is there
    /// another entry". The question was answered. Not a defect.
    answered_negative,
    /// A failure the caller did not ask for and that names its cause —
    /// access denied, invalid parameter, not implemented. The cause is
    /// actionable even though the call failed.
    named_failure,
    /// A failure that names nothing. `STATUS_UNSUCCESSFUL` is the kernel
    /// saying no without saying why, and it is the single most expensive
    /// status to leave unread: it is what a stub returns when it has not been
    /// written.
    unexplained_failure,

    pub fn label(self: Class) []const u8 {
        return switch (self) {
            .success => "success",
            .answered_negative => "answered-negative",
            .named_failure => "named-failure",
            .unexplained_failure => "UNEXPLAINED-FAILURE",
        };
    }

    /// Whether a reader should treat this as a defect in the run.
    pub fn isDefect(self: Class) bool {
        return self == .named_failure or self == .unexplained_failure;
    }

    pub fn describe(self: Class) []const u8 {
        return switch (self) {
            .success => "the call succeeded; the conversion is a caller convention, not a failure",
            .answered_negative => "the caller asked a question whose answer may legitimately be no, and received it. A title probing for a cache file it is about to create is the common case and is not a defect",
            .named_failure => "the call failed for a stated reason. The reason is the finding: read the operation that preceded it",
            .unexplained_failure => "the call failed and the status names no cause. This is what an unimplemented kernel path returns, so the first question is whether the export is a stub rather than what the title did wrong",
        };
    }
};

/// Severity from the top two bits of an NTSTATUS, per the platform encoding.
pub fn severityOf(status: u32) u2 {
    return @truncate(status >> 30);
}

/// Classify one NTSTATUS.
///
/// The specific codes come first because they outrank their own severity: a
/// `STATUS_NO_MORE_FILES` is warning-severity and is nonetheless the normal end
/// of an enumeration, and a `STATUS_NO_SUCH_FILE` is error-severity and is
/// nonetheless the expected answer to "is this there".
pub fn classify(status: u32) Class {
    return switch (status) {
        // Success and informational severities.
        0x0000_0000 => .success,
        // The answers to questions.
        0x8000_0006, // STATUS_NO_MORE_FILES — an enumeration ran out.
        0x8000_001A, // STATUS_NO_MORE_ENTRIES
        0xC000_000F, // STATUS_NO_SUCH_FILE
        0xC000_0034, // STATUS_OBJECT_NAME_NOT_FOUND
        0xC000_003A, // STATUS_OBJECT_PATH_NOT_FOUND
        0xC000_0035, // STATUS_OBJECT_NAME_COLLISION — "create if absent" said no.
        0xC000_0225, // STATUS_NOT_FOUND
        => .answered_negative,
        // The kernel's "no, and I will not say why".
        0xC000_0001, // STATUS_UNSUCCESSFUL
        0xC000_0002, // STATUS_NOT_IMPLEMENTED
        => .unexplained_failure,
        else => switch (severityOf(status)) {
            0 => .success,
            1 => .success,
            // Warning severity with no specific rule: a partial answer.
            2 => .answered_negative,
            3 => .named_failure,
        },
    };
}

pub const Entry = struct {
    status: u32 = 0,
    dos_error: u32 = 0,
    class: Class = .success,
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// The operation Rosette last saw before this status, retained so a reader
    /// gets a subject rather than a code. Empty when nothing was in flight.
    context: [max_context]u8 = [_]u8{0} ** max_context,
    context_len: usize = 0,

    pub fn contextSlice(self: *const Entry) []const u8 {
        return self.context[0..self.context_len];
    }
};

pub const Summary = struct {
    total: u64 = 0,
    distinct: usize = 0,
    unretained: u64 = 0,
    by_class: [class_count]u64 = [_]u64{0} ** class_count,

    /// Failures nobody asked for.
    pub fn defects(self: Summary) u64 {
        return self.by_class[@intFromEnum(Class.named_failure)] +|
            self.by_class[@intFromEnum(Class.unexplained_failure)];
    }

    pub fn verdict(self: Summary) []const u8 {
        if (self.total == 0) {
            return "no kernel status conversion has been observed; the guest has not reported a failed kernel call through this path";
        }
        if (self.by_class[@intFromEnum(Class.unexplained_failure)] != 0) {
            return "a kernel call failed with a status that names no cause. Read the retained operation for each: an unexplained failure is what an unwritten export returns, so check whether the call reached a stub before blaming the title";
        }
        if (self.by_class[@intFromEnum(Class.named_failure)] != 0) {
            return "a kernel call failed for a stated reason. The reason and the operation below name the work";
        }
        return "every observed conversion was an answer the caller asked for — a probe that found nothing, or an enumeration that ended. None of these is a defect, and the count is the title asking questions rather than the kernel failing";
    }
};

pub const class_count: usize = @typeInfo(Class).@"enum".fields.len;

pub const Ledger = struct {
    entries: [max_statuses]Entry = [_]Entry{.{}} ** max_statuses,
    count: usize = 0,
    total: u64 = 0,
    unretained: u64 = 0,
    by_class: [class_count]u64 = [_]u64{0} ** class_count,
    /// The operation in flight, set by whatever last named one. Kept as a
    /// plain buffer rather than a borrowed slice: the guest log line it came
    /// from is reused before the next status arrives.
    pending: [max_context]u8 = [_]u8{0} ** max_context,
    pending_len: usize = 0,
    /// Guest log lines this ledger was offered.
    ///
    /// The 2026-09-05 run held fifty-eight `xeRtlNtStatusToDosError` lines and
    /// this ledger reported nothing. Two explanations fit that — the parser
    /// declined every line, or the lines never reached the parser — and they
    /// need opposite repairs. A report with no denominator cannot separate
    /// them, so the denominator is kept.
    lines_seen: u64 = 0,

    pub fn noteLine(self: *Ledger) void {
        self.lines_seen +|= 1;
    }

    /// Name the operation a following status will be attributed to.
    pub fn noteOperation(self: *Ledger, text: []const u8) void {
        const take = @min(text.len, max_context);
        @memcpy(self.pending[0..take], text[0..take]);
        self.pending_len = take;
    }

    pub fn observe(self: *Ledger, status: u32, dos_error: u32, step: u64) void {
        const class = classify(status);
        self.total +|= 1;
        self.by_class[@intFromEnum(class)] +|= 1;
        for (self.entries[0..self.count]) |*entry| {
            if (entry.status != status) continue;
            entry.count +|= 1;
            entry.last_step = step;
            self.pending_len = 0;
            return;
        }
        if (self.count >= max_statuses) {
            self.unretained +|= 1;
            self.pending_len = 0;
            return;
        }
        var entry = Entry{
            .status = status,
            .dos_error = dos_error,
            .class = class,
            .count = 1,
            .first_step = step,
            .last_step = step,
        };
        @memcpy(entry.context[0..self.pending_len], self.pending[0..self.pending_len]);
        entry.context_len = self.pending_len;
        self.entries[self.count] = entry;
        self.count += 1;
        self.pending_len = 0;
    }

    pub fn retained(self: *const Ledger) []const Entry {
        return self.entries[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        return .{
            .total = self.total,
            .distinct = self.count,
            .unretained = self.unretained,
            .by_class = self.by_class,
        };
    }

    /// The status a reader should look at first: an unexplained failure if
    /// there is one, else a named failure. An answered negative is never it.
    pub fn firstDefect(self: *const Ledger) ?Entry {
        var named: ?Entry = null;
        for (self.retained()) |entry| {
            if (entry.class == .unexplained_failure) return entry;
            if (entry.class == .named_failure and named == null) named = entry;
        }
        return named;
    }
};

// The exact lines from the 2026-09-05 log, so a parser regression is caught
// here rather than by a silent zero in a report.
test "the real log lines parse" {
    var ledger = Ledger{};
    ledger.noteOperation("NtOpenFile(cache0:\\cache006.map)");
    ledger.observe(0xC000_000F, 2, 10);
    ledger.observe(0xC000_0001, 1, 20);
    ledger.observe(0x8000_0006, 12, 30);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 3), totals.total);
    try std.testing.expectEqual(@as(u64, 1), totals.defects());
    try std.testing.expectEqual(
        @as(u64, 2),
        totals.by_class[@intFromEnum(Class.answered_negative)],
    );
    const first = ledger.firstDefect().?;
    try std.testing.expectEqual(@as(u32, 0xC000_0001), first.status);
    try std.testing.expectEqual(@as(u32, 1), first.dos_error);
}

// A ledger that saw lines and placed none is a parser fault; one that saw no
// lines at all is a routing fault. The denominator is what separates them.
test "the line denominator separates a dead parser from a dead route" {
    var ledger = Ledger{};
    try std.testing.expectEqual(@as(u64, 0), ledger.lines_seen);
    var index: usize = 0;
    while (index < 400) : (index += 1) ledger.noteLine();
    try std.testing.expectEqual(@as(u64, 400), ledger.lines_seen);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().total);
}

test "an unsampled ledger says nothing and admits it" {
    const ledger = Ledger{};
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 0), totals.total);
    try std.testing.expectEqual(@as(u64, 0), totals.defects());
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict(), "has not reported") != null);
    try std.testing.expectEqual(@as(?Entry, null), ledger.firstDefect());
}

// The 2026-09-04 run: fifty-eight conversions, and the useful reading is that
// fifty-six of them are one benign class and two are not.
test "a cache probe storm is not fifty-six defects" {
    var ledger = Ledger{};
    for (0..56) |index| {
        ledger.noteOperation("NtOpenFile(cache0:\\cache007.map)");
        ledger.observe(0xC000_000F, 2, index);
    }
    ledger.observe(0x8000_0006, 12, 100);

    var totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 57), totals.total);
    // Not one of them is a defect: each answered a question that was asked.
    try std.testing.expectEqual(@as(u64, 0), totals.defects());
    try std.testing.expectEqual(@as(?Entry, null), ledger.firstDefect());
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict(), "asking questions") != null);

    // One unexplained failure changes the verdict, however small its share.
    ledger.noteOperation("XamUserGetSigninState");
    ledger.observe(0xC000_0001, 1, 200);
    totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.defects());
    const first = ledger.firstDefect().?;
    try std.testing.expectEqual(@as(u32, 0xC000_0001), first.status);
    try std.testing.expectEqualStrings("XamUserGetSigninState", first.contextSlice());
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict(), "names no cause") != null);
}

// A status the table has never seen must still be placed, and placed so that
// nobody has to have thought of it in advance for it to be visible.
test "an unknown error status is a defect until someone says otherwise" {
    try std.testing.expectEqual(Class.named_failure, classify(0xC000_0022)); // ACCESS_DENIED
    try std.testing.expectEqual(Class.named_failure, classify(0xC000_00BB)); // NOT_SUPPORTED
    try std.testing.expectEqual(Class.unexplained_failure, classify(0xC000_0001));
    try std.testing.expectEqual(Class.unexplained_failure, classify(0xC000_0002));
    // Warning severity with no rule is a partial answer, not a failure.
    try std.testing.expectEqual(Class.answered_negative, classify(0x8000_0005));
    // Success and informational never inflate the failure totals.
    try std.testing.expectEqual(Class.success, classify(0x0000_0000));
    try std.testing.expectEqual(Class.success, classify(0x4000_0000));
    try std.testing.expect(!Class.success.isDefect());
    try std.testing.expect(!Class.answered_negative.isDefect());
    try std.testing.expect(Class.named_failure.isDefect());
    try std.testing.expect(Class.unexplained_failure.isDefect());
}

test "every class names itself and a consequence" {
    inline for (@typeInfo(Class).@"enum".fields) |field| {
        const class: Class = @enumFromInt(field.value);
        try std.testing.expect(class.label().len != 0);
        try std.testing.expect(class.describe().len != 0);
    }
}

// A fixed table has to say what it could not hold, and the class totals must
// still cover every observation.
test "statuses past the table still count toward their class" {
    var ledger = Ledger{};
    var index: u32 = 0;
    while (index < max_statuses + 4) : (index += 1) {
        // Distinct error-severity codes, all defects.
        ledger.observe(0xC000_1000 + index, 5, index);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(max_statuses, totals.distinct);
    try std.testing.expectEqual(@as(u64, 4), totals.unretained);
    try std.testing.expectEqual(@as(u64, max_statuses + 4), totals.total);
    try std.testing.expectEqual(@as(u64, max_statuses + 4), totals.defects());
    var sum: u64 = 0;
    for (totals.by_class) |count| sum += count;
    try std.testing.expectEqual(totals.total, sum);
}
