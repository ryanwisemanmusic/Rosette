//! OFFLINE UPPER BOUND ONLY - never set in a run.
//!
//! What translated code would cost if guest memory sat at a fixed host
//! offset ("fastmem"): every software-TLB probe becomes a window check and
//! one add of the offset, which the glue then places where the TLB pointer
//! normally goes (`x23`). It is only correct where the guest memory a
//! benchmark touches is one host buffer and nothing is ever protected,
//! watched or unmapped - the offline benchmarks' `ElfState.mem` - because
//! no protection, alias, code page or MMIO page is checked at all. It
//! measures how much of a block's cost the probes are, to decide whether
//! the real design (host aliases, mirrored protection, fault-to-slow-path
//! recovery) is worth building.
const a64 = @import("arm64_encode");

/// The host minus guest offset of the benchmark's memory, or null (always,
/// outside the bound measurement).
pub var delta: ?u64 = null;

/// Guest addresses at or above this leave for the slow path: the window a
/// real design would reserve.
pub const window_shift: u6 = 38;

/// `t4 = guest + delta` after `guest < 2^window_shift`, where `guest` is in
/// x1 and the offset in `tlb`. Leaves NZCV alone, as the probe does.
pub fn emit(c: anytype, t2: a64.Reg, t4: a64.Reg, tlb: a64.Reg, slow: anytype) !void {
    try c.emit(a64.lsrImm(.x64, t2, 1, window_shift));
    try c.a.branchIfNonZero(.x64, t2, slow);
    try c.emit(a64.add(.x64, t4, 1, tlb));
}
