//! One synchronisation object, one identity, however many address spaces name
//! it.
//!
//! The emulator logs the same object two ways in the same line:
//!
//! ```
//! KeWaitForSingleObject tid=6 obj_ptr=CFF706E4 guest_obj=827206E4 handle=F8000058
//! ```
//!
//! `obj_ptr` is the host pointer the emulator dereferences; `guest_obj` is the
//! console address the title knows. They are the same object. Every other line
//! in the run picks one or the other depending on which code path printed it,
//! and a reader that takes the address at face value ends up tracking two
//! objects that are really one.
//!
//! That is not cosmetic. Evidence is *split*: an object waited on ten thousand
//! times through one name and signalled through the other looks like two
//! objects with a hundred percent timeout rate and a hundred percent signal
//! rate respectively, and neither is a finding. A predictor keyed on
//! recurrence then reports "first sight" over and over for the same behaviour,
//! which is precisely the scatter of one-count entries a stalled run produces
//! and precisely the wrong signal.
//!
//! ## Learning rather than computing
//!
//! The mapping could be computed — host equals console plus the emulator's
//! mapping base — but the emulator states it directly, on the same line, for
//! free. Learning it from the statement is exact, needs no address-space model
//! to be ready, and survives whatever bias or aliasing the platform applies.
//! The computed form is kept as a fallback and marked as such, because a
//! derived answer and an observed one should never be reported as equally
//! certain.
//!
//! ## The canonical name is the console address
//!
//! The title's address is the one a reader can act on: it appears in the
//! title's own memory, it is stable across runs, and it is what every other
//! guest-side diagnostic uses. Host pointers move with the mapping base and
//! mean nothing outside one process.

const std = @import("std");

/// How an address was resolved to its canonical form. A derived answer and an
/// observed one must never be reported as equally certain.
pub const Provenance = enum(u8) {
    /// The address was already canonical, or nothing is known about it.
    unmapped,
    /// The emulator printed both names on one line; this is exact.
    observed_pair,
    /// Derived by subtracting the emulator's mapping base. Correct when the
    /// address really is in the primary view and wrong when it is not, so it
    /// is only used when no pair was observed.
    derived_from_mapping_base,

    pub fn label(self: Provenance) []const u8 {
        return switch (self) {
            .unmapped => "unmapped",
            .observed_pair => "observed_pair",
            .derived_from_mapping_base => "derived",
        };
    }

    pub fn exact(self: Provenance) bool {
        return self == .observed_pair;
    }
};

pub const Resolution = struct {
    /// The canonical (console) address.
    canonical: u64,
    provenance: Provenance,
    /// Whether the input differed from the canonical form, which is what says
    /// evidence would have been split without this.
    rewritten: bool,
};

/// Recover the console address from a host pointer the emulator printed.
///
/// The emulator formats these with an eight-digit hex specifier, so a 64-bit
/// host pointer arrives **truncated to its low 32 bits**. The observed run maps
/// console `0x827CEC14` to printed `0xD001EC14` against a mapping base of
/// `0x34D850000` — and `0x827CEC14 + 0x34D850000` is `0x3D001EC14`, whose low
/// word is exactly what was printed.
///
/// A subtraction of the full base therefore underflows and finds nothing, which
/// is why three host pointers stayed unresolved and kept their objects split.
/// The arithmetic has to happen in the width the value was printed in.
pub fn deriveConsoleAddress(host: u64, mapping_base: u64) ?u64 {
    if (host == 0 or mapping_base == 0) return null;
    if (host > 0xFFFF_FFFF) {
        // An untruncated pointer: plain subtraction is correct.
        if (host <= mapping_base) return null;
        const full = host - mapping_base;
        return if (plausibleConsoleAddress(full) and full <= 0xFFFF_FFFF) full else null;
    }
    const base_low: u32 = @truncate(mapping_base);
    const derived: u32 = @as(u32, @truncate(host)) -% base_low;
    return if (plausibleConsoleAddress(derived)) derived else null;
}

/// A console address a title could plausibly be using for a kernel object.
/// Objects live in the title's data and the kernel's heaps, both well above the
/// first megabyte, and always inside the 32-bit console space.
pub fn plausibleConsoleAddress(address: u64) bool {
    return address >= 0x0001_0000 and address <= 0xFFFF_FFFF;
}

pub const max_pairs = 32;

pub const HandleEntry = struct {
    handle: u32 = 0,
    console: u64 = 0,
};

pub const Pair = struct {
    host: u64 = 0,
    console: u64 = 0,
    sightings: u64 = 0,
};

pub const Table = struct {
    pairs: [max_pairs]Pair = [_]Pair{.{}} ** max_pairs,
    count: usize = 0,
    dropped: u64 = 0,
    /// Addresses rewritten to their canonical form. A non-zero count is the
    /// measure of how much evidence would otherwise have been split.
    rewrites: u64 = 0,
    /// Times a host and console address were observed to disagree about which
    /// console address a host pointer maps to. Should stay zero; a non-zero
    /// value means the mapping moved mid-run, which invalidates every earlier
    /// normalisation.
    conflicts: u64 = 0,
    /// The emulator's mapping base, when known. Used only as a fallback.
    mapping_base: u64 = 0,
    /// Object-pointer fields that arrived shorter than their format width, and
    /// were therefore refused. Non-zero means the emulator's logging is
    /// splicing lines under this runtime; each refusal is a phantom object that
    /// did *not* get its own recurrence counter.
    truncated_reads: u64 = 0,
    /// Stated pairs whose two halves came from different log writes, caught by
    /// disagreeing with the mapping-base derivation. A wrong pair is worse than
    /// no pair: it carries exact provenance and outranks the derivation that
    /// would have been right.
    spliced_pairs: u64 = 0,
    /// Handle-to-console mappings learned from untruncated header lines.
    handles: [max_pairs]HandleEntry = [_]HandleEntry{.{}} ** max_pairs,
    handle_count: usize = 0,

    fn find(self: *Table, host: u64) ?*Pair {
        for (self.pairs[0..self.count]) |*pair| {
            if (pair.host == host) return pair;
        }
        return null;
    }

    /// Learn from a line that named the object both ways — if the line is
    /// intact.
    ///
    /// This is the dangerous input. The emulator's logging is not line-atomic
    /// under this runtime, so a "pair" is frequently the `obj_ptr=` of one line
    /// beside the `guest_obj=` of another. Both halves are individually valid
    /// eight-digit fields, so nothing about their *shape* betrays the splice —
    /// and a wrong pair learned here is worse than no pair at all, because it
    /// is exact-provenance and outranks the derivation that would have been
    /// right.
    ///
    /// The mapping base gives an independent answer, so a stated pair is only
    /// accepted when the two agree. Observed splices from one run:
    /// `obj_ptr=8D854BF4 guest_obj=400CEC14` (derives to `40004BF4`) and
    /// `obj_ptr=D001EC38 guest_obj=40004BF4` (derives to `827CEC38`) — both
    /// would have poisoned the table.
    pub fn observePair(self: *Table, host: u64, console: u64) void {
        if (host == 0 or console == 0 or host == console) return;
        if (!plausibleConsoleAddress(console)) return;
        if (self.mapping_base != 0) {
            const derived = deriveConsoleAddress(host, self.mapping_base) orelse {
                self.spliced_pairs +|= 1;
                return;
            };
            if (derived != console) {
                self.spliced_pairs +|= 1;
                return;
            }
        }
        if (self.find(host)) |pair| {
            if (pair.console != console) self.conflicts +|= 1;
            pair.console = console;
            pair.sightings +|= 1;
            return;
        }
        if (self.count == max_pairs) {
            self.dropped +|= 1;
            return;
        }
        self.pairs[self.count] = .{ .host = host, .console = console, .sightings = 1 };
        self.count += 1;
    }

    /// Learn from a line that named a *full* host address and a handle.
    ///
    /// `StashHandle: header=0x38d854bf4, handle=F8000154` is an untruncated
    /// 64-bit address, so it cannot be confused with anything and does not
    /// depend on a second field surviving the same write. That makes it the
    /// most trustworthy channel available, and it carries the handle — which is
    /// the identity the title's own code uses and the one an operator can grep
    /// the title for.
    pub fn observeHandleHeader(self: *Table, host_full: u64, handle: u32) void {
        if (host_full == 0 or handle == 0 or self.mapping_base == 0) return;
        if (host_full <= self.mapping_base) return;
        const console = host_full - self.mapping_base;
        if (!plausibleConsoleAddress(console)) return;
        for (self.handles[0..self.handle_count]) |*entry| {
            if (entry.handle == handle) {
                entry.console = console;
                return;
            }
        }
        if (self.handle_count == max_pairs) {
            self.dropped +|= 1;
            return;
        }
        self.handles[self.handle_count] = .{ .handle = handle, .console = console };
        self.handle_count += 1;
    }

    /// The console object a handle names, when one was learned.
    pub fn consoleForHandle(self: *const Table, handle: u32) ?u64 {
        for (self.handles[0..self.handle_count]) |entry| {
            if (entry.handle == handle) return entry.console;
        }
        return null;
    }

    /// Learning the base retro-validates everything accepted without it.
    ///
    /// Pairs read before the base was discovered were accepted on the line's
    /// word alone, which is exactly the input that cannot be trusted. Dropping
    /// the ones that disagree is what stops an early splice from outliving the
    /// evidence that would have caught it.
    pub fn observeMappingBase(self: *Table, base: u64) void {
        if (base == 0 or base == self.mapping_base) return;
        self.mapping_base = base;
        var index: usize = 0;
        while (index < self.count) {
            const pair = self.pairs[index];
            const derived = deriveConsoleAddress(pair.host, base);
            if (derived != null and derived.? == pair.console) {
                index += 1;
                continue;
            }
            self.spliced_pairs +|= 1;
            self.pairs[index] = self.pairs[self.count - 1];
            self.count -= 1;
        }
    }

    /// Resolve an address to the name a reader can act on.
    pub fn resolve(self: *Table, address: u64) Resolution {
        if (address == 0) return .{ .canonical = 0, .provenance = .unmapped, .rewritten = false };
        // An address already in console space is canonical. Checking this first
        // means a console address is never "resolved" through a coincidental
        // host match.
        if (address <= 0xFFFF_FFFF) {
            for (self.pairs[0..self.count]) |pair| {
                if (pair.console == address) {
                    return .{ .canonical = address, .provenance = .observed_pair, .rewritten = false };
                }
            }
        }
        if (self.find(address)) |pair| {
            self.rewrites +|= 1;
            return .{ .canonical = pair.console, .provenance = .observed_pair, .rewritten = true };
        }
        if (self.mapping_base != 0) {
            if (deriveConsoleAddress(address, self.mapping_base)) |derived| {
                self.rewrites +|= 1;
                return .{
                    .canonical = derived,
                    .provenance = .derived_from_mapping_base,
                    .rewritten = true,
                };
            }
        }
        return .{ .canonical = address, .provenance = .unmapped, .rewritten = false };
    }

    pub fn verdict(self: *const Table) []const u8 {
        if (self.conflicts != 0)
            return "a host pointer resolved to two different console addresses during this run. The emulator's mapping moved, so every normalisation taken before the move named the wrong object and any evidence merged across it is unsound";
        // Checked before the "nothing learned yet" case: truncation is a fact
        // about the log itself and stays true whether or not any pair was ever
        // read, so reporting the absence of pairs would bury it.
        if (self.spliced_pairs != 0)
            return "stated object pairs are being refused because their two halves disagree with the mapping-base derivation — the emulator's logging spliced them. Every refusal is a wrong identity that did not enter the table, and a wrong identity is worse than a missing one because it carries exact provenance and outranks the derivation that would have been right";
        if (self.truncated_reads != 0 and self.rewrites == 0)
            return "object-pointer fields are arriving truncated and are being refused rather than turned into phantom objects. The emulator's logging is not line-atomic under this runtime, so its synchronisation lines splice";
        if (self.count == 0)
            return "no line has named an object both ways yet, so every address is being taken at face value. Any object the run refers to through two address spaces is currently being counted as two objects";
        if (self.rewrites == 0)
            return "object identities are known and nothing has needed rewriting: every address seen so far was already canonical";
        return "host pointers are being folded onto the console addresses they name, so evidence about one object is no longer split across two identities";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// The exact pair the emulator prints, and the split it causes.
test "a host pointer folds onto the console address the same line named" {
    var table = Table{};
    table.observePair(0xCFF706E4, 0x827206E4);

    const host = table.resolve(0xCFF706E4);
    try std.testing.expectEqual(@as(u64, 0x827206E4), host.canonical);
    try std.testing.expect(host.rewritten);
    try std.testing.expect(host.provenance.exact());

    // The console address resolves to itself and is not counted as a rewrite.
    const console = table.resolve(0x827206E4);
    try std.testing.expectEqual(@as(u64, 0x827206E4), console.canonical);
    try std.testing.expect(!console.rewritten);
    try std.testing.expectEqual(@as(u64, 1), table.rewrites);
}

// Without this, one object waited on through one name and signalled through the
// other looks like two objects, neither of which is a finding.
test "evidence about one object stops being split across two identities" {
    var table = Table{};
    table.observePair(0x400CEC14, 0x827CEC14);
    try std.testing.expectEqual(
        table.resolve(0x400CEC14).canonical,
        table.resolve(0x827CEC14).canonical,
    );
    try std.testing.expect(std.mem.indexOf(u8, table.verdict(), "no longer split") != null);
}

test "an unknown address is returned unchanged rather than guessed at" {
    var table = Table{};
    const resolution = table.resolve(0x12345678);
    try std.testing.expectEqual(@as(u64, 0x12345678), resolution.canonical);
    try std.testing.expectEqual(Provenance.unmapped, resolution.provenance);
    try std.testing.expect(!resolution.rewritten);
    try std.testing.expect(std.mem.indexOf(u8, table.verdict(), "counted as two objects") != null);
}

// A derived answer and an observed one must not be reported as equally certain.
test "the mapping base is a fallback and is marked as derived" {
    var table = Table{};
    table.observeMappingBase(0x34D850000);
    const resolution = table.resolve(0x34D850000 + 0x827206E4);
    try std.testing.expectEqual(@as(u64, 0x827206E4), resolution.canonical);
    try std.testing.expectEqual(Provenance.derived_from_mapping_base, resolution.provenance);
    try std.testing.expect(!resolution.provenance.exact());
    try std.testing.expect(resolution.rewritten);
}

// The emulator prints host pointers with an eight-digit specifier, so they
// arrive truncated. Subtracting the full base underflows and leaves the object
// split — which is exactly what three of them did.
test "a truncated host pointer is derived in the width it was printed in" {
    var table = Table{};
    table.observeMappingBase(0x34D850000);

    // Every pair the observed run printed, none of which the full-width
    // subtraction could resolve.
    try std.testing.expectEqual(@as(?u64, 0x827CEC14), deriveConsoleAddress(0xD001EC14, 0x34D850000));
    try std.testing.expectEqual(@as(?u64, 0x827206E4), deriveConsoleAddress(0xCFF706E4, 0x34D850000));
    try std.testing.expectEqual(@as(?u64, 0x40004BF4), deriveConsoleAddress(0x8D854BF4, 0x34D850000));

    const resolution = table.resolve(0xD001EC38);
    try std.testing.expectEqual(@as(u64, 0x827CEC38), resolution.canonical);
    try std.testing.expect(resolution.rewritten);
    try std.testing.expectEqual(Provenance.derived_from_mapping_base, resolution.provenance);
}

test "an untruncated host pointer still derives by plain subtraction" {
    try std.testing.expectEqual(
        @as(?u64, 0x827206E4),
        deriveConsoleAddress(0x34D850000 + 0x827206E4, 0x34D850000),
    );
}

test "an observed pair outranks the derived fallback" {
    var table = Table{};
    table.observeMappingBase(0x34D850000);
    table.observePair(0xCFF706E4, 0x827206E4);
    const resolution = table.resolve(0xCFF706E4);
    try std.testing.expectEqual(@as(u64, 0x827206E4), resolution.canonical);
    try std.testing.expect(resolution.provenance.exact());
}

// A mapping that moves mid-run invalidates every normalisation taken before it,
// so silently accepting the new value would merge evidence about two different
// objects.
test "a host pointer resolving to two console addresses is a conflict" {
    var table = Table{};
    table.observePair(0xCFF706E4, 0x827206E4);
    table.observePair(0xCFF706E4, 0x82720000);
    try std.testing.expectEqual(@as(u64, 1), table.conflicts);
    try std.testing.expect(std.mem.indexOf(u8, table.verdict(), "is unsound") != null);
}

test "implausible or degenerate pairs are refused" {
    var table = Table{};
    table.observePair(0, 0x827206E4);
    table.observePair(0xCFF706E4, 0);
    // Identical addresses carry no mapping information.
    table.observePair(0x827206E4, 0x827206E4);
    // A console address below the first 64 KiB is a near-null value, not an
    // object.
    table.observePair(0xCFF706E4, 0x40);
    try std.testing.expectEqual(@as(usize, 0), table.count);
}

test "pairs past capacity are counted rather than dropped silently" {
    var table = Table{};
    var index: u64 = 1;
    while (index <= max_pairs) : (index += 1) {
        table.observePair(0x4000_0000 + index, 0x8200_0000 + index);
    }
    try std.testing.expectEqual(@as(usize, max_pairs), table.count);
    table.observePair(0x5000_0000, 0x8300_0000);
    try std.testing.expectEqual(@as(u64, 1), table.dropped);
}

test "repeated sightings of one pair are counted rather than duplicated" {
    var table = Table{};
    var index: u32 = 0;
    while (index < 5) : (index += 1) table.observePair(0xCFF706E4, 0x827206E4);
    try std.testing.expectEqual(@as(usize, 1), table.count);
    try std.testing.expectEqual(@as(u64, 5), table.pairs[0].sightings);
    try std.testing.expectEqual(@as(u64, 0), table.conflicts);
}

// A truncated field parsed leniently becomes a different address, and the
// predictors then give a phantom object its own recurrence counter.
// The dangerous input. Both halves are individually valid eight-digit fields,
// so nothing about their shape betrays the splice — only the independent
// derivation does.
test "a spliced pair is refused rather than poisoning the table" {
    var table = Table{};
    table.observeMappingBase(0x34D850000);

    // Observed splices: the obj_ptr of one line beside the guest_obj of another.
    table.observePair(0x8D854BF4, 0x400CEC14);
    table.observePair(0xD001EC38, 0x40004BF4);
    try std.testing.expectEqual(@as(usize, 0), table.count);
    try std.testing.expectEqual(@as(u64, 2), table.spliced_pairs);
    try std.testing.expect(std.mem.indexOf(u8, table.verdict(), "spliced them") != null);

    // The intact form of the same line is accepted.
    table.observePair(0x8D854BF4, 0x40004BF4);
    try std.testing.expectEqual(@as(usize, 1), table.count);
    try std.testing.expectEqual(@as(u64, 0x40004BF4), table.resolve(0x8D854BF4).canonical);
}

// Pairs read before the base was discovered were accepted on the line's word
// alone, which is exactly the input that cannot be trusted.
test "learning the mapping base retro-validates pairs accepted without it" {
    var table = Table{};
    table.observePair(0x8D854BF4, 0x400CEC14);
    table.observePair(0x8D854BF4 + 0x10, 0x40004C04);
    try std.testing.expectEqual(@as(usize, 2), table.count);

    table.observeMappingBase(0x34D850000);
    // The first disagrees with the derivation and is dropped; the second agrees.
    try std.testing.expectEqual(@as(usize, 1), table.count);
    try std.testing.expectEqual(@as(u64, 1), table.spliced_pairs);
    try std.testing.expectEqual(@as(u64, 0x40004C04), table.pairs[0].console);
}

// An untruncated 64-bit header line cannot be confused with anything and
// carries the handle, which is the identity the title's own code uses.
test "a handle header line gives the console object a handle names" {
    var table = Table{};
    table.observeMappingBase(0x34D850000);
    table.observeHandleHeader(0x38D854BF4, 0xF8000154);
    try std.testing.expectEqual(@as(?u64, 0x40004BF4), table.consoleForHandle(0xF8000154));
    try std.testing.expect(table.consoleForHandle(0xF8000000) == null);

    // Without a base there is nothing to subtract, so nothing is claimed.
    var bare = Table{};
    bare.observeHandleHeader(0x38D854BF4, 0xF8000154);
    try std.testing.expect(bare.consoleForHandle(0xF8000154) == null);
}

test "a short object-pointer field is counted as a refusal, not an object" {
    var table = Table{};
    table.truncated_reads = 3;
    try std.testing.expect(std.mem.indexOf(u8, table.verdict(), "phantom objects") != null);
    try std.testing.expect(std.mem.indexOf(u8, table.verdict(), "not line-atomic") != null);
}

test "zero resolves to zero rather than becoming an object" {
    var table = Table{};
    try std.testing.expectEqual(@as(u64, 0), table.resolve(0).canonical);
    try std.testing.expect(!plausibleConsoleAddress(0));
    try std.testing.expect(!plausibleConsoleAddress(0x40));
    try std.testing.expect(plausibleConsoleAddress(0x827206E4));
    inline for (.{ Provenance.unmapped, Provenance.observed_pair, Provenance.derived_from_mapping_base }) |provenance| {
        try std.testing.expect(provenance.label().len > 0);
    }
}
