//! KUSER_SHARED_DATA: the page every Windows process reads at 0x7FFE0000
//! without making a call.
//!
//! Xenia's Windows build takes the guest's interrupt time straight from it:
//! `Clock::QueryHostInterruptTime` loads `*(u64*)0x7FFE0008`, and
//! `KernelState::UpdateKeTimestampBundle` copies that into the title's
//! `KeTimeStampBundle.interrupt_time` every millisecond, which is also what
//! the guest's `KeQueryInterruptTime` returns. Rosette left the page
//! unmapped, so every read answered zero and the title's interrupt time stood
//! at zero in every run - 102,836 reads in the 2026-10-02 22:15 run alone,
//! the run in which Halo 3's renderer waited on a fence its D3D never kicked.
//!
//! The page is synthesised on read from the guest clock (it is never
//! admitted to a TLB, so every read reaches this through the read helper),
//! which keeps it exactly as current as QueryPerformanceCounter and FILETIME.

const std = @import("std");

pub const base: u64 = 0x7FFE_0000;
pub const size: u64 = 0x1000;

/// Field offsets (Windows 10, x64).
pub const tick_count_low_deprecated: u64 = 0x000;
pub const tick_count_multiplier: u64 = 0x004;
pub const interrupt_time: u64 = 0x008; // KSYSTEM_TIME
pub const system_time: u64 = 0x014; // KSYSTEM_TIME
pub const time_zone_bias: u64 = 0x020; // KSYSTEM_TIME
pub const image_number_low: u64 = 0x02C;
pub const image_number_high: u64 = 0x02E;
pub const nt_major_version: u64 = 0x26C;
pub const nt_minor_version: u64 = 0x270;
pub const qpc_frequency: u64 = 0x300;
pub const tick_count: u64 = 0x320; // KSYSTEM_TIME / TickCountQuad

/// 1.0 in 8.24 fixed point: `GetTickCount = TickCountQuad * multiplier >> 24`,
/// so the quad holds milliseconds directly.
pub const tick_multiplier_one: u32 = 0x0100_0000;

pub const Clock = struct {
    /// Time since boot in 100 ns units.
    interrupt_100ns: u64,
    /// FILETIME: 100 ns units since 1601-01-01.
    system_filetime: u64,
    /// Milliseconds since boot.
    tick_ms: u64,
    /// The performance-counter frequency the process is told.
    qpc_hz: u64,
};

pub fn contains(address: u64) bool {
    return address >= base and address - base < size;
}

/// The page's bytes at `offset`, `out.len` long, for `clock`. Fields this
/// does not model read as zero, as an unused field does on Windows.
pub fn read(offset: u64, out: []u8, clock: Clock) void {
    var page: [0x340]u8 = @splat(0);
    writeKSystemTime(&page, interrupt_time, clock.interrupt_100ns);
    writeKSystemTime(&page, system_time, clock.system_filetime);
    writeKSystemTime(&page, tick_count, clock.tick_ms);
    std.mem.writeInt(u32, page[tick_count_low_deprecated..][0..4], @truncate(clock.tick_ms), .little);
    std.mem.writeInt(u32, page[tick_count_multiplier..][0..4], tick_multiplier_one, .little);
    std.mem.writeInt(u16, page[image_number_low..][0..2], 0x8664, .little);
    std.mem.writeInt(u16, page[image_number_high..][0..2], 0x8664, .little);
    std.mem.writeInt(u32, page[nt_major_version..][0..4], 10, .little);
    std.mem.writeInt(u32, page[nt_minor_version..][0..4], 0, .little);
    std.mem.writeInt(u64, page[qpc_frequency..][0..8], clock.qpc_hz, .little);
    for (out, 0..) |*byte, index| {
        const at = offset + index;
        byte.* = if (at < page.len) page[@intCast(at)] else 0;
    }
}

/// A KSYSTEM_TIME: LowPart, High1Time, High2Time. A reader that sees
/// High1Time == High2Time has a consistent value; synthesised on read, it is
/// always consistent.
fn writeKSystemTime(page: []u8, offset: u64, value: u64) void {
    const at: usize = @intCast(offset);
    std.mem.writeInt(u32, page[at..][0..4], @truncate(value), .little);
    std.mem.writeInt(u32, page[at + 4 ..][0..4], @truncate(value >> 32), .little);
    std.mem.writeInt(u32, page[at + 8 ..][0..4], @truncate(value >> 32), .little);
}

pub fn readScalar(comptime T: type, address: u64, clock: Clock) T {
    var bytes: [@sizeOf(T)]u8 = undefined;
    read(address - base, &bytes, clock);
    return std.mem.readInt(T, &bytes, .little);
}

test "Xenia's interrupt-time read sees the clock" {
    const clock = Clock{ .interrupt_100ns = 0x1_2345_6789, .system_filetime = 0x01DC_7AB1_B3D4_F162, .tick_ms = 12345, .qpc_hz = 1_000_000 };
    // Clock::QueryHostInterruptTime: *(u64*)(0x7FFE0000 + 8).
    try std.testing.expectEqual(@as(u64, 0x1_2345_6789), readScalar(u64, base + interrupt_time, clock));
    try std.testing.expectEqual(@as(u64, 0x01DC_7AB1_B3D4_F162), readScalar(u64, base + system_time, clock));
    try std.testing.expectEqual(@as(u32, 0x0000_0001), readScalar(u32, base + interrupt_time + 8, clock));
    // GetTickCount's arithmetic gives milliseconds back.
    const quad = readScalar(u64, base + tick_count, clock);
    const multiplier = readScalar(u32, base + tick_count_multiplier, clock);
    try std.testing.expectEqual(@as(u64, 12345), (quad * multiplier) >> 24);
    try std.testing.expectEqual(@as(u32, 10), readScalar(u32, base + nt_major_version, clock));
    try std.testing.expect(contains(base + 0xFFF));
    try std.testing.expect(!contains(base + 0x1000));
}
