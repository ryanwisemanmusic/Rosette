//! Conservative limits for Vulkan submissions that MoltenVK turns into Metal
//! command buffers. These values describe the host Metal failure envelope;
//! they do not pretend to control Xenia's SPIR-V-to-MSL translation.

pub const FsiCommandBufferPolicy = struct {
    target_chunk_ns: u64 = 40_000_000,
    // The Oct 7 campaign's first GPU kill was observed at 507 ms. Escalate
    // before that observed failure, without claiming a documented OS limit.
    risk_ns: u64 = 200_000_000,
    severe_ns: u64 = 350_000_000,
    min_draws: u32 = 4,
    max_draws: u32 = 32,
    initial_draws: u32 = 16,
    min_sample_work: u64 = 512 * 1024,
    // Work units count scissor pixels times raster samples (4x is four
    // times the potential interlocked EDRAM work). An oversized individual
    // draw is isolated; splitting cannot bound its own execution time.
    max_sample_work: u64 = 2 * 1024 * 1024,
    // A verified shader-bounds pass protects the covered buffer-index accesses.
    // Healthy fence observations may then batch several full-screen 4x
    // draws. Queue depth and watchdog times stay unchanged.
    protected_max_sample_work: u64 = 32 * 1024 * 1024,
    calibration_samples: u64 = 128,
    // Recovery never returns to the protected 32 Mi ceiling that preceded
    // the slow campaign group. Thousands of representative, fast completed
    // groups may earn back only the original conservative work quantum.
    recovery_samples: u32 = 4096,
    recovery_max_sample_work: u64 = 2 * 1024 * 1024,
    initial_sample_work: u64 = 2 * 1024 * 1024,
    max_in_flight: usize = 2,
    hold_samples: u32 = 64,
};

/// One policy instance is shared by the FSI chunk budget and timing monitor.
pub const fsi = FsiCommandBufferPolicy{};

test "FSI Metal submission policy bounds work and queue depth conservatively" {
    try @import("std").testing.expect(fsi.min_draws <= fsi.initial_draws);
    try @import("std").testing.expect(fsi.initial_draws <= fsi.max_draws);
    try @import("std").testing.expect(fsi.min_sample_work <= fsi.initial_sample_work);
    try @import("std").testing.expect(fsi.initial_sample_work <= fsi.max_sample_work);
    try @import("std").testing.expectEqual(@as(u64, 2 * 1024 * 1024), fsi.max_sample_work);
    try @import("std").testing.expectEqual(@as(usize, 2), fsi.max_in_flight);
    try @import("std").testing.expectEqual(fsi.max_sample_work, fsi.recovery_max_sample_work);
    try @import("std").testing.expect(fsi.recovery_samples > fsi.calibration_samples);
}
