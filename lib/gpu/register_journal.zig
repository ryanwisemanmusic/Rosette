//! Which Xenos registers the executed PM4 stream actually wrote.
//!
//! The run this exists for reports, in the same checkpoint:
//!
//! ```text
//! XENOS PACKET TRACE: classes(state/draw/...)=40/24/...
//! XENOS RETAINED BATCH: target(state/color/depth/surface)=NO/0x0/0x0/0x0
//! ```
//!
//! Forty state-programming packets executed and every render-target register
//! read zero. Exactly one of two things is true and nothing in the subsystem
//! could say which:
//!
//!   * the title programmed other registers and has genuinely not chosen a
//!     colour target yet — a **guest** fact, and the correct answer is to keep
//!     watching; or
//!   * the writes happened and landed somewhere the target reader does not
//!     look — a **harness** defect, and every downstream "no target" verdict is
//!     an artefact.
//!
//! A count of state packets cannot distinguish those. The register indices can,
//! and they are already flowing through the executor: nothing was recording
//! them. This journal records which blocks were touched, how many writes each
//! took, and the exact disposition of the render-target registers.
//!
//! Bucketed rather than per-register: the file has 0x5000 registers and a
//! per-register table would be 160 KB of mostly zeros on the hot state object.
//! Blocks are the granularity a reader reasons at, and the handful of registers
//! that decide the render target are tracked exactly alongside them.

const std = @import("std");
// The map package rather than `xenos_registers.zig`: the register file owns a
// journal, so depending on it here would be a cycle. Both files agree because
// both read the same package.
const registers = @import("xenos_register_map");

pub const Register = registers.Register;
pub const register_count = registers.register_count;

/// The immutable block ranges live with the hardware register map. The journal
/// owns observations, not a second copy of the classification table.
pub const Block = registers.Block;
pub const block_count = registers.block_count;
pub const blockOf = registers.blockOf;

/// The registers that decide whether a draw has somewhere to go. Tracked
/// exactly, because "the render backend block was touched" is not the same
/// claim as "a colour target was programmed".
pub const target_registers = [_]Register{
    registers.RB_SURFACE_INFO,
    registers.RB_COLOR_INFO,
    registers.RB_DEPTH_INFO,
};

pub const BlockRecord = struct {
    writes: u64 = 0,
    /// Writes whose block came from a Rosette semantic name. Exact Xenia-table
    /// entries without a functional owner are tracked separately so this
    /// counter never hides the difference between semantic ownership and exact
    /// hardware identity.
    named_writes: u64 = 0,
    /// Distinct registers seen in this block, capped at the sample width.
    /// A block written a thousand times at one index is a different shape from
    /// one written once at each of a thousand.
    distinct_sampled: u32 = 0,
    first_register: Register = 0,
    last_register: Register = 0,
    last_value: u32 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,

    pub fn touched(self: BlockRecord) bool {
        return self.writes != 0;
    }
};

pub const TargetRecord = struct {
    register: Register = 0,
    writes: u64 = 0,
    last_value: u32 = 0,
    /// Whether a write ever carried a non-zero value. A register written with
    /// zero is programmed and empty; one never written is unprogrammed. Those
    /// are different findings and a bare value cannot separate them.
    ever_nonzero: bool = false,
    last_step: u64 = 0,

    pub fn written(self: TargetRecord) bool {
        return self.writes != 0;
    }
};

/// What the journal concludes about the render target.
pub const Verdict = enum(u8) {
    /// No state write of any kind has been journalled.
    no_state_observed,
    /// State writes happened and none touched the render-backend block. The
    /// title has not chosen a target: a guest fact.
    target_never_addressed,
    /// The render-backend block was written but the target registers
    /// themselves were not. Also a guest fact, and a more specific one.
    block_touched_target_untouched,
    /// The target registers were written and every write carried zero. The
    /// title programmed a null target deliberately, or its values are being
    /// lost before they arrive.
    target_written_zero,
    /// The target registers hold non-zero values. If a reader elsewhere still
    /// reports no target, that reader is the defect.
    target_programmed,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .no_state_observed => "no-state-observed",
            .target_never_addressed => "target-never-addressed",
            .block_touched_target_untouched => "block-touched-target-untouched",
            .target_written_zero => "target-written-zero",
            .target_programmed => "target-programmed",
        };
    }

    /// Whose problem the verdict makes it. This is the question the journal
    /// was built to answer.
    pub fn owner(self: Verdict) []const u8 {
        return switch (self) {
            .no_state_observed => "harness: nothing executed, so nothing can be concluded about the title",
            .target_never_addressed, .block_touched_target_untouched => "guest: the title has not programmed a colour target",
            .target_written_zero => "evidence: a deliberate null target and a lost value look identical here; compare against the raw packet payload",
            .target_programmed => "harness: the registers hold a target, so any reader still reporting none is not reading these registers",
        };
    }

    pub fn guidance(self: Verdict) []const u8 {
        return switch (self) {
            .no_state_observed => "no state-programming write has been journalled. Every render-target verdict below is unobserved rather than false, and the first thing to check is whether the command processor executed at all",
            .target_never_addressed => "state writes executed and not one addressed the render-backend block. The title is programming other parts of the pipeline and has not chosen where pixels go; this is title progress, not a defect, and the next question is what it is waiting for before it does",
            .block_touched_target_untouched => "the render-backend block was written but the surface/colour/depth registers were not. The title is configuring the backend without naming a target yet",
            .target_written_zero => "the target registers were written and every value was zero. A title can legitimately program a null target, and a decode defect that drops payload looks exactly the same from here. Compare the journalled write count against the raw packet payload before blaming either side",
            .target_programmed => "the target registers hold non-zero values. A draw now has somewhere to go, and any component still reporting no render target is reading different state than the command processor wrote",
        };
    }
};

pub const Summary = struct {
    writes: u64 = 0,
    unknown_writes: u64 = 0,
    blocks_touched: usize = 0,
    target_writes: u64 = 0,
    target_nonzero: usize = 0,
    verdict: Verdict = .no_state_observed,
};

pub const Journal = struct {
    blocks: [block_count]BlockRecord = [_]BlockRecord{.{}} ** block_count,
    targets: [target_registers.len]TargetRecord = blk: {
        var initial: [target_registers.len]TargetRecord = undefined;
        for (target_registers, 0..) |register, index| {
            initial[index] = .{ .register = register };
        }
        break :blk initial;
    },
    writes: u64 = 0,
    /// Writes to an index outside the register file. These are dropped by the
    /// register file itself, so a non-zero count here is a decode defect that
    /// would otherwise be invisible.
    out_of_range_writes: u64 = 0,
    /// In-range writes whose block came from the range fallback. The residual
    /// guess in every block total below.
    range_classified_writes: u64 = 0,
    /// In-range writes that landed on an exact Xenia-table entry whose richer
    /// Rosette functional owner is not modeled yet. These are exact hardware
    /// observations, not unverified register indices, so PM4 safety gates must
    /// not confuse them with unknown input.
    exact_unowned_writes: u64 = 0,
    /// In-range writes that are neither named by Rosette nor present in the
    /// copied Xenia register table. This is the subset that remains an
    /// unverified register-vocabulary observation.
    unknown_in_range_writes: u64 = 0,
    /// A bounded bitmap of which 64-register groups were touched, so
    /// "distinct registers" is answerable without a 0x5000-entry table.
    group_bits: [register_count / 64 / 8]u8 = [_]u8{0} ** (register_count / 64 / 8),

    pub fn record(self: *Journal, register: Register, value: u32, step: u64) void {
        self.writes +|= 1;
        if (register >= register_count) {
            self.out_of_range_writes +|= 1;
            return;
        }

        const which_block = blockOf(register);
        const entry = &self.blocks[@intFromEnum(which_block)];
        if (entry.writes == 0) {
            entry.first_register = register;
            entry.first_step = step;
        }
        entry.writes +|= 1;
        entry.last_register = register;
        entry.last_value = value;
        entry.last_step = step;
        // Whether this index has a Rosette semantic name, is an exact Xenia
        // table entry without a functional owner, or is genuinely outside the
        // copied vocabulary. A block total assembled from the last category is
        // the only remaining range approximation.
        if (registers.namedBlock(register) != null) {
            entry.named_writes +|= 1;
        } else if (registers.isKnownHardwareRegister(register)) {
            self.exact_unowned_writes +|= 1;
        } else {
            self.range_classified_writes +|= 1;
            self.unknown_in_range_writes +|= 1;
        }

        // One bit per 64-register group. Cheap, bounded, and enough to tell a
        // thousand writes at one index from a thousand spread across the file.
        const group = @as(usize, register) / 64;
        const byte = group / 8;
        const bit = @as(u8, 1) << @intCast(group % 8);
        if (byte < self.group_bits.len and self.group_bits[byte] & bit == 0) {
            self.group_bits[byte] |= bit;
            entry.distinct_sampled +|= 1;
        }

        for (&self.targets) |*slot| {
            if (slot.register != register) continue;
            slot.writes +|= 1;
            slot.last_value = value;
            slot.last_step = step;
            if (value != 0) slot.ever_nonzero = true;
        }
    }

    pub fn recordRange(self: *Journal, start: Register, values: []const u32, step: u64) void {
        for (values, 0..) |value, index| {
            const register = @as(u32, start) + @as(u32, @intCast(index));
            if (register > std.math.maxInt(Register)) {
                self.out_of_range_writes +|= 1;
                continue;
            }
            self.record(@intCast(register), value, step);
        }
    }

    pub fn block(self: *const Journal, which: Block) BlockRecord {
        return self.blocks[@intFromEnum(which)];
    }

    pub fn target(self: *const Journal, register: Register) ?TargetRecord {
        for (self.targets) |entry| {
            if (entry.register == register) return entry;
        }
        return null;
    }

    pub fn verdict(self: *const Journal) Verdict {
        if (self.writes == 0) return .no_state_observed;

        var any_target_write = false;
        var any_target_nonzero = false;
        for (self.targets) |entry| {
            if (entry.written()) any_target_write = true;
            if (entry.ever_nonzero) any_target_nonzero = true;
        }
        if (any_target_nonzero) return .target_programmed;
        if (any_target_write) return .target_written_zero;
        if (self.block(.render_backend).touched()) return .block_touched_target_untouched;
        return .target_never_addressed;
    }

    pub fn summary(self: *const Journal) Summary {
        var totals = Summary{
            .writes = self.writes,
            .unknown_writes = self.out_of_range_writes,
            .verdict = self.verdict(),
        };
        for (self.blocks) |entry| {
            if (entry.touched()) totals.blocks_touched += 1;
        }
        for (self.targets) |entry| {
            totals.target_writes +|= entry.writes;
            if (entry.ever_nonzero) totals.target_nonzero += 1;
        }
        return totals;
    }
};

test "state writes that never address the backend are a guest fact" {
    // The live shape: forty state packets executed, none of them a target.
    var journal = Journal{};
    var index: u32 = 0;
    while (index < 40) : (index += 1) {
        journal.record(@intCast(0x4000 + index), 0x1234_0000 + index, 100 + index);
    }

    const totals = journal.summary();
    try std.testing.expectEqual(@as(u64, 40), totals.writes);
    try std.testing.expectEqual(Verdict.target_never_addressed, totals.verdict);
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict.owner(), "guest:") != null);
    try std.testing.expect(journal.block(.shader_constants).touched());
    try std.testing.expect(!journal.block(.render_backend).touched());
    try std.testing.expectEqual(@as(u64, 0), totals.target_writes);
}

test "a programmed target makes any contrary reader the defect" {
    var journal = Journal{};
    journal.record(registers.RB_SURFACE_INFO, 1280 | (2 << 16), 10);
    journal.record(registers.RB_COLOR_INFO, 0x101 | (6 << 16), 11);

    try std.testing.expectEqual(Verdict.target_programmed, journal.verdict());
    try std.testing.expect(std.mem.indexOf(u8, Verdict.target_programmed.owner(), "harness:") != null);
    const colour = journal.target(registers.RB_COLOR_INFO).?;
    try std.testing.expect(colour.written());
    try std.testing.expect(colour.ever_nonzero);
    try std.testing.expectEqual(@as(u64, 1), colour.writes);
}

test "a target written with zero is not the same as one never written" {
    var journal = Journal{};
    journal.record(registers.RB_COLOR_INFO, 0, 10);
    try std.testing.expectEqual(Verdict.target_written_zero, journal.verdict());
    const colour = journal.target(registers.RB_COLOR_INFO).?;
    try std.testing.expect(colour.written());
    try std.testing.expect(!colour.ever_nonzero);
    // The verdict deliberately refuses to blame either side here.
    try std.testing.expect(std.mem.indexOf(u8, Verdict.target_written_zero.owner(), "evidence:") != null);

    var untouched = Journal{};
    untouched.record(0x4000, 1, 10);
    try std.testing.expectEqual(Verdict.target_never_addressed, untouched.verdict());
    try std.testing.expect(!untouched.target(registers.RB_COLOR_INFO).?.written());
}

test "the backend block can be touched without a target being named" {
    var journal = Journal{};
    // A render-backend register that is not one of the three target
    // registers. `RB_DEPTHCONTROL` rather than a raw index: this test used to
    // pass `0x2080` under the belief that it was render-backend, and it is
    // `PA_SC_WINDOW_OFFSET` — scissor. The register map now says so, and
    // naming the constant is what stops the belief coming back.
    journal.record(registers.RB_DEPTHCONTROL, 0xFFFF_FFFF, 10);
    try std.testing.expectEqual(Verdict.block_touched_target_untouched, journal.verdict());
    try std.testing.expect(journal.block(.render_backend).touched());
    try std.testing.expect(std.mem.indexOf(u8, Verdict.block_touched_target_untouched.owner(), "guest:") != null);
}

// The reading that made the 2026-09-01 journal misleading: the title wrote
// scissor and viewport state and nothing in the render backend, and the report
// said the backend block had been written.
test "a title that programs only scissor has not touched the backend" {
    var journal = Journal{};
    journal.record(registers.PA_SC_WINDOW_OFFSET, 0, 10);
    journal.record(registers.PA_SC_WINDOW_SCISSOR_TL, 0, 11);
    journal.record(registers.PA_SC_WINDOW_SCISSOR_BR, 0x0500_0280, 12);
    journal.record(registers.PA_SC_SCREEN_SCISSOR_BR, 0x0500_0280, 13);

    try std.testing.expect(journal.block(.raster_setup).touched());
    try std.testing.expect(!journal.block(.render_backend).touched());
    try std.testing.expectEqual(@as(u64, 4), journal.writes);
    // With no backend write at all the verdict is the stronger statement, not
    // the one that says a block was touched.
    try std.testing.expect(journal.verdict() != .block_touched_target_untouched);
}

test "an out-of-range write is counted rather than lost" {
    // The register file silently drops these. A decode defect that aims writes
    // past the end of the file would otherwise look like a title that wrote
    // nothing.
    var journal = Journal{};
    journal.record(@intCast(register_count - 1), 1, 10);
    journal.record(0xFFFF, 1, 11);
    try std.testing.expectEqual(@as(u64, 1), journal.out_of_range_writes);
    try std.testing.expectEqual(@as(u64, 2), journal.writes);
    try std.testing.expectEqual(@as(u64, 1), journal.summary().unknown_writes);
}

test "distinct groups separate a hot register from a swept file" {
    var journal = Journal{};
    var repeat: u32 = 0;
    while (repeat < 500) : (repeat += 1) {
        journal.record(registers.RB_COLOR_INFO, repeat, 10);
    }
    // Five hundred writes, one group.
    try std.testing.expectEqual(@as(u32, 1), journal.block(.render_backend).distinct_sampled);

    var swept = Journal{};
    var index: u32 = 0;
    while (index < 500) : (index += 1) {
        swept.record(@intCast(0x4000 + index), 1, 10);
    }
    try std.testing.expect(swept.block(.shader_constants).distinct_sampled > 1);
}

test "a range write journals every register it covers" {
    var journal = Journal{};
    const values = [_]u32{ 1, 2, 3, 4, 5, 6 };
    journal.recordRange(registers.RB_SURFACE_INFO, &values, 20);
    try std.testing.expectEqual(@as(u64, 6), journal.writes);
    // The range covers all three target registers.
    try std.testing.expectEqual(Verdict.target_programmed, journal.verdict());
    try std.testing.expectEqual(@as(usize, 3), journal.summary().target_nonzero);
}

test "an empty journal concludes nothing about the title" {
    const journal = Journal{};
    const totals = journal.summary();
    try std.testing.expectEqual(Verdict.no_state_observed, totals.verdict);
    try std.testing.expectEqual(@as(usize, 0), totals.blocks_touched);
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict.owner(), "harness:") != null);
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict.guidance(), "unobserved rather than false") != null);
}

test "every block and verdict carries a label, meaning and owner" {
    inline for (@typeInfo(Block).@"enum".fields) |field| {
        const value: Block = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.meaning().len > 15);
    }
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const value: Verdict = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.owner().len > 15);
        try std.testing.expect(value.guidance().len > 40);
    }
    // The target registers must all classify into the render backend, or the
    // block ranges and the target list have drifted apart.
    for (target_registers) |register| {
        try std.testing.expectEqual(Block.render_backend, blockOf(register));
    }
}

// A block total assembled from ranges is a guess about an interleaved index
// space, and the 2026-09-01 report read very differently once that was
// visible: `render-backend writes=10 first=0x2080` was ten scissor writes.
test "a block says how much of its total was classified by name" {
    var journal = Journal{};
    journal.record(registers.RB_COLOR_INFO, 0x1234, 10);
    journal.record(registers.RB_DEPTHCONTROL, 0x5678, 11);
    // An index nothing names, inside the render-backend range.
    journal.record(0x2050, 1, 12);

    const backend = journal.block(.render_backend);
    try std.testing.expectEqual(@as(u64, 3), backend.writes);
    try std.testing.expectEqual(@as(u64, 2), backend.named_writes);
    try std.testing.expectEqual(@as(u64, 1), journal.range_classified_writes);

    // An out-of-range write is neither: it never reached a block at all.
    journal.record(0xFFFF, 1, 13);
    try std.testing.expectEqual(@as(u64, 1), journal.out_of_range_writes);
    try std.testing.expectEqual(@as(u64, 1), journal.range_classified_writes);
}

test "exact Xenia entries do not count as unknown vocabulary" {
    var journal = Journal{};
    // 0x0A30 is present in Xenia's exact table but has no Rosette
    // functional name. It must therefore be exact hardware identity without
    // being mistaken for a range approximation.
    journal.record(0x0A30, 1, 10);
    try std.testing.expectEqual(@as(u64, 1), journal.exact_unowned_writes);
    try std.testing.expectEqual(@as(u64, 0), journal.unknown_in_range_writes);
    try std.testing.expectEqual(@as(u64, 0), journal.range_classified_writes);

    journal.record(0x0A32, 1, 11);
    try std.testing.expectEqual(@as(u64, 1), journal.exact_unowned_writes);
    try std.testing.expectEqual(@as(u64, 1), journal.unknown_in_range_writes);
    try std.testing.expectEqual(@as(u64, 1), journal.range_classified_writes);
}
