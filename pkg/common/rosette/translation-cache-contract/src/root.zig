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

/// Local set count per ownership bank.
///
/// Banks are sized by measured demand, not by symmetry. An equal split reads
/// as fair and is not: it hands every domain the same capacity regardless of
/// how much code that domain actually contains, so the busiest bank runs out
/// while the others hold nothing. Index order matches `Domain.bank()`.
pub const BankSets = [domain_count]usize;

/// A cache layout expressed in per-bank set counts, not entry count. An
/// unbanked layout keeps all of its sets in index 0 and leaves the rest zero.
pub const Layout = struct {
    name: []const u8,
    bank_sets: BankSets,
    ways: usize,
    banked: bool,
    kind: LayoutKind,

    pub fn totalSetCount(self: Layout) usize {
        if (!self.banked) return self.bank_sets[0];
        var total: usize = 0;
        for (self.bank_sets) |sets| total += sets;
        return total;
    }

    pub fn entryCount(self: Layout) usize {
        return self.totalSetCount() * self.ways;
    }

    pub fn localSetCount(self: Layout, domain: Domain) usize {
        if (!self.banked) return self.bank_sets[0];
        return self.bank_sets[domain.bank()];
    }

    /// The first *set* of a bank, in whole-table set coordinates. With unequal
    /// banks this is a running sum rather than `bank * localSetCount`, and
    /// reproducing the old product anywhere would land a lookup in the wrong
    /// domain's memory.
    pub fn bankFirstSet(self: Layout, domain: Domain) usize {
        if (!self.banked) return 0;
        var first: usize = 0;
        for (self.bank_sets[0..domain.bank()]) |sets| first += sets;
        return first;
    }

    /// Return the local set number before the domain-bank offset is applied.
    /// Keeping this separate makes it possible to compare two domains' set
    /// coordinates without accidentally comparing their global slot bases.
    pub fn setIndex(self: Layout, address: u64, domain: Domain) usize {
        return self.setIndexChoice(address, domain, 0);
    }

    /// Return a local set using one of the bounded primary hash choices.
    /// Non-primary layouts have one canonical choice; callers should use their
    /// ordinary `setIndex`/`setBase` methods for those layouts.
    pub fn setIndexChoice(self: Layout, address: u64, domain: Domain, choice: usize) usize {
        // Only the primary table has sibling placements. Silently accepting
        // choice 1 for the victim or static-L2 tables would make a caller's
        // lookup and invalidation disagree about which secondary entry is
        // authoritative.
        if (self.kind != .primary) std.debug.assert(choice == 0);
        const local_sets = self.localSetCount(domain);
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
        const local_set = self.setIndexChoice(address, domain, choice);
        return (self.bankFirstSet(domain) + local_set) * self.ways;
    }

    pub fn bankRange(self: Layout, domain: Domain) BankRange {
        if (!self.banked) {
            return .{ .start = 0, .end = self.entryCount() };
        }
        const start = self.bankFirstSet(domain) * self.ways;
        return .{ .start = start, .end = start + self.localSetCount(domain) * self.ways };
    }

    pub fn wellFormed(self: Layout) bool {
        if (self.ways == 0) return false;
        if (!self.banked) return self.bank_sets[0] != 0 and self.entryCount() != 0;
        // Every bank has to be able to hold something. A zero-set bank makes
        // `mixed % local_sets` divide by zero for any address routed to it,
        // and a domain that looks unused today is one classifier change away
        // from being used tomorrow.
        for (self.bank_sets) |sets| {
            if (sets == 0) return false;
        }
        return self.entryCount() != 0;
    }
};

pub const primary_layout = Layout{
    .name = "primary",
    // Sized from the 2026-09-07 run's own domain census at 3.8 billion steps:
    //
    //   static(h/m/f)=3704998956/903034/903034
    //   dynamic      = 101986938/156999/156999
    //   thunk        = 0/0/0
    //   unknown      = 0/0/0
    //
    // Under the previous equal split every domain held 65,536 sets, so the
    // static-image bank was 86% full and evicting while the thunk and unknown
    // banks — 2,097,152 entries between them, 208 MiB — had never held a
    // single decode. That is what the split costs when it is chosen for
    // symmetry: the one bank doing the work runs out while three quarters of
    // the table is untouched, and the run stops on a capacity fault raised by
    // a cache that is 25% utilised.
    //
    // Static image code is the dominant and slowest-growing consumer (+1,000
    // fills per 100M steps at this point, essentially converged), so it gets
    // the room. Generated JIT code is an order of magnitude smaller but grows
    // ten times faster (+10,000 per 100M steps), so it keeps a full bank.
    // Thunks and the unclassified fallback are bounded by construction and
    // get enough to never be the reason a run stops.
    .bank_sets = .{
        1 << 17, // static_image      2,097,152 entries — 903K observed, 43%
        1 << 16, // dynamic_generated 1,048,576 entries — 157K observed, 15%
        1 << 12, // thunk_bridge         65,536 entries
        1 << 12, // unknown              65,536 entries
    },
    // Keep sixteen ways so a local working set still has substantial
    // associativity. The replacement contract chooses cold entries first and
    // continues to fail fast when every resident is reused, and `chooseSet`
    // balances across the two hashed choices before depth becomes an issue.
    .ways = 16,
    .banked = true,
    .kind = .primary,
};

pub const victim_layout = Layout{
    .name = "victim",
    // The victim tier holds what the primary drops, so it is scaled to the
    // same demand ratio rather than split evenly. It stays far smaller than
    // primary in every bank: its job is to absorb a short-lived burst, not to
    // be a second copy of the working set.
    .bank_sets = .{
        1 << 12, // static_image
        1 << 10, // dynamic_generated
        1 << 8, // thunk_bridge
        1 << 8, // unknown
    },
    .ways = 4,
    .banked = true,
    .kind = .victim,
};

pub const static_l2_layout = Layout{
    .name = "static-l2",
    // Only ever holds static-image decodes evicted from the primary, so it is
    // sized against that eviction stream rather than against the whole image.
    // See `saveStaticDecodeL2`: filling it on every primary fill instead made
    // it a write-only table — the 2026-09-07 run recorded 903,034 fills and
    // zero hits.
    .bank_sets = .{ 1 << 15, 0, 0, 0 },
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

/// One hashed set choice, summarised for a placement decision.
///
/// The runtime passes a count rather than the ways themselves so this decision
/// stays free of entry layout, and so a caller can compute occupancy with a
/// side-effect-free scan instead of running the replacement policy — which
/// clears reference bits — on a set it is not going to use.
pub const SetOccupancy = struct {
    occupied: usize,
    ways: usize,
    /// Only read when the set is full: the reuse count and reference bit of
    /// the resident `chooseReplacement` would evict from it.
    victim_reuse_count: u16 = 0,
    victim_recently_used: bool = false,

    pub fn hasFreeWay(self: SetOccupancy) bool {
        return self.occupied < self.ways;
    }
};

/// Choose which hashed set a fill goes into.
///
/// The two independently seeded set choices exist to balance load, and that
/// only happens if placement actually compares them. Filling the first choice
/// until it is *completely* full and consulting the second only then is
/// first-fit, not two-choice: it leaves placement statistically single-choice,
/// so set depth follows the plain balls-in-bins tail instead of the doubly
/// logarithmic one that two choices buy.
///
/// Measured on the 2026-09-07 run's own numbers — 470,192 static-image fills
/// across 65,536 sets of 16 ways, replayed through `mixAddress` — first fit
/// drove 226 fills into a completely full first choice and left exactly one
/// with both choices full, which is the single `cold-eviction` that run
/// reported. Comparing the two choices holds the deepest set at 10 of 16 for
/// the same stream, so no set fills and no eviction happens at all.
///
/// When every choice is full the decision falls back to the victim comparison,
/// which is the point at which the working set genuinely does not fit and
/// strict policy is supposed to say so.
pub fn chooseSet(candidates: []const SetOccupancy) ?usize {
    if (candidates.len == 0) return null;
    var selected: usize = 0;
    var found_free = candidates[0].hasFreeWay();
    for (candidates[1..], 1..) |candidate, index| {
        const current = candidates[selected];
        if (candidate.hasFreeWay()) {
            // Prefer a free way, then the shallower set. Depth is what the
            // second choice is for; ties keep the first choice so placement
            // stays deterministic and reproducible across runs.
            if (!found_free or candidate.occupied < current.occupied) {
                selected = index;
                found_free = true;
            }
            continue;
        }
        if (found_free) continue;
        // Every choice so far is full: evict the least valuable resident.
        if (candidate.victim_reuse_count < current.victim_reuse_count or
            (candidate.victim_reuse_count == current.victim_reuse_count and
                !candidate.victim_recently_used and current.victim_recently_used))
        {
            selected = index;
        }
    }
    return selected;
}

/// A fill's cause is part of the cache boundary, not a post-hoc interpretation
/// of a page counter. A strict fault run is deliberately miss-intolerant, but
/// it can only be intolerant of misses a cache was ever in a position to
/// avoid: a cold eviction and every recurring class stop at the exact
/// instruction that paid for them, while a compulsory first touch is the one
/// permanent carve-out.
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
    /// Strict fault mode is intentionally stronger than the economics
    /// verdict. A cold eviction stops the run even though `recurring()` says
    /// it proves no hot conflict, because it is a decode the cache performed
    /// and then discarded, and it will be performed again if the address is
    /// reached twice.
    ///
    /// `vacant_fill` is the one permanent carve-out, and it is not a matter
    /// of taste. An instruction has to be decoded once; no cache size,
    /// associativity or replacement policy makes a first touch free. Arming
    /// this cause stops the very first guest instruction of every run — at
    /// step zero the cache is empty, so the first fill is necessarily vacant
    /// — which leaves the invariant unsatisfiable and an allow-list that
    /// disables it outright as the only usable configuration. `compulsory()`
    /// keeps the distinction visible and the economics report still counts
    /// every first touch, so the miss is observed rather than excused.
    pub fn requiresFailFast(self: Cause) bool {
        return switch (self) {
            .capacity_conflict,
            .cold_eviction,
            .stale_bytes,
            .flush_collateral,
            => true,
            .vacant_fill => false,
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
            .cold_eviction => "FATAL/DEFERRED: a non-empty, never-reused decode was displaced during warming; strict fault mode stops at the miss while retaining it as cold working-set evidence",
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
// reused. It stays out of `recurring()` for that reason and still stops a
// strict run, because the decode itself was performed and thrown away.
test "a cold eviction is fail-fast evidence and a compulsory fill is not" {
    try std.testing.expect(!Cause.cold_eviction.recurring());
    try std.testing.expect(Cause.cold_eviction.requiresFailFast());
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
    try std.testing.expect(shouldFailFast(.cold_eviction, .{ .strict = true, .fault_policy = true }));
    // And a compulsory miss never fails fast, whatever the gate says.
    try std.testing.expect(!shouldFailFast(.vacant_fill, .{ .strict = true, .fault_policy = true }));
}

// Banks are sized by measured demand, so the properties that used to follow
// from symmetry now have to be asserted. The 2026-09-07 census is the input:
// static 903,034 fills, dynamic 156,999, thunk 0, unknown 0, against an equal
// split that gave every domain 65,536 sets.
test "bank capacity follows demand and every bank can still hold a decode" {
    // The busiest domain gets the most room, and the two that recorded no
    // fills at all are no longer holding a quarter of the table each.
    try std.testing.expect(
        primary_layout.localSetCount(.static_image) > primary_layout.localSetCount(.dynamic_generated),
    );
    try std.testing.expect(
        primary_layout.localSetCount(.dynamic_generated) > primary_layout.localSetCount(.thunk_bridge),
    );

    // The observed working sets fit with room to grow. Occupancy is what the
    // eviction tail is driven by, so these are the numbers that matter, not
    // the absolute entry count.
    const static_occupancy = 903_034 * 100 /
        (primary_layout.localSetCount(.static_image) * primary_layout.ways);
    const dynamic_occupancy = 156_999 * 100 /
        (primary_layout.localSetCount(.dynamic_generated) * primary_layout.ways);
    try std.testing.expect(static_occupancy < 50);
    try std.testing.expect(dynamic_occupancy < 50);

    // No bank may be empty: `setIndexChoice` reduces modulo the bank's set
    // count, so a zero-set bank is a divide by zero for any address a future
    // classifier change routes there.
    for (all) |domain| {
        try std.testing.expect(primary_layout.localSetCount(domain) != 0);
        try std.testing.expect(victim_layout.localSetCount(domain) != 0);
    }

    // The unequal split still costs less memory than the equal one it
    // replaced: four banks of 65,536 sets was 262,144 sets in total.
    try std.testing.expect(primary_layout.totalSetCount() < (1 << 16) * domain_count);
    try std.testing.expect(primary_layout.wellFormed());

    // A bank with no sets is refused rather than silently mapped onto its
    // neighbour.
    const starved = Layout{
        .name = "starved",
        .bank_sets = .{ 1 << 10, 0, 1 << 4, 1 << 4 },
        .ways = 4,
        .banked = true,
        .kind = .victim,
    };
    try std.testing.expect(!starved.wellFormed());
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
    // Banks are unequal now, so the dynamic bank starts where the static bank
    // ends. Reproducing the old `bank * localSetCount` product here is exactly
    // the mistake `bankFirstSet` exists to prevent.
    try std.testing.expectEqual(
        static_base / primary_layout.ways + primary_layout.localSetCount(.static_image),
        dynamic_base / primary_layout.ways,
    );
    try std.testing.expectEqual(
        primary_layout.bankFirstSet(.dynamic_generated),
        primary_layout.localSetCount(.static_image),
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
    const source_set = primary_layout.setIndex(0x001c_bcca, .static_image);
    const victim_set = primary_layout.setIndex(0x0019_c23, .static_image);
    try std.testing.expect(source_set != victim_set);
    try std.testing.expectEqual(@as(usize, 1 << 17), primary_layout.localSetCount(.static_image));
    try std.testing.expectEqual(@as(usize, 1 << 12), victim_layout.localSetCount(.static_image));
}

test "graphics setup conflict pair is separated by the expanded static bank" {
    // Regression for the genuine 17th-resident overflow observed after
    // GraphicsSystem setup began. Both starts were static image code and
    // exhausted one 16-way set under the previous 32,768-set budget.
    const source_set = primary_layout.setIndex(0x00c3_42fc, .static_image);
    const victim_set = primary_layout.setIndex(0x009c_0618, .static_image);
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
                const set = base / primary_layout.ways;
                const first = primary_layout.bankFirstSet(domain);
                try std.testing.expect(set >= first);
                try std.testing.expect(set < first + primary_layout.localSetCount(domain));
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
    const source_set = primary_layout.setIndex(0x0027_5a10, .static_image);
    const victim_set = primary_layout.setIndex(0x001d_b24, .static_image);
    try std.testing.expect(source_set != victim_set);
}

test "previous static-init overflow pair is separated by the primary remap" {
    // This pair previously shared a set under the former primary seed. Once
    // the table is expanded, retain a deterministic separation regression so
    // a future mapper change cannot recreate that avoidable pressure hotspot.
    const source_set = primary_layout.setIndex(0x0014_1ff3, .static_image);
    const victim_set = primary_layout.setIndex(0x0018_a32, .static_image);
    try std.testing.expect(source_set != victim_set);
    try std.testing.expectEqual(@as(usize, 16), primary_layout.ways);
}

// Strict mode stops on every miss the cache could have avoided, while
// retaining the cause distinction needed to tell unavoidable first-touch work
// from avoidable reusable loss.
test "strict policy stops on every avoidable miss class" {
    const armed = FailFastGate{ .strict = true, .fault_policy = true };
    try std.testing.expect(shouldFailFast(.capacity_conflict, armed));
    try std.testing.expect(shouldFailFast(.stale_bytes, armed));
    try std.testing.expect(shouldFailFast(.flush_collateral, armed));
    try std.testing.expect(shouldFailFast(.cold_eviction, armed));
    try std.testing.expect(!shouldFailFast(.vacant_fill, armed));
    // A cold eviction still proves no hot conflict: the entry it displaced had
    // never been reused, and the two predicates must not be collapsed.
    try std.testing.expect(!Cause.cold_eviction.recurring());
    try std.testing.expect(!shouldFailFast(.capacity_conflict, .{ .strict = false, .fault_policy = true }));
    try std.testing.expect(!shouldFailFast(.capacity_conflict, .{ .strict = true, .fault_policy = false }));
    try std.testing.expect(!shouldFailFast(.capacity_conflict, .{ .strict = true, .fault_policy = true, .allowlisted = true }));
}

// The 2026-09-07 cold eviction. `spirv_cross::Parser::parse+0x397` at guest
// 0x11f7357 found both of its hashed sets holding sixteen residents each, and
// the run stopped on `cold-eviction` with `fills/vacant/conflict/cold =
// 470193/470192/0/1`. Nothing about that set was special: placement had been
// first-fit, so the second choice only ever saw an address whose first choice
// was already completely full.
test "placement compares the two set choices instead of filling the first" {
    const ways: usize = primary_layout.ways;

    // The regression itself. First fit puts this fill in choice 0 because a
    // way is free there; the second choice is three deep and is the right
    // answer.
    try std.testing.expectEqual(@as(?usize, 1), chooseSet(&.{
        .{ .occupied = 15, .ways = ways },
        .{ .occupied = 3, .ways = ways },
    }));

    // Ties keep the first choice, so placement stays reproducible.
    try std.testing.expectEqual(@as(?usize, 0), chooseSet(&.{
        .{ .occupied = 7, .ways = ways },
        .{ .occupied = 7, .ways = ways },
    }));

    // A full choice never wins against one with room, in either order.
    try std.testing.expectEqual(@as(?usize, 1), chooseSet(&.{
        .{ .occupied = ways, .ways = ways },
        .{ .occupied = 15, .ways = ways },
    }));
    try std.testing.expectEqual(@as(?usize, 0), chooseSet(&.{
        .{ .occupied = 15, .ways = ways },
        .{ .occupied = ways, .ways = ways },
    }));

    // Only when both are genuinely full does the victim comparison decide,
    // and that is the case strict policy is supposed to stop on.
    try std.testing.expectEqual(@as(?usize, 1), chooseSet(&.{
        .{ .occupied = ways, .ways = ways, .victim_reuse_count = 9 },
        .{ .occupied = ways, .ways = ways, .victim_reuse_count = 0 },
    }));
    try std.testing.expectEqual(@as(?usize, 1), chooseSet(&.{
        .{ .occupied = ways, .ways = ways, .victim_reuse_count = 4, .victim_recently_used = true },
        .{ .occupied = ways, .ways = ways, .victim_reuse_count = 4, .victim_recently_used = false },
    }));
    try std.testing.expectEqual(@as(?usize, null), chooseSet(&.{}));
}

// The measurement behind the rule above, run against the real mixer rather
// than argued from a distribution. The stream is the failing run's own demand:
// 903,034 static-image fills — the working set that bank held when the
// 2026-09-07 run stopped — placed into the static bank's real geometry.
//
// This asserts the pair of fixes together. First-fit at this density overflows
// a set and evicts; comparing the two choices holds the deepest set at 10 of
// 16 and evicts nothing. If a later change makes the deepest set reach `ways`
// again, that is the cold eviction coming back, and the run will stop on it.
test "two-choice placement keeps the observed demand inside the static bank" {
    const sets = primary_layout.localSetCount(.static_image);
    const ways = primary_layout.ways;
    // The static-image fill count at the 2026-09-07 stop.
    const fills: usize = 903_034;
    const load = &struct {
        var data: [1 << 17]u8 = undefined;
    }.data;
    try std.testing.expectEqual(load.len, sets);

    var deepest: usize = 0;
    var both_full: usize = 0;
    @memset(load, 0);
    var prng = std.Random.DefaultPrng.init(0x9E37_79B9_7F4A_7C15);
    const random = prng.random();
    for (0..fills) |_| {
        const address: u64 = 0x1e380 + random.uintLessThan(u64, 0xdc8bf7 - 0x1e380);
        const first = primary_layout.setIndexChoice(address, .static_image, 0);
        const second = primary_layout.setIndexChoice(address, .static_image, 1);
        const candidates = [_]SetOccupancy{
            .{ .occupied = load[first], .ways = ways },
            .{ .occupied = load[second], .ways = ways },
        };
        if (!candidates[0].hasFreeWay() and !candidates[1].hasFreeWay()) both_full += 1;
        const set = if (chooseSet(&candidates).? == 0) first else second;
        if (load[set] == ways) continue;
        load[set] += 1;
        deepest = @max(deepest, load[set]);
    }

    // No set reaches capacity, so no fill ever has to evict a resident, and
    // the bank is only 43% occupied when it holds the whole observed image.
    try std.testing.expect(deepest < ways);
    try std.testing.expectEqual(@as(usize, 0), both_full);
    try std.testing.expect(fills * 100 / (sets * ways) < 50);
}

// The 2026-09-07 step-zero fault. `requiresFailFast` had been widened to every
// cause, so the first fill of an empty cache — `___cxx_global_var_init.2` at
// guest 0x28a80, initializer 1 of 724, totals `fills/vacant=1/1` — raised
// SIGSEGV before a single guest instruction retired. No cache holds an address
// it has never seen, so this configuration cannot be satisfied by any run: the
// gate is either allow-listed away entirely or the process never starts.
//
// The test is written as the run's own first fill rather than as a predicate
// on the enum, because that is the fact that has to keep holding.
test "the first fill of an empty cache cannot terminate a strict run" {
    const armed = FailFastGate{ .strict = true, .fault_policy = true };
    const empty = [_]ReplacementState{.{ .occupied = false, .recently_used = false, .reuse_count = 0 }} ** primary_layout.ways;
    const choice = chooseReplacement(&empty).?;
    try std.testing.expect(choice.empty);

    // An empty way is a vacant fill by construction, and a vacant fill is
    // compulsory. The two together are what makes step zero survivable.
    const first_touch = Cause.vacant_fill;
    try std.testing.expect(first_touch.compulsory());
    try std.testing.expect(!shouldFailFast(first_touch, armed));

    // Exactly one cause is carved out. Anything else the cache discards is
    // still work it did and lost, and still stops the run.
    var carve_outs: usize = 0;
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const cause: Cause = @enumFromInt(field.value);
        if (!shouldFailFast(cause, armed)) carve_outs += 1;
        // Compulsory and fail-fast are exclusive: a miss no policy could have
        // avoided is never the thing that proves the policy wrong.
        try std.testing.expect(!(cause.compulsory() and cause.requiresFailFast()));
    }
    try std.testing.expectEqual(@as(usize, 1), carve_outs);
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
