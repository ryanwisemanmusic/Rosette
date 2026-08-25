//! KERNEL SURFACE — the GPU-facing kernel state a title reads before it will
//! ever decide to present, and whether anything has supplied it.
//!
//! This is the concrete form of "hidden control flow Windows gives you for
//! free". An Xbox 360 title does not only *call* kernel exports; it *reads*
//! them. `VdGlobalDevice`, `VdGlobalXamDevice`, `VdGpuClockInMHz` and
//! `VdHSIOCalibrationLock` are **variable** exports — blocks of guest memory
//! the kernel populated before the title ran. A title's display layer reads
//! them to decide whether a device exists, what it can do, and whether to keep
//! going. On real hardware they are already correct. Here they are whatever
//! nobody wrote.
//!
//! That produces the exact failure this run has: engine init runs, the ring is
//! initialised, the interrupt callback fires, PM4 is submitted and drained,
//! draws are issued — and the title never enters `VdSwap`. The ladder calls
//! that "guest VdSwap export entered = 0" and stops, because a ladder can only
//! see calls. The title is not stuck on anything it *called*; it is stuck on
//! something it *read*.
//!
//! ## What this module does and does not claim
//!
//! It does not synthesise a swap and it does not call anything on the title's
//! behalf. It models the surface: for each export, what it is, how large it is,
//! whether anything has populated it, and whether the value a reader would get
//! is usable. Then it says which entries are unpopulated and who owns them.
//!
//! The distinction that makes this safe: populating a kernel *variable* is
//! supplying platform state, which is what a harness is for and what the real
//! kernel did. Entering `VdSwap` is title behaviour. The first is a legitimate
//! harness action, the second never is — and `gpu.contract` already enforces
//! that split by owner.
//!
//! ## Reading the report
//!
//! `unpopulated` on an export the title imported is the finding. An export the
//! title never imported cannot be why it is stuck, however empty it is, and is
//! reported separately so it cannot be mistaken for a cause.

const std = @import("std");
const kernel_export_map = @import("xenia_kernel_export_map");

/// The GPU-facing kernel exports, function and variable alike, in the order a
/// title's display bring-up touches them.
pub const Export = enum(u16) {
    vd_get_graphics_asic_id = 0x1BC,
    vd_get_system_command_buffer = 0x1BD,
    vd_global_device = 0x1BE,
    vd_global_xam_device = 0x1BF,
    vd_gpu_clock_in_mhz = 0x1C0,
    vd_hsio_calibration_lock = 0x1C1,
    vd_initialize_engines = 0x1C2,
    vd_initialize_ring_buffer = 0x1C3,
    vd_persist_display = 0x1C7,
    vd_is_hsio_training_succeeded = 0x1C6,
    vd_enable_ring_buffer_rptr_writeback = 0x1B6,
    vd_set_graphics_interrupt_callback = 0x1D5,
    vd_swap = 0x25B,
    vd_initialize_edram = 0x268,
    vd_retrain_edram = 0x269,
    vd_retrain_edram_worker = 0x26A,

    pub fn ordinal(self: Export) u16 {
        return @intFromEnum(self);
    }

    pub fn name(self: Export) []const u8 {
        return switch (self) {
            .vd_get_graphics_asic_id => "VdGetGraphicsAsicID",
            .vd_get_system_command_buffer => "VdGetSystemCommandBuffer",
            .vd_global_device => "VdGlobalDevice",
            .vd_global_xam_device => "VdGlobalXamDevice",
            .vd_gpu_clock_in_mhz => "VdGpuClockInMHz",
            .vd_hsio_calibration_lock => "VdHSIOCalibrationLock",
            .vd_initialize_engines => "VdInitializeEngines",
            .vd_initialize_ring_buffer => "VdInitializeRingBuffer",
            .vd_persist_display => "VdPersistDisplay",
            .vd_is_hsio_training_succeeded => "VdIsHSIOTrainingSucceeded",
            .vd_enable_ring_buffer_rptr_writeback => "VdEnableRingBufferRPtrWriteBack",
            .vd_set_graphics_interrupt_callback => "VdSetGraphicsInterruptCallback",
            .vd_swap => "VdSwap",
            .vd_initialize_edram => "VdInitializeEDRAM",
            .vd_retrain_edram => "VdRetrainEDRAM",
            .vd_retrain_edram_worker => "VdRetrainEDRAMWorker",
        };
    }

    /// A variable export is memory the title reads. A function export is
    /// something it calls. The two fail in completely different ways: an
    /// unpopulated variable produces a silent early return inside the title,
    /// and an unbound function produces a call that goes somewhere wrong.
    pub fn isVariable(self: Export) bool {
        return switch (self) {
            .vd_global_device,
            .vd_global_xam_device,
            .vd_gpu_clock_in_mhz,
            .vd_hsio_calibration_lock,
            => true,
            else => false,
        };
    }

    /// Bytes the kernel would have populated. Zero for function exports.
    ///
    /// The sizes match the emulator's own `video_force_*` configuration values,
    /// which exist precisely because nothing else was supplying them — a
    /// forcing option is a defect wearing a workaround as a disguise, and these
    /// are the defects.
    pub fn byteSize(self: Export) u32 {
        return switch (self) {
            .vd_global_device, .vd_global_xam_device => 256,
            .vd_gpu_clock_in_mhz, .vd_hsio_calibration_lock => 4,
            else => 0,
        };
    }

    /// Whether a title reaching its present path must be able to use this.
    /// Everything else is reported but never becomes the frontier.
    pub fn requiredForPresent(self: Export) bool {
        return switch (self) {
            .vd_global_device,
            .vd_gpu_clock_in_mhz,
            .vd_initialize_engines,
            .vd_initialize_ring_buffer,
            .vd_set_graphics_interrupt_callback,
            => true,
            else => false,
        };
    }

    pub fn guidance(self: Export) []const u8 {
        return switch (self) {
            .vd_global_device => "the display device block the title reads to decide a device exists. Unpopulated, a display layer returns early and never reaches its present path — which looks exactly like a title that chose not to draw",
            .vd_global_xam_device => "the XAM-side device block. Read by system UI paths rather than the title's renderer",
            .vd_gpu_clock_in_mhz => "read for timing maths. A zero here divides or scales to nonsense and can gate a frame-pacing decision",
            .vd_hsio_calibration_lock => "read alongside HSIO training. A title that polls it and never sees a settled value keeps waiting",
            .vd_get_system_command_buffer => "returns the system command buffer. A title that never calls it is not using it; a title that calls it and gets nothing cannot submit through it",
            .vd_is_hsio_training_succeeded => "polled during display bring-up",
            .vd_swap => "the present entry point. Never satisfiable from outside: entering it on the title's behalf fabricates a frame it did not draw",
            else => "observed for completeness; not on the critical path to a first frame",
        };
    }
};

pub const export_count = @typeInfo(Export).@"enum".fields.len;

pub const Population = enum {
    /// Nothing has been observed to write or read it, and no value is known.
    unknown,
    /// The title's import table references it, but nothing populated it.
    unpopulated,
    /// Populated with a value a reader cannot use (a zero device pointer, a
    /// zero clock). Distinct from unpopulated: something ran and produced a
    /// value that is still unusable, which is a different bug.
    implausible,
    /// Populated with a usable value.
    populated,

    pub fn usable(self: Population) bool {
        return self == .populated;
    }

    pub fn label(self: Population) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .unpopulated => "UNPOPULATED",
            .implausible => "IMPLAUSIBLE",
            .populated => "populated",
        };
    }
};

/// The name of *any* xboxkrnl ordinal, not only the video ones above.
///
/// `Export` deliberately carries just the sixteen exports the GPU bring-up
/// path touches, because those are the ones this module reasons about. But a
/// title imports by ordinal across the whole 922-entry kernel, and a
/// diagnostic that can only name sixteen of them prints a bare number for the
/// rest — which is what made the kernel-export layer unreadable and left
/// "kernel export binding" reported as untested.
///
/// `pkg/common/xenia/kernel-export-map` carries the full table transcribed
/// from the console's own export tables, so every ordinal a title can import
/// resolves here. Null still means "the kernel does not publish this", which
/// is a real and useful answer — a fabricated `ordinal_258` would read as a
/// genuine export and send someone looking for one.
pub fn nameOfOrdinal(ordinal: u16) ?[]const u8 {
    return kernel_export_map.nameOf(.xboxkrnl, ordinal);
}

/// Whether an ordinal names a variable export, across the whole kernel.
///
/// The distinction matters at the import boundary: binding a variable as
/// though it were code produces a jump into data the moment the title
/// dereferences it.
pub fn ordinalIsVariable(ordinal: u16) bool {
    return kernel_export_map.isVariable(.xboxkrnl, ordinal);
}

test "any kernel ordinal resolves, not just the video ones" {
    // The sixteen this module knows still resolve...
    try std.testing.expectEqualStrings(
        "VdInitializeRingBuffer",
        nameOfOrdinal(@intFromEnum(Export.vd_initialize_ring_buffer)).?,
    );
    // ...and so does the rest of the kernel, which previously printed as a
    // bare number.
    try std.testing.expectEqualStrings("DbgBreakPoint", nameOfOrdinal(0x0001).?);
    try std.testing.expectEqualStrings("KeTlsAlloc", nameOfOrdinal(0x0152).?);
    // The call that produces the pointer VdInitializeRingBuffer is handed.
    // Being able to name it is the difference between "the title called 0xBE"
    // and "the title asked for a physical address for its ring".
    try std.testing.expectEqualStrings("MmGetPhysicalAddress", nameOfOrdinal(0x00BE).?);
    // An unpublished ordinal is reported as absent rather than invented.
    try std.testing.expect(nameOfOrdinal(0xFFFF) == null);
}

test "the enum's own names agree with the full table" {
    // Two independently maintained lists of the same facts: if lib's hand
    // written sixteen ever drift from the console's table, this names the one
    // that moved instead of letting a wrong name reach a report.
    for (std.enums.values(Export)) |entry| {
        const from_table = nameOfOrdinal(entry.ordinal()) orelse {
            return error.TestUnexpectedResult;
        };
        try std.testing.expectEqualStrings(entry.name(), from_table);
        try std.testing.expectEqual(entry.isVariable(), ordinalIsVariable(entry.ordinal()));
    }
}

const Entry = struct {
    /// Whether the title's import table references this export at all.
    imported: bool = false,
    /// Whether anything called it or touched its storage this run.
    runtime_activity: bool = false,
    address: u32 = 0,
    value: u64 = 0,
    value_known: bool = false,
    population: Population = .unknown,
    calls: u64 = 0,
};

pub const Finding = struct {
    /// First required export a reader could not use, if any.
    blocking: ?Export,
    imported_count: u32,
    usable_count: u32,
    unpopulated_imported: u32,
};

/// Is a value one a title could actually use for this export?
///
/// Kept as a free function so the judgement is testable without a ledger. The
/// rules are deliberately weak — "not zero", "a plausible guest pointer" —
/// because a strict model of what the kernel writes would be a guess, and a
/// confident wrong answer here sends the investigation to the wrong export.
pub fn plausible(which: Export, value: u64) bool {
    return switch (which) {
        // A device block pointer. Zero is the failure; anything in the guest's
        // addressable range is accepted rather than pattern-matched.
        .vd_global_device, .vd_global_xam_device => value != 0,
        // A clock in MHz. Zero divides to nonsense; an absurd value is not
        // something this module can adjudicate, so only zero is rejected.
        .vd_gpu_clock_in_mhz => value != 0,
        // A lock word. Any settled value is usable; the failure mode is a
        // reader spinning on a slot nobody ever writes, which shows up as
        // `unpopulated` rather than as an implausible value.
        .vd_hsio_calibration_lock => true,
        else => true,
    };
}

pub const Surface = struct {
    entries: [export_count]Entry = [_]Entry{.{}} ** export_count,

    fn index(which: Export) usize {
        inline for (@typeInfo(Export).@"enum".fields, 0..) |field, i| {
            if (field.value == @intFromEnum(which)) return i;
        }
        unreachable;
    }

    pub fn fromOrdinal(ordinal: u16) ?Export {
        inline for (@typeInfo(Export).@"enum".fields) |field| {
            if (field.value == ordinal) return @enumFromInt(field.value);
        }
        return null;
    }

    /// Record what the emulator reported about an export: whether the title
    /// imported it and whether anything touched it this run.
    pub fn observeBinding(
        self: *Surface,
        which: Export,
        is_imported: bool,
        runtime_activity: bool,
        calls: u64,
    ) void {
        const entry = &self.entries[index(which)];
        entry.imported = entry.imported or is_imported;
        entry.runtime_activity = entry.runtime_activity or runtime_activity;
        if (calls > entry.calls) entry.calls = calls;
        self.reclassify(which);
    }

    /// Record the guest address a variable export lives at.
    pub fn observeAddress(self: *Surface, which: Export, address: u32) void {
        const entry = &self.entries[index(which)];
        entry.address = address;
        self.reclassify(which);
    }

    /// Record the value a reader would get. This is what promotes an entry out
    /// of `unpopulated`, and the only thing that can.
    pub fn observeValue(self: *Surface, which: Export, value: u64) void {
        const entry = &self.entries[index(which)];
        entry.value = value;
        entry.value_known = true;
        self.reclassify(which);
    }

    fn reclassify(self: *Surface, which: Export) void {
        const entry = &self.entries[index(which)];
        if (!which.isVariable()) {
            // A function export is "populated" when it is bound and reachable;
            // whether the title chose to call it is the title's business.
            entry.population = if (entry.imported) .populated else .unknown;
            return;
        }
        if (!entry.value_known) {
            entry.population = if (entry.imported) .unpopulated else .unknown;
            return;
        }
        entry.population = if (plausible(which, entry.value)) .populated else .implausible;
    }

    pub fn population(self: *const Surface, which: Export) Population {
        return self.entries[index(which)].population;
    }

    pub fn imported(self: *const Surface, which: Export) bool {
        return self.entries[index(which)].imported;
    }

    /// The first required export the title imported and cannot use, plus the
    /// tally. An export the title never imported is never blocking, however
    /// empty: it cannot be the reason a title it is not part of is stuck.
    pub fn finding(self: *const Surface) Finding {
        var blocking: ?Export = null;
        var imported_count: u32 = 0;
        var usable_count: u32 = 0;
        var unpopulated_imported: u32 = 0;
        inline for (@typeInfo(Export).@"enum".fields) |field| {
            const which: Export = @enumFromInt(field.value);
            const entry = self.entries[index(which)];
            if (entry.imported) imported_count += 1;
            if (entry.population.usable()) usable_count += 1;
            if (entry.imported and entry.population == .unpopulated) unpopulated_imported += 1;
            if (blocking == null and entry.imported and
                which.requiredForPresent() and !entry.population.usable())
            {
                blocking = which;
            }
        }
        return .{
            .blocking = blocking,
            .imported_count = imported_count,
            .usable_count = usable_count,
            .unpopulated_imported = unpopulated_imported,
        };
    }

    /// Variable exports the title imported and nothing populated. This is the
    /// harness's actionable list: every one is guest memory the real kernel
    /// would have written, and writing it is supplying platform state rather
    /// than fabricating title behaviour.
    pub fn harnessPopulationWork(self: *const Surface, out: []Export) []Export {
        var count: usize = 0;
        inline for (@typeInfo(Export).@"enum".fields) |field| {
            const which: Export = @enumFromInt(field.value);
            const entry = self.entries[index(which)];
            if (count < out.len and which.isVariable() and entry.imported and
                !entry.population.usable())
            {
                out[count] = which;
                count += 1;
            }
        }
        return out[0..count];
    }
};

test "a variable export the title imported and nobody populated is the finding" {
    var surface = Surface{};
    // Exactly what the run reported for ordinal 0x1BE.
    surface.observeBinding(.vd_global_device, true, false, 0);
    surface.observeAddress(.vd_global_device, 0x820006B8);
    try std.testing.expectEqual(Population.unpopulated, surface.population(.vd_global_device));

    const finding = surface.finding();
    try std.testing.expectEqual(Export.vd_global_device, finding.blocking.?);
    try std.testing.expectEqual(@as(u32, 1), finding.unpopulated_imported);
    try std.testing.expect(std.mem.indexOf(u8, Export.vd_global_device.guidance(), "returns early") != null);
}

// The distinction that keeps the report honest. `VdGlobalXamDevice` was not in
// this title's import table, so however empty it is it cannot be why the title
// is stuck — and listing it as a cause would send the next hour somewhere
// useless.
test "an export the title never imported is never the blocker" {
    var surface = Surface{};
    surface.observeBinding(.vd_global_xam_device, false, false, 0);
    try std.testing.expectEqual(Population.unknown, surface.population(.vd_global_xam_device));
    try std.testing.expect(surface.finding().blocking == null);

    var buffer: [export_count]Export = undefined;
    try std.testing.expectEqual(@as(usize, 0), surface.harnessPopulationWork(&buffer).len);
}

test "a populated value promotes the entry and clears the blocker" {
    var surface = Surface{};
    surface.observeBinding(.vd_global_device, true, false, 0);
    surface.observeValue(.vd_global_device, 0x8200_1000);
    try std.testing.expectEqual(Population.populated, surface.population(.vd_global_device));
    try std.testing.expect(surface.finding().blocking == null);
}

// A zero that something actually wrote is a different bug from a slot nobody
// wrote: the first means a producer ran and produced nothing usable, the second
// means no producer ran at all. Collapsing them loses the only clue about which
// half to look at.
test "a written-but-unusable value is implausible, not unpopulated" {
    var surface = Surface{};
    surface.observeBinding(.vd_gpu_clock_in_mhz, true, true, 0);
    surface.observeValue(.vd_gpu_clock_in_mhz, 0);
    try std.testing.expectEqual(Population.implausible, surface.population(.vd_gpu_clock_in_mhz));
    try std.testing.expectEqual(@as(u32, 0), surface.finding().unpopulated_imported);
    try std.testing.expectEqual(Export.vd_gpu_clock_in_mhz, surface.finding().blocking.?);

    surface.observeValue(.vd_gpu_clock_in_mhz, 500);
    try std.testing.expectEqual(Population.populated, surface.population(.vd_gpu_clock_in_mhz));
}

test "a function export is not judged by whether the title called it" {
    // `VdSwap` imported and never called is the title's decision, not a
    // surface defect. Reporting it as unpopulated would blame the harness for
    // a choice only the title can make.
    var surface = Surface{};
    surface.observeBinding(.vd_swap, true, false, 0);
    try std.testing.expectEqual(Population.populated, surface.population(.vd_swap));
    try std.testing.expect(surface.finding().blocking == null);
    try std.testing.expect(std.mem.indexOf(u8, Export.vd_swap.guidance(), "fabricates a frame") != null);
}

// The observed run, entered exactly as the emulator reported it.
test "the observed run's surface names the harness work outstanding" {
    var surface = Surface{};
    const observed = [_]struct { which: Export, imported: bool, activity: bool }{
        .{ .which = .vd_enable_ring_buffer_rptr_writeback, .imported = true, .activity = true },
        .{ .which = .vd_get_graphics_asic_id, .imported = false, .activity = false },
        .{ .which = .vd_get_system_command_buffer, .imported = true, .activity = false },
        .{ .which = .vd_global_device, .imported = true, .activity = false },
        .{ .which = .vd_global_xam_device, .imported = false, .activity = false },
        .{ .which = .vd_initialize_engines, .imported = true, .activity = true },
        .{ .which = .vd_initialize_ring_buffer, .imported = true, .activity = true },
        .{ .which = .vd_is_hsio_training_succeeded, .imported = true, .activity = false },
        .{ .which = .vd_set_graphics_interrupt_callback, .imported = true, .activity = true },
        .{ .which = .vd_swap, .imported = true, .activity = false },
        .{ .which = .vd_retrain_edram, .imported = true, .activity = false },
        .{ .which = .vd_retrain_edram_worker, .imported = true, .activity = false },
    };
    for (observed) |row| surface.observeBinding(row.which, row.imported, row.activity, 0);
    surface.observeAddress(.vd_global_device, 0x820006B8);

    // The ladder said "VdSwap not entered" and stopped. The surface says why a
    // title might never get there: a device block it imported and nobody wrote.
    const finding = surface.finding();
    try std.testing.expectEqual(Export.vd_global_device, finding.blocking.?);

    var buffer: [export_count]Export = undefined;
    const work = surface.harnessPopulationWork(&buffer);
    try std.testing.expectEqual(@as(usize, 1), work.len);
    try std.testing.expectEqual(Export.vd_global_device, work[0]);
    // And VdSwap, imported but uncalled, is not on that list — populating it is
    // not a thing a harness can do.
    for (work) |which| try std.testing.expect(which.isVariable());
}

test "ordinals round-trip so emulator log lines can be joined to the model" {
    try std.testing.expectEqual(Export.vd_global_device, Surface.fromOrdinal(0x1BE).?);
    try std.testing.expectEqual(Export.vd_swap, Surface.fromOrdinal(0x25B).?);
    try std.testing.expectEqual(@as(u16, 0x1BD), Export.vd_get_system_command_buffer.ordinal());
    try std.testing.expect(Surface.fromOrdinal(0x0059) == null);
    // Sizes agree with the emulator's own forcing configuration, which is where
    // the numbers came from.
    try std.testing.expectEqual(@as(u32, 256), Export.vd_global_device.byteSize());
    try std.testing.expectEqual(@as(u32, 0), Export.vd_swap.byteSize());
}

/// Guest addresses of variable exports, learned from the emulator's export
/// table dump.
///
/// Separate from `Surface` because the two facts arrive from different log
/// lines at different times, and a surface entry that silently carried a zero
/// address would read a value out of page zero and report it as implausible —
/// blaming the export for a bookkeeping gap.
pub const AddressTable = struct {
    pub const capacity: usize = 32;

    ordinals: [capacity]u16 = [_]u16{0} ** capacity,
    addresses: [capacity]u32 = [_]u32{0} ** capacity,
    count: usize = 0,

    pub fn record(self: *AddressTable, ordinal: u16, address: u32) void {
        if (ordinal == 0 or address == 0) return;
        for (self.ordinals[0..self.count], 0..) |existing, i| {
            if (existing == ordinal) {
                self.addresses[i] = address;
                return;
            }
        }
        if (self.count == capacity) return;
        self.ordinals[self.count] = ordinal;
        self.addresses[self.count] = address;
        self.count += 1;
    }

    pub fn lookup(self: *const AddressTable, ordinal: u16) ?u32 {
        for (self.ordinals[0..self.count], 0..) |existing, i| {
            if (existing == ordinal) return self.addresses[i];
        }
        return null;
    }
};

test "the address table keeps one entry per ordinal and refuses zeros" {
    var table = AddressTable{};
    table.record(0x1BE, 0x820006B8);
    table.record(0x1C0, 0x82000718);
    try std.testing.expectEqual(@as(u32, 0x820006B8), table.lookup(0x1BE).?);
    try std.testing.expectEqual(@as(u32, 0x82000718), table.lookup(0x1C0).?);
    try std.testing.expect(table.lookup(0x25B) == null);

    // A re-dump updates rather than duplicating.
    table.record(0x1BE, 0x820006C0);
    try std.testing.expectEqual(@as(u32, 0x820006C0), table.lookup(0x1BE).?);
    try std.testing.expectEqual(@as(usize, 2), table.count);

    // A zero address is not an address. Recording it would make a later read
    // land in page zero and report the export as implausible, which blames the
    // export for a gap in this table.
    table.record(0x1C1, 0);
    try std.testing.expect(table.lookup(0x1C1) == null);
}
