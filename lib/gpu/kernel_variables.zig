//! The two dereferences behind a kernel *variable* import, and what each of
//! them failing actually means.
//!
//! A title that imports `VdGlobalDevice` does not read a value at the address
//! its import table names. The loader writes the *address of* the kernel's
//! storage into that slot, and the title's code loads the slot and then loads
//! through it. There are therefore two dereferences and three states, and the
//! subsystem that treated the slot's contents as the value could not see the
//! difference between them:
//!
//!   1. The slot holds a plausible pointer and the storage holds a value.
//!   2. The slot holds the loader's *unimplemented* sentinel — the emulator
//!      declared the export but supplied no storage, so the title is about to
//!      dereference a made-up address.
//!   3. The slot holds a pointer and the storage holds zero.
//!
//! Only the second is an emulator defect. The third is usually not a defect at
//! all: `VdGlobalDevice` is a slot the *title* fills in once it creates its
//! Direct3D device, and the kernel deliberately initialises it to zero. Reading
//! zero there is a statement about how far the title has got, which is exactly
//! the signal a stalled bring-up needs — and reporting it as "unpopulated, the
//! harness should write it" sends the next hour into fabricating a device
//! pointer that would make the title dereference garbage.
//!
//! ## Why the harness reads and does not write
//!
//! Populating platform state the real kernel wrote is legitimate harness work,
//! and this module does it for the variables the kernel genuinely owns — a GPU
//! clock, a calibration lock. It refuses the ones the *title* owns, by the same
//! owner rule the graphics contract enforces, because a device pointer invented
//! here is a pointer to nothing and the crash it causes lands three subsystems
//! away from the invention.
//!
//! The distinction is per-variable and stated in the model, not left to the
//! caller to remember.

const std = @import("std");

/// Who writes a variable on real hardware, which decides whether a harness may.
pub const Writer = enum {
    /// The kernel populates it before the title runs. A harness supplying it is
    /// supplying platform state, which is what a harness is for.
    kernel,
    /// The title fills it in as it initialises. Zero means "not yet", and a
    /// harness writing it fabricates progress the title has not made.
    title,

    pub fn harnessMayWrite(self: Writer) bool {
        return self == .kernel;
    }
};

/// The GPU-facing kernel variables, with the facts a reader needs about each.
pub const Variable = enum(u16) {
    global_device = 0x1BE,
    global_xam_device = 0x1BF,
    gpu_clock_in_mhz = 0x1C0,
    hsio_calibration_lock = 0x1C1,

    pub fn ordinal(self: Variable) u16 {
        return @intFromEnum(self);
    }

    pub fn fromOrdinal(value: u16) ?Variable {
        return switch (value) {
            0x1BE => .global_device,
            0x1BF => .global_xam_device,
            0x1C0 => .gpu_clock_in_mhz,
            0x1C1 => .hsio_calibration_lock,
            else => null,
        };
    }

    pub fn name(self: Variable) []const u8 {
        return switch (self) {
            .global_device => "VdGlobalDevice",
            .global_xam_device => "VdGlobalXamDevice",
            .gpu_clock_in_mhz => "VdGpuClockInMHz",
            .hsio_calibration_lock => "VdHSIOCalibrationLock",
        };
    }

    /// Bytes of storage behind the pointer. A device slot is one pointer; the
    /// calibration lock is a critical section. These are the emulator's own
    /// allocation sizes — a harness that assumed a 256-byte device block would
    /// read 252 bytes of unrelated heap and call whatever it found a value.
    pub fn storageBytes(self: Variable) u32 {
        return switch (self) {
            .global_device, .global_xam_device, .gpu_clock_in_mhz => 4,
            .hsio_calibration_lock => 28,
        };
    }

    pub fn writer(self: Variable) Writer {
        return switch (self) {
            // "Games only seem to set this" — the kernel allocates the slot and
            // zeroes it, and the title stores its device pointer there.
            .global_device, .global_xam_device => .title,
            .gpu_clock_in_mhz, .hsio_calibration_lock => .kernel,
        };
    }

    /// How much structure a correct value has.
    ///
    /// The distinction is not pedantry. A critical section is a dispatch header
    /// with packed byte fields, a lock count that is -1 when free, a recursion
    /// count and an owning thread — six fields across twenty-eight bytes. A
    /// harness that wrote one dword of that would leave a *half*-initialised
    /// lock, which is strictly worse than an uninitialised one: an uninitialised
    /// lock is recognisably empty, and a half-initialised one is a valid-looking
    /// object with a corrupt header that the title will happily take.
    pub fn writeShape(self: Variable) WriteShape {
        return switch (self) {
            .gpu_clock_in_mhz => .dword,
            .hsio_calibration_lock => .critical_section,
            .global_device, .global_xam_device => .dword,
        };
    }

    /// The value the real kernel would have left here, when the kernel is the
    /// writer *and* the value is a single dword. Null where the title owns it
    /// or where a correct value needs more structure than one store — which is
    /// what stops a caller looping over the enum and writing all four.
    pub fn kernelValue(self: Variable) ?u32 {
        return switch (self) {
            // The Xenos runs at 500 MHz. A zero here divides to nonsense in any
            // title that scales a timing constant by it.
            .gpu_clock_in_mhz => 500,
            // Not a dword. See `writeShape`.
            .hsio_calibration_lock => null,
            .global_device, .global_xam_device => null,
        };
    }

    pub fn meaning(self: Variable) []const u8 {
        return switch (self) {
            .global_device => "the title's own Direct3D device pointer. The kernel allocates the slot and zeroes it; the title stores through it once it has created a device. Zero here is a statement about the title's progress, not a missing kernel write",
            .global_xam_device => "the system-UI device pointer. Read by XAM paths rather than by the title's renderer, so it is never the reason a title does not present",
            .gpu_clock_in_mhz => "the GPU clock, read for timing arithmetic. Zero divides or scales to nonsense and can gate a frame-pacing decision the title makes before it will present",
            .hsio_calibration_lock => "a critical section the display bring-up takes. A title that acquires a lock whose state word was never initialised can wait on an owner that does not exist",
        };
    }
};

/// Whether a correct value for a variable fits in one store.
pub const WriteShape = enum {
    dword,
    /// A critical section: a dispatch header with packed byte fields, a lock
    /// count that is -1 when free, a recursion count and an owning thread. The
    /// emulator initialises it through `RtlInitializeCriticalSectionAndSpinCount`
    /// with `header.type = 1`, `header.absolute = spin_count / 256`,
    /// `signal_state = 0`, `lock_count = -1`, `recursion_count = 0` and
    /// `owning_thread = 0`.
    critical_section,

    pub fn singleStore(self: WriteShape) bool {
        return self == .dword;
    }
};

/// The loader writes this when an export is declared but has no storage, so
/// the title dereferences a recognisable address rather than null. Spotting it
/// is the difference between "the emulator did not implement this" and "the
/// value happens to be zero".
pub const unimplemented_sentinel_base: u32 = 0xD000BEEF;

pub fn isUnimplementedSentinel(slot_value: u32, ordinal: u16) bool {
    return slot_value == (unimplemented_sentinel_base | (@as(u32, ordinal & 0xFFF) << 16));
}

/// A guest address a title could actually be reading through. The console's
/// virtual space puts kernel data well above the image base, and a pointer
/// below the first megabyte is a null-adjacent value rather than an address.
pub fn plausiblePointer(value: u32) bool {
    return value >= 0x0010_0000 and value != 0xFFFF_FFFF;
}

/// What the two dereferences found. Every state names a different owner, which
/// is the only reason to have four of them rather than a boolean.
pub const State = enum {
    /// The title's import table does not reference this variable at all, so
    /// however empty it is it cannot be why the title is stuck.
    not_imported,
    /// The slot has not been read yet.
    unresolved,
    /// The slot holds the loader's unimplemented sentinel. The emulator
    /// declared the export and supplied no storage; the title is dereferencing
    /// a fabricated address. This is an emulator defect.
    unimplemented_export,
    /// The slot holds something that is not a usable pointer.
    slot_implausible,
    /// The pointer resolves and the storage holds zero. For a title-written
    /// variable this is progress information; for a kernel-written one it is
    /// missing platform state.
    storage_zero,
    /// The pointer resolves and the storage holds a value.
    populated,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .not_imported => "not-imported",
            .unresolved => "unresolved",
            .unimplemented_export => "UNIMPLEMENTED-EXPORT",
            .slot_implausible => "SLOT-IMPLAUSIBLE",
            .storage_zero => "storage-zero",
            .populated => "populated",
        };
    }

    /// Whether a reader would get something it can use.
    pub fn usable(self: State) bool {
        return self == .populated;
    }
};

pub const Entry = struct {
    imported: bool = false,
    /// Guest address of the import slot, from the emulator's export dump.
    slot_address: u32 = 0,
    /// What the slot holds: the address of the storage.
    slot_value: u32 = 0,
    slot_read: bool = false,
    /// What the storage holds.
    storage_value: u32 = 0,
    storage_read: bool = false,
    state: State = .not_imported,
    /// Times the harness wrote this variable. Non-zero on a title-owned
    /// variable would be a contract violation, so it is counted rather than
    /// assumed impossible.
    harness_writes: u32 = 0,
};

/// Whether a harness write is permitted, and why not when it is not. Returned
/// rather than a boolean so the refusal reason reaches the log: a harness that
/// silently declines makes a missing capability invisible.
pub const WriteDecision = union(enum) {
    allowed: u32,
    refused_title_owned,
    refused_already_populated,
    refused_no_storage,
    /// The kernel owns it and a correct value does not fit in one store.
    /// Refused rather than partially written, because a half-initialised
    /// object is worse than an empty one: the title takes it.
    refused_structured_initialiser,

    pub fn label(self: WriteDecision) []const u8 {
        return switch (self) {
            .allowed => "allowed",
            .refused_title_owned => "refused: the title writes this one, and a value invented here is a pointer to nothing",
            .refused_already_populated => "refused: the storage already holds a usable value",
            .refused_no_storage => "refused: the slot does not resolve to storage, so there is nowhere to write",
            .refused_structured_initialiser => "refused: this is a critical section, not a value. A correct initialiser sets header.type=1, header.absolute=spin_count/256, signal_state=0, lock_count=-1, recursion_count=0 and owning_thread=0 across 28 bytes; writing one dword of that leaves a valid-looking object with a corrupt header, which the title will take and then wait on forever. Supplying it needs a structured writer, not a wider store",
        };
    }
};

pub const variable_count = 4;

fn index(which: Variable) usize {
    return switch (which) {
        .global_device => 0,
        .global_xam_device => 1,
        .gpu_clock_in_mhz => 2,
        .hsio_calibration_lock => 3,
    };
}

pub const Finding = struct {
    /// The first variable a title imported that an emulator defect has broken.
    /// Deliberately not "the first unusable one": a title-owned zero is not a
    /// defect, and naming it as the blocker is what sent the last investigation
    /// at a device pointer nobody was supposed to write.
    blocking: ?Variable = null,
    imported_count: u32 = 0,
    usable_count: u32 = 0,
    harness_writable_outstanding: u32 = 0,
};

pub const Surface = struct {
    entries: [variable_count]Entry = [_]Entry{.{}} ** variable_count,

    pub fn observeImport(self: *Surface, which: Variable, imported: bool, slot_address: u32) void {
        const record = &self.entries[index(which)];
        record.imported = record.imported or imported;
        if (slot_address != 0) record.slot_address = slot_address;
        if (record.imported and record.state == .not_imported) record.state = .unresolved;
    }

    /// Record what the import slot holds. This is the first dereference, and
    /// the one that separates an unimplemented export from an empty value.
    pub fn observeSlot(self: *Surface, which: Variable, slot_value: u32) void {
        const record = &self.entries[index(which)];
        record.slot_value = slot_value;
        record.slot_read = true;
        record.storage_read = false;
        self.reclassify(which);
    }

    /// Record what the storage behind the slot holds. The second dereference.
    pub fn observeStorage(self: *Surface, which: Variable, value: u32) void {
        const record = &self.entries[index(which)];
        record.storage_value = value;
        record.storage_read = true;
        self.reclassify(which);
    }

    fn reclassify(self: *Surface, which: Variable) void {
        const record = &self.entries[index(which)];
        if (!record.imported) {
            record.state = .not_imported;
            return;
        }
        if (!record.slot_read) {
            record.state = .unresolved;
            return;
        }
        if (isUnimplementedSentinel(record.slot_value, which.ordinal())) {
            record.state = .unimplemented_export;
            return;
        }
        if (!plausiblePointer(record.slot_value)) {
            record.state = .slot_implausible;
            return;
        }
        if (!record.storage_read) {
            record.state = .unresolved;
            return;
        }
        record.state = if (record.storage_value == 0) .storage_zero else .populated;
    }

    pub fn state(self: *const Surface, which: Variable) State {
        return self.entries[index(which)].state;
    }

    pub fn entry(self: *const Surface, which: Variable) Entry {
        return self.entries[index(which)];
    }

    /// Whether the harness may write this variable, and what value.
    pub fn writeDecision(self: *const Surface, which: Variable) WriteDecision {
        const record = self.entries[index(which)];
        if (!which.writer().harnessMayWrite()) return .refused_title_owned;
        if (!which.writeShape().singleStore()) return .refused_structured_initialiser;
        const value = which.kernelValue() orelse return .refused_title_owned;
        if (record.state == .populated) return .refused_already_populated;
        if (record.state != .storage_zero) return .refused_no_storage;
        return .{ .allowed = value };
    }

    /// Record that the harness performed a write. Refuses — and does not count
    /// — a write the owner rule forbids, so a caller that ignores
    /// `writeDecision` still cannot fabricate title state.
    pub fn noteHarnessWrite(self: *Surface, which: Variable) bool {
        if (!which.writer().harnessMayWrite()) return false;
        const record = &self.entries[index(which)];
        record.harness_writes +|= 1;
        record.storage_value = which.kernelValue() orelse return false;
        record.storage_read = true;
        self.reclassify(which);
        return true;
    }

    pub fn finding(self: *const Surface) Finding {
        var result = Finding{};
        inline for (.{
            Variable.global_device,
            Variable.global_xam_device,
            Variable.gpu_clock_in_mhz,
            Variable.hsio_calibration_lock,
        }) |which| {
            const record = self.entries[index(which)];
            if (record.imported) result.imported_count += 1;
            if (record.state.usable()) result.usable_count += 1;
            if (record.imported and switch (self.writeDecision(which)) {
                .allowed => true,
                else => false,
            }) result.harness_writable_outstanding += 1;
            // Only an emulator defect blocks. A title-owned zero is progress
            // information and must never become the frontier.
            if (result.blocking == null and record.imported and
                (record.state == .unimplemented_export or record.state == .slot_implausible))
            {
                result.blocking = which;
            }
        }
        return result;
    }
};

test "the slot holds a pointer and the value lives behind it" {
    var surface = Surface{};
    surface.observeImport(.global_device, true, 0x820006B8);
    try std.testing.expectEqual(State.unresolved, surface.state(.global_device));

    // Exactly what the emulator's loader writes: the address of its 4-byte
    // system-heap allocation.
    surface.observeSlot(.global_device, 0x8010_0040);
    try std.testing.expectEqual(State.unresolved, surface.state(.global_device));

    surface.observeStorage(.global_device, 0);
    try std.testing.expectEqual(State.storage_zero, surface.state(.global_device));

    surface.observeStorage(.global_device, 0x4012_3400);
    try std.testing.expectEqual(State.populated, surface.state(.global_device));
}

// The bug this module was written to kill. A slot holding a pointer is not a
// value, and treating it as one makes an unimplemented export — whose sentinel
// is a large non-zero number — read as a healthy populated variable.
test "the unimplemented sentinel is recognised rather than read as a value" {
    var surface = Surface{};
    surface.observeImport(.gpu_clock_in_mhz, true, 0x820006C0);
    surface.observeSlot(.gpu_clock_in_mhz, unimplemented_sentinel_base | (0x1C0 << 16));
    try std.testing.expectEqual(State.unimplemented_export, surface.state(.gpu_clock_in_mhz));
    try std.testing.expectEqual(Variable.gpu_clock_in_mhz, surface.finding().blocking.?);

    // The same bit pattern under a different ordinal is not that ordinal's
    // sentinel, so it must not be absorbed as one.
    try std.testing.expect(!isUnimplementedSentinel(unimplemented_sentinel_base | (0x1C0 << 16), 0x1BE));
}

// The finding that sent the previous investigation the wrong way. A zero device
// pointer is the title not having created a device yet, and calling it the
// blocker produces harness work that cannot help and would crash the title if
// it did anything at all.
test "a title-owned zero is reported but never becomes the blocker" {
    var surface = Surface{};
    surface.observeImport(.global_device, true, 0x820006B8);
    surface.observeSlot(.global_device, 0x8010_0040);
    surface.observeStorage(.global_device, 0);

    try std.testing.expectEqual(State.storage_zero, surface.state(.global_device));
    try std.testing.expect(surface.finding().blocking == null);
    try std.testing.expectEqual(WriteDecision.refused_title_owned, surface.writeDecision(.global_device));
    try std.testing.expect(!surface.noteHarnessWrite(.global_device));
    try std.testing.expectEqual(@as(u32, 0), surface.entry(.global_device).harness_writes);
    try std.testing.expect(std.mem.indexOf(u8, Variable.global_device.meaning(), "not a missing kernel write") != null);
}

test "a kernel-owned zero is harness work, and writing it clears the outstanding item" {
    var surface = Surface{};
    surface.observeImport(.gpu_clock_in_mhz, true, 0x820006C0);
    surface.observeSlot(.gpu_clock_in_mhz, 0x8010_0080);
    surface.observeStorage(.gpu_clock_in_mhz, 0);

    try std.testing.expectEqual(@as(u32, 1), surface.finding().harness_writable_outstanding);
    switch (surface.writeDecision(.gpu_clock_in_mhz)) {
        .allowed => |value| try std.testing.expectEqual(@as(u32, 500), value),
        else => return error.TestUnexpectedResult,
    }

    try std.testing.expect(surface.noteHarnessWrite(.gpu_clock_in_mhz));
    try std.testing.expectEqual(State.populated, surface.state(.gpu_clock_in_mhz));
    try std.testing.expectEqual(@as(u32, 0), surface.finding().harness_writable_outstanding);
    try std.testing.expectEqual(WriteDecision.refused_already_populated, surface.writeDecision(.gpu_clock_in_mhz));
}

// A half-initialised critical section is worse than an empty one: an empty one
// is recognisably empty, and a half-initialised one is a valid-looking object
// with a corrupt header that the title will take and then wait on forever.
test "a critical section is refused rather than written one dword at a time" {
    try std.testing.expectEqual(@as(?u32, null), Variable.hsio_calibration_lock.kernelValue());
    try std.testing.expectEqual(@as(u32, 28), Variable.hsio_calibration_lock.storageBytes());
    try std.testing.expect(Variable.hsio_calibration_lock.writer().harnessMayWrite());
    try std.testing.expect(!Variable.hsio_calibration_lock.writeShape().singleStore());

    var surface = Surface{};
    surface.observeImport(.hsio_calibration_lock, true, 0x82000728);
    surface.observeSlot(.hsio_calibration_lock, 0x8010_00C0);
    surface.observeStorage(.hsio_calibration_lock, 0);
    try std.testing.expectEqual(State.storage_zero, surface.state(.hsio_calibration_lock));
    try std.testing.expectEqual(
        WriteDecision.refused_structured_initialiser,
        surface.writeDecision(.hsio_calibration_lock),
    );
    // The refusal states the exact initialiser a structured writer would need,
    // so closing the gap does not require rediscovering it.
    const reason = (WriteDecision{ .refused_structured_initialiser = {} }).label();
    try std.testing.expect(std.mem.indexOf(u8, reason, "lock_count=-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, reason, "28 bytes") != null);

    // And it never counts as outstanding harness work, because the harness
    // cannot currently do it.
    try std.testing.expectEqual(@as(u32, 0), surface.finding().harness_writable_outstanding);
}

// A 256-byte read of a 4-byte allocation returns 252 bytes of unrelated heap,
// and whatever it finds there becomes "the value".
test "storage sizes match the emulator's allocations rather than a forcing option" {
    try std.testing.expectEqual(@as(u32, 4), Variable.global_device.storageBytes());
    try std.testing.expectEqual(@as(u32, 4), Variable.global_xam_device.storageBytes());
    try std.testing.expectEqual(@as(u32, 4), Variable.gpu_clock_in_mhz.storageBytes());
}

test "a variable the title never imported is never a finding" {
    var surface = Surface{};
    surface.observeImport(.global_xam_device, false, 0);
    try std.testing.expectEqual(State.not_imported, surface.state(.global_xam_device));
    const finding = surface.finding();
    try std.testing.expect(finding.blocking == null);
    try std.testing.expectEqual(@as(u32, 0), finding.imported_count);
}

test "a slot holding a near-null value is implausible rather than a pointer" {
    var surface = Surface{};
    surface.observeImport(.global_device, true, 0x820006B8);
    surface.observeSlot(.global_device, 0x40);
    try std.testing.expectEqual(State.slot_implausible, surface.state(.global_device));
    try std.testing.expectEqual(Variable.global_device, surface.finding().blocking.?);

    try std.testing.expect(!plausiblePointer(0));
    try std.testing.expect(!plausiblePointer(0xFFFF_FFFF));
    try std.testing.expect(plausiblePointer(0x8010_0000));
}

test "every variable maps to and from its ordinal and describes itself" {
    inline for (.{
        Variable.global_device,
        Variable.global_xam_device,
        Variable.gpu_clock_in_mhz,
        Variable.hsio_calibration_lock,
    }) |which| {
        try std.testing.expectEqual(which, Variable.fromOrdinal(which.ordinal()).?);
        try std.testing.expect(which.name().len > 0);
        try std.testing.expect(which.meaning().len > 0);
        try std.testing.expect(which.storageBytes() > 0);
    }
    try std.testing.expect(Variable.fromOrdinal(0x1C2) == null);
}

// Re-reading the slot must invalidate the storage read taken through the old
// pointer, or a stale value survives a relocation and reads as populated.
test "a new slot value discards the value read through the previous one" {
    var surface = Surface{};
    surface.observeImport(.gpu_clock_in_mhz, true, 0x820006C0);
    surface.observeSlot(.gpu_clock_in_mhz, 0x8010_0080);
    surface.observeStorage(.gpu_clock_in_mhz, 500);
    try std.testing.expectEqual(State.populated, surface.state(.gpu_clock_in_mhz));

    surface.observeSlot(.gpu_clock_in_mhz, 0x8010_00C0);
    try std.testing.expectEqual(State.unresolved, surface.state(.gpu_clock_in_mhz));
}
