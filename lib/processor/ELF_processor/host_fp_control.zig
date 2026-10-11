//! Guest MXCSR on the host's FPCR.
//!
//! x86 SSE/AVX arithmetic obeys MXCSR: FTZ (bit 15) flushes denormal results to
//! zero, DAZ (bit 6) reads denormal inputs as zero, and RC (bits 13-14) picks
//! the rounding mode. Rosette executes those instructions with native AArch64
//! floating point - interpreted and translated alike - and AArch64 arithmetic
//! obeys FPCR instead: FZ (bit 24) is DAZ and FTZ together, RMode (bits 22-23)
//! the rounding mode. Storing MXCSR without moving FPCR made every guest run
//! with denormals kept and round-to-nearest, whatever it asked for.
//!
//! That is not a corner case for Xenia. Its PowerPC JIT loads MXCSR 0x9FC0
//! (FTZ | DAZ) around VMX code, because the Xbox 360's VMX unit flushes
//! denormals in non-Java mode, and 0x1F80..0xFF80 from the guest FPSCR for
//! FPU code (`x64_backend.cc` `mxcsr_table`). Titles are written for the
//! flush: Halo 3's CPU-side per-object lighting arrived on the GPU with
//! spherical-harmonics coefficients of 1e8-1e22 and NaN for some objects
//! (GFXReconstruct captures of 2026-10-09, `tools/vulkan/capture_constants.py`)
//! while other objects' coefficients were ordinary, the pattern of a guard
//! against a vanishing length that a kept denormal walks past.
//!
//! FPCR is per host thread. Each parallel guest worker owns its thread, so
//! applying the guest value whenever MXCSR is loaded, and whenever a guest
//! context is bound to a thread, keeps the two equal. ARM has one bit for
//! DAZ and FTZ; either x86 bit sets it (Xenia only ever sets both, or FTZ
//! alone for the PowerPC non-IEEE FPU mode).
const std = @import("std");
const builtin = @import("builtin");

pub const fpcr_fz: u64 = 1 << 24;
pub const fpcr_rmode_shift: u6 = 22;
/// The FPCR bits MXCSR owns. AHP, DN, FZ16 and the trap enables stay host's.
pub const fpcr_guest_mask: u64 = fpcr_fz | (@as(u64, 3) << fpcr_rmode_shift);

pub const mxcsr_ftz: u32 = 1 << 15;
pub const mxcsr_daz: u32 = 1 << 6;
pub const mxcsr_rc_shift: u5 = 13;
pub const mxcsr_default: u32 = 0x1F80;

const supported = builtin.cpu.arch == .aarch64;

/// FPCR bits (within `fpcr_guest_mask`) for an MXCSR value.
pub fn fpcrBits(mxcsr: u32) u64 {
    const flush: u64 = if (mxcsr & (mxcsr_ftz | mxcsr_daz) != 0) fpcr_fz else 0;
    // x86 RC: 00 nearest, 01 toward -inf, 10 toward +inf, 11 toward zero.
    // ARM RMode: 00 nearest, 01 toward +inf, 10 toward -inf, 11 toward zero.
    const rc: u64 = (mxcsr >> mxcsr_rc_shift) & 3;
    const rmode = ((rc & 1) << 1) | (rc >> 1);
    return flush | (rmode << fpcr_rmode_shift);
}

pub inline fn read() u64 {
    if (!supported) return 0;
    return asm volatile ("mrs %[value], fpcr"
        : [value] "=r" (-> u64),
    );
}

pub inline fn write(value: u64) void {
    if (!supported) return;
    asm volatile ("msr fpcr, %[value]"
        :
        : [value] "r" (value),
        : .{ .memory = true });
}

/// Make this host thread's floating point behave as `mxcsr` asks.
pub inline fn applyGuestMxcsr(mxcsr: u32) void {
    if (!supported) return;
    const current = read();
    const wanted = (current & ~fpcr_guest_mask) | fpcrBits(mxcsr);
    if (wanted != current) write(wanted);
}

/// True when this host thread already matches `mxcsr`.
pub inline fn matchesGuestMxcsr(mxcsr: u32) bool {
    if (!supported) return true;
    return (read() & fpcr_guest_mask) == fpcrBits(mxcsr);
}

/// The x86 power-on MXCSR: nearest rounding, denormals kept.
pub fn restoreDefault() void {
    applyGuestMxcsr(mxcsr_default);
}

test "MXCSR modes map onto FPCR flush and rounding bits" {
    try std.testing.expectEqual(@as(u64, 0), fpcrBits(0x1F80));
    // Xenia's VMX mode: FTZ | DAZ.
    try std.testing.expectEqual(fpcr_fz, fpcrBits(0x9FC0));
    // Xenia's PowerPC non-IEEE FPU mode: FTZ alone still flushes.
    try std.testing.expectEqual(fpcr_fz, fpcrBits(0x9F80));
    // mxcsr_table rounding modes: toward zero, +inf, -inf.
    try std.testing.expectEqual(@as(u64, 3) << fpcr_rmode_shift, fpcrBits(0x7F80));
    try std.testing.expectEqual(@as(u64, 1) << fpcr_rmode_shift, fpcrBits(0x5F80));
    try std.testing.expectEqual(@as(u64, 2) << fpcr_rmode_shift, fpcrBits(0x3F80));
    try std.testing.expectEqual(fpcr_fz | (@as(u64, 3) << fpcr_rmode_shift), fpcrBits(0xFF80));
}

/// Arithmetic the compiler cannot move across the FPCR write: the operands
/// come from memory the write's memory clobber orders against.
noinline fn product(a: *const volatile f32, b: *const volatile f32) f32 {
    return a.* * b.*;
}

noinline fn quotient(a: *const volatile f32, b: *const volatile f32) f32 {
    return a.* / b.*;
}

fn mul(a: f32, b: f32) f32 {
    const x: f32 = a;
    const y: f32 = b;
    return product(&x, &y);
}

test "the host flushes a denormal product only while the guest asks for it" {
    if (!supported) return error.SkipZigTest;
    const saved = read();
    defer write(saved);
    applyGuestMxcsr(0x9FC0);
    try std.testing.expect(!matchesGuestMxcsr(0x1F80));
    try std.testing.expectEqual(@as(f32, 0), mul(1e-20, 1e-20));
    // DAZ: a denormal input reads as zero.
    try std.testing.expectEqual(@as(f32, 0), mul(1e-40, 1e10));
    applyGuestMxcsr(0x1F80);
    try std.testing.expect(matchesGuestMxcsr(0x1F80));
    try std.testing.expect(mul(1e-20, 1e-20) != 0);
    try std.testing.expect(mul(1e-40, 1e10) != 0);
}

test "guest rounding mode reaches host arithmetic" {
    if (!supported) return error.SkipZigTest;
    const saved = read();
    defer write(saved);
    const one: f32 = 1.0;
    const three: f32 = 3.0;
    applyGuestMxcsr(0x5F80); // toward +inf
    const up = quotient(&one, &three);
    applyGuestMxcsr(0x3F80); // toward -inf
    const down = quotient(&one, &three);
    applyGuestMxcsr(0x1F80);
    try std.testing.expect(up > down);
    try std.testing.expectEqual(@as(u32, @bitCast(up)), @as(u32, @bitCast(down)) + 1);
}
