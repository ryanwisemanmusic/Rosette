//! Where a sampled instruction pointer actually was, and whether it may be
//! quoted as the guest's location.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run's final crash report names Xenia's
//! `RegisterAllocationPass::AdvanceUses`. Earlier measurements in the same
//! project showed Xbyak emission and register allocation dominating host time.
//! Neither of those is guest code, and a report that says "the guest is
//! stalled at ..." over a host JIT symbol sends the next reader after a
//! deadlock that is really a throughput problem.
//!
//! Some samples are worse than wrong: they are seeded. A program counter
//! carried forward from an earlier observation names an instruction that is
//! not the one executing, and it does so with the same confident formatting as
//! a real one.
//!
//! The rule
//! --------
//! Every sample states a provenance and a quality, and "the guest is here"
//! requires both — guest-domain provenance *and* a trustworthy quality. A
//! sample that fails either is labelled a host-observed wait with no guest
//! proof, which is a weaker and true statement instead of a strong false one.
//! Where the program counter cannot be cited, the link register still can be:
//! it is written by the call instruction itself and names the caller.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const CodeLocation = bridge.contract.CodeLocation;
pub const Provenance = CodeLocation.Provenance;
pub const Quality = CodeLocation.Quality;

pub const provenance_count: usize = @typeInfo(Provenance).@"enum".fields.len;

/// A translation block, so a translated sample can name the guest range it
/// came from rather than only its host address.
pub const Block = struct {
    id: u64 = 0,
    generation: u64 = 0,
    guest_start: u32 = 0,
    guest_end: u32 = 0,
    host_start: u64 = 0,
    host_end: u64 = 0,
    module_id: u32 = 0,
    /// Whether the mapping was validated rather than assumed. An unvalidated
    /// map resolves an address to a guest range that may not be its own.
    validated: bool = false,

    pub fn containsHost(self: Block, rip: u64) bool {
        return self.host_start != 0 and rip >= self.host_start and rip < self.host_end;
    }

    pub fn guestFor(self: Block, rip: u64) ?u32 {
        if (!self.containsHost(rip)) return null;
        if (!self.validated) return null;
        if (self.guest_start == 0) return null;
        return self.guest_start;
    }
};

/// What a report may say about one sample.
pub const Citation = enum(u8) {
    /// A guest address with a module, safe to print as the guest's location.
    guest_location,
    /// The program counter cannot be cited and the link register names the
    /// caller. A reader can still look this up in the title.
    guest_call_site,
    /// Host code. Naming it as a guest location is the defect this prevents.
    host_location,
    /// Nothing usable.
    unlocatable,

    pub fn label(self: Citation) []const u8 {
        return switch (self) {
            .guest_location => "guest-location",
            .guest_call_site => "guest-call-site",
            .host_location => "host-location",
            .unlocatable => "unlocatable",
        };
    }

    pub fn describe(self: Citation) []const u8 {
        return switch (self) {
            .guest_location => "a guest instruction with an address and a module. A report may say the guest is here",
            .guest_call_site => "the program counter is seeded or unavailable and the link register still names the caller, because the call instruction writes it. Look that address up in the title rather than treating the waiter as unlocatable",
            .host_location => "this sample is host code — the runtime, the emulator, its JIT, or a system library. A wait reported at this address is a host-observed wait with no guest proof, and a compiler loop here is a throughput finding rather than a deadlock",
            .unlocatable => "no address of any kind is available. The sample says a thread exists and nothing about where it is",
        };
    }

    /// Whether a "the guest stalled here" claim may cite this sample.
    pub fn namesGuest(self: Citation) bool {
        return self == .guest_location or self == .guest_call_site;
    }
};

/// Decide what one location may be cited as.
pub fn cite(location: CodeLocation) Citation {
    if (location.citableAsGuestLocation()) return .guest_location;
    if (location.provenanceOf().namesGuestCode() and location.guest_lr != 0) return .guest_call_site;
    if (location.host_rip != 0) return .host_location;
    if (location.guest_lr != 0) return .guest_call_site;
    return .unlocatable;
}

pub const max_blocks: usize = 32;

pub const Summary = struct {
    samples: u64 = 0,
    guest_locations: u64 = 0,
    guest_call_sites: u64 = 0,
    host_locations: u64 = 0,
    unlocatable: u64 = 0,
    by_provenance: [provenance_count]u64 = [_]u64{0} ** provenance_count,
    /// Samples whose host address fell in no known block. A host RIP that no
    /// map claims is not a guest address by default.
    unmapped_host: u64 = 0,
    /// Claims a report tried to make and the ledger refused.
    refused_guest_claims: u64 = 0,

    /// The share of samples that could name a guest location at all. A run
    /// that cannot locate the guest is not a run whose guest is idle.
    pub fn guestLocatablePercent(self: Summary) u64 {
        if (self.samples == 0) return 0;
        const located = self.guest_locations +| self.guest_call_sites;
        return (located *| 100) / self.samples;
    }
};

fn provenanceIndex(which: Provenance) usize {
    inline for (@typeInfo(Provenance).@"enum".fields, 0..) |field, position| {
        if (field.value == @intFromEnum(which)) return position;
    }
    return provenance_count - 1;
}

pub const Ledger = struct {
    blocks: [max_blocks]Block = [_]Block{.{}} ** max_blocks,
    block_count: usize = 0,
    blocks_dropped: u64 = 0,
    totals: Summary = .{},

    pub fn declareBlock(self: *Ledger, block: Block) bool {
        if (self.block_count >= max_blocks) {
            self.blocks_dropped +|= 1;
            return false;
        }
        self.blocks[self.block_count] = block;
        self.block_count += 1;
        return true;
    }

    pub fn blockFor(self: *const Ledger, rip: u64) ?Block {
        var index: usize = 0;
        while (index < self.block_count) : (index += 1) {
            if (self.blocks[index].containsHost(rip)) return self.blocks[index];
        }
        return null;
    }

    /// Resolve a raw host address into a location, using the block map when
    /// one claims it. An address no validated block claims stays host code.
    pub fn resolve(self: *const Ledger, rip: u64, guest_lr: u32) CodeLocation {
        if (self.blockFor(rip)) |block| {
            if (block.guestFor(rip)) |guest_pc| {
                return .{
                    .guest_pc = guest_pc,
                    .guest_lr = guest_lr,
                    .host_rip = rip,
                    .module_id = block.module_id,
                    .provenance = @intFromEnum(Provenance.translated_block),
                    .quality = @intFromEnum(Quality.tracked),
                };
            }
        }
        return .{
            .guest_lr = guest_lr,
            .host_rip = rip,
            .provenance = @intFromEnum(Provenance.unknown),
            .quality = @intFromEnum(Quality.unavailable),
        };
    }

    pub fn observe(self: *Ledger, location: CodeLocation) Citation {
        self.totals.samples +|= 1;
        self.totals.by_provenance[provenanceIndex(location.provenanceOf())] +|= 1;
        if (location.host_rip != 0 and self.blockFor(location.host_rip) == null) {
            self.totals.unmapped_host +|= 1;
        }
        const citation = cite(location);
        switch (citation) {
            .guest_location => self.totals.guest_locations +|= 1,
            .guest_call_site => self.totals.guest_call_sites +|= 1,
            .host_location => self.totals.host_locations +|= 1,
            .unlocatable => self.totals.unlocatable +|= 1,
        }
        return citation;
    }

    /// Ask whether a report may say the guest is stalled here. A refusal is
    /// counted, because a refused claim and a claim nobody made look the same
    /// in a report that only prints what it accepted.
    pub fn mayCiteAsGuestStall(self: *Ledger, location: CodeLocation) bool {
        if (cite(location).namesGuest()) return true;
        self.totals.refused_guest_claims +|= 1;
        return false;
    }

    pub fn summary(self: *const Ledger) Summary {
        return self.totals;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = self.totals.samples;
        hash = hash *% 31 +% self.totals.guest_locations;
        hash = hash *% 31 +% self.totals.host_locations;
        hash = hash *% 31 +% self.totals.refused_guest_claims;
        return hash;
    }
};

// The exact 2026-08-31 crash-report shape: a JIT symbol sampled while the
// investigation was looking for a guest deadlock.
test "a JIT compiler sample is never a guest stall" {
    var ledger = Ledger{};
    const jit = CodeLocation{
        .host_rip = 0x1_0000,
        .provenance = @intFromEnum(Provenance.xenia_jit),
        .quality = @intFromEnum(Quality.direct),
    };
    try std.testing.expectEqual(Citation.host_location, ledger.observe(jit));
    try std.testing.expect(!ledger.mayCiteAsGuestStall(jit));
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().refused_guest_claims);
    try std.testing.expect(std.mem.indexOf(u8, Citation.host_location.describe(), "throughput finding") != null);
}

test "a seeded program counter falls back to the link register" {
    var ledger = Ledger{};
    const seeded = CodeLocation{
        .guest_pc = 0x8258_A470,
        .guest_lr = 0x825A_E908,
        .provenance = @intFromEnum(Provenance.guest_instruction),
        .quality = @intFromEnum(Quality.seeded),
    };
    try std.testing.expectEqual(Citation.guest_call_site, ledger.observe(seeded));
    try std.testing.expect(ledger.mayCiteAsGuestStall(seeded));
    try std.testing.expectEqual(@as(u32, 0x825A_E908), seeded.fallbackCallSite().?);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().refused_guest_claims);
}

test "a direct guest sample is citable and a tracked one is too" {
    var ledger = Ledger{};
    const direct = CodeLocation{
        .guest_pc = 0x8209_6008,
        .module_id = 1,
        .provenance = @intFromEnum(Provenance.guest_instruction),
        .quality = @intFromEnum(Quality.direct),
    };
    try std.testing.expectEqual(Citation.guest_location, ledger.observe(direct));
    const tracked = CodeLocation{
        .guest_pc = 0x8209_6008,
        .provenance = @intFromEnum(Provenance.translated_block),
        .quality = @intFromEnum(Quality.tracked),
    };
    try std.testing.expectEqual(Citation.guest_location, ledger.observe(tracked));
    try std.testing.expectEqual(@as(u64, 2), ledger.summary().guest_locations);
    try std.testing.expectEqual(@as(u64, 100), ledger.summary().guestLocatablePercent());
}

test "an unvalidated block never turns a host address into a guest one" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.declareBlock(.{
        .id = 1,
        .guest_start = 0x8258_2A98,
        .guest_end = 0x8258_2B00,
        .host_start = 0x2_0000,
        .host_end = 0x2_0100,
        .module_id = 7,
        .validated = false,
    }));
    const unvalidated = ledger.resolve(0x2_0010, 0);
    try std.testing.expectEqual(Provenance.unknown, unvalidated.provenanceOf());
    try std.testing.expectEqual(Citation.host_location, cite(unvalidated));

    ledger.blocks[0].validated = true;
    const validated = ledger.resolve(0x2_0010, 0x825A_E908);
    try std.testing.expectEqual(Provenance.translated_block, validated.provenanceOf());
    try std.testing.expectEqual(@as(u32, 0x8258_2A98), validated.guest_pc);
    try std.testing.expectEqual(Citation.guest_location, cite(validated));
    try std.testing.expectEqual(@as(u32, 7), validated.module_id);
}

test "a host address no block claims is counted as unmapped" {
    var ledger = Ledger{};
    _ = ledger.observe(.{ .host_rip = 0x9999, .provenance = @intFromEnum(Provenance.native_library) });
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().unmapped_host);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().host_locations);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().guestLocatablePercent());
}

test "a sample with nothing in it is unlocatable rather than guest code" {
    var ledger = Ledger{};
    try std.testing.expectEqual(Citation.unlocatable, ledger.observe(.{}));
    try std.testing.expect(!ledger.mayCiteAsGuestStall(.{}));
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().unlocatable);
}

test "the block map is bounded and says what it could not hold" {
    var ledger = Ledger{};
    var index: usize = 0;
    while (index < max_blocks) : (index += 1) {
        try std.testing.expect(ledger.declareBlock(.{ .id = index + 1, .host_start = 1, .host_end = 2 }));
    }
    try std.testing.expect(!ledger.declareBlock(.{ .id = 999 }));
    try std.testing.expectEqual(@as(u64, 1), ledger.blocks_dropped);
}

test "every provenance and citation states its own vocabulary" {
    inline for (@typeInfo(Provenance).@"enum".fields) |field| {
        const which: Provenance = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Citation).@"enum".fields) |field| {
        const which: Citation = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
    // Only the two guest provenances may name guest code.
    try std.testing.expect(Provenance.guest_instruction.namesGuestCode());
    try std.testing.expect(Provenance.translated_block.namesGuestCode());
    try std.testing.expect(!Provenance.xenia_jit.namesGuestCode());
    try std.testing.expect(!Provenance.rosette_runtime.namesGuestCode());
}
