//! Route-independent: the `Vd*` video bring-up sequence and the command ring's
//! geometry.
//!
//! This is the contract at Rosette's current frontier. `HOST CONTRACT COVERAGE`
//! reports `gpu_bringup` at 0%, `VdInitializeRingBuffer` has been armed with a
//! tracepoint and hit zero times, and every stage above `ring_buffer_ready`
//! reports `PREREQUISITES_UNMET` as a consequence. Nothing in the graphics
//! stack can advance until a title calls these functions in this order.
//!
//! ## The size argument is not a byte count
//!
//! `VdInitializeRingBuffer(ptr, size_log2)` allocates
//! `1 << (size_log2 + 3)` bytes — the argument counts **quadwords**, not
//! bytes. The `+ 3` is the whole subtlety: read as a byte exponent, the ring is
//! computed eight times too small, the write pointer wraps early, and the
//! command processor reads packets that were overwritten before it got to
//! them. What that produces is not an error but a stream of malformed PM4, and
//! the resulting diagnosis lands on the packet parser.
//!
//! `VdEnableRingBufferRPtrWriteBack(ptr, block_size_log2)` has the mirror
//! problem in the other direction: the update frequency is
//! `(1 << block_size_log2) >> 2`, converting a quadword count to dwords. A
//! reader who skips the shift makes the read pointer update four times less
//! often than the title expects, and the title's own free-space calculation
//! then believes the ring is fuller than it is.
//!
//! ## Order is a precondition, not a convention
//!
//! A title cannot usefully initialise the ring before the engines exist, and
//! the command processor cannot report progress to a title that never
//! registered an interrupt callback. The order below is what a working
//! bring-up looks like, and `firstUnsatisfied` exists so a runtime can say
//! *which* step has not happened rather than reporting the whole sequence as
//! incomplete.
//!
//! ## What this package is not
//!
//! * It is not a ring. It holds no base, no size and no pointers; the live ring
//!   state is `lib/gpu/`'s.
//! * It cannot say a title called anything. Every predicate here answers a
//!   question about values it was handed.
//! * It does not initialise on the guest's behalf. The device tree records
//!   `allow-synthetic-bootstrap: false` and this package cannot override it.

const std = @import("std");

// ---------------------------------------------------------------------------
// Ring geometry
// ---------------------------------------------------------------------------

/// The exponent bias in `VdInitializeRingBuffer`. Size is in quadwords.
pub const ring_size_log2_bias: u5 = 3;

/// Bytes per quadword, which is what the bias encodes.
pub const bytes_per_quadword: u32 = 8;

/// Bytes the ring occupies for a given `size_log2` argument.
///
/// The one calculation this package exists to make impossible to get wrong.
pub fn ringBytesFor(size_log2: u5) u64 {
    return @as(u64, 1) << (size_log2 + ring_size_log2_bias);
}

/// Dwords the ring holds, which is what a packet walker counts in.
pub fn ringDwordsFor(size_log2: u5) u64 {
    return ringBytesFor(size_log2) / 4;
}

/// The read-pointer update frequency in dwords, from a block size exponent.
///
/// `(1 << block_size_log2) >> 2`: the argument counts quadwords and the
/// frequency is expressed in dwords.
pub fn readPointerUpdateFrequency(block_size_log2: u5) u32 {
    return (@as(u32, 1) << block_size_log2) >> 2;
}

/// Xenia's comment records that titles pass 6 and that the value stays at or
/// below 19. Stated so a wildly different argument is recognisable as a
/// misdecoded register rather than an unusual title.
pub const typical_writeback_block_size_log2: u5 = 6;
pub const max_writeback_block_size_log2: u5 = 19;

/// Whether a writeback block exponent is one the hardware accepts.
pub fn isPlausibleWritebackBlockSize(block_size_log2: u32) bool {
    return block_size_log2 <= max_writeback_block_size_log2;
}

/// Whether a ring size exponent yields a ring inside the guest's address space.
///
/// The console's physical space is 512 MiB; a ring larger than that was not
/// allocated by `MmAllocatePhysicalMemory` and the argument was misread.
pub const guest_physical_bytes: u64 = 0x2000_0000;

pub fn isPlausibleRingSize(size_log2: u32) bool {
    if (size_log2 > 31) return false;
    const bytes = ringBytesFor(@intCast(size_log2));
    // A ring smaller than one page cannot hold a useful batch, and one larger
    // than physical memory was never allocated.
    return bytes >= 4096 and bytes <= guest_physical_bytes;
}

// ---------------------------------------------------------------------------
// Ring buffer memory
// ---------------------------------------------------------------------------

/// The ring lives in physical memory allocated write-combined. That matters
/// for ordering: write-combined stores are not globally ordered against the
/// write-pointer store, so a producer must fence before publishing or the
/// command processor can observe an advanced pointer over stale payload.
pub const ring_memory_is_write_combined: bool = true;

/// Whether a guest address is in one of the physical windows the ring can live
/// in. Ring pointers come from `MmGetPhysicalAddress`, so a virtual-looking
/// address here means the title passed the wrong pointer.
pub fn isPhysicalWindowAddress(address: u32) bool {
    return address >= 0xA000_0000 or (address >= 0x1000_0000 and address < 0x2000_0000);
}

// ---------------------------------------------------------------------------
// Bring-up sequence
// ---------------------------------------------------------------------------

/// The video bring-up steps, in the order a title performs them.
pub const BringupStep = enum(u8) {
    /// `VdGetGraphicsAsicID`. The title branches on `< 0x10`, taking the
    /// EDRAM-initialisation path or the retrain path.
    asic_identified = 0,
    /// `VdInitializeEngines`.
    engines_initialized = 1,
    /// `VdSetGraphicsInterruptCallback`.
    interrupt_callback_registered = 2,
    /// `VdInitializeRingBuffer`.
    ring_initialized = 3,
    /// `VdEnableRingBufferRPtrWriteBack`.
    read_pointer_writeback_enabled = 4,
    /// The title advanced `CP_RB_WPTR`.
    write_pointer_published = 5,
    /// `VdSwap`.
    swap_requested = 6,

    pub fn exportName(self: BringupStep) []const u8 {
        return switch (self) {
            .asic_identified => "VdGetGraphicsAsicID",
            .engines_initialized => "VdInitializeEngines",
            .interrupt_callback_registered => "VdSetGraphicsInterruptCallback",
            .ring_initialized => "VdInitializeRingBuffer",
            .read_pointer_writeback_enabled => "VdEnableRingBufferRPtrWriteBack",
            .write_pointer_published => "CP_RB_WPTR",
            .swap_requested => "VdSwap",
        };
    }

    /// The kernel export ordinal, where the step is a call.
    ///
    /// `write_pointer_published` is a register write rather than an export, so
    /// it has no ordinal — reporting one would invent a call that never
    /// happens.
    pub fn ordinal(self: BringupStep) ?u16 {
        return switch (self) {
            .asic_identified => 0x1BC,
            .engines_initialized => 0x1C2,
            .interrupt_callback_registered => 0x1D5,
            .ring_initialized => 0x1C3,
            .read_pointer_writeback_enabled => 0x1B6,
            .write_pointer_published => null,
            .swap_requested => 0x25B,
        };
    }

    /// Who is expected to perform this step.
    ///
    /// Every one of them is the guest's. Recording that explicitly is what
    /// stops a stalled bring-up being read as a Rosette forwarding failure:
    /// there is no step here Rosette could perform on the title's behalf.
    pub fn owner(self: BringupStep) []const u8 {
        _ = self;
        return "guest:title";
    }
};

pub const bringup_order = [_]BringupStep{
    .asic_identified,
    .engines_initialized,
    .interrupt_callback_registered,
    .ring_initialized,
    .read_pointer_writeback_enabled,
    .write_pointer_published,
    .swap_requested,
};

/// A bit per step.
pub fn stepBit(step: BringupStep) u8 {
    return @as(u8, 1) << @as(u3, @intCast(@intFromEnum(step)));
}

/// The first step in the order that a `reached` mask does not contain.
///
/// Reporting the earliest gap rather than the highest reached step: a title
/// that skipped the interrupt callback but advanced the write pointer has a
/// specific problem, and reporting only "swap not requested" hides it.
pub fn firstUnsatisfied(reached: u8) ?BringupStep {
    for (bringup_order) |step| {
        if (reached & stepBit(step) == 0) return step;
    }
    return null;
}

/// Whether every step up to and including `step` is present in `reached`.
pub fn prerequisitesMet(reached: u8, step: BringupStep) bool {
    for (bringup_order) |candidate| {
        if (@intFromEnum(candidate) >= @intFromEnum(step)) break;
        if (reached & stepBit(candidate) == 0) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Graphics interrupt
// ---------------------------------------------------------------------------

/// The interrupt callback's first argument.
pub const InterruptSource = enum(u32) {
    /// An ordinary command-processor interrupt.
    command_processor = 0,
    /// The acquire/lock variant.
    acquire = 1,
    _,
};

/// The CPU number the callback is told it is running on. Xenia dispatches the
/// vsync interrupt on 2.
pub const vsync_interrupt_cpu: u32 = 2;

/// The ASIC id below which a title takes the EDRAM-initialisation path.
///
/// Xenia returns 0x11, which is above the threshold, so a title takes the
/// retrain path. Recorded because a title that unexpectedly calls
/// `VdInitializeEDRAM` is reading a different id than the one being returned.
pub const asic_id_edram_threshold: u32 = 0x10;
pub const reported_asic_id: u32 = 0x11;

pub fn takesEdramInitializationPath(asic_id: u32) bool {
    return asic_id < asic_id_edram_threshold;
}

pub fn contractIsWellFormed() bool {
    if (ringBytesFor(0) != 8) return false;
    if (readPointerUpdateFrequency(2) != 1) return false;
    if (bringup_order.len != 7) return false;
    if (takesEdramInitializationPath(reported_asic_id)) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the ring size argument counts quadwords, not bytes" {
    // The subtlety this package exists for. Read as a byte exponent the ring
    // is eight times too small, the write pointer wraps early, and the command
    // processor reads packets that were overwritten — which surfaces as
    // malformed PM4 and gets blamed on the packet parser.
    try std.testing.expectEqual(@as(u64, 8), ringBytesFor(0));
    try std.testing.expectEqual(@as(u64, 8 * 1024), ringBytesFor(10));
    // A title passing 16 gets 512 KiB, not 64 KiB.
    try std.testing.expectEqual(@as(u64, 512 * 1024), ringBytesFor(16));
    try std.testing.expect(ringBytesFor(16) != @as(u64, 1) << 16);
    // Exactly eight times the naive reading, at every exponent.
    var exponent: u5 = 0;
    while (exponent < 20) : (exponent += 1) {
        try std.testing.expectEqual(
            (@as(u64, 1) << exponent) * bytes_per_quadword,
            ringBytesFor(exponent),
        );
    }
}

test "ring dwords follow from ring bytes" {
    // A packet walker counts dwords; getting the unit wrong here mis-sizes
    // every wrap calculation.
    try std.testing.expectEqual(@as(u64, 2), ringDwordsFor(0));
    try std.testing.expectEqual(@as(u64, 128 * 1024), ringDwordsFor(16));
    try std.testing.expectEqual(ringBytesFor(12) / 4, ringDwordsFor(12));
}

test "the writeback frequency converts quadwords to dwords" {
    // (1 << n) >> 2. Skipping the shift makes the read pointer update four
    // times less often than the title expects, and the title's free-space
    // calculation then believes the ring is fuller than it is.
    try std.testing.expectEqual(@as(u32, 16), readPointerUpdateFrequency(6));
    try std.testing.expectEqual(@as(u32, 1), readPointerUpdateFrequency(2));
    // Below the shift the frequency floors to zero rather than wrapping.
    try std.testing.expectEqual(@as(u32, 0), readPointerUpdateFrequency(1));
    try std.testing.expectEqual(@as(u32, 0), readPointerUpdateFrequency(0));
}

test "the typical and maximum writeback block sizes are bounded" {
    try std.testing.expectEqual(@as(u5, 6), typical_writeback_block_size_log2);
    try std.testing.expect(isPlausibleWritebackBlockSize(6));
    try std.testing.expect(isPlausibleWritebackBlockSize(19));
    // 20 and up is a misdecoded register rather than an unusual title.
    try std.testing.expect(!isPlausibleWritebackBlockSize(20));
    try std.testing.expect(!isPlausibleWritebackBlockSize(0xFFFF_FFFF));
}

test "an implausible ring size is recognisable" {
    // A ring smaller than a page cannot hold a batch; one larger than the
    // console's physical memory was never allocated, so the argument was
    // misread rather than the title being unusual.
    try std.testing.expect(!isPlausibleRingSize(0));
    try std.testing.expect(!isPlausibleRingSize(8)); // 2 KiB
    try std.testing.expect(isPlausibleRingSize(9)); // 4 KiB
    try std.testing.expect(isPlausibleRingSize(16)); // 512 KiB
    try std.testing.expect(!isPlausibleRingSize(27)); // 1 GiB
    try std.testing.expect(!isPlausibleRingSize(32));
    try std.testing.expect(!isPlausibleRingSize(0xFFFF_FFFF));
}

test "ring pointers are physical, not virtual" {
    // The pointer comes from MmGetPhysicalAddress. A virtual-looking address
    // means the title passed the wrong pointer, and the ring then reads zeroes
    // forever with nothing faulting.
    try std.testing.expect(isPhysicalWindowAddress(0xA000_0000));
    try std.testing.expect(isPhysicalWindowAddress(0xC000_0000));
    try std.testing.expect(isPhysicalWindowAddress(0xE000_0000));
    try std.testing.expect(isPhysicalWindowAddress(0x1F00_0000));
    // A title's own code/data segment is not a ring location.
    try std.testing.expect(!isPhysicalWindowAddress(0x8200_0000));
    try std.testing.expect(!isPhysicalWindowAddress(0));
}

test "the bring-up order names the earliest missing step" {
    // Reporting only the highest step reached hides a skipped one: a title
    // that never registered the interrupt callback but did advance the write
    // pointer has a specific, different problem.
    try std.testing.expectEqual(BringupStep.asic_identified, firstUnsatisfied(0).?);

    // The state the current run is actually in: nothing reached at all.
    const nothing_reached: u8 = 0;
    try std.testing.expectEqualStrings(
        "VdGetGraphicsAsicID",
        firstUnsatisfied(nothing_reached).?.exportName(),
    );

    // Engines up, callback registered, ring not initialised.
    const partial = stepBit(.asic_identified) |
        stepBit(.engines_initialized) |
        stepBit(.interrupt_callback_registered);
    try std.testing.expectEqual(BringupStep.ring_initialized, firstUnsatisfied(partial).?);
    try std.testing.expectEqualStrings(
        "VdInitializeRingBuffer",
        firstUnsatisfied(partial).?.exportName(),
    );
}

test "a skipped step is reported even when later ones happened" {
    // Everything except the interrupt callback.
    var reached: u8 = 0;
    for (bringup_order) |step| reached |= stepBit(step);
    reached &= ~stepBit(.interrupt_callback_registered);
    try std.testing.expectEqual(
        BringupStep.interrupt_callback_registered,
        firstUnsatisfied(reached).?,
    );
}

test "a complete bring-up has no unsatisfied step" {
    var reached: u8 = 0;
    for (bringup_order) |step| reached |= stepBit(step);
    try std.testing.expect(firstUnsatisfied(reached) == null);
}

test "prerequisites are the steps strictly before this one" {
    const early = stepBit(.asic_identified) | stepBit(.engines_initialized);
    try std.testing.expect(prerequisitesMet(early, .interrupt_callback_registered));
    // The ring needs the callback first.
    try std.testing.expect(!prerequisitesMet(early, .ring_initialized));
    // The first step has no prerequisites, so it is always satisfiable.
    try std.testing.expect(prerequisitesMet(0, .asic_identified));
}

test "every call step has an ordinal and the register write does not" {
    // Giving CP_RB_WPTR an ordinal would invent a kernel call that never
    // happens; the title writes a register directly.
    for (bringup_order) |step| {
        if (step == .write_pointer_published) {
            try std.testing.expect(step.ordinal() == null);
        } else {
            try std.testing.expect(step.ordinal() != null);
        }
        try std.testing.expectEqualStrings("guest:title", step.owner());
    }
    try std.testing.expectEqual(@as(u16, 0x1C3), BringupStep.ring_initialized.ordinal().?);
    try std.testing.expectEqual(@as(u16, 0x25B), BringupStep.swap_requested.ordinal().?);
}

test "the reported ASIC id keeps the title off the EDRAM path" {
    // Xenia returns 0x11, above the 0x10 threshold. A title that unexpectedly
    // calls VdInitializeEDRAM is reading a different id than the one returned.
    try std.testing.expect(!takesEdramInitializationPath(reported_asic_id));
    try std.testing.expect(takesEdramInitializationPath(0x0F));
    try std.testing.expect(!takesEdramInitializationPath(0x10));
}

test "interrupt sources are open ended" {
    // The hardware can raise a source Xenia does not name; a checked cast
    // would trap on one rather than passing it to the title.
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(InterruptSource.command_processor));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(InterruptSource.acquire));
    const unknown: InterruptSource = @enumFromInt(7);
    try std.testing.expectEqual(@as(u32, 7), @intFromEnum(unknown));
    try std.testing.expectEqual(@as(u32, 2), vsync_interrupt_cpu);
}

test "write-combined ring memory needs a fence before publication" {
    // Recorded as a fact because the consequence is invisible: without a
    // fence the command processor can observe an advanced write pointer over
    // payload that has not landed, and the packets it reads are stale.
    try std.testing.expect(ring_memory_is_write_combined);
}
