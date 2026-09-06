//! Which Xenos registers were programmed, by whom, and whether the values
//! describe somewhere real.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run executed 156 register writes and left the three target
//! registers — `RB_SURFACE_INFO`, `RB_COLOR_INFO`, `RB_COLOR1_INFO` — never
//! written. A count of register writes said the GPU was being programmed and
//! could not say that the part deciding where pixels land was untouched.
//!
//! The other half is provenance. A register written by a PM4 packet and a
//! register written through the MMIO aperture are different routes with
//! different owners, and a report that counts them together cannot say that a
//! title programming its GPU through the ring leaves the aperture at zero
//! forever. That zero was read as "the title never reached its register
//! writes" in an earlier pass, which is a conclusion about a path this
//! observer does not own.
//!
//! So a register carries its domain, its write route, and whether the value is
//! valid for its domain. `unclassified` is a real outcome and is never folded
//! into a healthy count.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;

/// Which functional block a register belongs to. Wrong domains produce
/// counters that add unrelated state together.
pub const Domain = enum(u8) {
    /// Ring and command-processor control.
    command_processor = 0,
    /// Where pixels land: colour, depth, surface, masks.
    render_backend = 1,
    /// Viewport, scissor and rasteriser state.
    raster_setup = 2,
    /// Vertex and index fetch, draw initiation.
    geometry = 3,
    /// Shader program selection and export setup.
    shader_control = 4,
    /// Float, boolean and loop constants.
    shader_constants = 5,
    /// Texture and vertex fetch descriptors.
    fetch_constants = 6,
    /// Inside the register file and outside every known block.
    unclassified = 255,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .command_processor => "command-processor",
            .render_backend => "render-backend",
            .raster_setup => "raster-setup",
            .geometry => "geometry",
            .shader_control => "shader-control",
            .shader_constants => "shader-constants",
            .fetch_constants => "fetch-constants",
            .unclassified => "unclassified",
        };
    }

    /// Whether this domain has to be programmed before a draw can land
    /// anywhere. Used to separate "the GPU is being configured" from "the
    /// destination has been chosen".
    pub fn requiredForOutput(self: Domain) bool {
        return self == .render_backend;
    }
};

pub const domain_count: usize = @typeInfo(Domain).@"enum".fields.len;

/// How a register value arrived.
pub const Route = enum(u8) {
    /// A guest store into the register aperture.
    mmio_aperture = 0,
    /// A register write carried in the PM4 stream. The normal path.
    pm4_stream = 1,
    /// Rosette's model executing a retained batch.
    model_replay = 2,
    /// The harness wrote it.
    harness = 3,
    unknown = 255,

    pub fn label(self: Route) []const u8 {
        return switch (self) {
            .mmio_aperture => "mmio-aperture",
            .pm4_stream => "pm4-stream",
            .model_replay => "model-replay",
            .harness => "harness",
            .unknown => "unknown",
        };
    }

    pub fn sourceClass(self: Route) SourceClass {
        return switch (self) {
            .mmio_aperture, .pm4_stream => .guest_authentic,
            .model_replay => .replay,
            .harness => .synthetic,
            .unknown => .unknown,
        };
    }
};

/// The three registers that decide where a draw lands. Named individually
/// because "the render backend block was written" is true when only a scissor
/// register was touched.
pub const target_registers = [_]u16{ 0x2000, 0x2001, 0x2002 };

/// One register's history.
pub const Record = struct {
    index: u16 = 0,
    domain: Domain = .unclassified,
    writes: u64 = 0,
    last_value: u32 = 0,
    ever_nonzero: bool = false,
    first_step: u64 = 0,
    last_step: u64 = 0,
    route: Route = .unknown,
    /// Writes whose value the decoder could not validate for its domain.
    invalid_values: u64 = 0,

    pub fn written(self: Record) bool {
        return self.writes != 0;
    }
};

pub const max_records: usize = 96;

pub const Summary = struct {
    writes: u64 = 0,
    distinct: usize = 0,
    dropped: u64 = 0,
    by_domain: [domain_count]u64 = [_]u64{0} ** domain_count,
    by_route: [5]u64 = [_]u64{0} ** 5,
    out_of_range: u64 = 0,
    invalid_values: u64 = 0,
    target_writes: u64 = 0,
    target_nonzero: usize = 0,

    /// A title that programs through the ring leaves the aperture at zero
    /// forever, so an aperture count of zero beside a busy PM4 count is the
    /// normal shape and not an absence of register programming.
    pub fn apertureSilentWhilePm4Busy(self: Summary) bool {
        return self.by_route[@intFromEnum(Route.mmio_aperture)] == 0 and
            self.by_route[@intFromEnum(Route.pm4_stream)] != 0;
    }
};

/// What the register file as a whole says.
pub const Verdict = enum(u8) {
    /// Nothing has written a register.
    untouched,
    /// Registers are being written and no target register has been.
    configured_without_a_target,
    /// A target register was written and holds zero.
    target_named_as_zero,
    /// A target register holds a non-zero value.
    target_programmed,
    /// Registers were written outside the known file.
    out_of_range_writes,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .untouched => "untouched",
            .configured_without_a_target => "CONFIGURED-WITHOUT-A-TARGET",
            .target_named_as_zero => "TARGET-NAMED-AS-ZERO",
            .target_programmed => "target-programmed",
            .out_of_range_writes => "OUT-OF-RANGE-WRITES",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .untouched => "no register has been written by any route. The GPU has not been programmed, and that is a fact about the title rather than about this observer",
            .configured_without_a_target => "the backend is being configured and the surface, colour and depth registers are untouched. The title is setting up the GPU without naming where pixels go; a draw issued in this state legitimately lands nowhere",
            .target_named_as_zero => "a target register was written with zero. That is a decoded value and not a destination, and a draw against it has nowhere to land",
            .target_programmed => "a target register holds a non-zero value. The title has named a destination",
            .out_of_range_writes => "a write landed outside the Xenos register file. Either the packet stream is desynchronised or the decoder's register map is wrong, and neither state supports a conclusion about what was programmed",
        };
    }

    pub fn owner(self: Verdict) []const u8 {
        return switch (self) {
            .untouched, .configured_without_a_target, .target_named_as_zero => "guest:title",
            .target_programmed => "-",
            .out_of_range_writes => "emulator:gpu",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .out_of_range_writes;
    }
};

pub const Journal = struct {
    records: [max_records]Record = [_]Record{.{}} ** max_records,
    count: usize = 0,
    dropped: u64 = 0,
    writes: u64 = 0,
    out_of_range: u64 = 0,
    by_domain: [domain_count]u64 = [_]u64{0} ** domain_count,
    by_route: [5]u64 = [_]u64{0} ** 5,

    fn domainIndex(which: Domain) usize {
        inline for (@typeInfo(Domain).@"enum".fields, 0..) |field, position| {
            if (field.value == @intFromEnum(which)) return position;
        }
        return domain_count - 1;
    }

    fn routeIndex(which: Route) usize {
        return switch (which) {
            .mmio_aperture => 0,
            .pm4_stream => 1,
            .model_replay => 2,
            .harness => 3,
            .unknown => 4,
        };
    }

    fn find(self: *Journal, index: u16) ?*Record {
        var position: usize = 0;
        while (position < self.count) : (position += 1) {
            if (self.records[position].index == index) return &self.records[position];
        }
        return null;
    }

    /// Record one write. `valid` is the decoder's own judgement of whether the
    /// value makes sense for the register's domain; an invalid value is kept
    /// rather than dropped, because a decoder that silently discarded what it
    /// could not parse would report a cleaner file than the guest wrote.
    pub fn write(
        self: *Journal,
        index: u16,
        value: u32,
        domain: Domain,
        route: Route,
        valid: bool,
        step: u64,
    ) void {
        self.writes +|= 1;
        self.by_domain[domainIndex(domain)] +|= 1;
        self.by_route[routeIndex(route)] +|= 1;

        const existing = self.find(index) orelse blk: {
            if (self.count >= max_records) {
                self.dropped +|= 1;
                break :blk null;
            }
            const slot = &self.records[self.count];
            self.count += 1;
            slot.* = .{ .index = index, .domain = domain, .route = route, .first_step = step };
            break :blk slot;
        };
        if (existing) |record| {
            record.writes +|= 1;
            record.last_value = value;
            record.last_step = step;
            record.route = route;
            if (value != 0) record.ever_nonzero = true;
            if (!valid) record.invalid_values +|= 1;
        }
    }

    pub fn noteOutOfRange(self: *Journal) void {
        self.out_of_range +|= 1;
        self.writes +|= 1;
    }

    pub fn recordFor(self: *const Journal, index: u16) ?Record {
        var position: usize = 0;
        while (position < self.count) : (position += 1) {
            if (self.records[position].index == index) return self.records[position];
        }
        return null;
    }

    pub fn retained(self: *const Journal) []const Record {
        return self.records[0..self.count];
    }

    pub fn summary(self: *const Journal) Summary {
        var out = Summary{
            .writes = self.writes,
            .distinct = self.count,
            .dropped = self.dropped,
            .by_domain = self.by_domain,
            .by_route = self.by_route,
            .out_of_range = self.out_of_range,
        };
        for (self.retained()) |record| out.invalid_values +|= record.invalid_values;
        for (target_registers) |index| {
            if (self.recordFor(index)) |record| {
                out.target_writes +|= record.writes;
                if (record.ever_nonzero) out.target_nonzero += 1;
            }
        }
        return out;
    }

    pub fn verdict(self: *const Journal) Verdict {
        const totals = self.summary();
        if (totals.out_of_range != 0) return .out_of_range_writes;
        if (totals.writes == 0) return .untouched;
        if (totals.target_nonzero != 0) return .target_programmed;
        if (totals.target_writes != 0) return .target_named_as_zero;
        return .configured_without_a_target;
    }

    pub fn fingerprint(self: *const Journal) u64 {
        const totals = self.summary();
        var hash: u64 = totals.writes;
        hash = hash *% 31 +% totals.target_writes;
        hash = hash *% 31 +% totals.target_nonzero;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

// The 2026-08-31 register file: busy, and no destination named.
test "a busy register file with untouched targets is not a programmed target" {
    var journal = Journal{};
    var index: u64 = 0;
    while (index < 156) : (index += 1) {
        journal.write(0x2080 + @as(u16, @intCast(index % 3)), 1, .raster_setup, .pm4_stream, true, 3_000_000 + index);
    }
    const verdict = journal.verdict();
    try std.testing.expectEqual(Verdict.configured_without_a_target, verdict);
    try std.testing.expectEqualStrings("guest:title", verdict.owner());
    try std.testing.expect(!verdict.isDefect());

    const totals = journal.summary();
    try std.testing.expectEqual(@as(u64, 156), totals.writes);
    try std.testing.expectEqual(@as(u64, 0), totals.target_writes);
    // The aperture is silent and the PM4 path is busy: the normal shape, and
    // never evidence that registers were not programmed.
    try std.testing.expect(totals.apertureSilentWhilePm4Busy());
}

test "a target register written with zero is a decoded value and not a destination" {
    var journal = Journal{};
    journal.write(0x2000, 0, .render_backend, .pm4_stream, true, 100);
    try std.testing.expectEqual(Verdict.target_named_as_zero, journal.verdict());
    try std.testing.expectEqual(@as(u64, 1), journal.summary().target_writes);
    try std.testing.expectEqual(@as(usize, 0), journal.summary().target_nonzero);

    journal.write(0x2000, 0x1234, .render_backend, .pm4_stream, true, 200);
    try std.testing.expectEqual(Verdict.target_programmed, journal.verdict());
    try std.testing.expectEqual(@as(usize, 1), journal.summary().target_nonzero);
    try std.testing.expect(journal.recordFor(0x2000).?.ever_nonzero);
}

test "an out-of-range write outranks everything the file otherwise says" {
    var journal = Journal{};
    journal.write(0x2000, 0x1234, .render_backend, .pm4_stream, true, 100);
    try std.testing.expectEqual(Verdict.target_programmed, journal.verdict());
    journal.noteOutOfRange();
    const verdict = journal.verdict();
    try std.testing.expectEqual(Verdict.out_of_range_writes, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expectEqualStrings("emulator:gpu", verdict.owner());
}

test "an invalid value is retained rather than discarded" {
    var journal = Journal{};
    journal.write(0x2000, 0xFFFF_FFFF, .render_backend, .pm4_stream, false, 100);
    try std.testing.expectEqual(@as(u64, 1), journal.summary().invalid_values);
    try std.testing.expectEqual(@as(u64, 1), journal.recordFor(0x2000).?.invalid_values);
    // The write still counts: a decoder that dropped what it could not parse
    // would report a cleaner file than the guest wrote.
    try std.testing.expectEqual(@as(u64, 1), journal.summary().target_writes);
}

test "routes are counted apart so provenance survives into the report" {
    var journal = Journal{};
    journal.write(0x044B, 1, .command_processor, .mmio_aperture, true, 10);
    journal.write(0x2080, 1, .raster_setup, .pm4_stream, true, 20);
    journal.write(0x2081, 1, .raster_setup, .model_replay, true, 30);
    const totals = journal.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.by_route[0]);
    try std.testing.expectEqual(@as(u64, 1), totals.by_route[1]);
    try std.testing.expectEqual(@as(u64, 1), totals.by_route[2]);
    try std.testing.expect(!totals.apertureSilentWhilePm4Busy());
    try std.testing.expectEqual(SourceClass.replay, Route.model_replay.sourceClass());
    try std.testing.expectEqual(SourceClass.synthetic, Route.harness.sourceClass());
}

test "an untouched file is a fact about the title and not about the observer" {
    const journal = Journal{};
    const verdict = journal.verdict();
    try std.testing.expectEqual(Verdict.untouched, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "about this observer") != null);
}

test "the record table is bounded and totals survive the bound" {
    var journal = Journal{};
    var index: u16 = 0;
    while (index < max_records + 10) : (index += 1) {
        journal.write(0x1000 + index, 1, .unclassified, .pm4_stream, true, index);
    }
    try std.testing.expectEqual(max_records, journal.retained().len);
    try std.testing.expectEqual(@as(u64, 10), journal.dropped);
    try std.testing.expectEqual(@as(u64, max_records + 10), journal.summary().writes);
}

test "every domain and route states its own vocabulary" {
    inline for (@typeInfo(Domain).@"enum".fields) |field| {
        const which: Domain = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Route).@"enum".fields) |field| {
        const which: Route = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    try std.testing.expect(Domain.render_backend.requiredForOutput());
    try std.testing.expect(!Domain.raster_setup.requiredForOutput());
    try std.testing.expectEqual(@as(usize, 3), target_registers.len);
}
