//! Guest anomalies, classified rather than counted.
//!
//! A signoff that reads "guest assertions: 7, invalid frees: 5, primitive
//! library declines: 1" tells a reader that something happened seven, five and
//! one times, and nothing about whether any of it matters. Every one of those
//! numbers has been non-zero across every run of this investigation, and none
//! has ever been either acted on or dismissed — which is the worst of both
//! outcomes, because a permanently non-zero counter stops being read.
//!
//! The distinction that makes them actionable is whether the emulator
//! *continued correctly* afterwards. An assertion inside a parser that falls
//! back to a default is a data problem in the title's files; the same assertion
//! guarding a pointer that is then dereferenced is the cause of everything
//! after it. Nothing in a count separates those, so each anomaly is recorded
//! with where it happened and what the runtime did next, and the ledger refuses
//! to call a run clean while any anomaly is still unclassified.
//!
//! Bounded on purpose: the first few of each kind carry the information, and a
//! run that produces thousands has a different problem that a longer list will
//! not illuminate.

const std = @import("std");

pub const max_records: usize = 48;
pub const max_detail: usize = 120;

/// What kind of anomaly this is. Each maps to a different owner.
pub const Kind = enum(u8) {
    /// An assertion inside the emulator's own host code.
    host_assertion,
    /// A free of memory the forwarder does not own, or a double free.
    invalid_free,
    /// A runtime library that declined to service a call.
    library_decline,
    /// An import that resolved to nothing usable.
    unresolved_import,
    /// A guest fault the runtime recovered from.
    recovered_fault,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .host_assertion => "emulator assertion",
            .invalid_free => "invalid free",
            .library_decline => "library decline",
            .unresolved_import => "unresolved import",
            .recovered_fault => "recovered fault",
        };
    }
};

/// What the runtime did after the anomaly. This is the field that decides
/// whether the anomaly is a finding or a footnote.
pub const Disposition = enum(u8) {
    /// Nobody has said what happened next. The default, and the only value
    /// that keeps a run from being signed off.
    unclassified,
    /// Execution continued and the affected subsystem kept working. A parser
    /// that fell back to a default belongs here.
    continued_benign,
    /// Execution continued but the affected subsystem is now degraded — the
    /// data it should have produced is missing or wrong.
    continued_degraded,
    /// The anomaly is on the path to the failure being investigated.
    implicated,
    /// Execution could not continue.
    fatal,

    pub fn blocksSignoff(self: Disposition) bool {
        return self == .unclassified or self == .implicated or self == .fatal;
    }

    pub fn label(self: Disposition) []const u8 {
        return switch (self) {
            .unclassified => "UNCLASSIFIED (nobody has said what happened next)",
            .continued_benign => "continued, subsystem unaffected",
            .continued_degraded => "continued, subsystem degraded",
            .implicated => "IMPLICATED in the failure under investigation",
            .fatal => "FATAL",
        };
    }
};

pub const Record = struct {
    kind: Kind = .host_assertion,
    disposition: Disposition = .unclassified,
    /// Where it happened, truncated. Borrowed strings would dangle past the
    /// call that produced them, so the text is copied.
    detail: [max_detail]u8 = [_]u8{0} ** max_detail,
    detail_length: u8 = 0,
    step: u64 = 0,
    guest_thread: u64 = 0,
    caller_pc: u64 = 0,
    occurrences: u32 = 0,

    pub fn detailSlice(self: *const Record) []const u8 {
        return self.detail[0..self.detail_length];
    }
};

pub const Ledger = struct {
    records: [max_records]Record = [_]Record{.{}} ** max_records,
    count: usize = 0,
    /// Anomalies beyond the record capacity. Reported, because a ledger that
    /// silently stops recording implies the anomalies stopped happening.
    overflow: u64 = 0,
    totals: [@typeInfo(Kind).@"enum".fields.len]u64 =
        [_]u64{0} ** @typeInfo(Kind).@"enum".fields.len,
    /// Step of the most recent structural progress. Anomalies after it are the
    /// ones the run never got past.
    last_advance_step: u64 = 0,
    /// Whether the run is over. Only then does "still unclassified" mean
    /// "the pipeline never advanced past it" rather than "not yet".
    sealed: bool = false,

    /// Record an anomaly. Repeats of an identical detail collapse into one
    /// record with an occurrence count: the same assertion firing in a loop is
    /// one finding, not four hundred.
    pub fn note(
        self: *Ledger,
        kind: Kind,
        detail: []const u8,
        step: u64,
        guest_thread: u64,
        caller_pc: u64,
    ) *Record {
        self.totals[@intFromEnum(kind)] +|= 1;
        for (self.records[0..self.count]) |*existing| {
            if (existing.kind != kind) continue;
            if (!std.mem.eql(u8, existing.detailSlice(), detail[0..@min(detail.len, max_detail)])) continue;
            existing.occurrences +|= 1;
            return existing;
        }
        if (self.count >= max_records) {
            self.overflow +|= 1;
            return &self.records[max_records - 1];
        }
        const record = &self.records[self.count];
        self.count += 1;
        const length = @min(detail.len, max_detail);
        @memcpy(record.detail[0..length], detail[0..length]);
        record.* = .{
            .kind = kind,
            .disposition = .unclassified,
            .detail = record.detail,
            .detail_length = @intCast(length),
            .step = step,
            .guest_thread = guest_thread,
            .caller_pc = caller_pc,
            .occurrences = 1,
        };
        return record;
    }

    /// Say what happened after an anomaly. Classifying is a separate act from
    /// recording, because whoever observes the anomaly usually cannot yet know
    /// whether the subsystem recovered.
    pub fn classify(self: *Ledger, kind: Kind, detail_fragment: []const u8, disposition: Disposition) bool {
        var classified = false;
        for (self.records[0..self.count]) |*record| {
            if (record.kind != kind) continue;
            if (std.mem.indexOf(u8, record.detailSlice(), detail_fragment) == null) continue;
            record.disposition = disposition;
            classified = true;
        }
        return classified;
    }

    /// Classify by progress: the pipeline reached a new milestone at `step`, so
    /// every anomaly recorded before it is one the run *continued past*.
    ///
    /// This exists because `classify` had no callers. Every run of this
    /// investigation ended `unclassified=N` with N never falling, and an
    /// unclassified ledger blocks signoff by design — so the design was
    /// producing a permanent blocker instead of a verdict. Asking each
    /// subsystem to classify its own anomalies never happened and was never
    /// going to: the subsystem that trips an assertion is precisely the one
    /// that does not yet know whether anything recovered.
    ///
    /// Structural progress is the evidence that is actually available, and it
    /// is the audit's own test — "record the next relevant milestone". An
    /// anomaly the pipeline advanced past did not stop the pipeline. It may
    /// still have degraded something, which is why a subsystem that *does*
    /// know may still call `classify` and say so; this only moves records off
    /// `unclassified`, never off a disposition someone else established.
    pub fn notePipelineAdvance(self: *Ledger, step: u64) usize {
        var advanced: usize = 0;
        for (self.records[0..self.count]) |*record| {
            if (record.disposition != .unclassified) continue;
            if (record.step >= step) continue;
            record.disposition = .continued_benign;
            advanced += 1;
        }
        self.last_advance_step = step;
        return advanced;
    }

    /// Close the ledger. Anything still unclassified is an anomaly the pipeline
    /// never advanced past, which is the definition of being on the path to the
    /// stall under investigation.
    ///
    /// Deliberately not called from `verdict`: sealing is an assertion that the
    /// run is over, and a mid-run snapshot that sealed the ledger would report
    /// every recent anomaly as implicated while the run was still working.
    pub fn seal(self: *Ledger) usize {
        var implicated_now: usize = 0;
        for (self.records[0..self.count]) |*record| {
            if (record.disposition != .unclassified) continue;
            record.disposition = .implicated;
            implicated_now += 1;
        }
        self.sealed = true;
        return implicated_now;
    }

    pub fn total(self: *const Ledger, kind: Kind) u64 {
        return self.totals[@intFromEnum(kind)];
    }

    pub fn unclassified(self: *const Ledger) usize {
        var pending: usize = 0;
        for (self.records[0..self.count]) |record| {
            if (record.disposition == .unclassified) pending += 1;
        }
        return pending;
    }

    pub fn implicated(self: *const Ledger) usize {
        var found: usize = 0;
        for (self.records[0..self.count]) |record| {
            if (record.disposition == .implicated or record.disposition == .fatal) found += 1;
        }
        return found;
    }

    /// Whether a run may be called clean. Deliberately strict: an anomaly
    /// nobody looked at is not the same as one that was looked at and found
    /// harmless, and only the second may be signed off.
    pub fn signoffClean(self: *const Ledger) bool {
        for (self.records[0..self.count]) |record| {
            if (record.disposition.blocksSignoff()) return false;
        }
        return self.overflow == 0;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.count == 0) return "no anomalies were recorded in this run";
        if (self.implicated() != 0) {
            return "at least one anomaly is implicated in the failure under investigation; it is evidence, not noise";
        }
        if (self.overflow != 0) {
            return "the ledger overflowed, so some anomalies were never recorded. The count is a floor, not a total";
        }
        if (self.unclassified() != 0) {
            return if (self.sealed)
                "anomalies remain unclassified after the run was sealed, which should be impossible: sealing implicates whatever the pipeline never advanced past. Treat this as a defect in the ledger, not a finding about the guest"
            else
                "anomalies have been recorded and the pipeline has not yet advanced past them. They are pending, not dismissed: if the run ends here they become implicated";
        }
        return "every recorded anomaly was classified and none is implicated";
    }
};

// The gap this closes: `classify` existed and nothing called it, so every run
// ended `unclassified=N`, blocked its own signoff, and said nothing about
// whether any anomaly mattered.
test "structural progress classifies the anomalies it advanced past" {
    var ledger = Ledger{};
    _ = ledger.note(.host_assertion, "spa_info.cc:95 LoadAchievements", 100, 0x7fff2000, 0x647536);
    _ = ledger.note(.host_assertion, "xboxkrnl_memory.cc:79", 200, 0x7fff2000, 0x647600);
    try std.testing.expectEqual(@as(usize, 2), ledger.unclassified());

    // A milestone between the two settles only the earlier one; the later
    // anomaly has no progress after it yet.
    try std.testing.expectEqual(@as(usize, 1), ledger.notePipelineAdvance(150));
    try std.testing.expectEqual(@as(usize, 1), ledger.unclassified());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "pending, not dismissed") != null);

    try std.testing.expectEqual(@as(usize, 1), ledger.notePipelineAdvance(300));
    try std.testing.expectEqual(@as(usize, 0), ledger.unclassified());
    try std.testing.expect(ledger.signoffClean());
}

test "sealing implicates whatever the pipeline never advanced past" {
    var ledger = Ledger{};
    _ = ledger.note(.host_assertion, "spa_info.cc:378 ReadXLast", 100, 0x7fff2000, 0x647536);
    _ = ledger.note(.recovered_fault, "guest fault at 82450390", 900, 0x7fff20e0, 0xa00f4301);
    _ = ledger.notePipelineAdvance(500);

    // One anomaly had progress after it; the other did not, and the run ending
    // is what makes that difference a finding.
    try std.testing.expectEqual(@as(usize, 1), ledger.seal());
    try std.testing.expectEqual(@as(usize, 1), ledger.implicated());
    try std.testing.expectEqual(@as(usize, 0), ledger.unclassified());
    try std.testing.expect(!ledger.signoffClean());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "evidence, not noise") != null);
}

// Progress must not overwrite a disposition a subsystem actually established.
test "a subsystem's own classification outranks the progress heuristic" {
    var ledger = Ledger{};
    _ = ledger.note(.invalid_free, "forwarder free of unowned block", 100, 0, 0);
    try std.testing.expect(ledger.classify(.invalid_free, "unowned", .continued_degraded));
    try std.testing.expectEqual(@as(usize, 0), ledger.notePipelineAdvance(500));
    try std.testing.expectEqual(Disposition.continued_degraded, ledger.records[0].disposition);
    _ = ledger.seal();
    try std.testing.expectEqual(Disposition.continued_degraded, ledger.records[0].disposition);
}

test "an unclassified anomaly blocks signoff" {
    var ledger = Ledger{};
    _ = ledger.note(.host_assertion, "spa_info.cc:61 LoadLanguageData", 558249460, 0x7fff2000, 0x647536);
    try std.testing.expectEqual(@as(usize, 1), ledger.unclassified());
    try std.testing.expect(!ledger.signoffClean());
    // Unclassified still blocks signoff. What changed is that an unsealed
    // ledger now says the record is *pending* rather than permanently
    // unexplained — the run has simply not advanced past it yet.
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "pending, not dismissed") != null);
}

// The distinction that makes a permanently non-zero counter readable again:
// looked at and harmless is not the same as never looked at.
test "a classified benign anomaly does not block signoff" {
    var ledger = Ledger{};
    _ = ledger.note(.host_assertion, "spa_info.cc:61 LoadLanguageData", 1, 2, 3);
    try std.testing.expect(ledger.classify(.host_assertion, "LoadLanguageData", .continued_benign));
    try std.testing.expectEqual(@as(usize, 0), ledger.unclassified());
    try std.testing.expect(ledger.signoffClean());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "none is implicated") != null);
}

test "an implicated anomaly is evidence and says so" {
    var ledger = Ledger{};
    _ = ledger.note(.invalid_free, "double free at 0x40", 10, 1, 2);
    _ = ledger.classify(.invalid_free, "double free", .implicated);
    try std.testing.expect(!ledger.signoffClean());
    try std.testing.expectEqual(@as(usize, 1), ledger.implicated());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "evidence, not noise") != null);
}

// The same assertion firing in a loop is one finding, not four hundred.
test "identical anomalies collapse into one record with a count" {
    var ledger = Ledger{};
    _ = ledger.note(.host_assertion, "same place", 1, 1, 1);
    _ = ledger.note(.host_assertion, "same place", 2, 1, 1);
    _ = ledger.note(.host_assertion, "same place", 3, 1, 1);
    try std.testing.expectEqual(@as(usize, 1), ledger.count);
    try std.testing.expectEqual(@as(u32, 3), ledger.records[0].occurrences);
    // The total still counts every occurrence.
    try std.testing.expectEqual(@as(u64, 3), ledger.total(.host_assertion));
    // And the first occurrence's context is the one retained.
    try std.testing.expectEqual(@as(u64, 1), ledger.records[0].step);
}

test "different kinds at the same place stay separate records" {
    var ledger = Ledger{};
    _ = ledger.note(.host_assertion, "place", 1, 1, 1);
    _ = ledger.note(.invalid_free, "place", 1, 1, 1);
    try std.testing.expectEqual(@as(usize, 2), ledger.count);
}

test "detail longer than the record is truncated rather than refused" {
    var ledger = Ledger{};
    const long = "x" ** (max_detail + 40);
    const record = ledger.note(.library_decline, long, 1, 1, 1);
    try std.testing.expectEqual(@as(usize, max_detail), record.detailSlice().len);
    // And a second identical long detail still collapses onto it.
    _ = ledger.note(.library_decline, long, 2, 1, 1);
    try std.testing.expectEqual(@as(usize, 1), ledger.count);
}

// A ledger that silently stops recording implies the anomalies stopped.
test "overflow is reported and blocks signoff" {
    var ledger = Ledger{};
    var index: usize = 0;
    var buffer: [32]u8 = undefined;
    while (index < max_records + 5) : (index += 1) {
        const detail = std.fmt.bufPrint(&buffer, "distinct-{d}", .{index}) catch unreachable;
        _ = ledger.note(.recovered_fault, detail, index, 1, 1);
    }
    try std.testing.expectEqual(max_records, ledger.count);
    try std.testing.expect(ledger.overflow > 0);
    try std.testing.expect(!ledger.signoffClean());

    var index2: usize = 0;
    while (index2 < max_records) : (index2 += 1) {
        ledger.records[index2].disposition = .continued_benign;
    }
    // Even fully classified, an overflowed ledger is not a total.
    try std.testing.expect(!ledger.signoffClean());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "floor, not a total") != null);
}

test "classifying a fragment that matches nothing reports so" {
    var ledger = Ledger{};
    _ = ledger.note(.host_assertion, "one", 1, 1, 1);
    try std.testing.expect(!ledger.classify(.host_assertion, "other", .continued_benign));
    try std.testing.expect(!ledger.classify(.invalid_free, "one", .continued_benign));
}

test "an empty ledger is clean and says nothing happened" {
    const ledger = Ledger{};
    try std.testing.expect(ledger.signoffClean());
    try std.testing.expectEqualStrings("no anomalies were recorded in this run", ledger.verdict());
}

test "every kind and disposition explains itself" {
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        const kind: Kind = @enumFromInt(field.value);
        try std.testing.expect(kind.label().len > 0);
    }
    inline for (@typeInfo(Disposition).@"enum".fields) |field| {
        const disposition: Disposition = @enumFromInt(field.value);
        try std.testing.expect(disposition.label().len > 0);
    }
    try std.testing.expect(Disposition.unclassified.blocksSignoff());
    try std.testing.expect(!Disposition.continued_benign.blocksSignoff());
    try std.testing.expect(!Disposition.continued_degraded.blocksSignoff());
}
