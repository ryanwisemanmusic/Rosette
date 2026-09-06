//! What each Vd* export owes the title, what Xenia currently gives it, and
//! whether the difference is on the dependency chain.
//!
//! The defect this exists for
//! --------------------------
//! Xenia's mac video export file contains several deliberate scaffolds:
//! `VdInitializeEngines` returns a stub success with a fork-specific callback
//! reading; `VdCallGraphicsNotificationRoutines` returns zero;
//! `VdInitializeScalerCommandBuffer` fills a destination with NOPs;
//! `VdSetSystemCommandBufferGpuIdentifierAddress` writes `0x12345678`;
//! the EDRAM entry points return a configurable stub; `VdPersistDisplay`
//! allocates 64 bytes of NoAccess and returns success.
//!
//! None of those is proven to be the 2026-08-31 cause — the title never
//! reaches `VdSwap` and the observed batch never reaches a target — and every
//! one of them is a high-value suspect for the guest synchronization loop. The
//! mistake would be to replace them all with host behaviour: a stub the title
//! never reads costs nothing to leave, and a stub whose *side effect* the
//! title waits on is the whole problem.
//!
//! So each export records what the title does with it — ignores it, tests it
//! for non-zero, reads the value, or waits on a side effect — and only the
//! last two make a stub actionable. The ordering is: find out whether the
//! title consumes it, then implement the smallest faithful behaviour.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;

/// The exports on Halo's graphics path.
pub const Export = enum(u8) {
    initialize_engines = 0,
    set_graphics_interrupt_callback = 1,
    query_video_mode = 2,
    initialize_ring_buffer = 3,
    enable_ring_buffer_rptr_write_back = 4,
    set_system_command_buffer_gpu_identifier_address = 5,
    get_system_command_buffer = 6,
    initialize_scaler_command_buffer = 7,
    initialize_edram = 8,
    retrain_edram = 9,
    is_hsio_training_succeeded = 10,
    call_graphics_notification_routines = 11,
    persist_display = 12,
    swap = 13,

    pub fn label(self: Export) []const u8 {
        return switch (self) {
            .initialize_engines => "VdInitializeEngines",
            .set_graphics_interrupt_callback => "VdSetGraphicsInterruptCallback",
            .query_video_mode => "VdQueryVideoMode",
            .initialize_ring_buffer => "VdInitializeRingBuffer",
            .enable_ring_buffer_rptr_write_back => "VdEnableRingBufferRPtrWriteBack",
            .set_system_command_buffer_gpu_identifier_address => "VdSetSystemCommandBufferGpuIdentifierAddress",
            .get_system_command_buffer => "VdGetSystemCommandBuffer",
            .initialize_scaler_command_buffer => "VdInitializeScalerCommandBuffer",
            .initialize_edram => "VdInitializeEDRAM",
            .retrain_edram => "VdRetrainEDRAM",
            .is_hsio_training_succeeded => "VdIsHSIOTrainingSucceeded",
            .call_graphics_notification_routines => "VdCallGraphicsNotificationRoutines",
            .persist_display => "VdPersistDisplay",
            .swap => "VdSwap",
        };
    }

    /// Whether this export writes guest memory the title can later read. A
    /// stub that only returns a value and one that also writes a buffer fail
    /// in different ways.
    pub fn writesGuestMemory(self: Export) bool {
        return switch (self) {
            .query_video_mode,
            .set_system_command_buffer_gpu_identifier_address,
            .get_system_command_buffer,
            .initialize_scaler_command_buffer,
            .swap,
            => true,
            else => false,
        };
    }
};

pub const export_count: usize = @typeInfo(Export).@"enum".fields.len;

/// How faithfully the emulator implements it today.
pub const Implementation = enum(u8) {
    /// Does what the console did.
    real = 0,
    /// Approximates it, with the approximation documented.
    modelled = 1,
    /// Returns a plausible value and performs no side effect.
    stub = 2,
    /// Present only to keep a diagnostic run moving.
    diagnostic = 3,
    /// Not implemented at all.
    absent = 4,
    unknown = 255,

    pub fn label(self: Implementation) []const u8 {
        return switch (self) {
            .real => "real",
            .modelled => "modelled",
            .stub => "stub",
            .diagnostic => "diagnostic",
            .absent => "absent",
            .unknown => "unknown",
        };
    }

    pub fn faithful(self: Implementation) bool {
        return self == .real or self == .modelled;
    }
};

/// What the title actually does with the result. This is the field that turns
/// a suspect into a finding, and the reason a stub is not automatically a bug.
pub const Consumption = enum(u8) {
    /// Nobody has seen the title use it.
    unobserved = 0,
    /// The title calls it and discards the result.
    ignored = 1,
    /// The title branches on non-zero only.
    tested_nonzero = 2,
    /// The title reads the returned value or the memory it wrote.
    value_read = 3,
    /// The title waits on a side effect — an event, a callback, a flag.
    side_effect_awaited = 4,

    pub fn label(self: Consumption) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .ignored => "ignored",
            .tested_nonzero => "tested-nonzero",
            .value_read => "value-read",
            .side_effect_awaited => "side-effect-awaited",
        };
    }

    /// Whether a stub here can change what the title does.
    pub fn stubCanMatter(self: Consumption) bool {
        return self == .value_read or self == .side_effect_awaited;
    }
};

/// What to do about one export.
pub const Standing = enum(u8) {
    /// Faithful, or unfaithful in a way the title cannot notice.
    acceptable,
    /// Never called. Nothing to decide yet.
    not_demanded,
    /// A stub whose value the title reads. Implement the smallest faithful
    /// behaviour and add a probe.
    actionable_value,
    /// A stub whose side effect the title waits on. This is where a
    /// synchronization loop comes from.
    actionable_side_effect,
    /// Called and not implemented at all.
    missing,

    pub fn label(self: Standing) []const u8 {
        return switch (self) {
            .acceptable => "acceptable",
            .not_demanded => "not-demanded",
            .actionable_value => "ACTIONABLE-VALUE",
            .actionable_side_effect => "ACTIONABLE-SIDE-EFFECT",
            .missing => "MISSING",
        };
    }

    pub fn describe(self: Standing) []const u8 {
        return switch (self) {
            .acceptable => "the implementation is faithful, or the title cannot tell the difference. Replacing it would cost time and change nothing",
            .not_demanded => "the title has not called this. It may still be a stub and it is not on the dependency chain, so it is not work yet",
            .actionable_value => "the title reads a value this export makes up. Implement the smallest faithful behaviour and add a probe that checks it — do not replace the whole export on suspicion",
            .actionable_side_effect => "the title waits on a side effect this export does not perform. This is the shape a guest synchronization loop takes, and it is the highest-value class in this table",
            .missing => "the title called an export that is not implemented. Whatever it expected did not happen",
        };
    }

    pub fn isActionable(self: Standing) bool {
        return self == .actionable_value or self == .actionable_side_effect or self == .missing;
    }

    /// Ordering for the audit's "prioritise in evidence order" instruction.
    pub fn priority(self: Standing) u8 {
        return switch (self) {
            .actionable_side_effect => 0,
            .missing => 1,
            .actionable_value => 2,
            .not_demanded => 3,
            .acceptable => 4,
        };
    }
};

/// One export's row in the differential table.
pub const Entry = struct {
    which: Export,
    implementation: Implementation = .unknown,
    consumption: Consumption = .unobserved,
    calls: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// The value the emulator returns, and what a reference implementation
    /// would. Equal values with a `stub` implementation still matter when a
    /// side effect is missing.
    returned_value: u64 = 0,
    reference_value: u64 = 0,
    reference_known: bool = false,
    /// A guest object this export is supposed to touch.
    side_effect_object: u64 = 0,
    side_effect_observed: bool = false,
    /// Whether a probe exists that would catch a regression here.
    probe_exists: bool = false,

    pub fn standing(self: Entry) Standing {
        if (self.calls == 0) return .not_demanded;
        if (self.implementation == .absent) return .missing;
        if (self.implementation.faithful()) return .acceptable;
        if (self.consumption == .side_effect_awaited and !self.side_effect_observed) {
            return .actionable_side_effect;
        }
        if (self.consumption == .value_read) {
            if (self.reference_known and self.returned_value == self.reference_value) return .acceptable;
            return .actionable_value;
        }
        return .acceptable;
    }

    /// Whether the value the emulator returns differs from the reference.
    /// `null` when nothing has stated a reference, which is a hole rather than
    /// agreement.
    pub fn valueDiffers(self: Entry) ?bool {
        if (!self.reference_known) return null;
        return self.returned_value != self.reference_value;
    }
};

pub const Summary = struct {
    demanded: usize = 0,
    acceptable: usize = 0,
    actionable_value: usize = 0,
    actionable_side_effect: usize = 0,
    missing: usize = 0,
    not_demanded: usize = 0,
    stubs_on_chain: usize = 0,
    probes_missing: usize = 0,
    references_missing: usize = 0,

    pub fn actionable(self: Summary) usize {
        return self.actionable_value + self.actionable_side_effect + self.missing;
    }
};

pub const Table = struct {
    entries: [export_count]Entry = blk: {
        var table: [export_count]Entry = undefined;
        for (&table, 0..) |*slot, index| {
            slot.* = .{ .which = @enumFromInt(index) };
        }
        break :blk table;
    },

    pub fn entry(self: *Table, which: Export) *Entry {
        return &self.entries[@intFromEnum(which)];
    }

    pub fn get(self: *const Table, which: Export) Entry {
        return self.entries[@intFromEnum(which)];
    }

    pub fn noteCall(self: *Table, which: Export, step: u64) void {
        const slot = self.entry(which);
        if (slot.calls == 0) slot.first_step = step;
        slot.calls +|= 1;
        slot.last_step = step;
    }

    pub fn summary(self: *const Table) Summary {
        var out = Summary{};
        for (self.entries) |item| {
            switch (item.standing()) {
                .acceptable => {
                    out.demanded += 1;
                    out.acceptable += 1;
                },
                .actionable_value => {
                    out.demanded += 1;
                    out.actionable_value += 1;
                },
                .actionable_side_effect => {
                    out.demanded += 1;
                    out.actionable_side_effect += 1;
                },
                .missing => {
                    out.demanded += 1;
                    out.missing += 1;
                },
                .not_demanded => out.not_demanded += 1,
            }
            if (item.calls != 0 and !item.implementation.faithful()) out.stubs_on_chain += 1;
            if (item.calls != 0 and !item.probe_exists) out.probes_missing += 1;
            if (item.calls != 0 and !item.reference_known) out.references_missing += 1;
        }
        return out;
    }

    /// The export to work on next, in the audit's evidence order: a missing
    /// side effect first, then an absent export, then a read value.
    pub fn nextSubject(self: *const Table) ?Entry {
        var best: ?Entry = null;
        for (self.entries) |item| {
            const standing = item.standing();
            if (!standing.isActionable()) continue;
            if (best == null or standing.priority() < best.?.standing().priority()) best = item;
        }
        return best;
    }

    pub fn fingerprint(self: *const Table) u64 {
        var hash: u64 = 0;
        for (self.entries) |item| {
            hash = hash *% 31 +% @intFromEnum(item.standing());
        }
        return hash;
    }
};

test "a stub the title ignores is not work" {
    var table = Table{};
    const slot = table.entry(.call_graphics_notification_routines);
    slot.implementation = .stub;
    slot.consumption = .ignored;
    table.noteCall(.call_graphics_notification_routines, 100);
    try std.testing.expectEqual(Standing.acceptable, table.get(.call_graphics_notification_routines).standing());
    try std.testing.expect(!Consumption.ignored.stubCanMatter());
}

// The highest-value class in the audit's table: a stub whose side effect the
// title waits on. This is the shape the observed synchronization loop takes.
test "a stub whose side effect is awaited outranks everything else" {
    var table = Table{};
    const scaler = table.entry(.initialize_scaler_command_buffer);
    scaler.implementation = .stub;
    scaler.consumption = .value_read;
    table.noteCall(.initialize_scaler_command_buffer, 100);

    const edram = table.entry(.initialize_edram);
    edram.implementation = .stub;
    edram.consumption = .side_effect_awaited;
    edram.side_effect_object = 0x4000_4BF4;
    edram.side_effect_observed = false;
    table.noteCall(.initialize_edram, 200);

    try std.testing.expectEqual(Standing.actionable_value, table.get(.initialize_scaler_command_buffer).standing());
    try std.testing.expectEqual(Standing.actionable_side_effect, table.get(.initialize_edram).standing());
    try std.testing.expectEqual(Export.initialize_edram, table.nextSubject().?.which);
    try std.testing.expectEqual(@as(usize, 2), table.summary().actionable());
    try std.testing.expect(std.mem.indexOf(u8, Standing.actionable_side_effect.describe(), "synchronization loop") != null);
}

test "a stub returning the reference value is acceptable however stubby it is" {
    var table = Table{};
    const slot = table.entry(.is_hsio_training_succeeded);
    slot.implementation = .stub;
    slot.consumption = .value_read;
    slot.returned_value = 1;
    slot.reference_value = 1;
    slot.reference_known = true;
    table.noteCall(.is_hsio_training_succeeded, 100);
    try std.testing.expectEqual(Standing.acceptable, table.get(.is_hsio_training_succeeded).standing());
    try std.testing.expectEqual(false, table.get(.is_hsio_training_succeeded).valueDiffers().?);

    slot.returned_value = 0;
    try std.testing.expectEqual(Standing.actionable_value, table.get(.is_hsio_training_succeeded).standing());
    try std.testing.expectEqual(true, table.get(.is_hsio_training_succeeded).valueDiffers().?);
}

test "an unstated reference is a hole rather than agreement" {
    var table = Table{};
    const slot = table.entry(.initialize_engines);
    slot.implementation = .stub;
    slot.consumption = .value_read;
    slot.returned_value = 0;
    table.noteCall(.initialize_engines, 100);
    try std.testing.expect(table.get(.initialize_engines).valueDiffers() == null);
    try std.testing.expectEqual(Standing.actionable_value, table.get(.initialize_engines).standing());
    try std.testing.expectEqual(@as(usize, 1), table.summary().references_missing);
}

test "an export nobody called is not work yet however stubbed it is" {
    var table = Table{};
    const slot = table.entry(.persist_display);
    slot.implementation = .diagnostic;
    slot.consumption = .side_effect_awaited;
    try std.testing.expectEqual(Standing.not_demanded, table.get(.persist_display).standing());
    try std.testing.expect(!Standing.not_demanded.isActionable());
    try std.testing.expect(table.nextSubject() == null);
}

test "an absent implementation the title called is missing" {
    var table = Table{};
    table.entry(.get_system_command_buffer).implementation = .absent;
    table.noteCall(.get_system_command_buffer, 100);
    try std.testing.expectEqual(Standing.missing, table.get(.get_system_command_buffer).standing());
    try std.testing.expectEqual(@as(usize, 1), table.summary().missing);
}

test "a side effect that was observed clears the finding" {
    var table = Table{};
    const slot = table.entry(.swap);
    slot.implementation = .modelled;
    slot.consumption = .side_effect_awaited;
    table.noteCall(.swap, 100);
    // A faithful implementation is acceptable whatever the consumption.
    try std.testing.expectEqual(Standing.acceptable, table.get(.swap).standing());

    slot.implementation = .stub;
    try std.testing.expectEqual(Standing.actionable_side_effect, table.get(.swap).standing());
    slot.side_effect_observed = true;
    try std.testing.expectEqual(Standing.acceptable, table.get(.swap).standing());
}

test "the table tracks probe and reference coverage on the chain" {
    var table = Table{};
    table.entry(.query_video_mode).implementation = .real;
    table.noteCall(.query_video_mode, 100);
    try std.testing.expectEqual(@as(usize, 1), table.summary().probes_missing);
    table.entry(.query_video_mode).probe_exists = true;
    try std.testing.expectEqual(@as(usize, 0), table.summary().probes_missing);
    try std.testing.expectEqual(@as(usize, 0), table.summary().stubs_on_chain);
}

test "every export and classification states its own vocabulary" {
    inline for (@typeInfo(Export).@"enum".fields) |field| {
        const which: Export = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Standing).@"enum".fields) |field| {
        const which: Standing = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
    try std.testing.expect(Export.swap.writesGuestMemory());
    try std.testing.expect(!Export.initialize_edram.writesGuestMemory());
    try std.testing.expectEqual(@as(usize, 14), export_count);
}
