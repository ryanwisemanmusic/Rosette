//! How much of the generated code the bounded machine can actually get through.
//!
//! The transducer reports each fault it meets, one at a time, and each report
//! reads the same as the last. What it never reported is *scope*: whether the
//! run is meeting one stubborn site or forty, whether the sites it halts on are
//! the ones it already halted on, and how the count of sites it can traverse
//! compares to the count it cannot. Without that, every occurrence looks like
//! the first occurrence, and the same investigation is repeated forever.
//!
//! A census answers it in one line. Sites are identified by the instruction
//! address, grouped by the generated block containing them, and each carries how
//! often it was reached, how often the machine got through, and how often it
//! stopped. The useful number is not the total of faults — a hot site inflates
//! that — but the number of *distinct sites*, split by whether any recovery has
//! ever succeeded there:
//!
//!   * **clean** — reached and always traversed. The machine covers it.
//!   * **mixed** — sometimes traversed, sometimes not. A shape the machine
//!     recognises under some register states and not others; usually the most
//!     informative category, because the difference between the two is the bug.
//!   * **halting** — reached and never traversed. These are the gaps, and their
//!     count is the size of the problem.
//!
//! Bounded and zero-allocation: it is consulted from fault paths, and a census
//! that can grow without limit is a memory leak with a report attached.

const std = @import("std");

/// Which owner acted, or refused to. Deliberately open-ended in meaning — this
/// module does not know what the families do, only that they are distinct and
/// that attributing an outcome to one of them is what makes the census
/// actionable rather than a total.
pub const Family = enum(u8) {
    unknown,
    /// The transducer proved a continuation.
    bounded_dispatch,
    /// A guest return executed as a dispatch because the target register held a
    /// byte-reversed address.
    missed_guest_return,
    /// A base register holding a byte-reversed guest address was corrected and
    /// the access re-executed.
    byte_order_repair,
    /// The endian contract repaired a swapped effective address.
    endian_contract,
    /// A null indirect transfer was skipped and the frame returned.
    null_indirect_transfer,
    /// A generated dispatch to an unpatched guest sentinel.
    guest_dispatch_miss,
    /// A small scalar load from a null base was satisfied as zero.
    null_scalar_read,
};

pub const Outcome = enum(u8) {
    /// The machine got through: execution continued past the site.
    traversed,
    /// The machine stopped. Either a recovery refused, or none claimed it.
    halted,
};

pub const Site = struct {
    rip: u64 = 0,
    /// Start of the reconstructed generated block containing `rip`, when known.
    /// Zero means the block could not be reconstructed, which is itself worth
    /// distinguishing from "block starts at zero".
    block_start: u64 = 0,
    observations: u32 = 0,
    traversals: u32 = 0,
    halts: u32 = 0,
    /// The family that most recently acted, so a mixed site can be read without
    /// keeping a full history.
    last_family: Family = .unknown,
    /// Caller-defined reason code for the most recent halt. Opaque here: the
    /// census does not interpret it, it just carries it so the report can.
    last_halt_reason: u16 = 0,

    pub fn clean(self: Site) bool {
        return self.traversals != 0 and self.halts == 0;
    }

    pub fn halting(self: Site) bool {
        return self.halts != 0 and self.traversals == 0;
    }

    pub fn mixed(self: Site) bool {
        return self.traversals != 0 and self.halts != 0;
    }
};

/// Fixed capacity. Generated code has far more dispatch sites than this, but
/// the ones a bounded machine *meets* are few — and a census that evicts is
/// still a census, as long as it says so.
pub const max_sites: usize = 64;

pub const Census = struct {
    sites: [max_sites]Site = [_]Site{.{}} ** max_sites,
    count: usize = 0,
    /// Sites that arrived after the table was full. Their observations are
    /// still counted in the totals; only their per-site detail is lost.
    overflow_sites: u64 = 0,
    observations: u64 = 0,
    traversals: u64 = 0,
    halts: u64 = 0,
    /// Per-family traversal counts, so "the machine got through" can be
    /// attributed rather than asserted.
    by_family: [@typeInfo(Family).@"enum".fields.len]u64 =
        [_]u64{0} ** @typeInfo(Family).@"enum".fields.len,

    pub fn note(
        self: *Census,
        rip: u64,
        block_start: u64,
        family: Family,
        outcome: Outcome,
        halt_reason: u16,
    ) void {
        self.observations +|= 1;
        switch (outcome) {
            .traversed => {
                self.traversals +|= 1;
                self.by_family[@intFromEnum(family)] +|= 1;
            },
            .halted => self.halts +|= 1,
        }

        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const site = &self.sites[index];
            if (site.rip != rip) continue;
            site.observations +|= 1;
            site.last_family = family;
            switch (outcome) {
                .traversed => site.traversals +|= 1,
                .halted => {
                    site.halts +|= 1;
                    site.last_halt_reason = halt_reason;
                },
            }
            // A block start learned later is still worth keeping.
            if (site.block_start == 0 and block_start != 0) site.block_start = block_start;
            return;
        }
        if (self.count == self.sites.len) {
            self.overflow_sites +|= 1;
            return;
        }
        self.sites[self.count] = .{
            .rip = rip,
            .block_start = block_start,
            .observations = 1,
            .traversals = if (outcome == .traversed) 1 else 0,
            .halts = if (outcome == .halted) 1 else 0,
            .last_family = family,
            .last_halt_reason = if (outcome == .halted) halt_reason else 0,
        };
        self.count += 1;
    }

    pub const Coverage = struct {
        sites: usize = 0,
        clean: usize = 0,
        mixed: usize = 0,
        halting: usize = 0,
    };

    pub fn coverage(self: *const Census) Coverage {
        var result = Coverage{ .sites = self.count };
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const site = self.sites[index];
            if (site.clean()) {
                result.clean += 1;
            } else if (site.mixed()) {
                result.mixed += 1;
            } else if (site.halting()) {
                result.halting += 1;
            }
        }
        return result;
    }

    /// Coverage restricted to one generated block: the answer to "how much of
    /// the code I am trying to get through can I get through". `block_start` of
    /// zero matches only sites whose block could not be reconstructed.
    pub fn coverageForBlock(self: *const Census, block_start: u64) Coverage {
        var result = Coverage{};
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const site = self.sites[index];
            if (site.block_start != block_start) continue;
            result.sites += 1;
            if (site.clean()) {
                result.clean += 1;
            } else if (site.mixed()) {
                result.mixed += 1;
            } else if (site.halting()) {
                result.halting += 1;
            }
        }
        return result;
    }

    pub fn find(self: *const Census, rip: u64) ?Site {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.sites[index].rip == rip) return self.sites[index];
        }
        return null;
    }
};

test "a site traversed every time is clean and a site never traversed is halting" {
    var census = Census{};
    census.note(0xa000_1000, 0xa000_0f00, .bounded_dispatch, .traversed, 0);
    census.note(0xa000_1000, 0xa000_0f00, .bounded_dispatch, .traversed, 0);
    census.note(0xa000_2000, 0xa000_0f00, .unknown, .halted, 7);

    const coverage = census.coverage();
    try std.testing.expectEqual(@as(usize, 2), coverage.sites);
    try std.testing.expectEqual(@as(usize, 1), coverage.clean);
    try std.testing.expectEqual(@as(usize, 1), coverage.halting);
    try std.testing.expectEqual(@as(usize, 0), coverage.mixed);
    try std.testing.expectEqual(@as(u64, 3), census.observations);
    try std.testing.expectEqual(@as(u64, 2), census.traversals);
    try std.testing.expectEqual(@as(u64, 1), census.halts);
}

// The category that carries the most information: the same instruction is
// sometimes traversable and sometimes not, so the difference between the two
// register states is the defect.
test "a site that sometimes traverses is mixed, not counted as either" {
    var census = Census{};
    census.note(0xa000_3000, 0, .byte_order_repair, .traversed, 0);
    census.note(0xa000_3000, 0, .unknown, .halted, 3);

    const coverage = census.coverage();
    try std.testing.expectEqual(@as(usize, 1), coverage.sites);
    try std.testing.expectEqual(@as(usize, 0), coverage.clean);
    try std.testing.expectEqual(@as(usize, 0), coverage.halting);
    try std.testing.expectEqual(@as(usize, 1), coverage.mixed);

    const site = census.find(0xa000_3000) orelse return error.TestFailed;
    try std.testing.expect(site.mixed());
    try std.testing.expectEqual(@as(u16, 3), site.last_halt_reason);
}

test "coverage can be asked about one block" {
    var census = Census{};
    census.note(0xa000_1000, 0xa000_0f00, .bounded_dispatch, .traversed, 0);
    census.note(0xa000_1010, 0xa000_0f00, .unknown, .halted, 1);
    census.note(0xa000_9000, 0xa000_8f00, .unknown, .halted, 2);

    const block = census.coverageForBlock(0xa000_0f00);
    try std.testing.expectEqual(@as(usize, 2), block.sites);
    try std.testing.expectEqual(@as(usize, 1), block.clean);
    try std.testing.expectEqual(@as(usize, 1), block.halting);

    const other = census.coverageForBlock(0xa000_8f00);
    try std.testing.expectEqual(@as(usize, 1), other.sites);
    try std.testing.expectEqual(@as(usize, 1), other.halting);
}

test "traversals are attributed to the family that achieved them" {
    var census = Census{};
    census.note(0xa000_1000, 0, .byte_order_repair, .traversed, 0);
    census.note(0xa000_1004, 0, .byte_order_repair, .traversed, 0);
    census.note(0xa000_1008, 0, .missed_guest_return, .traversed, 0);
    try std.testing.expectEqual(@as(u64, 2), census.by_family[@intFromEnum(Family.byte_order_repair)]);
    try std.testing.expectEqual(@as(u64, 1), census.by_family[@intFromEnum(Family.missed_guest_return)]);
    try std.testing.expectEqual(@as(u64, 0), census.by_family[@intFromEnum(Family.bounded_dispatch)]);
}

test "a block start learned after the first observation is retained" {
    var census = Census{};
    census.note(0xa000_1000, 0, .unknown, .halted, 1);
    census.note(0xa000_1000, 0xa000_0f00, .unknown, .halted, 1);
    const site = census.find(0xa000_1000) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 0xa000_0f00), site.block_start);
}

test "capacity is bounded and overflow keeps the totals honest" {
    var census = Census{};
    var index: usize = 0;
    while (index < max_sites) : (index += 1) {
        census.note(0xa000_0000 + index * 4, 0, .unknown, .halted, 0);
    }
    try std.testing.expectEqual(max_sites, census.count);
    try std.testing.expectEqual(@as(u64, 0), census.overflow_sites);

    census.note(0xb000_0000, 0, .unknown, .halted, 0);
    try std.testing.expectEqual(@as(u64, 1), census.overflow_sites);
    // The totals still count it; only the per-site row is lost.
    try std.testing.expectEqual(@as(u64, max_sites + 1), census.observations);
    try std.testing.expectEqual(@as(u64, max_sites + 1), census.halts);
    try std.testing.expectEqual(max_sites, census.coverage().sites);
}
