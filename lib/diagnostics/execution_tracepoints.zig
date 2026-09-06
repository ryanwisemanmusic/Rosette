//! Whether a function executed, decided by watching the instruction pointer
//! rather than by reading the log it was supposed to write.
//!
//! `VdSwap=0` has been the central fact of this investigation for three passes,
//! and it was never a fact about execution. It was a fact about text: the
//! observer matched the mirrored string `VdSwap(` in Xenia's own log output, so
//! a zero could equally mean the title never called it, the call took a route
//! that logs differently, the line was filtered, or the log level suppressed
//! it. Four causes, one number, and no way to tell them apart — which is how a
//! run gets classified `SUBMITTING_BUT_NEVER_PRESENTING` when nothing was
//! submitted, and how an investigation spends its time downstream of a
//! boundary it never confirmed.
//!
//! Rosette can do better because Rosette *is* the interpreter. It knows the
//! instruction pointer on every step, so "did this function run" is a question
//! it can answer directly. Arming a tracepoint at a resolved symbol address
//! turns a textual absence into an execution fact: entered, with a caller, a
//! thread and a step, or genuinely never reached.
//!
//! The cost is the whole design constraint. This is consulted on every
//! interpreted step at roughly nine million steps per second, so the common
//! case — no tracepoint anywhere near the current address — must be two
//! comparisons and nothing else. Hence the range gate: addresses outside
//! `[low, high]` are rejected before any search happens, and the search itself
//! is binary over a sorted array. An armed set that made the interpreter
//! measurably slower would change the scheduling it exists to observe.

const std = @import("std");

pub const max_tracepoints: usize = 256;
/// Buckets in the address filter. Sized so that arming every candidate for a
/// question still leaves the filter sparse: with ~160 tracepoints, 4096 buckets
/// reject about 96% of in-range addresses before any search happens.
///
/// The capacity above was 64 while the armed set was nine symbol fragments.
/// The full graphics boundary surface is thirty-three, and four candidates per
/// fragment is what covers a virtual and its backend overrides — so a set that
/// silently stopped arming at 64 would have reported NEVER ENTERED for
/// whatever happened to sort last, which is exactly the failure the whole
/// module exists to prevent.
pub const filter_buckets: usize = 4096;
const filter_words: usize = filter_buckets / 64;

/// A tracepoint armed for a question the graphics boundary contract does not
/// cover. Kept out of the contract's index space so `boundaryEntered` cannot
/// accidentally answer for one.
pub const unbound_boundary: u8 = 0xFF;

/// Boundary ids are contract enum indices, so one slot per possible id.
pub const boundary_slots: usize = 255;

// Entry de-duplication needs no timing constant. An earlier version used a
// 256-step window, which is fragile in both directions: an export shim that
// does real work between two armed addresses exceeds it and splits one call in
// two, while a tight loop under it merges two calls into one. The epoch rule
// below is exact for any call duration.

/// What a traced boundary means, so a hit report can say why it was watched.
/// The categories are the frontier the graphics investigation is walking.
pub const Role = enum(u8) {
    /// Entry into the authentic guest VdSwap export path. This proves the call
    /// path was entered, but deliberately does not claim the guest published
    /// an XE_SWAP packet. Host diagnostic work must never satisfy this role.
    swap,
    /// Entry into the kernel video ring setup path. This is deliberately
    /// separate from ring publication: allocating/configuring a ring and
    /// advancing its write pointer are different state transitions.
    ring_setup,
    /// Ring publication by the kernel video path. This role is reserved for a
    /// true producer/publish entry, not VdInitializeRingBuffer setup.
    ring_publication,
    /// Command-processor packet execution.
    command_processor,
    /// A swap that has reached a command processor. This can be reached by an
    /// authentic guest packet or by an explicitly-labelled host diagnostic.
    command_swap,
    /// Entry into the PM4_XE_SWAP decoder. A diagnostic ring injection reaches
    /// this same function, so this role proves decoding, not guest provenance.
    xe_swap_decode,
    /// A host-only swap probe. Entering this proves the host presentation path
    /// without claiming that the guest produced a frame boundary.
    diagnostic_swap,
    /// The presenter's own frame path inside the emulator.
    presenter,
    /// Anything else armed for a specific question.
    other,

    pub fn label(self: Role) []const u8 {
        return switch (self) {
            .swap => "guest VdSwap call",
            .ring_setup => "ring setup",
            .ring_publication => "ring publication",
            .command_processor => "command processor",
            .command_swap => "command-processor swap",
            .xe_swap_decode => "PM4_XE_SWAP decoder",
            .diagnostic_swap => "host diagnostic swap",
            .presenter => "emulator presenter",
            .other => "observation",
        };
    }

    /// The role that must execute before this one can. Ordering is the ABI's,
    /// not a preference: a title publishes a ring before the command processor
    /// has anything to consume, and consumes packets before a swap can name a
    /// finished frame.
    ///
    /// This exists so a zero can be read correctly. A role whose predecessor
    /// also never ran has not been skipped — the run has not arrived at it, and
    /// reporting it as "never entered" points the next investigation at the
    /// wrong end of the pipeline.
    pub fn predecessor(self: Role) ?Role {
        return switch (self) {
            .ring_setup => null,
            .ring_publication => .ring_setup,
            // There is no universal command-processor entry that proves the
            // guest advanced its write pointer. Ring setup is therefore the
            // reachability predecessor; publication itself remains an
            // independent measured effect in the substantiation contract.
            .command_processor => .ring_setup,
            .swap => .command_processor,
            .command_swap => .command_processor,
            .xe_swap_decode => .command_processor,
            .diagnostic_swap => null,
            .presenter => .command_swap,
            .other => null,
        };
    }
};

/// What a zero hit count licenses a reader to conclude.
pub const Verdict = enum {
    not_watched,
    entered,
    entered_but_not_recorded,
    not_yet_reached,
    never_entered,

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .not_watched => "NOT WATCHED: no tracepoint was armed for this role, so a zero count says nothing about whether it executed. Resolve the symbol first",
            .entered => "ENTERED: the instruction pointer reached this function, so its absence from any log is a logging question, not an execution one",
            .entered_but_not_recorded => "ENTERED BUT NOT RECORDED: the instruction pointer reached this function and the subsystem that owns it produced no record of the work. The execution happened; the accounting for it did not, so every downstream counter reading zero is measuring the gap and not the guest",
            .not_yet_reached => "NOT YET REACHED: armed, unentered, and the role that must precede it is also unentered. The run has not arrived here yet, so this zero is a consequence of the earlier gap and names nothing on its own — read the predecessor's verdict instead",
            .never_entered => "NEVER ENTERED: a tracepoint was armed at the resolved address, the role that must precede it did execute, and the instruction pointer still never reached it. This is an execution fact, not a missing log line",
        };
    }
};

pub const Tracepoint = struct {
    address: u64 = 0,
    role: Role = .other,
    /// Symbol name, borrowed. The metadata that resolved it outlives the run.
    name: []const u8 = "",
    hits: u64 = 0,
    first_step: u64 = 0,
    first_thread: u64 = 0,
    first_caller: u64 = 0,
    last_step: u64 = 0,
    last_thread: u64 = 0,
    /// Which entry of this address's boundary last crossed it.
    ///
    /// A call enters an export through a chain — trampoline, shim,
    /// implementation — and crosses each armed address at most once. Seeing an
    /// address twice in the same entry therefore means a *new* call began, and
    /// that is an exact signal with no timing constant in it.
    entry_epoch: u64 = 0,
    /// Records the owning subsystem produced for this boundary — ring writes,
    /// consumed packets, presented frames. Left at zero by subsystems that do
    /// not report one, which is why `records_expected` gates the comparison
    /// rather than the count alone.
    records: u64 = 0,
    /// Whether the owning subsystem promises to call `record`. Only then does
    /// `hits > 0 and records == 0` mean anything.
    records_expected: bool = false,
    /// Which boundary of the graphics bring-up contract this address stands
    /// for, as the contract's own enum index, or `unbound_boundary`.
    ///
    /// `role` is a nine-value vocabulary that predates the contract and stays
    /// as it is because a dozen call sites read it. It is too coarse to answer
    /// "did the title register an interrupt callback" — that question and "did
    /// it initialise the ring" are both `ring_setup`. Carrying the contract
    /// index alongside keeps both readings exact without a flag day.
    boundary: u8 = unbound_boundary,

    pub fn entered(self: *const Tracepoint) bool {
        return self.hits != 0;
    }
};

pub const Set = struct {
    entries: [max_tracepoints]Tracepoint = [_]Tracepoint{.{}} ** max_tracepoints,
    count: usize = 0,
    /// The range gate. `low > high` when empty, so the emptiness check and the
    /// range check are the same comparison and a disarmed set costs nothing.
    low: u64 = std.math.maxInt(u64),
    high: u64 = 0,
    /// A sparse filter over the armed addresses. The range gate alone is not
    /// enough: Xenia's text segment spans megabytes, so most executing
    /// addresses fall *between* the lowest and highest tracepoint and would
    /// each pay for a binary search. One multiply and a bit test rejects them.
    bucket_mask: [filter_words]u64 = [_]u64{0} ** filter_words,
    sealed: bool = false,
    /// Addresses offered that did not resolve to a symbol. Worth reporting:
    /// a tracepoint that was never armed reads exactly like one that was armed
    /// and never hit.
    unresolved: u32 = 0,
    /// Distinct entries per contract boundary, de-duplicated across the
    /// several addresses one boundary is armed on.
    ///
    /// A boundary is armed on an ordinal trampoline, an export shim and the
    /// implementation; one guest call crosses however many lie on its path.
    /// Summing the per-address hits counted the path length, which is how
    /// `VdInitializeEngines` reported 2 against the emulator's breadcrumb of 1
    /// and stopped the 2026-09-05 run on a contested claim where both
    /// observers were correct.
    boundary_entries: [boundary_slots]u64 = [_]u64{0} ** boundary_slots,
    /// The identifier of the entry currently in progress for each boundary.
    /// Compared against each address's `entry_epoch` to tell "another address
    /// on the same call" from "this address again, so a new call".
    boundary_epoch: [boundary_slots]u64 = [_]u64{0} ** boundary_slots,
    boundary_entry_thread: [boundary_slots]u64 = [_]u64{0} ** boundary_slots,
    probes: u64 = 0,
    gate_rejections: u64 = 0,

    /// Arm a tracepoint. Duplicate addresses collapse — several symbol names
    /// commonly resolve to one address after inlining, and counting one entry
    /// twice would overstate how much is being watched.
    pub fn arm(self: *Set, name: []const u8, address: u64, role: Role) bool {
        return self.armBoundary(name, address, role, unbound_boundary);
    }

    /// Arm a tracepoint that also stands for one boundary of the graphics
    /// contract. A duplicate address still collapses, but the surviving entry
    /// adopts the contract boundary when it had none: inlining routinely maps
    /// a shim and its trampoline onto one address, and losing the boundary tag
    /// because the coarse role was armed first would leave the gate reporting
    /// UNWATCHED for something it was in fact watching.
    pub fn armBoundary(self: *Set, name: []const u8, address: u64, role: Role, boundary: u8) bool {
        if (self.sealed or address == 0 or self.count >= max_tracepoints) {
            if (address == 0) self.unresolved +|= 1;
            return false;
        }
        for (self.entries[0..self.count]) |*existing| {
            if (existing.address != address) continue;
            if (existing.boundary == unbound_boundary) existing.boundary = boundary;
            return false;
        }
        self.entries[self.count] = .{
            .address = address,
            .role = role,
            .name = name,
            .boundary = boundary,
        };
        self.count += 1;
        return true;
    }

    /// Whether the set is full. Reported rather than discovered: an arm that
    /// silently fails produces a zero indistinguishable from never executing.
    pub fn saturated(self: *const Set) bool {
        return self.count >= max_tracepoints;
    }

    pub fn noteUnresolved(self: *Set) void {
        self.unresolved +|= 1;
    }

    /// Sort and compute the gate. Must be called before `match`: an unsealed
    /// set deliberately matches nothing, so a caller that forgets gets silence
    /// rather than a binary search over unsorted entries.
    pub fn seal(self: *Set) void {
        const entries = self.entries[0..self.count];
        std.mem.sort(Tracepoint, entries, {}, struct {
            fn lessThan(_: void, a: Tracepoint, b: Tracepoint) bool {
                return a.address < b.address;
            }
        }.lessThan);
        if (self.count == 0) {
            self.low = std.math.maxInt(u64);
            self.high = 0;
        } else {
            self.low = entries[0].address;
            self.high = entries[self.count - 1].address;
        }
        self.bucket_mask = [_]u64{0} ** filter_words;
        for (entries) |entry| {
            const bucket = bucketOf(entry.address);
            self.bucket_mask[bucket / 64] |= @as(u64, 1) << @truncate(bucket % 64);
        }
        self.sealed = true;
    }

    /// The hot path: two comparisons and a bit test. A false positive costs a
    /// binary search that finds nothing, which is correct and rare; a false
    /// negative is impossible, because every armed address sets its own bit.
    pub fn mightMatch(self: *const Set, address: u64) bool {
        if (address < self.low or address > self.high) return false;
        const bucket = bucketOf(address);
        return (self.bucket_mask[bucket / 64] >> @truncate(bucket % 64)) & 1 != 0;
    }

    /// Full lookup, only worth calling when `mightMatch` passed.
    pub fn find(self: *Set, address: u64) ?*Tracepoint {
        if (!self.sealed or !self.mightMatch(address)) return null;
        var lower: usize = 0;
        var upper: usize = self.count;
        while (lower < upper) {
            const middle = lower + (upper - lower) / 2;
            const candidate = self.entries[middle].address;
            if (candidate == address) return &self.entries[middle];
            if (candidate < address) lower = middle + 1 else upper = middle;
        }
        return null;
    }

    /// Record a hit. Returns the tracepoint when this is the first time it has
    /// been entered, because the first entry is the interesting event and
    /// every subsequent one is a frame rate.
    pub fn observe(self: *Set, address: u64, step: u64, thread: u64, caller: u64) ?*Tracepoint {
        self.probes +|= 1;
        if (!self.mightMatch(address)) {
            self.gate_rejections +|= 1;
            return null;
        }
        const entry = self.find(address) orelse return null;
        const first = entry.hits == 0;
        entry.hits +|= 1;
        entry.last_step = step;
        entry.last_thread = thread;
        self.noteBoundaryEntry(entry, thread);
        if (first) {
            entry.first_step = step;
            entry.first_thread = thread;
            entry.first_caller = caller;
            return entry;
        }
        return null;
    }

    pub fn byRole(self: *const Set, role: Role) ?*const Tracepoint {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.role == role) return entry;
        }
        return null;
    }

    /// Whether any tracepoint with this role was entered. The distinction that
    /// matters: `false` here with `count > 0` means genuinely not executed,
    /// while `count == 0` means nothing was watching.
    pub fn roleEntered(self: *const Set, role: Role) bool {
        for (self.entries[0..self.count]) |entry| {
            if (entry.role == role and entry.entered()) return true;
        }
        return false;
    }

    /// Whether any address armed for this contract boundary was entered.
    pub fn boundaryEntered(self: *const Set, boundary: u8) bool {
        if (boundary == unbound_boundary) return false;
        for (self.entries[0..self.count]) |entry| {
            if (entry.boundary == boundary and entry.entered()) return true;
        }
        return false;
    }

    /// Whether anything at all is watching this contract boundary. The
    /// distinction this module exists for: `false` here makes every downstream
    /// zero Rosette's rather than the title's.
    pub fn boundaryArmed(self: *const Set, boundary: u8) bool {
        if (boundary == unbound_boundary) return false;
        for (self.entries[0..self.count]) |entry| {
            if (entry.boundary == boundary) return true;
        }
        return false;
    }

    /// The earliest crossing recorded for a contract boundary, with the thread
    /// and caller that made it. Several addresses can stand for one boundary —
    /// a shim, its trampoline, a backend override — and the first of them to
    /// execute is the crossing.
    pub fn boundaryFirst(self: *const Set, boundary: u8) ?*const Tracepoint {
        if (boundary == unbound_boundary) return null;
        var earliest: ?*const Tracepoint = null;
        for (self.entries[0..self.count]) |*entry| {
            if (entry.boundary != boundary or !entry.entered()) continue;
            if (earliest) |held| {
                if (entry.first_step >= held.first_step) continue;
            }
            earliest = entry;
        }
        return earliest;
    }

    /// Count a crossing as a new entry unless it belongs to a call already
    /// counted.
    ///
    /// A call enters an export through a chain of armed addresses and crosses
    /// each at most once, so a *repeat* of an address that has already been
    /// crossed in the current entry is the start of the next call. A different
    /// thread is always a different call: two threads cannot share a frame.
    ///
    /// Exact regardless of how long a call takes or how far apart two calls
    /// are, which a step window could never be.
    fn noteBoundaryEntry(self: *Set, entry: *Tracepoint, thread: u64) void {
        const boundary = entry.boundary;
        if (boundary == unbound_boundary or boundary >= boundary_slots) return;
        const index: usize = boundary;
        const started = self.boundary_entries[index] != 0;
        const repeat_address = started and entry.entry_epoch == self.boundary_epoch[index];
        const other_thread = started and self.boundary_entry_thread[index] != thread;
        if (!started or repeat_address or other_thread) {
            self.boundary_entries[index] +|= 1;
            self.boundary_epoch[index] +|= 1;
            self.boundary_entry_thread[index] = thread;
        }
        entry.entry_epoch = self.boundary_epoch[index];
    }

    /// Entries into a contract boundary, across every address armed for it.
    ///
    /// The **maximum** across the boundary's addresses, not the sum. One
    /// boundary routinely has several armed addresses — an ordinal trampoline,
    /// an export shim, the implementation — and a single guest call crosses
    /// however many of them lie on its path. Each address is crossed at most
    /// once per call, so the largest per-address count is the number of calls
    /// and the sum is that number multiplied by the path length.
    ///
    /// Summing is what made `VdInitializeEngines` read 2 against the emulator's
    /// own breadcrumb of 1 on 2026-09-05, and stopped the run on a contested
    /// claim where both observers were behaving correctly. It also inflated
    /// every pump reading built on this number: `MarkVblank` and
    /// `DispatchInterruptCallback` each have four armed addresses, so a report
    /// of 147 vblanks and 113 dispatches was counting path crossings and
    /// calling them events.
    ///
    /// `boundaryCrossings` below keeps the old total for the questions that
    /// genuinely want it.
    pub fn boundaryHits(self: *const Set, boundary: u8) u64 {
        if (boundary == unbound_boundary or boundary >= boundary_slots) return 0;
        return self.boundary_entries[boundary];
    }

    /// Total crossings summed over every armed address for a boundary.
    ///
    /// Not an entry count. Useful only for questions about the tracepoints
    /// themselves — how much of the armed surface is live, whether an address
    /// was armed and never reached — and never for "how many times did this
    /// happen".
    pub fn boundaryCrossings(self: *const Set, boundary: u8) u64 {
        if (boundary == unbound_boundary) return 0;
        var total: u64 = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.boundary == boundary) total +|= entry.hits;
        }
        return total;
    }

    /// Armed addresses for a boundary, and how many of them were ever reached.
    ///
    /// The pair is what distinguishes "armed on the right address" from "armed
    /// on six and reached two". A boundary whose reached count is zero while
    /// its armed count is high is an observer hole wearing the costume of a
    /// guest that never called.
    pub fn boundaryAddressCoverage(self: *const Set, boundary: u8) struct { armed: u32, reached: u32 } {
        if (boundary == unbound_boundary) return .{ .armed = 0, .reached = 0 };
        var armed: u32 = 0;
        var reached: u32 = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.boundary != boundary) continue;
            armed += 1;
            if (entry.hits != 0) reached += 1;
        }
        return .{ .armed = armed, .reached = reached };
    }

    /// The most recent step at which any address for this boundary executed.
    /// A pump that ran and stopped is a different finding from one that never
    /// ran, and only the last step separates them.
    pub fn boundaryLastStep(self: *const Set, boundary: u8) u64 {
        if (boundary == unbound_boundary) return 0;
        var latest: u64 = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.boundary != boundary or !entry.entered()) continue;
            if (entry.last_step > latest) latest = entry.last_step;
        }
        return latest;
    }

    /// How many addresses are armed for this boundary. Reported so a reader can
    /// tell "one shim watched" from "a shim, a trampoline and two backend
    /// overrides watched", which changes how much a zero is worth.
    pub fn boundaryWatchers(self: *const Set, boundary: u8) u32 {
        if (boundary == unbound_boundary) return 0;
        var total: u32 = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.boundary == boundary) total += 1;
        }
        return total;
    }

    pub fn roleArmed(self: *const Set, role: Role) bool {
        for (self.entries[0..self.count]) |entry| {
            if (entry.role == role) return true;
        }
        return false;
    }

    /// Whether the subsystem owning this role promised records and produced
    /// none despite the boundary executing.
    pub fn roleEnteredWithoutRecords(self: *const Set, role: Role) bool {
        var expected = false;
        var records: u64 = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.role != role) continue;
            if (entry.records_expected) expected = true;
            records +|= entry.records;
        }
        return expected and records == 0;
    }

    /// Attribute a record to whichever tracepoint owns `address`, so the
    /// "executed but produced nothing" case can be told from "never executed".
    pub fn record(self: *Set, address: u64) void {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.address != address) continue;
            entry.records +|= 1;
            entry.records_expected = true;
            return;
        }
    }

    /// Declare that this role's owner will report records, so a later zero is
    /// readable as a gap rather than as silence.
    pub fn expectRecords(self: *Set, role: Role) void {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.role == role) entry.records_expected = true;
        }
    }

    /// What a zero hit count for this role actually licenses a reader to
    /// conclude. This is the sentence three passes of this investigation
    /// needed and did not have.
    pub fn classify(self: *const Set, role: Role) Verdict {
        if (!self.roleArmed(role)) return .not_watched;
        if (self.roleEntered(role)) {
            return if (self.roleEnteredWithoutRecords(role)) .entered_but_not_recorded else .entered;
        }
        // A predecessor that never ran means this role was never eligible. Only
        // when the predecessor did run is a zero here a fact about *this*
        // boundary — that is the difference between naming the frontier and
        // naming everything downstream of it.
        if (role.predecessor()) |earlier| {
            if (self.roleArmed(earlier) and !self.roleEntered(earlier)) return .not_yet_reached;
        }
        return .never_entered;
    }

    pub fn verdict(self: *const Set, role: Role) []const u8 {
        return self.classify(role).describe();
    }
};

/// Top bits of a multiplicative hash: cheap, and it spreads aligned function
/// entry addresses that would collide under a plain shift-and-mask.
fn bucketOf(address: u64) usize {
    const mixed = (address *% 0x9E37_79B9_7F4A_7C15) >> 54;
    return @intCast(mixed % filter_buckets);
}

test "an empty set matches nothing and costs one comparison" {
    var set = Set{};
    set.seal();
    try std.testing.expect(!set.mightMatch(0));
    try std.testing.expect(!set.mightMatch(0x4000));
    try std.testing.expect(!set.mightMatch(std.math.maxInt(u64)));
}

// The hot path is the whole design constraint: nine million steps a second
// must not pay for a search.
test "addresses outside the range are rejected by the gate alone" {
    var set = Set{};
    _ = set.arm("mid", 0x5000, .swap);
    _ = set.arm("high", 0x9000, .ring_publication);
    set.seal();

    try std.testing.expect(!set.mightMatch(0x4FFF));
    try std.testing.expect(!set.mightMatch(0x9001));
    try std.testing.expect(set.mightMatch(0x5000));
    // An address inside the range that no tracepoint claims is normally
    // rejected by the bucket filter, and when it collides the search still
    // finds nothing. Both outcomes are correct.
    try std.testing.expect(set.find(0x7000) == null);

    _ = set.observe(0x100, 1, 1, 0);
    try std.testing.expectEqual(@as(u64, 1), set.gate_rejections);
}

test "entries are found regardless of the order they were armed in" {
    var set = Set{};
    _ = set.arm("c", 0x9000, .other);
    _ = set.arm("a", 0x1000, .swap);
    _ = set.arm("b", 0x5000, .ring_publication);
    set.seal();
    try std.testing.expect(set.find(0x1000) != null);
    try std.testing.expect(set.find(0x5000) != null);
    try std.testing.expect(set.find(0x9000) != null);
    try std.testing.expectEqualStrings("a", set.find(0x1000).?.name);
}

// Inlining commonly maps several names onto one address, and counting that
// twice would overstate how much is being watched.
test "a duplicate address is armed once" {
    var set = Set{};
    try std.testing.expect(set.arm("first", 0x2000, .swap));
    try std.testing.expect(!set.arm("alias", 0x2000, .other));
    try std.testing.expectEqual(@as(usize, 1), set.count);
}

test "an unresolved symbol is counted rather than silently skipped" {
    var set = Set{};
    try std.testing.expect(!set.arm("missing", 0, .swap));
    try std.testing.expectEqual(@as(u32, 1), set.unresolved);
    try std.testing.expectEqual(@as(usize, 0), set.count);
}

// An unsealed set matching nothing is deliberate: silence beats a binary
// search over unsorted entries returning wrong answers.
test "an unsealed set matches nothing" {
    var set = Set{};
    _ = set.arm("a", 0x1000, .swap);
    try std.testing.expect(set.find(0x1000) == null);
    set.seal();
    try std.testing.expect(set.find(0x1000) != null);
}

test "the first entry is reported and later ones are only counted" {
    var set = Set{};
    _ = set.arm("VdSwap", 0x8000, .swap);
    set.seal();

    const first = set.observe(0x8000, 1000, 0x7fff2000, 0x4400).?;
    try std.testing.expectEqual(@as(u64, 1000), first.first_step);
    try std.testing.expectEqual(@as(u64, 0x7fff2000), first.first_thread);
    try std.testing.expectEqual(@as(u64, 0x4400), first.first_caller);

    try std.testing.expect(set.observe(0x8000, 2000, 0x7fff2000, 0x4400) == null);
    try std.testing.expectEqual(@as(u64, 2), set.byRole(.swap).?.hits);
    try std.testing.expectEqual(@as(u64, 2000), set.byRole(.swap).?.last_step);
}

// The distinction three passes of this investigation lacked: not-watched,
// watched-and-never-entered, and entered are three different findings.
test "an unwatched role is distinguished from one that never executed" {
    var nothing_armed = Set{};
    nothing_armed.seal();
    try std.testing.expect(std.mem.indexOf(u8, nothing_armed.verdict(.swap), "NOT WATCHED") != null);

    var armed = Set{};
    _ = armed.arm("VdSwap", 0x8000, .swap);
    armed.seal();
    try std.testing.expect(std.mem.indexOf(u8, armed.verdict(.swap), "NEVER ENTERED") != null);
    try std.testing.expect(std.mem.indexOf(u8, armed.verdict(.swap), "not a missing log line") != null);

    _ = armed.observe(0x8000, 1, 1, 0);
    try std.testing.expect(std.mem.indexOf(u8, armed.verdict(.swap), "ENTERED") != null);
    try std.testing.expect(std.mem.indexOf(u8, armed.verdict(.swap), "logging question") != null);
}

// The whole pipeline reads zero when the *first* stage never ran. Saying
// "NEVER ENTERED" four times names four frontiers, and there is only one.
test "a downstream zero is not a finding while its predecessor is also zero" {
    var set = Set{};
    _ = set.arm("VdInitializeRingBuffer", 0x1000, .ring_setup);
    _ = set.arm("ExecutePrimaryBuffer", 0x2000, .command_processor);
    _ = set.arm("VdSwap", 0x3000, .swap);
    set.seal();

    // Nothing has run: only the head of the pipeline is a real finding.
    try std.testing.expectEqual(Verdict.never_entered, set.classify(.ring_setup));
    try std.testing.expectEqual(Verdict.not_yet_reached, set.classify(.command_processor));
    try std.testing.expectEqual(Verdict.not_yet_reached, set.classify(.swap));

    // Once ring setup is entered, the command processor's zero becomes its
    // own finding, and the frontier moves one stage down. Setup is not
    // publication, so the publication boundary remains independently
    // unsubstantiated until a producer effect is observed.
    _ = set.observe(0x1000, 10, 1, 0);
    try std.testing.expectEqual(Verdict.entered, set.classify(.ring_setup));
    try std.testing.expectEqual(Verdict.never_entered, set.classify(.command_processor));
    try std.testing.expectEqual(Verdict.not_yet_reached, set.classify(.swap));
}

// An unarmed predecessor cannot license "not yet reached": nothing was
// watching it, so it may well have run.
test "an unwatched predecessor leaves the downstream zero a finding" {
    var set = Set{};
    _ = set.arm("ExecutePrimaryBuffer", 0x2000, .command_processor);
    set.seal();
    try std.testing.expectEqual(Verdict.not_watched, set.classify(.ring_publication));
    try std.testing.expectEqual(Verdict.never_entered, set.classify(.command_processor));
}

test "a boundary that executed and recorded nothing is its own verdict" {
    var set = Set{};
    _ = set.arm("VdInitializeRingBuffer", 0x1000, .ring_publication);
    set.seal();
    set.expectRecords(.ring_publication);

    _ = set.observe(0x1000, 10, 1, 0);
    // Executed, and the subsystem that owns it produced nothing. That is a
    // different problem from never executing, and pointed a whole pass of this
    // investigation at the guest when the gap was in the accounting.
    try std.testing.expectEqual(Verdict.entered_but_not_recorded, set.classify(.ring_publication));

    set.record(0x1000);
    try std.testing.expectEqual(Verdict.entered, set.classify(.ring_publication));
}

// Without a promise of records, zero records is silence and must not be read
// as a gap.
test "a subsystem that never promised records is not accused of losing them" {
    var set = Set{};
    _ = set.arm("VdSwap", 0x3000, .swap);
    set.seal();
    _ = set.observe(0x3000, 10, 1, 0);
    try std.testing.expectEqual(Verdict.entered, set.classify(.swap));
}

test "roles report armed and entered independently" {
    var set = Set{};
    _ = set.arm("VdSwap", 0x8000, .swap);
    set.seal();
    try std.testing.expect(set.roleArmed(.swap));
    try std.testing.expect(!set.roleEntered(.swap));
    try std.testing.expect(!set.roleArmed(.presenter));
}

test "diagnostic and command swaps do not satisfy authentic guest swap" {
    var set = Set{};
    _ = set.arm("ExecutePrimaryBuffer", 0x1000, .command_processor);
    _ = set.arm("DebugIssueSwapFromHost", 0x2000, .diagnostic_swap);
    _ = set.arm("VulkanCommandProcessor::IssueSwap", 0x3000, .command_swap);
    _ = set.arm("VdSwap", 0x4000, .swap);
    set.seal();

    _ = set.observe(0x1000, 1, 1, 0);
    _ = set.observe(0x2000, 2, 1, 0);
    _ = set.observe(0x3000, 3, 1, 0);

    try std.testing.expect(set.roleEntered(.diagnostic_swap));
    try std.testing.expect(set.roleEntered(.command_swap));
    try std.testing.expect(!set.roleEntered(.swap));
    try std.testing.expectEqual(Verdict.never_entered, set.classify(.swap));
}

test "XE swap decode does not imply authentic guest provenance" {
    var set = Set{};
    _ = set.arm("ExecutePacketType3_XE_SWAP", 0x2800, .xe_swap_decode);
    _ = set.arm("DebugIssueSwapFromHost", 0x2000, .diagnostic_swap);
    set.seal();

    _ = set.observe(0x2000, 10, 1, 0);
    _ = set.observe(0x2800, 11, 1, 0);
    try std.testing.expect(set.roleEntered(.diagnostic_swap));
    try std.testing.expect(set.roleEntered(.xe_swap_decode));
    try std.testing.expect(!set.roleEntered(.swap));
}

test "the set refuses to overflow" {
    var set = Set{};
    var index: usize = 0;
    while (index < max_tracepoints + 8) : (index += 1) {
        _ = set.arm("x", 0x1000 + index * 0x10, .other);
    }
    try std.testing.expectEqual(max_tracepoints, set.count);
    set.seal();
    try std.testing.expect(set.find(0x1000) != null);
}

// A false negative would silently disarm a tracepoint; a false positive only
// costs a fruitless search.
test "every armed address passes its own filter" {
    var set = Set{};
    var index: usize = 0;
    while (index < max_tracepoints) : (index += 1) {
        _ = set.arm("x", 0x1_0000 + index * 0x137, .other);
    }
    set.seal();
    for (set.entries[0..set.count]) |entry| {
        try std.testing.expect(set.mightMatch(entry.address));
        try std.testing.expect(set.find(entry.address) != null);
    }
}

// The filter must actually reject: without it every in-range address pays for
// a binary search on every interpreted step.
test "the filter rejects most in-range addresses that are not tracepoints" {
    var set = Set{};
    _ = set.arm("low", 0x10_0000, .swap);
    _ = set.arm("high", 0x90_0000, .presenter);
    set.seal();

    var rejected: usize = 0;
    var probe: u64 = 0x10_0000;
    while (probe < 0x90_0000) : (probe += 0x40) {
        if (!set.mightMatch(probe)) rejected += 1;
    }
    // Two buckets of a thousand are live, so all but a fraction of a percent
    // of in-range probes must never reach the search.
    try std.testing.expect(rejected > 33000);
}

test "every role explains itself" {
    inline for (@typeInfo(Role).@"enum".fields) |field| {
        const role: Role = @enumFromInt(field.value);
        try std.testing.expect(role.label().len > 0);
    }
}

test "ring setup is distinct from ring publication" {
    try std.testing.expectEqualStrings("ring setup", Role.ring_setup.label());
    try std.testing.expectEqual(Role.ring_setup, Role.ring_publication.predecessor().?);
}

test "a contract boundary is answered from its earliest crossing" {
    var set = Set{};
    try std.testing.expect(set.armBoundary("shim", 0x1000, .ring_setup, 7));
    try std.testing.expect(set.armBoundary("trampoline", 0x2000, .ring_setup, 7));
    set.seal();
    try std.testing.expect(set.boundaryArmed(7));
    try std.testing.expect(!set.boundaryEntered(7));

    _ = set.observe(0x2000, 900, 0xaa, 0);
    _ = set.observe(0x1000, 400, 0xbb, 0);
    try std.testing.expect(set.boundaryEntered(7));
    try std.testing.expectEqual(@as(u64, 400), set.boundaryFirst(7).?.first_step);
    try std.testing.expectEqual(@as(u64, 2), set.boundaryHits(7));
    try std.testing.expectEqual(@as(u32, 2), set.boundaryWatchers(7));
    try std.testing.expectEqual(@as(u64, 900), set.boundaryLastStep(7));
}

// An unwatched boundary must never answer, or "Rosette did not look" becomes
// indistinguishable from "the title did not do it" all over again.
test "an unbound boundary answers nothing" {
    var set = Set{};
    _ = set.arm("plain", 0x1000, .swap);
    set.seal();
    _ = set.observe(0x1000, 1, 0, 0);
    try std.testing.expect(!set.boundaryArmed(unbound_boundary));
    try std.testing.expect(!set.boundaryEntered(unbound_boundary));
    try std.testing.expect(!set.boundaryArmed(3));
    try std.testing.expect(set.boundaryFirst(3) == null);
}

// Inlining maps a shim and its trampoline onto one address often enough that
// losing the contract tag to whichever was armed first would leave the gate
// blind to a boundary it was watching.
test "a collapsed duplicate adopts the contract boundary" {
    var set = Set{};
    try std.testing.expect(set.arm("role-only", 0x3000, .ring_setup));
    try std.testing.expect(!set.armBoundary("with-boundary", 0x3000, .ring_setup, 12));
    try std.testing.expectEqual(@as(usize, 1), set.count);
    try std.testing.expect(set.boundaryArmed(12));
}

// 2026-09-05. `VdInitializeEngines` is armed on three addresses; one guest call
// crossed two of them and the summed count read 2 against the emulator's own
// breadcrumb of 1. The run stopped on a contested claim in which both observers
// were behaving correctly and only the arithmetic was wrong.
test "one call across several armed addresses is one entry" {
    var set = Set{};
    const boundary: u8 = 3;
    // Three addresses armed for one boundary, as the run arms them.
    _ = set.armBoundary("a", 0x875090, .other, boundary);
    _ = set.armBoundary("b", 0x8754a0, .other, boundary);
    _ = set.armBoundary("c", 0x87f2b0, .other, boundary);

    const coverage_before = set.boundaryAddressCoverage(boundary);
    try std.testing.expectEqual(@as(u32, 3), coverage_before.armed);
    try std.testing.expectEqual(@as(u32, 0), coverage_before.reached);
    try std.testing.expectEqual(@as(u64, 0), set.boundaryHits(boundary));

    set.seal();
    // One guest call whose path crosses two of the three.
    _ = set.observe(0x875090, 10, 1, 0);
    _ = set.observe(0x8754a0, 12, 1, 0);
    try std.testing.expectEqual(@as(u64, 1), set.boundaryHits(boundary));
    // The sum is still available, and is still 2 — it just is not an entry count.
    try std.testing.expectEqual(@as(u64, 2), set.boundaryCrossings(boundary));

    const coverage = set.boundaryAddressCoverage(boundary);
    try std.testing.expectEqual(@as(u32, 3), coverage.armed);
    try std.testing.expectEqual(@as(u32, 2), coverage.reached);

    // A second call advances by exactly one, however far away it is.
    _ = set.observe(0x875090, 100_000, 1, 0);
    _ = set.observe(0x8754a0, 100_002, 1, 0);
    try std.testing.expectEqual(@as(u64, 2), set.boundaryHits(boundary));
    try std.testing.expectEqual(@as(u64, 4), set.boundaryCrossings(boundary));
}

// A boundary armed on many addresses and reached on none is an observer hole,
// not a guest that never called. The pair is what separates them.
test "address coverage separates an observer hole from a silent guest" {
    var set = Set{};
    const boundary: u8 = 7;
    _ = set.armBoundary("x", 0x1000, .other, boundary);
    _ = set.armBoundary("y", 0x2000, .other, boundary);
    set.seal();
    const cold = set.boundaryAddressCoverage(boundary);
    try std.testing.expectEqual(@as(u32, 2), cold.armed);
    try std.testing.expectEqual(@as(u32, 0), cold.reached);

    _ = set.observe(0x2000, 5, 1, 0);
    const warm = set.boundaryAddressCoverage(boundary);
    try std.testing.expectEqual(@as(u32, 1), warm.reached);
    try std.testing.expectEqual(@as(u64, 1), set.boundaryHits(boundary));
}

// The step window this replaced would have split this call in two: a shim that
// does real work between its armed addresses can span far more than a few
// hundred guest steps, which is exactly what left `VdInitializeEngines`
// contested at 2 against the emulator's breadcrumb of 1.
test "a slow call chain is still one entry" {
    var set = Set{};
    const boundary: u8 = 11;
    _ = set.armBoundary("trampoline", 0x1000, .other, boundary);
    _ = set.armBoundary("shim", 0x2000, .other, boundary);
    _ = set.armBoundary("impl", 0x3000, .other, boundary);
    set.seal();

    // One call, its three addresses millions of steps apart.
    _ = set.observe(0x1000, 1, 7, 0);
    _ = set.observe(0x2000, 5_000_000, 7, 0);
    _ = set.observe(0x3000, 9_000_000, 7, 0);
    try std.testing.expectEqual(@as(u64, 1), set.boundaryHits(boundary));
    try std.testing.expectEqual(@as(u64, 3), set.boundaryCrossings(boundary));

    // The next call repeats the first address, which is what makes it next.
    _ = set.observe(0x1000, 9_000_010, 7, 0);
    try std.testing.expectEqual(@as(u64, 2), set.boundaryHits(boundary));
}

// Two calls back to back through a single address are two entries, however
// close together. A step window merged these.
test "rapid repeat calls through one address are counted separately" {
    var set = Set{};
    const boundary: u8 = 12;
    _ = set.armBoundary("only", 0x4000, .other, boundary);
    set.seal();
    _ = set.observe(0x4000, 100, 7, 0);
    _ = set.observe(0x4000, 101, 7, 0);
    _ = set.observe(0x4000, 102, 7, 0);
    try std.testing.expectEqual(@as(u64, 3), set.boundaryHits(boundary));
}

// Two threads cannot share a call frame, so interleaved crossings of the same
// address are separate entries even inside one epoch.
test "two threads entering one boundary are two entries" {
    var set = Set{};
    const boundary: u8 = 13;
    _ = set.armBoundary("a", 0x5000, .other, boundary);
    _ = set.armBoundary("b", 0x6000, .other, boundary);
    set.seal();
    _ = set.observe(0x5000, 10, 0xaa, 0);
    _ = set.observe(0x5000, 11, 0xbb, 0);
    try std.testing.expectEqual(@as(u64, 2), set.boundaryHits(boundary));
}
