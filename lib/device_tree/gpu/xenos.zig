//! Xenos — the Xbox 360 GPU.
//!
//! An ATI part with a unified shader architecture and a separate eDRAM die. The
//! specification numbers are recorded because they are the ones a consumer asks
//! about; the constraints below are the ones that decide whether an operation
//! Rosette is about to perform is consistent with the hardware.
//!
//! The distinction matters here more than anywhere else in the tree. The GPU is
//! reached through a command ring in *guest physical* memory, and physical
//! memory is visible through several virtual windows at different page
//! granularities. A runtime that treats those windows as unrelated regions —
//! rather than as views of the same RAM — will let the guest write a command in
//! one window and the command processor read zeroes from another, with nothing
//! anywhere reporting a fault.
//!
//! So the alias relationship is stated as a fact, and the runtime can ask
//! whether two addresses are the same storage instead of assuming they are not.

const std = @import("std");
const constraint = @import("../constraint.zig");

pub const name = "Xenos";
pub const vendor = "ATI";
pub const clock_hz: u64 = 500_000_000;

/// Unified shader architecture: every pipeline runs pixel or vertex work.
pub const unified_shaders = true;
pub const shader_simd_groups: u32 = 3;
pub const shader_processors_per_group: u32 = 16;
pub const shader_processor_count: u32 = shader_simd_groups * shader_processors_per_group;
pub const alus_per_processor: u32 = 4;

pub const texture_filtering_units: u32 = 16;
pub const texture_addressing_units: u32 = 16;
pub const render_output_units: u32 = 8;
pub const z_samples_per_rop: u32 = 2;

/// The eDRAM daughter die. Separate storage from main RAM — a framebuffer lives
/// here and is *not* addressable as part of the 512 MiB the title allocates
/// from, which is why a runtime that models it as main memory will find the
/// title's physical allocations mysteriously short.
pub const edram_bytes: u64 = 10 * 1024 * 1024;
pub const edram_bandwidth_bytes_per_second: u64 = 256 * 1024 * 1024 * 1024;

/// Guest physical memory, and the virtual windows that view it. Same storage,
/// different page granularity — that is the entire content of the alias rule.
pub const physical_size: u64 = 0x2000_0000;

pub const PhysicalWindow = struct {
    base: u32,
    /// Allocation granularity the title uses through this window.
    page_size: u64,
};

pub const physical_windows = [_]PhysicalWindow{
    .{ .base = 0xA000_0000, .page_size = 64 * 1024 },
    .{ .base = 0xC000_0000, .page_size = 16 * 1024 * 1024 },
    .{ .base = 0xE000_0000, .page_size = 4096 },
};

/// The physical offset a guest virtual address refers to, when it is inside one
/// of the physical windows.
pub fn physicalOffsetOf(guest_address: u64) ?u64 {
    const low: u32 = @truncate(guest_address);
    for (physical_windows) |window| {
        if (low < window.base) continue;
        const offset = low - window.base;
        if (offset < physical_size) return offset;
    }
    return null;
}

/// Whether two guest addresses name the same physical storage through different
/// windows. The question a command ring makes unavoidable: the guest writes
/// through one view and the command processor reads through another.
pub fn aliasesSameStorage(first: u64, second: u64) bool {
    const a = physicalOffsetOf(first) orelse return false;
    const b = physicalOffsetOf(second) orelse return false;
    return a == b;
}

/// The memory-mapped register aperture.
///
/// Xenos is programmed by storing to a 64 KiB window of guest physical address
/// space, not by calling anything. That is the fact this block exists to state,
/// because it changes how one specific observation must be read: the pages
/// behind this window are deliberately mapped **with no access at all**, so
/// that every store into them faults and the fault is what delivers the
/// register write. A runtime looking at those page permissions sees exactly
/// what a corrupted mapping looks like, and "NO_ACCESS" here is not a defect to
/// repair — repairing it would make the writes land in ordinary memory and
/// silently stop reaching the GPU.
///
/// The second thing it makes answerable: a run in which the ring never starts
/// has two very different explanations — the title never stored to these
/// registers, or it did and the stores never arrived. Those are opposite
/// findings pointing at opposite subsystems, and telling them apart requires
/// knowing which addresses are registers before anything touches them.
pub const register_aperture_base: u32 = 0x7FC8_0000;
pub const register_aperture_size: u32 = 0x1_0000;
pub const register_stride: u32 = 4;

pub fn registerApertureContains(guest_address: u64) bool {
    const low: u32 = @truncate(guest_address);
    return low >= register_aperture_base and
        low - register_aperture_base < register_aperture_size;
}

/// The register index a guest address selects, or null when the address is not
/// in the aperture. Indices are dword-numbered, which is why the ring write
/// pointer at index 0x1C5 appears at byte offset 0x714.
pub fn registerIndexOf(guest_address: u64) ?u32 {
    if (!registerApertureContains(guest_address)) return null;
    const low: u32 = @truncate(guest_address);
    return (low - register_aperture_base) / register_stride;
}

/// Registers whose traffic decides whether the command ring ever starts.
///
/// Deliberately not the whole register file: a name Rosette cannot vouch for is
/// worse than an index, because it invites a reader to trust it. Unknown
/// indices report as indices.
pub const RegisterName = struct {
    index: u32,
    name: []const u8,
};

pub const named_registers = [_]RegisterName{
    .{ .index = 0x01C0, .name = "CP_RB_BASE" },
    .{ .index = 0x01C1, .name = "CP_RB_CNTL" },
    .{ .index = 0x01C3, .name = "CP_RB_RPTR_ADDR" },
    .{ .index = 0x01C4, .name = "CP_RB_RPTR" },
    .{ .index = 0x01C5, .name = "CP_RB_WPTR" },
    .{ .index = 0x01C6, .name = "CP_RB_WPTR_DELAY" },
    .{ .index = 0x01C7, .name = "CP_RB_RPTR_WR" },
    .{ .index = 0x01C8, .name = "CP_DMA_SRC_ADDR" },
    .{ .index = 0x01C9, .name = "CP_DMA_DST_ADDR" },
    .{ .index = 0x01CA, .name = "CP_DMA_COMMAND" },
    .{ .index = 0x01CC, .name = "CP_IB1_BASE" },
    .{ .index = 0x01CD, .name = "CP_IB1_BUFSZ" },
    .{ .index = 0x01CE, .name = "CP_IB2_BASE" },
    .{ .index = 0x01CF, .name = "CP_IB2_BUFSZ" },
};

pub fn registerName(index: u32) ?[]const u8 {
    for (named_registers) |entry| {
        if (entry.index == index) return entry.name;
    }
    return null;
}

/// The three registers that constitute ring setup. A run that reaches none of
/// them has not started the GPU, whatever else it reached.
pub const ring_setup_registers = [_]u32{ 0x01C0, 0x01C1, 0x01C5 };

pub fn isRingSetupRegister(index: u32) bool {
    for (ring_setup_registers) |candidate| {
        if (candidate == index) return true;
    }
    return false;
}

/// Whether a no-access page at this address is the hardware's design or a
/// mapping defect. Asked before "repairing" a protection, because repairing
/// this one converts every future register write into a silent write to RAM.
pub fn checkRegisterProtection(guest_address: u64, readable_or_writable: bool) constraint.Check {
    if (!registerApertureContains(guest_address)) {
        return constraint.unconstrained("register-aperture-protection");
    }
    if (!readable_or_writable) return constraint.permitted("register-aperture-protection");
    return constraint.violation(
        "register-aperture-protection",
        "this address is inside the Xenos register aperture, which must be mapped with no access so that stores fault and are delivered to the register write handler. A page here that permits access will absorb register writes into ordinary memory, and the command processor will never see them — with no fault raised anywhere to say so",
    );
}

/// A command ring must live in physical memory, because the command processor
/// reads it through a physical view. A ring the guest names by a virtual
/// address outside the physical windows cannot be read by the hardware.
pub fn checkRingPlacement(ring_physical_address: u64) constraint.Check {
    if (ring_physical_address == 0) return constraint.unconstrained("ring-placement");
    if (ring_physical_address >= physical_size) {
        return constraint.violation(
            "ring-placement",
            "the command ring must lie inside the 512 MiB of guest physical memory the command processor reads; an address beyond it names storage the hardware cannot reach",
        );
    }
    return constraint.permitted("ring-placement");
}

/// Two accesses to a ring are coherent only if they resolve to the same
/// physical storage. Asking this is cheaper than discovering it as an empty ring.
pub fn checkRingCoherence(producer_address: u64, consumer_address: u64) constraint.Check {
    if (producer_address == 0 or consumer_address == 0) {
        return constraint.unconstrained("ring-alias-coherence");
    }
    if (aliasesSameStorage(producer_address, consumer_address)) {
        return constraint.permitted("ring-alias-coherence");
    }
    return constraint.violation(
        "ring-alias-coherence",
        "the producer and the consumer are using addresses that resolve to different physical storage. Xenos views one physical memory through several virtual windows, so a write in one window is visible in the others only when both resolve to the same offset — otherwise the guest writes commands nobody reads and no fault is raised anywhere",
    );
}

test "the three physical windows view one memory" {
    // Same offset through every window.
    try std.testing.expectEqual(@as(?u64, 0x1FC9_B000), physicalOffsetOf(0xA000_0000 + 0x1FC9_B000));
    try std.testing.expectEqual(@as(?u64, 0x1FC9_B000), physicalOffsetOf(0xC000_0000 + 0x1FC9_B000));
    try std.testing.expectEqual(@as(?u64, 0x1FC9_B000), physicalOffsetOf(0xE000_0000 + 0x1FC9_B000));
    // A virtual address outside them is not physical at all.
    try std.testing.expect(physicalOffsetOf(0x8258_a4a0) == null);
}

// The failure this exists to make askable: a ring written through one window and
// read through another looks like a ring nobody ever wrote.
test "addresses in different windows alias when their offsets match" {
    const ring: u64 = 0x1FC9_B000;
    try std.testing.expect(aliasesSameStorage(0xA000_0000 + ring, 0xE000_0000 + ring));
    try std.testing.expect(!aliasesSameStorage(0xA000_0000 + ring, 0xE000_0000 + ring + 0x1000));

    const coherent = checkRingCoherence(0xA000_0000 + ring, 0xE000_0000 + ring);
    try std.testing.expect(coherent.ruling.allowed());

    const incoherent = checkRingCoherence(0xA000_0000 + ring, 0xE000_0000 + ring + 0x40);
    try std.testing.expect(!incoherent.ruling.allowed());
    try std.testing.expect(std.mem.indexOf(u8, incoherent.detail, "no fault is raised") != null);
}

test "a ring beyond physical memory cannot be read by the hardware" {
    try std.testing.expect(checkRingPlacement(0x1FC9_B000).ruling.allowed());
    try std.testing.expect(!checkRingPlacement(0x2000_0000).ruling.allowed());
    // Zero is "not stated yet", not "illegal".
    try std.testing.expectEqual(constraint.Ruling.unconstrained, checkRingPlacement(0).ruling);
}

test "shader topology is derived, not restated" {
    try std.testing.expectEqual(@as(u32, 48), shader_processor_count);
    // Peak shader operations, from the parts rather than as a magic number.
    const shader_ops_per_second =
        @as(u64, shader_simd_groups) * shader_processors_per_group * alus_per_processor * clock_hz;
    try std.testing.expectEqual(@as(u64, 96_000_000_000), shader_ops_per_second);
    // Peak texel fill: one filtered sample per texture unit per clock.
    try std.testing.expectEqual(@as(u64, 8_000_000_000), @as(u64, texture_filtering_units) * clock_hz);
    // Peak pixel fill without MSAA.
    try std.testing.expectEqual(@as(u64, 4_000_000_000), @as(u64, render_output_units) * clock_hz);
    // Peak Z sample rate.
    try std.testing.expectEqual(
        @as(u64, 8_000_000_000),
        @as(u64, z_samples_per_rop) * render_output_units * clock_hz,
    );
}

test "eDRAM is separate storage from the physical heap" {
    try std.testing.expect(edram_bytes < physical_size);
    // No window maps it: the framebuffer is on its own die and is not part of
    // what the title allocates from. The windows themselves are contiguous —
    // one past the end of the 0xA0000000 view is the start of the 0xC0000000
    // view, not unmapped space — so the boundary that matters is the end of the
    // last one.
    try std.testing.expectEqual(@as(?u64, 0), physicalOffsetOf(0xC000_0000));
    try std.testing.expect(physicalOffsetOf(0xE000_0000 + physical_size) == null);
}
