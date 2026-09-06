//! The standalone contract for Rosette's translation-cache boundary.
//!
//! This package owns the facts that must be identical wherever a translation
//! cache is looked up, invalidated, diagnosed, or judged: domain ownership,
//! cache geometry, address mixing, and the small set of fill causes that are
//! allowed to terminate a strict run. It deliberately owns no entries,
//! allocator, guest memory, or signal handling. Those are live runtime state
//! and remain in lib; this package is the replayable rule set underneath it.
//!
//! Keeping the mapper here is important. A lookup hash, an invalidation hash,
//! an L2 hash, and a diagnostic hash that drift apart can all compile and can
//! all produce plausible numbers while invalidating or explaining the wrong
//! cache line. The package makes one mapping function the authority and roots
//! it with tests that can run without Mach-O, Xenia, or a host window.

const std = @import("std");

pub const schema_version: u16 = 1;

/// The four ownership banks in the primary and victim caches.
pub const Domain = enum(u2) {
    static_image,
    dynamic_generated,
    thunk_bridge,
    unknown,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .static_image => "static-image",
            .dynamic_generated => "dynamic-generated",
            .thunk_bridge => "thunk-bridge",
            .unknown => "unknown",
        };
    }

    pub fn bank(self: Domain) usize {
        return @intFromEnum(self);
    }
};

pub const domain_count: usize = @typeInfo(Domain).@"enum".fields.len;
pub const count = domain_count;
pub const all = [_]Domain{ .static_image, .dynamic_generated, .thunk_bridge, .unknown };

pub const Classification = struct {
    static_image: bool = false,
    executable: bool = false,
    thunk_bridge: bool = false,

    pub fn domain(self: Classification) Domain {
        if (self.thunk_bridge) return .thunk_bridge;
        if (self.static_image) return .static_image;
        if (self.executable) return .dynamic_generated;
        return .unknown;
    }
};

/// The kinds of table that use the shared address-mixing rule. Primary and
/// victim tables are banked by Domain; the static L2 is one image-only table.
pub const LayoutKind = enum(u8) {
    primary,
    victim,
    static_l2,
};

/// The primary cache gives a fetch two independently hashed set choices. The
/// table size stays fixed, while a skewed placement prevents one unlucky hash
/// bucket from being allowed to terminate the run when its sibling bucket has
/// usable capacity.
pub const primary_set_choice_count: usize = 2;

pub const BankRange = struct {
    start: usize,
    end: usize,
};

/// A cache layout expressed in total set count, not entry count. For a banked
/// layout, `total_set_count` includes every domain bank. For an unbanked
/// layout, all sets belong to the one owner selected by the caller.
pub const Layout = struct {
    name: []const u8,
    total_set_count: usize,
    ways: usize,
    banked: bool,
    kind: LayoutKind,

    pub fn entryCount(self: Layout) usize {
        return self.total_set_count * self.ways;
    }

    pub fn localSetCount(self: Layout) usize {
        if (!self.banked) return self.total_set_count;
        std.debug.assert(self.total_set_count >= domain_count);
        std.debug.assert(self.total_set_count % domain_count == 0);
        return self.total_set_count / domain_count;
    }

    /// Return the local set number before the domain-bank offset is applied.
    /// Keeping this separate makes it possible to compare two domains' set
    /// coordinates without accidentally comparing their global slot bases.
    pub fn setIndex(self: Layout, address: u64) usize {
        return self.setIndexChoice(address, 0);
    }

    /// Return a local set using one of the bounded primary hash choices.
    /// Non-primary layouts have one canonical choice; callers should use their
    /// ordinary `setIndex`/`setBase` methods for those layouts.
    pub fn setIndexChoice(self: Layout, address: u64, choice: usize) usize {
        // Only the primary table has sibling placements. Silently accepting
        // choice 1 for the victim or static-L2 tables would make a caller's
        // lookup and invalidation disagree about which secondary entry is
        // authoritative.
        if (self.kind != .primary) std.debug.assert(choice == 0);
        const local_sets = self.localSetCount();
        std.debug.assert(local_sets != 0);
        const mixed = mixAddress(address, self.kind, choice);
        return @intCast(mixed % local_sets);
    }

    /// Return the first entry in the set selected for `address` and `domain`.
    /// Every consumer must use this rather than reproducing the arithmetic.
    pub fn setBase(self: Layout, address: u64, domain: Domain) usize {
        return self.setBaseChoice(address, domain, 0);
    }

    pub fn setBaseChoice(self: Layout, address: u64, domain: Domain, choice: usize) usize {
        const local_set = self.setIndexChoice(address, choice);
        const bank = if (self.banked) domain.bank() else 0;
        return (bank * self.localSetCount() + local_set) * self.ways;
    }

    pub fn bankRange(self: Layout, domain: Domain) BankRange {
        if (!self.banked) {
            return .{ .start = 0, .end = self.entryCount() };
        }
        const bank_entries = self.localSetCount() * self.ways;
        const start = domain.bank() * bank_entries;
        return .{ .start = start, .end = start + bank_entries };
    }

    pub fn wellFormed(self: Layout) bool {
        if (self.total_set_count == 0 or self.ways == 0) return false;
        if (self.banked and self.total_set_count % domain_count != 0) return false;
        return self.entryCount() != 0;
    }
};

pub const primary_layout = Layout{
    .name = "primary",
    // Give every ownership bank 65,536 local sets. The previous 32,768-set
    // budget was enough for static initialization, but a later graphics setup
    // burst produced a genuine reused-only 17th resident in one static set.
    // Doubling the set budget lowers dispersed occupancy without weakening the
    // strict response to a set that is still genuinely over capacity.
    .total_set_count = (1 << 16) * domain_count,
    // Keep sixteen ways so a local working set still has substantial
    // associativity after the set-budget increase. The replacement contract
    // chooses cold entries first and continues to fail fast when every
    // resident is reused.
    .ways = 16,
    .banked = true,
    .kind = .primary,
};

pub const victim_layout = Layout{
    .name = "victim",
    // Keep the former 1,024-set victim budget in each bank as well. A victim
    // table is smaller than primary, but reducing it fourfold per domain
    // would make its protection dependent on which address class won the
    // bank partition.
    .total_set_count = (1 << 10) * domain_count,
    .ways = 4,
    .banked = true,
    .kind = .victim,
};

pub const static_l2_layout = Layout{
    .name = "static-l2",
    .total_set_count = 1 << 15,
    .ways = 4,
    .banked = false,
    .kind = .static_l2,
};

fn hashSalt(kind: LayoutKind, choice: usize) u64 {
    return switch (kind) {
        // The first seed is the stable placement used by the previous
        // contract. The second is an independently mixed choice for the same
        // bank. Both choices are deterministic and allocation-free; the
        // runtime probes both before declaring a real capacity conflict.
        .primary => switch (choice) {
            0 => 0x517C_C1B7_2722_0A95,
            1 => 0xC6BC_2796_92B5_CC83,
            else => unreachable,
        },
        .victim => 0xD6E8_FEB8_6659_FD93,
        .static_l2 => 0xA24B_AED4_963E_E407,
    };
}

/// Avalanche every address bit before reducing to a power-of-two set count.
/// An odd multiply alone is not a hash here: modulo 2^n it is invertible and
/// therefore preserves the low n bits exactly. The previous folded multiply
/// consequently let addresses that differed only above bit 14 collide even
/// though their higher bits appeared in the intermediate value. This final
/// mix is allocation-free, deterministic on every target, and shared by all
/// table kinds through `Layout.setIndex`.
fn mixAddress(address: u64, kind: LayoutKind, choice: usize) u64 {
    var mixed = address ^ (address >> 13) ^ (address >> 29) ^ (address >> 47) ^ hashSalt(kind, choice);
    mixed ^= mixed >> 30;
    mixed *%= 0xBF58_476D_1CE4_E5B9;
    mixed ^= mixed >> 27;
    mixed *%= 0x94D0_49BB_1331_11EB;
    mixed ^= mixed >> 31;
    return mixed;
}

pub inline fn primarySetBase(address: u64, domain: Domain) usize {
    return primary_layout.setBase(address, domain);
}

pub inline fn primarySetBaseChoice(address: u64, domain: Domain, choice: usize) usize {
    std.debug.assert(choice < primary_set_choice_count);
    return primary_layout.setBaseChoice(address, domain, choice);
}

pub inline fn primarySetBases(address: u64, domain: Domain) [primary_set_choice_count]usize {
    return .{
        primarySetBaseChoice(address, domain, 0),
        primarySetBaseChoice(address, domain, 1),
    };
}

pub inline fn victimSetBase(address: u64, domain: Domain) usize {
    return victim_layout.setBase(address, domain);
}

pub inline fn staticL2SetBase(address: u64) usize {
    return static_l2_layout.setBase(address, .static_image);
}

/// The runtime uses a bounded second-chance replacement policy for every
/// associative translation-cache tier. Keeping the decision here prevents the
/// primary, static L2, and victim caches from quietly acquiring different
/// notions of which resident is safe to displace.
pub const max_replacement_ways: usize = 64;

pub const ReplacementState = struct {
    occupied: bool,
    recently_used: bool,
    reuse_count: u16,
};

pub const ReplacementChoice = struct {
    index: usize,
    empty: bool,
    /// All reference bits were set, so the caller must clear them after the
    /// choice. The selected way is still chosen by reuse count, not by its
    /// physical position in the set.
    reset_reference_bits: bool,
};

/// Choose a resident for insertion without making way order part of the
/// eviction policy.
///
/// Empty ways always win. A never-reused entry is the coldest possible
/// resident, even if its reference bit was set when it was filled, so it is
/// preferred before any entry that has already produced a cache hit. Among
/// cold entries, an unmarked way still wins. If every resident has been
/// reused, an unmarked way is preferred and the least-reused entry wins within
/// that group. If every way is marked, the reference epoch rolls over and the
/// least-reused resident is selected. This preserves hot code when a cold
/// candidate is available while retaining a bounded, allocation-free path on
/// a miss.
pub fn chooseReplacement(states: []const ReplacementState) ?ReplacementChoice {
    if (states.len == 0 or states.len > max_replacement_ways) return null;

    for (states, 0..) |state, index| {
        if (!state.occupied) {
            return .{
                .index = index,
                .empty = true,
                .reset_reference_bits = false,
            };
        }
    }

    // Whether the reference epoch still carries information.
    //
    // A set in which every occupied way is marked has no second chance left to
    // give: the bit distinguishes nothing, so it has to roll whichever way is
    // selected below. Computed over every way rather than assumed from the
    // path taken, because a set can hold cold-and-marked entries beside
    // reused-and-unmarked ones, and only the former exhausts the epoch.
    var epoch_exhausted = true;
    for (states) |state| {
        if (!state.recently_used) {
            epoch_exhausted = false;
            break;
        }
    }

    // A reference bit set by insertion does not prove reuse. Prefer entries
    // whose reuse counter is still zero, and retain second-chance ordering
    // only as a tie-break inside that cold group.
    for (states, 0..) |state, index| {
        if (state.reuse_count == 0 and !state.recently_used) {
            return .{
                .index = index,
                .empty = false,
                .reset_reference_bits = false,
            };
        }
    }
    // Every cold way is marked, or there are none. Reaching here with the
    // epoch exhausted is the case that used to leave `reset_reference_bits`
    // false: the bits were set on insertion and this path never cleared them,
    // so every way in the set stayed marked for the life of the run. The
    // tie-break above could then never fire, and the selection below decayed
    // into "the lowest-numbered cold way", which is precisely the way-order
    // policy this function exists to avoid — one way evicted and refilled
    // while six equally cold ways beside it were never touched.
    for (states, 0..) |state, index| {
        if (state.reuse_count == 0) {
            return .{
                .index = index,
                .empty = false,
                .reset_reference_bits = epoch_exhausted,
            };
        }
    }

    var selected_index: ?usize = null;
    var selected_reuse: u16 = std.math.maxInt(u16);
    for (states, 0..) |state, index| {
        if (state.recently_used) continue;
        if (selected_index == null or state.reuse_count < selected_reuse) {
            selected_index = index;
            selected_reuse = state.reuse_count;
        }
    }
    if (selected_index) |index| {
        return .{
            .index = index,
            .empty = false,
            .reset_reference_bits = false,
        };
    }

    // Every way was recently referenced. Start a new reference epoch, but
    // retain the reuse-count ordering so the fallback does not hammer way 0.
    selected_index = 0;
    selected_reuse = states[0].reuse_count;
    for (states[1..], 1..) |state, index| {
        if (state.reuse_count < selected_reuse) {
            selected_index = index;
            selected_reuse = state.reuse_count;
        }
    }
    return .{
        .index = selected_index.?,
        .empty = false,
        .reset_reference_bits = true,
    };
}

/// A fill's cause is part of the cache boundary, not a post-hoc interpretation
/// of a page counter. In particular, a vacant fill and a cold eviction are
/// legitimate warming work; they must not be promoted into a fail-fast fault.
pub const Cause = enum(u8) {
    vacant_fill,
    capacity_conflict,
    cold_eviction,
    stale_bytes,
    flush_collateral,

    pub fn label(self: Cause) []const u8 {
        return switch (self) {
            .vacant_fill => "vacant-fill",
            .capacity_conflict => "capacity-conflict",
            .cold_eviction => "cold-eviction",
            .stale_bytes => "stale-bytes",
            .flush_collateral => "flush-collateral",
        };
    }

    pub fn recurring(self: Cause) bool {
        return switch (self) {
            .capacity_conflict, .stale_bytes, .flush_collateral => true,
            .vacant_fill, .cold_eviction => false,
        };
    }

    /// Whether a run configured to fail fast must stop on this cause.
    ///
    /// A cold eviction stays out of this predicate for the same reason it is
    /// out of `recurring()`: the displaced entry had never been reused. It is
    /// evidence that the cache saw a non-empty working set during warm-up, not
    /// evidence that a useful translation was repeatedly lost. The victim and
    /// static-image L2 caches can also recover that entry without another
    /// decode. A later address-specific refetch can make cold loss actionable,
    /// but this fill-site fact alone cannot prove that.
    ///
    /// `vacant_fill` stays out as well: an instruction has to be decoded once,
    /// and no cache policy makes a first touch free. The report keeps both
    /// classes visible instead of conflating either one with reusable conflict.
    pub fn requiresFailFast(self: Cause) bool {
        return switch (self) {
            .capacity_conflict, .stale_bytes, .flush_collateral => true,
            .vacant_fill, .cold_eviction => false,
        };
    }

    /// Whether this miss was unavoidable: the address had never been decoded,
    /// so no cache of any size or policy could have held it.
    pub fn compulsory(self: Cause) bool {
        return self == .vacant_fill;
    }

    /// Why this class is or is not allowed to stop the run.
    pub fn policy(self: Cause) []const u8 {
        return switch (self) {
            .vacant_fill => "COMPULSORY: a first touch of an address never decoded before. No cache can avoid it, so it never stops the run — but it must converge, and a steady rate late in a run means the working set is still growing",
            .capacity_conflict => "FATAL: a live, reused decode was displaced. The work is lost and will be redone",
            .cold_eviction => "DEFERRED: a non-empty, never-reused decode was displaced during warming; retain it as working-set evidence and require an address-specific refetch before calling it lost reusable work",
            .stale_bytes => "FATAL: the cached bytes changed under the cached RIP. Executable mutation is proven for this address",
            .flush_collateral => "FATAL: a coarse invalidation discarded a decode without proving overlap. The refill is avoidable",
        };
    }

    pub fn meaning(self: Cause) []const u8 {
        return switch (self) {
            .vacant_fill => "the selected set had an unused way; this is a cold or precisely-cleared fill and does not prove executable code was rewritten",
            .capacity_conflict => "a live decode was evicted by another address; larger capacity, wider associativity or separate immutable and mutable tiers can recover this work",
            .cold_eviction => "a non-empty but never-reused decode was displaced by a cold working-set stream; this is fill cost, not hot conflict evidence",
            .stale_bytes => "the cached RIP was reached with different source bytes; executable mutation is proven for this address",
            .flush_collateral => "a coarse invalidation discarded a decode without proving overlap; the refill is avoidable invalidation collateral",
        };
    }
};

/// The runtime passes booleans instead of importing the run-integrity package:
/// this keeps the cache contract usable by a small offline verifier and by
/// future processors that may have a different policy enum.
pub const FailFastGate = struct {
    strict: bool = false,
    fault_policy: bool = false,
    allowlisted: bool = false,
};

pub inline fn shouldFailFast(cause: Cause, gate: FailFastGate) bool {
    return gate.strict and gate.fault_policy and !gate.allowlisted and cause.requiresFailFast();
}

// A cold eviction proves no hot conflict — the entry it displaced was never
// reused. It remains visible as warming/working-set evidence, but the fill site
// has not proved that the cache discarded useful reusable work.
test "a cold eviction is observed without becoming fail-fast evidence" {
    try std.testing.expect(!Cause.cold_eviction.recurring());
    try std.testing.expect(!Cause.cold_eviction.requiresFailFast());
    try std.testing.expect(!Cause.cold_eviction.compulsory());

    // The one carve-out, and it is permanent.
    try std.testing.expect(Cause.vacant_fill.compulsory());
    try std.testing.expect(!Cause.vacant_fill.requiresFailFast());

    // Everything that was already fatal stays fatal.
    for ([_]Cause{ .capacity_conflict, .stale_bytes, .flush_collateral }) |cause| {
        try std.testing.expect(cause.recurring());
        try std.testing.expect(cause.requiresFailFast());
        try std.testing.expect(!cause.compulsory());
    }

    // Every class states the policy that governs it, so a reader never has to
    // know the taxonomy to judge a row.
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const cause: Cause = @enumFromInt(field.value);
        try std.testing.expect(cause.policy().len != 0);
        try std.testing.expect(cause.meaning().len != 0);
    }
}

test "the fail-fast gate still needs strict mode and a fault policy" {
    const cause = Cause.capacity_conflict;
    try std.testing.expect(!shouldFailFast(cause, .{}));
    try std.testing.expect(!shouldFailFast(cause, .{ .strict = true }));
    try std.testing.expect(shouldFailFast(cause, .{ .strict = true, .fault_policy = true }));
    try std.testing.expect(!shouldFailFast(cause, .{ .strict = true, .fault_policy = true, .allowlisted = true }));
    try std.testing.expect(!shouldFailFast(.cold_eviction, .{ .strict = true, .fault_policy = true }));
    // And a compulsory miss never fails fast, whatever the gate says.
    try std.testing.expect(!shouldFailFast(.vacant_fill, .{ .strict = true, .fault_policy = true }));
}

test "all layouts are well formed and primary banks are disjoint" {
    try std.testing.expect(primary_layout.wellFormed());
    try std.testing.expect(victim_layout.wellFormed());
    try std.testing.expect(static_l2_layout.wellFormed());

    const primary_ranges = [_]BankRange{
        primary_layout.bankRange(.static_image),
        primary_layout.bankRange(.dynamic_generated),
        primary_layout.bankRange(.thunk_bridge),
        primary_layout.bankRange(.unknown),
    };
    for (primary_ranges, 0..) |left, left_index| {
        try std.testing.expect(left.end > left.start);
        for (primary_ranges, 0..) |right, right_index| {
            if (left_index == right_index) continue;
            try std.testing.expect(left.end <= right.start or right.end <= left.start);
        }
    }
}

test "every mapper and its geometry agree on the selected bank" {
    const address = 0xA000_5AF8;
    const static_base = primarySetBase(address, .static_image);
    const dynamic_base = primarySetBase(address, .dynamic_generated);
    try std.testing.expect(static_base != dynamic_base);
    try std.testing.expectEqual(static_base % primary_layout.ways, dynamic_base % primary_layout.ways);
    try std.testing.expectEqual(
        static_base / primary_layout.ways + primary_layout.localSetCount(),
        dynamic_base / primary_layout.ways,
    );
    try std.testing.expectEqual(static_base, primary_layout.setBase(address, .static_image));
    try std.testing.expectEqual(victimSetBase(address, .thunk_bridge), victim_layout.setBase(address, .thunk_bridge));
    try std.testing.expectEqual(staticL2SetBase(address), static_l2_layout.setBase(address, .unknown));
}

test "same-offset image functions do not alias the same cache set" {
    // This is the exact shape caught by the strict runtime run. A hash that
    // only observed the low modulo bits mapped both addresses to the same set.
    const first = primarySetBase(0x0001_8520, .static_image);
    const second = primarySetBase(0x0004_0520, .static_image);
    try std.testing.expect(first != second);
}

test "static startup conflict pair stays in distinct local sets" {
    // Regression for the exact strict-run casualty. Both addresses are in the
    // static-image bank. They aliased when the banked table accidentally gave
    // that bank only 8,192 sets; the expanded geometry and remapped seed keep
    // this particular reusable initializer decode out of the same set.
    const source_set = primary_layout.setIndex(0x001c_bcca);
    const victim_set = primary_layout.setIndex(0x0019_c23);
    try std.testing.expect(source_set != victim_set);
    try std.testing.expectEqual(@as(usize, 1 << 16), primary_layout.localSetCount());
    try std.testing.expectEqual(@as(usize, 1 << 10), victim_layout.localSetCount());
}

test "graphics setup conflict pair is separated by the expanded static bank" {
    // Regression for the genuine 17th-resident overflow observed after
    // GraphicsSystem setup began. Both starts were static image code and
    // exhausted one 16-way set under the previous 32,768-set budget.
    const source_set = primary_layout.setIndex(0x00c3_42fc);
    const victim_set = primary_layout.setIndex(0x009c_0618);
    try std.testing.expect(source_set != victim_set);
}

test "graphics setup conflict pair has an independent primary placement choice" {
    // The latest strict-run casualty still aliased in choice zero after the
    // table expansion. Two-choice placement must offer a different set for
    // the source and the reused resident before the runtime calls it a full
    // working set.
    const source_sets = primarySetBases(0x00d3_7f54, .static_image);
    const victim_sets = primarySetBases(0x00cb_da1, .static_image);
    try std.testing.expect(!(source_sets[0] == victim_sets[0] and source_sets[1] == victim_sets[1]));
    try std.testing.expect(source_sets[0] != source_sets[1]);
    try std.testing.expect(victim_sets[0] != victim_sets[1]);
}

test "every primary placement choice stays inside its ownership bank" {
    const addresses = [_]u64{ 0, 0x00d3_7f54, 0x00cb_da1, 0xA000_5AF8, std.math.maxInt(u64) };
    for (all) |domain| {
        for (addresses) |address| {
            const bases = primarySetBases(address, domain);
            for (bases) |base| {
                try std.testing.expect(base + primary_layout.ways <= primary_layout.entryCount());
                try std.testing.expectEqual(@as(usize, 0), base % primary_layout.ways);
                try std.testing.expectEqual(domain.bank(), (base / primary_layout.ways) / primary_layout.localSetCount());
            }
        }
    }
    // These secondary layouts deliberately have one canonical placement.
    try std.testing.expectEqual(
        victim_layout.setBase(0x1234, .dynamic_generated),
        victim_layout.setBaseChoice(0x1234, .dynamic_generated, 0),
    );
    try std.testing.expectEqual(
        static_l2_layout.setBase(0x1234, .static_image),
        static_l2_layout.setBaseChoice(0x1234, .static_image, 0),
    );
}

test "higher address bits participate in the startup cache set" {
    // Regression for the next strict-run casualty. The prior odd multiply
    // preserved the low 15 bits under modulo 2^15, so these two unrelated
    // static functions landed in the same local set despite differing well
    // above bit 14.
    const source_set = primary_layout.setIndex(0x0027_5a10);
    const victim_set = primary_layout.setIndex(0x001d_b24);
    try std.testing.expect(source_set != victim_set);
}

test "previous static-init overflow pair is separated by the primary remap" {
    // This pair previously shared a set under the former primary seed. Once
    // the table is expanded, retain a deterministic separation regression so
    // a future mapper change cannot recreate that avoidable pressure hotspot.
    const source_set = primary_layout.setIndex(0x0014_1ff3);
    const victim_set = primary_layout.setIndex(0x0018_a32);
    try std.testing.expect(source_set != victim_set);
    try std.testing.expectEqual(@as(usize, 16), primary_layout.ways);
}

// Strict mode stops on proven reusable loss, not on every non-empty fill. A
// cold eviction is intentionally retained as evidence but is not actionable
// until a later address-specific observation proves that reusable work was
// actually lost.
test "strict policy stops on actionable miss classes" {
    const armed = FailFastGate{ .strict = true, .fault_policy = true };
    try std.testing.expect(shouldFailFast(.capacity_conflict, armed));
    try std.testing.expect(shouldFailFast(.stale_bytes, armed));
    try std.testing.expect(shouldFailFast(.flush_collateral, armed));
    try std.testing.expect(!shouldFailFast(.cold_eviction, armed));
    try std.testing.expect(!shouldFailFast(.vacant_fill, armed));
    // A cold eviction still proves no hot conflict: the entry it displaced had
    // never been reused, and the two predicates must not be collapsed.
    try std.testing.expect(!Cause.cold_eviction.recurring());
    try std.testing.expect(!shouldFailFast(.capacity_conflict, .{ .strict = false, .fault_policy = true }));
    try std.testing.expect(!shouldFailFast(.capacity_conflict, .{ .strict = true, .fault_policy = false }));
    try std.testing.expect(!shouldFailFast(.capacity_conflict, .{ .strict = true, .fault_policy = true, .allowlisted = true }));
}

// The 2026-09-03 fail-fast. The resident dump showed all thirty-two ways of
// both set choices reading `recently_used=true`, with seven of the sixteen in
// the target set at `reuse_count=0`. The bits are set on insertion and this
// path never cleared them, so the epoch never rolled: the unmarked tie-break
// could not fire, and the cold fallback picked the lowest-numbered cold way
// every time. Way 1 was evicted, refilled, and evicted again while six equally
// cold ways beside it were never touched.
test "a set of cold marked ways rolls the reference epoch" {
    // Seven cold ways, every way marked — the shape the log recorded.
    var states: [16]ReplacementState = undefined;
    const reuse = [16]u16{ 11, 0, 0, 0, 0, 0, 149, 13, 9, 1, 11, 0, 16, 17, 2, 0 };
    for (&states, reuse) |*slot, hits| {
        slot.* = .{ .occupied = true, .recently_used = true, .reuse_count = hits };
    }
    var cold: usize = 0;
    for (reuse) |hits| {
        if (hits == 0) cold += 1;
    }
    try std.testing.expectEqual(@as(usize, 7), cold);

    const choice = chooseReplacement(&states) orelse unreachable;
    try std.testing.expect(!choice.empty);
    // A cold way is still the right victim; nothing reused may be displaced.
    try std.testing.expectEqual(@as(u16, 0), states[choice.index].reuse_count);
    // And the epoch must roll, or the next miss makes the identical choice.
    try std.testing.expect(choice.reset_reference_bits);
}

// Rolling is not unconditional: an unmarked way anywhere in the set means the
// epoch still discriminates and clearing it would throw that away.
test "the epoch holds while any way is still unmarked" {
    var states = [_]ReplacementState{
        .{ .occupied = true, .recently_used = true, .reuse_count = 0 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 5 },
        // Reused but unmarked: the epoch is live even though no cold way is.
        .{ .occupied = true, .recently_used = false, .reuse_count = 7 },
    };
    const choice = chooseReplacement(&states) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 0), choice.index);
    try std.testing.expect(!choice.reset_reference_bits);

    // Once that unmarked way is marked too, the same set rolls.
    states[2].recently_used = true;
    const rolled = chooseReplacement(&states) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 0), rolled.index);
    try std.testing.expect(rolled.reset_reference_bits);
}

// After a roll the caller clears every bit, so the next miss has real
// information again and stops landing on the same way.
test "a rolled epoch stops the cold fallback repeating one way" {
    var states: [4]ReplacementState = .{
        .{ .occupied = true, .recently_used = true, .reuse_count = 0 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 0 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 0 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 4 },
    };
    const first = chooseReplacement(&states) orelse unreachable;
    try std.testing.expect(first.reset_reference_bits);
    // What the fill path does with that answer.
    for (&states) |*slot| slot.recently_used = false;
    states[first.index] = .{ .occupied = true, .recently_used = true, .reuse_count = 0 };

    // The next miss must not choose the way just installed.
    const second = chooseReplacement(&states) orelse unreachable;
    try std.testing.expect(second.index != first.index);
    try std.testing.expect(!second.reset_reference_bits);
    try std.testing.expectEqual(@as(u16, 0), states[second.index].reuse_count);
}

test "replacement prefers an empty way and then the least-reused unmarked way" {
    var states = [_]ReplacementState{
        .{ .occupied = true, .recently_used = false, .reuse_count = 9 },
        .{ .occupied = true, .recently_used = false, .reuse_count = 2 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 7 },
        .{ .occupied = false, .recently_used = true, .reuse_count = 99 },
    };

    const empty_choice = chooseReplacement(&states) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 3), empty_choice.index);
    try std.testing.expect(empty_choice.empty);
    try std.testing.expect(!empty_choice.reset_reference_bits);

    states[3].occupied = true;
    const cold_choice = chooseReplacement(&states) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 1), cold_choice.index);
    try std.testing.expect(!cold_choice.empty);
    try std.testing.expect(!cold_choice.reset_reference_bits);
}

test "replacement evicts a never-reused marked fill before a reused way" {
    const states = [_]ReplacementState{
        .{ .occupied = true, .recently_used = true, .reuse_count = 0 },
        .{ .occupied = true, .recently_used = false, .reuse_count = 2 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 5 },
    };
    const choice = chooseReplacement(&states) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 0), choice.index);
    try std.testing.expect(!choice.empty);
    try std.testing.expect(!choice.reset_reference_bits);
}

test "replacement rolls the reference epoch but still avoids the hottest way" {
    const states = [_]ReplacementState{
        .{ .occupied = true, .recently_used = true, .reuse_count = 8 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 2 },
        .{ .occupied = true, .recently_used = true, .reuse_count = 5 },
    };
    const choice = chooseReplacement(&states) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 1), choice.index);
    try std.testing.expect(!choice.empty);
    try std.testing.expect(choice.reset_reference_bits);
}

test "replacement rejects unbounded or empty way sets" {
    try std.testing.expect(chooseReplacement(&.{}) == null);
    var states: [max_replacement_ways + 1]ReplacementState = undefined;
    @memset(&states, .{ .occupied = true, .recently_used = false, .reuse_count = 0 });
    try std.testing.expect(chooseReplacement(&states) == null);
}

test "classification gives thunk ranges precedence over executable ranges" {
    try std.testing.expectEqual(Domain.thunk_bridge, (Classification{
        .static_image = true,
        .executable = true,
        .thunk_bridge = true,
    }).domain());
    try std.testing.expectEqual(Domain.static_image, (Classification{ .static_image = true, .executable = true }).domain());
    try std.testing.expectEqual(Domain.dynamic_generated, (Classification{ .executable = true }).domain());
    try std.testing.expectEqual(Domain.unknown, (Classification{}).domain());
}
