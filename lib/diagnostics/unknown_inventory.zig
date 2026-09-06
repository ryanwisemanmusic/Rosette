//! What Rosette could not map, named by the raw value it could not map.
//!
//! ## The gap this closes
//!
//! On 2026-09-05 a run emitted `unknown` thirteen thousand five hundred and
//! seventy-seven times. That word is the single most common finding in the log
//! and it is the least actionable: it says a classifier declined and nothing
//! about what it declined on. A reader cannot act on "unknown". A reader can
//! act on "guest object type code 6, seen 1767 times, blocks wait
//! classification" — that is a case statement someone can write this afternoon.
//!
//! The distance between those two sentences is this file.
//!
//! ## Why counting `unknown` is not enough
//!
//! Most of that thirteen thousand was noise. `event_mode=unknown` appeared
//! seven thousand times on Semaphores, Threads and Timers — objects that have
//! no event mode, so the honest answer was never "unknown" but "not
//! applicable". Fake unknowns crowd out real ones, and a count that mixes them
//! ranks the noise first. An entry belongs here only when a classifier had a
//! value in hand, was supposed to recognise it, and did not.
//!
//! ## What it is and is not
//!
//! It is an inventory of missing mappings, ranked by how often the run hit
//! them. It is not a defect ledger: an unmapped value seen once during bring-up
//! is a note, and the same value seen two thousand times while a conclusion
//! waits on it is the reason the run is stuck. The `blocking` flag is what
//! separates them, and it is set by the call site — which is the only place
//! that knows whether anything downstream needed the answer.

const std = @import("std");

/// Distinct (domain, value) pairs retained. A run's unmapped surface is small;
/// anything past this is counted so a diffuse gap cannot look concentrated.
pub const max_entries: usize = 48;
pub const max_note: usize = 64;

/// What kind of mapping is missing.
///
/// Coarse on purpose: the domain says which table to extend, and the raw value
/// says which row to add to it. Anything finer would be a fact about one
/// classifier rather than about the work.
pub const Domain = enum(u8) {
    /// A guest kernel object type code no `ObjectKind` case covers. Every wait
    /// policy decision about such an object is unclassified.
    guest_object_type,
    /// A guest kernel status code the status ledger placed only by severity.
    guest_status_code,
    /// A PM4 opcode the packet decoder does not recognise.
    pm4_opcode,
    /// A Xenos register index outside every known block.
    xenos_register,
    /// A stage or boundary whose owner the contract cannot name.
    stage_owner,
    /// An address no symbol and no region covers.
    code_address,
    /// A guest export ordinal with no entry in the export map.
    kernel_ordinal,
    /// A host capability or format the negotiation could not place.
    host_capability,
    /// A VFS device that resolved a path with no backing store.
    vfs_device,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .guest_object_type => "guest-object-type",
            .guest_status_code => "guest-status-code",
            .pm4_opcode => "pm4-opcode",
            .xenos_register => "xenos-register",
            .stage_owner => "stage-owner",
            .code_address => "code-address",
            .kernel_ordinal => "kernel-ordinal",
            .host_capability => "host-capability",
            .vfs_device => "vfs-device",
        };
    }

    /// Where the missing case goes. A domain that cannot say this is a domain
    /// that has not earned a row in the report.
    pub fn remedy(self: Domain) []const u8 {
        return switch (self) {
            .guest_object_type => "add the type code to xeniaWaitObjectKind in guest_log.zig and give it an ObjectKind. Until then every wait on this object is unclassified and cannot support a consumption conclusion",
            .guest_status_code => "add the status to guest_status_ledger.classify so it is placed by meaning rather than by severity alone",
            .pm4_opcode => "add the opcode to the PM4 decoder. An unrecognised packet stops the walk, so every stage downstream of it reads zero for a reason that is Rosette's",
            .xenos_register => "add the index to the Xenos register block map. An unclassified write is counted but attributed to no block, so the render-target verdicts above it are short",
            .stage_owner => "give the stage an owner in its contract. A stage nobody owns is a stage nobody is asked to fix",
            .code_address => "extend the region or symbol classifier. Check the address against the sparse mappings first: generated code has no symbol and never will",
            .kernel_ordinal => "add the ordinal to the kernel export map. Titles import by ordinal, so an unmapped one is a call whose name nobody knows",
            .host_capability => "add the capability or format to the negotiation table so its absence is a decision rather than a gap",
            .vfs_device => "give the path a backing device, or record it as intentionally null-backed. A null device that answers for content is a silent read of nothing",
        };
    }
};

pub const domain_count: usize = @typeInfo(Domain).@"enum".fields.len;

pub const Entry = struct {
    domain: Domain = .guest_object_type,
    /// The value the classifier had in hand and could not place. This is the
    /// whole point of the record: it is what turns a report into a patch.
    value: u64 = 0,
    /// Whether anything downstream needed the answer. An unmapped value nobody
    /// consulted is a note; one a conclusion waits on is why a run is stuck.
    blocking: bool = false,
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    note: [max_note]u8 = [_]u8{0} ** max_note,
    note_len: usize = 0,

    pub fn noteSlice(self: *const Entry) []const u8 {
        return self.note[0..self.note_len];
    }
};

pub const Summary = struct {
    total: u64 = 0,
    distinct: usize = 0,
    unretained: u64 = 0,
    blocking_total: u64 = 0,
    blocking_distinct: usize = 0,
    by_domain: [domain_count]u64 = [_]u64{0} ** domain_count,

    pub fn verdict(self: Summary) []const u8 {
        if (self.total == 0) {
            return "no classifier reported an unmapped value; every value the run handed to a table was one the table knew";
        }
        if (self.blocking_distinct != 0) {
            return "a classifier declined a value that a conclusion downstream needed. The rows marked blocking are missing table entries, and each names the exact value to add. This is the shortest path out of a run that keeps reaching the same frontier";
        }
        return "values were left unmapped, and nothing downstream has asked for them yet. These are notes rather than blockers: they become blocking the moment a conclusion needs the answer";
    }
};

pub const Ledger = struct {
    entries: [max_entries]Entry = [_]Entry{.{}} ** max_entries,
    count: usize = 0,
    total: u64 = 0,
    unretained: u64 = 0,
    by_domain: [domain_count]u64 = [_]u64{0} ** domain_count,
    /// The path a VFS resolution is about to answer for. Held here rather than
    /// at the call site because the device line and the path that led to it are
    /// two separate guest log lines, and only the pair is a finding.
    pending_path: [max_note]u8 = [_]u8{0} ** max_note,
    pending_path_len: usize = 0,

    pub fn notePath(self: *Ledger, text: []const u8) void {
        const take = @min(text.len, max_note);
        @memcpy(self.pending_path[0..take], text[0..take]);
        self.pending_path_len = take;
    }

    pub fn pendingPath(self: *const Ledger) []const u8 {
        return self.pending_path[0..self.pending_path_len];
    }

    /// Whether the path in flight is one the console answers from nothing by
    /// design. The raw partition device is opened by titles for geometry and
    /// has no file system behind it on any console; a null answer there is
    /// correct and stopping on it would stop every run.
    pub fn pendingPathIsNullBackedByDesign(self: *const Ledger) bool {
        const path = self.pendingPath();
        if (path.len == 0) return true;
        const designed = [_][]const u8{ "Harddisk0", "partition0", "\\Device\\Cdrom0", "nul" };
        for (designed) |needle| {
            if (std.mem.indexOf(u8, path, needle) != null) return true;
        }
        return false;
    }

    /// Record one value a classifier could not place.
    ///
    /// `blocking` is the caller's statement that something downstream needed
    /// the answer. It is deliberately not inferred: only the call site knows
    /// whether the unmapped value stopped a conclusion or merely went unread,
    /// and a ledger that guessed would rank noise above the thing to fix.
    pub fn observe(
        self: *Ledger,
        domain: Domain,
        value: u64,
        blocking: bool,
        note: []const u8,
        step: u64,
    ) void {
        self.total +|= 1;
        self.by_domain[@intFromEnum(domain)] +|= 1;
        for (self.entries[0..self.count]) |*entry| {
            if (entry.domain != domain or entry.value != value) continue;
            entry.count +|= 1;
            entry.last_step = step;
            // Blocking is sticky: one consultation that needed the answer is
            // enough to make the gap matter, and a later unread sighting must
            // not demote it.
            if (blocking) entry.blocking = true;
            return;
        }
        if (self.count >= max_entries) {
            self.unretained +|= 1;
            return;
        }
        var entry = Entry{
            .domain = domain,
            .value = value,
            .blocking = blocking,
            .count = 1,
            .first_step = step,
            .last_step = step,
        };
        const take = @min(note.len, max_note);
        @memcpy(entry.note[0..take], note[0..take]);
        entry.note_len = take;
        self.entries[self.count] = entry;
        self.count += 1;
    }

    pub fn retained(self: *const Ledger) []const Entry {
        return self.entries[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{
            .total = self.total,
            .distinct = self.count,
            .unretained = self.unretained,
            .by_domain = self.by_domain,
        };
        for (self.retained()) |entry| {
            if (!entry.blocking) continue;
            out.blocking_distinct += 1;
            out.blocking_total +|= entry.count;
        }
        return out;
    }

    /// The `wanted` gaps a reader should close first, most-consulted first,
    /// with blocking gaps always ahead of notes. Selection sort over a fixed
    /// table, called once per report.
    pub fn ranked(self: *const Ledger, out: []Entry) usize {
        var written: usize = 0;
        var taken = [_]bool{false} ** max_entries;
        while (written < out.len) {
            var best: ?usize = null;
            for (self.retained(), 0..) |entry, index| {
                if (taken[index]) continue;
                const held = best orelse {
                    best = index;
                    continue;
                };
                const incumbent = self.entries[held];
                if (entry.blocking != incumbent.blocking) {
                    if (entry.blocking) best = index;
                    continue;
                }
                if (entry.count > incumbent.count) best = index;
            }
            const chosen = best orelse break;
            taken[chosen] = true;
            out[written] = self.entries[chosen];
            written += 1;
        }
        return written;
    }

    /// Gaps consulted often enough that they are certainly real.
    ///
    /// A value seen once during bring-up may be a transient the run never
    /// revisits. One consulted this many times while a conclusion waits is a
    /// missing table entry, and no amount of further running produces it.
    pub fn settledBlockers(self: *const Ledger, threshold: u64) usize {
        var found: usize = 0;
        for (self.retained()) |entry| {
            if (entry.blocking and entry.count >= threshold) found += 1;
        }
        return found;
    }
};

/// How many consultations make a blocking gap certainly real rather than a
/// bring-up transient. Low enough to catch a gap in the first checkpoints,
/// high enough that a single odd value does not stop a run.
pub const settled_blocker_threshold: u64 = 32;

test "an empty inventory says nothing and admits it" {
    const ledger = Ledger{};
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 0), totals.total);
    try std.testing.expectEqual(@as(usize, 0), totals.blocking_distinct);
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict(), "every value") != null);
    try std.testing.expectEqual(@as(usize, 0), ledger.settledBlockers(settled_blocker_threshold));
}

// The 2026-09-05 run: guest object type 6 (Mutant) reached the wait classifier
// 1767 times and fell to `.unknown` every time, so no wait on a mutex could
// support a consumption conclusion. The count is what makes it the first thing
// to fix; the value 6 is what makes it fixable.
test "a blocking gap names the value to add and outranks a note" {
    var ledger = Ledger{};
    for (0..1767) |index| {
        ledger.observe(.guest_object_type, 6, true, "Mutant", index);
    }
    // A more frequent but non-blocking gap must not outrank it.
    for (0..5000) |index| {
        ledger.observe(.code_address, 0xa000_fdb4, false, "generated code", index);
    }

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 2), totals.distinct);
    try std.testing.expectEqual(@as(usize, 1), totals.blocking_distinct);
    try std.testing.expectEqual(@as(u64, 1767), totals.blocking_total);
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict(), "shortest path") != null);

    var top: [4]Entry = undefined;
    const written = ledger.ranked(&top);
    try std.testing.expectEqual(@as(usize, 2), written);
    // Blocking first, even though the note was seen three times as often.
    try std.testing.expectEqual(Domain.guest_object_type, top[0].domain);
    try std.testing.expectEqual(@as(u64, 6), top[0].value);
    try std.testing.expectEqualStrings("Mutant", top[0].noteSlice());
    try std.testing.expectEqual(Domain.code_address, top[1].domain);

    try std.testing.expectEqual(@as(usize, 1), ledger.settledBlockers(settled_blocker_threshold));
}

// Blocking is sticky. A gap that stopped a conclusion once is a gap even if
// every later sighting went unread.
test "a later unread sighting does not demote a blocker" {
    var ledger = Ledger{};
    ledger.observe(.pm4_opcode, 0x42, true, "", 1);
    ledger.observe(.pm4_opcode, 0x42, false, "", 2);
    try std.testing.expect(ledger.retained()[0].blocking);
    try std.testing.expectEqual(@as(u64, 2), ledger.retained()[0].count);
}

// A single sighting during bring-up is a note, not a reason to stop.
test "one sighting is not a settled blocker" {
    var ledger = Ledger{};
    ledger.observe(.xenos_register, 0x2000, true, "", 1);
    try std.testing.expectEqual(@as(usize, 0), ledger.settledBlockers(settled_blocker_threshold));
    var index: u64 = 0;
    while (index < settled_blocker_threshold) : (index += 1) {
        ledger.observe(.xenos_register, 0x2000, true, "", index);
    }
    try std.testing.expectEqual(@as(usize, 1), ledger.settledBlockers(settled_blocker_threshold));
}

// A null device answering for the raw partition is how a console behaves; a
// null device answering for content is a silent read of zero. The two arrive as
// the same log line and only the path in flight separates them.
test "a null-backed path by design is separated from a content path" {
    var ledger = Ledger{};
    // Nothing in flight: cannot accuse, so do not.
    try std.testing.expect(ledger.pendingPathIsNullBackedByDesign());

    ledger.notePath("(00000000,\\Device\\Harddisk0\\partition0,00000040)");
    try std.testing.expect(ledger.pendingPathIsNullBackedByDesign());
    try std.testing.expect(std.mem.indexOf(u8, ledger.pendingPath(), "partition0") != null);

    ledger.notePath("(FFFFFFFD,game:\\default.xex,00000040)");
    try std.testing.expect(!ledger.pendingPathIsNullBackedByDesign());
}

test "every domain names itself and where its missing case goes" {
    inline for (@typeInfo(Domain).@"enum".fields) |field| {
        const domain: Domain = @enumFromInt(field.value);
        try std.testing.expect(domain.label().len != 0);
        try std.testing.expect(domain.remedy().len != 0);
    }
}

test "gaps past the table still count toward their domain" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_entries + 5) : (index += 1) {
        ledger.observe(.kernel_ordinal, index, false, "", index);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(max_entries, totals.distinct);
    try std.testing.expectEqual(@as(u64, 5), totals.unretained);
    try std.testing.expectEqual(@as(u64, max_entries + 5), totals.total);
    var sum: u64 = 0;
    for (totals.by_domain) |count| sum += count;
    try std.testing.expectEqual(totals.total, sum);
}
