//! How much fragment-shader-interlock work one Metal command buffer may carry.
//!
//! macOS kills a command buffer the GPU takes too long to finish
//! (`kIOGPUCommandBufferCallbackErrorHang`, MTLCommandBufferErrorTimeout).
//! After one or a few kills it ignores every later submission from the process
//! (`kIOGPUCommandBufferCallbackErrorSubmissionsIgnored`, the "penalty box")
//! until the process exits, which MoltenVK reports as VK_ERROR_DEVICE_LOST and
//! Xenia as "Graphics device lost". Nothing recovers a process in that state,
//! so the only defence is never approaching the limit, which is undocumented.
//!
//! Under FSI every fragment of every draw reads and writes the EDRAM buffer
//! inside a raster-ordered critical section, so a command buffer's GPU time
//! follows overdraw rather than draw count. The 2026-10-05 Halo 3 campaign run
//! recorded 1,014-1,021 FSI draws into one command buffer per frame; two of
//! those buffers hung and the process was banned. MoltenVK turns each
//! VkSubmitInfo into one MTLCommandBuffer, so the bridge bounds the FSI draws
//! per VkSubmitInfo it hands the driver (see `chain.zig`).
//!
//! Both draw count and clipped scissor area times raster samples bound a chunk.
//! Submission-to-fence-observation latency conservatively bounds GPU time and
//! adapts each limit downward or upward only within the Metal policy's hard
//! ceiling. A chunk still running after `risk_ns` divides both limits by four
//! at once. That reduced ceiling survives the remainder of the run, including
//! cheap chunks; a severe chunk pins the draw cap to its minimum. Thousands
//! of representative fast completions with verified shader bounds may recover
//! sample work only as far as the original conservative 2 Mi quantum.
const std = @import("std");
const metal_policy = @import("../../metal/command_buffer_policy.zig").fsi;

pub const ns_per_ms: u64 = 1_000_000;

pub const Config = struct {
    target_chunk_ns: u64 = metal_policy.target_chunk_ns,
    risk_ns: u64 = metal_policy.risk_ns,
    severe_ns: u64 = metal_policy.severe_ns,
    min_draws: u32 = metal_policy.min_draws,
    max_draws: u32 = metal_policy.max_draws,
    initial_draws: u32 = metal_policy.initial_draws,
    min_sample_work: u64 = metal_policy.min_sample_work,
    max_sample_work: u64 = metal_policy.max_sample_work,
    initial_sample_work: u64 = metal_policy.initial_sample_work,
    hold_samples: u32 = metal_policy.hold_samples,
};

pub const Escalation = enum(u8) { none, risk, severe };

/// Upper bounds (exclusive) of the completion-latency histogram buckets, in ms. The
/// last bucket holds everything at or above the final bound.
pub const histogram_bounds_ms = [_]u64{ 5, 20, 50, 100, 250, 500, 1000 };

pub const Budget = struct {
    config: Config = .{},
    cap: u32 = metal_policy.initial_draws,
    /// Running average completion-observation latency per FSI draw; zero until the first sample.
    ns_per_draw: u64 = 0,
    /// Running average completion-observation latency per potential interlocked sample (scissor pixel times MSAA).
    ns_per_sample: u64 = 0,
    /// Adaptive work ceiling, never raised above the policy's hard maximum.
    sample_work_cap: u64 = metal_policy.initial_sample_work,
    /// Learned risk ceilings constrain ordinary calibration for this device/run.
    /// Emergency recovery has its own much lower ceiling and qualifying samples;
    /// it never restores the large protected budget that approached a hang.
    risk_draw_ceiling: u32 = std.math.maxInt(u32),
    risk_sample_ceiling: u64 = std.math.maxInt(u64),
    samples: u64 = 0,
    hold_until_sample: u64 = 0,
    emergency: bool = false,
    risk_events: u64 = 0,
    severe_events: u64 = 0,
    max_chunk_ns: u64 = 0,
    max_chunk_draws: u32 = 0,
    max_chunk_sample_work: u64 = 0,
    max_draw_sample_work: u64 = 0,
    shader_bounds_verified: bool = false,
    recovery_fast_groups: u32 = 0,
    recovery_work_cap: u64 = metal_policy.min_sample_work,
    recovery_growths: u64 = 0,
    total_observed_ns: u64 = 0,
    histogram: [histogram_bounds_ms.len + 1]u64 = [_]u64{0} ** (histogram_bounds_ms.len + 1),

    pub fn init(config: Config) Budget {
        return .{
            .config = config,
            .cap = clampCap(config, config.initial_draws),
            .sample_work_cap = clampPixels(config, config.initial_sample_work),
        };
    }

    pub fn setShaderBoundsVerified(self: *Budget, verified: bool) void {
        self.shader_bounds_verified = verified;
        self.config.max_sample_work = if (verified) metal_policy.protected_max_sample_work else metal_policy.max_sample_work;
        self.sample_work_cap = @min(self.sample_work_cap, self.config.max_sample_work);
        if (!verified and self.emergency) self.resetRecovery();
    }

    fn resetRecovery(self: *Budget) void {
        self.recovery_fast_groups = 0;
        self.recovery_work_cap = self.config.min_sample_work;
        if (self.emergency) self.sample_work_cap = self.recovery_work_cap;
    }

    fn noteRecovery(self: *Budget, sample_work: u64, observed_ns: u64) void {
        if (!self.shader_bounds_verified) {
            self.resetRecovery();
            return;
        }
        if (observed_ns > self.config.target_chunk_ns) {
            self.recovery_fast_groups = 0;
            self.recovery_work_cap = @max(self.config.min_sample_work, self.recovery_work_cap / 2);
        } else if (observed_ns > self.config.target_chunk_ns / 2) {
            self.recovery_fast_groups = 0;
        } else if (observed_ns != 0 and observed_ns <= self.config.target_chunk_ns / 2 and sample_work >= self.recovery_work_cap) {
            // Tiny scissors cannot establish the cost of a larger quantum.
            // Reserve half the target latency before doubling the work.
            self.recovery_fast_groups +|= 1;
            if (self.recovery_fast_groups >= metal_policy.recovery_samples) {
                const limit = @min(self.config.max_sample_work, metal_policy.recovery_max_sample_work);
                const next = @max(self.config.min_sample_work, @min(limit, self.recovery_work_cap *| 2));
                if (next > self.recovery_work_cap) self.recovery_growths +|= 1;
                self.recovery_work_cap = next;
                self.recovery_fast_groups = 0;
            }
        }
        // Empty/tiny/zero-duration groups cannot earn a larger quantum, but
        // do not erase fast measurements since the last slow/risk observation.
        // Otherwise a small tail every frame would prevent recovery forever.
        self.sample_work_cap = self.recovery_work_cap;
    }

    /// Whether the chunk that already holds `chunk_draws` FSI draws must be
    /// closed before the next one is recorded.
    pub fn shouldSplit(self: *const Budget, chunk_draws: u32, chunk_pixels: u64, next_draw_pixels: u64) bool {
        if (chunk_draws >= self.cap) return true;
        if (chunk_draws == 0) return false;
        if (next_draw_pixels > self.sample_work_cap) return true;
        return chunk_pixels > self.sample_work_cap - next_draw_pixels;
    }

    /// Account one completed chunk. `draws` or `sample_work` may be zero
    /// for a chunk that carried no FSI work; it still counts toward timing.
    pub fn noteChunk(self: *Budget, draws: u32, sample_work: u64, max_draw_sample_work: u64, observed_ns: u64) void {
        self.samples +|= 1;
        self.total_observed_ns +|= observed_ns;
        self.histogram[bucket(observed_ns)] +|= 1;
        if (observed_ns > self.max_chunk_ns) {
            self.max_chunk_ns = observed_ns;
            self.max_chunk_draws = draws;
        }
        self.max_chunk_sample_work = @max(self.max_chunk_sample_work, sample_work);
        self.max_draw_sample_work = @max(self.max_draw_sample_work, max_draw_sample_work);
        if (draws == 0) {
            if (self.emergency) self.noteRecovery(0, observed_ns);
            return;
        }
        const per_draw = @max(@as(u64, 1), observed_ns / draws);
        self.ns_per_draw = if (self.ns_per_draw == 0) per_draw else (self.ns_per_draw * 7 + per_draw) / 8;
        if (sample_work != 0) {
            // Integer rounding must not turn a nonzero observation into a
            // zero-cost workload and therefore the policy's maximum cap.
            const per_pixel = @max(@as(u64, 1), observed_ns / sample_work);
            self.ns_per_sample = if (self.ns_per_sample == 0) per_pixel else (self.ns_per_sample * 7 + per_pixel) / 8;
            const fit = self.config.target_chunk_ns / @max(self.ns_per_sample, 1);
            const calibrated_max = if (self.shader_bounds_verified and self.samples < metal_policy.calibration_samples)
                metal_policy.max_sample_work
            else
                self.config.max_sample_work;
            const proposed_pixels = @min(@min(self.risk_sample_ceiling, clampPixels(self.config, fit)), calibrated_max);
            if (self.emergency) {
                self.noteRecovery(sample_work, observed_ns);
            } else if (self.samples < self.hold_until_sample) {
                // A risk response may tighten the work ceiling during the hold,
                // but a few cheap chunks cannot immediately undo it.
                if (proposed_pixels < self.sample_work_cap) self.sample_work_cap = proposed_pixels;
            } else {
                self.sample_work_cap = @min(proposed_pixels, self.sample_work_cap *| 2);
            }
        }
        if (self.emergency) {
            if (sample_work == 0) self.noteRecovery(0, observed_ns);
            self.cap = self.config.min_draws;
            return;
        }
        const proposed = @min(self.risk_draw_ceiling, self.capForCost());
        if (self.samples < self.hold_until_sample) {
            // After a risk event only a further decrease is taken.
            if (proposed < self.cap) self.cap = proposed;
            return;
        }
        self.cap = @min(proposed, self.cap *| 2);
    }

    /// Account a chunk that is still running after `running_ns`. Returns the
    /// escalation newly reached, so the caller reports each level once per
    /// chunk; `already` is the level this chunk had reached before.
    pub fn noteOutstanding(self: *Budget, running_ns: u64, already: Escalation) Escalation {
        if (running_ns >= self.config.severe_ns and already != .severe) {
            self.severe_events +|= 1;
            self.emergency = true;
            self.resetRecovery();
            self.cap = self.config.min_draws;
            self.sample_work_cap = self.config.min_sample_work;
            self.risk_draw_ceiling = self.cap;
            self.risk_sample_ceiling = self.sample_work_cap;
            return .severe;
        }
        if (running_ns >= self.config.risk_ns and already == .none) {
            if (self.emergency) self.resetRecovery();
            self.risk_events +|= 1;
            self.cap = @max(self.config.min_draws, self.cap / 4);
            self.sample_work_cap = @max(self.config.min_sample_work, self.sample_work_cap / 4);
            self.risk_draw_ceiling = @min(self.risk_draw_ceiling, self.cap);
            self.risk_sample_ceiling = @min(self.risk_sample_ceiling, self.sample_work_cap);
            self.hold_until_sample = self.samples + self.config.hold_samples;
            return .risk;
        }
        return .none;
    }

    pub fn meanChunkNs(self: *const Budget) u64 {
        if (self.samples == 0) return 0;
        return self.total_observed_ns / self.samples;
    }

    /// The smallest histogram bound at or above `fraction` of the samples,
    /// in ms (the last bucket reports its lower bound).
    pub fn percentileMs(self: *const Budget, fraction_per_mille: u64) u64 {
        if (self.samples == 0) return 0;
        const wanted = (self.samples * fraction_per_mille + 999) / 1000;
        var seen: u64 = 0;
        for (self.histogram, 0..) |count, index| {
            seen += count;
            if (seen >= wanted) {
                return if (index < histogram_bounds_ms.len) histogram_bounds_ms[index] else histogram_bounds_ms[histogram_bounds_ms.len - 1];
            }
        }
        return histogram_bounds_ms[histogram_bounds_ms.len - 1];
    }

    fn capForCost(self: *const Budget) u32 {
        if (self.ns_per_draw == 0) return self.cap;
        const fit = self.config.target_chunk_ns / @max(self.ns_per_draw, 1);
        return clampCap(self.config, @intCast(@min(fit, std.math.maxInt(u32))));
    }
};

fn clampCap(config: Config, draws: u32) u32 {
    return std.math.clamp(draws, config.min_draws, @max(config.min_draws, config.max_draws));
}

fn clampPixels(config: Config, pixels: u64) u64 {
    return std.math.clamp(pixels, config.min_sample_work, @max(config.min_sample_work, config.max_sample_work));
}

fn bucket(observed_ns: u64) usize {
    for (histogram_bounds_ms, 0..) |bound, index| {
        if (observed_ns < bound * ns_per_ms) return index;
    }
    return histogram_bounds_ms.len;
}

test "the cap starts conservative and follows the measured cost per draw" {
    var budget = Budget.init(.{});
    try std.testing.expectEqual(@as(u32, 16), budget.cap);
    try std.testing.expectEqual(@as(u64, 2 * 1024 * 1024), budget.sample_work_cap);
    try std.testing.expect(!budget.shouldSplit(15, 0, 1000));
    try std.testing.expect(budget.shouldSplit(16, 0, 1000));
    // 16 draws in 12 ms: 750 us per draw, so 53 fit in 40 ms, but the cap
    // only doubles per sample.
    budget.noteChunk(16, 1 * 1024 * 1024, 512 * 1024, 12 * ns_per_ms);
    try std.testing.expectEqual(@as(u32, 32), budget.cap);
    try std.testing.expect(budget.sample_work_cap < 4 * 1024 * 1024);
    budget.noteChunk(32, 2 * 1024 * 1024, 512 * 1024, 24 * ns_per_ms);
    try std.testing.expectEqual(@as(u32, 32), budget.cap);
    // Cheap draws never lift either ceiling past the Metal policy maximum.
    for (0..16) |_| budget.noteChunk(32, 32 * 1000, 1000, 1000);
    try std.testing.expectEqual(@as(u32, 32), budget.cap);
    try std.testing.expect(budget.sample_work_cap <= 2 * 1024 * 1024);
}

test "adaptive FSI pixel budget can grow to but never exceed the 2 M sample-work policy cap" {
    var budget = Budget.init(.{});
    try std.testing.expectEqual(@as(u64, 2 * 1024 * 1024), budget.sample_work_cap);

    // Even a cheap completion cannot exceed two million sample-work units.
    budget.noteChunk(1, 1024 * 1024, 1024 * 1024, ns_per_ms);
    try std.testing.expectEqual(@as(u64, 2 * 1024 * 1024), budget.sample_work_cap);
    try std.testing.expect(!budget.shouldSplit(1, 1024 * 1024, 1024 * 1024));
    try std.testing.expect(budget.shouldSplit(1, 1024 * 1024, 1024 * 1024 + 1));

    for (0..32) |_| budget.noteChunk(1, 1024 * 1024, 1024 * 1024, ns_per_ms);
    try std.testing.expect(budget.sample_work_cap <= budget.config.max_sample_work);
}

test "Halo 3's campaign cost shrinks the cap below one frame's thousand draws" {
    var budget = Budget.init(.{});
    // The 2026-10-05 run waited up to 1.37 s on fences for frames of about a
    // thousand FSI draws: roughly 1 ms per draw.
    budget.noteChunk(16, 16 * 1024 * 1024, 1024 * 1024, 48 * ns_per_ms);
    budget.noteChunk(16, 16 * 1024 * 1024, 1024 * 1024, 48 * ns_per_ms);
    try std.testing.expect(budget.cap <= 16);
    // Another draw beyond the multi-draw work cap starts a fresh chunk.
    try std.testing.expect(budget.shouldSplit(1, 8 * 1024 * 1024, 1));
}

test "a chunk still running at the risk bound cuts draw and pixel budgets at once and holds them" {
    var budget = Budget.init(.{});
    try std.testing.expectEqual(Escalation.none, budget.noteOutstanding(100 * ns_per_ms, .none));
    try std.testing.expectEqual(Escalation.risk, budget.noteOutstanding(250 * ns_per_ms, .none));
    try std.testing.expectEqual(@as(u32, 4), budget.cap);
    try std.testing.expectEqual(@as(u64, 512 * 1024), budget.sample_work_cap);
    // The same chunk is not reported twice at the same level.
    try std.testing.expectEqual(Escalation.none, budget.noteOutstanding(300 * ns_per_ms, .risk));
    // Cheap completions during the hold may not raise it again.
    budget.noteChunk(12, 12 * 1024 * 1024, 1024 * 1024, 1 * ns_per_ms);
    try std.testing.expectEqual(@as(u32, 4), budget.cap);
    try std.testing.expectEqual(@as(u64, 1), budget.risk_events);
}

test "a chunk past the severe bound pins the cap to the minimum for the rest of the run" {
    var budget = Budget.init(.{});
    try std.testing.expectEqual(Escalation.risk, budget.noteOutstanding(250 * ns_per_ms, .none));
    try std.testing.expectEqual(Escalation.severe, budget.noteOutstanding(1600 * ns_per_ms, .risk));
    try std.testing.expect(budget.emergency);
    try std.testing.expectEqual(@as(u32, 4), budget.cap);
    for (0..200) |_| budget.noteChunk(4, 4 * 1024 * 1024, 1024 * 1024, 1000);
    try std.testing.expectEqual(@as(u32, 4), budget.cap);
}

test "the GPU-time distribution reports what the watchdog sees" {
    var budget = Budget.init(.{});
    budget.noteChunk(0, 0, 0, 3 * ns_per_ms);
    budget.noteChunk(10, 10 * 1024 * 1024, 1024 * 1024, 30 * ns_per_ms);
    budget.noteChunk(10, 10 * 1024 * 1024, 1024 * 1024, 30 * ns_per_ms);
    budget.noteChunk(10, 10 * 1024 * 1024, 1024 * 1024, 1200 * ns_per_ms);
    try std.testing.expectEqual(@as(u64, 1200 * ns_per_ms), budget.max_chunk_ns);
    try std.testing.expectEqual(@as(u32, 10), budget.max_chunk_draws);
    try std.testing.expectEqual(@as(u64, 50), budget.percentileMs(500));
    try std.testing.expectEqual(@as(u64, 1000), budget.percentileMs(990));
    try std.testing.expectEqual(@as(u64, 315_750_000), budget.meanChunkNs());
}

test "FSI risk reductions survive thousands of cheap completions" {
    var budget = Budget.init(.{ .risk_ns = 500 * ns_per_ms, .severe_ns = 1500 * ns_per_ms });
    _ = budget.noteOutstanding(600 * ns_per_ms, .none);
    const safe_draws = budget.cap;
    const safe_pixels = budget.sample_work_cap;
    for (0..1000) |_| budget.noteChunk(4, 1024 * 1024, 256 * 1024, 1000);
    try std.testing.expect(budget.cap <= safe_draws);
    try std.testing.expect(budget.sample_work_cap <= safe_pixels);
}

test "FSI protected calibration batches full-screen MSAA without widening queue or risk limits" {
    var budget = Budget.init(.{});
    budget.setShaderBoundsVerified(true);
    const work: u64 = 1152 * 640 * 4;
    // At the old 2 M limit every one of these draws is an isolated chunk.
    try std.testing.expect(budget.shouldSplit(1, work, work));
    for (0..127) |_| budget.noteChunk(2, work * 2, work, ns_per_ms);
    try std.testing.expectEqual(metal_policy.max_sample_work, budget.sample_work_cap);
    for (0..16) |_| budget.noteChunk(2, work * 2, work, ns_per_ms);
    try std.testing.expectEqual(metal_policy.protected_max_sample_work, budget.sample_work_cap);
    var chunks: u32 = 1;
    var draws: u32 = 0;
    var chunk_work: u64 = 0;
    for (0..1000) |_| {
        if (budget.shouldSplit(draws, chunk_work, work)) {
            chunks += 1;
            draws = 0;
            chunk_work = 0;
        }
        draws += 1;
        chunk_work += work;
    }
    // 11 full-screen draws per chunk, 91 rather than 1000 chunks.
    try std.testing.expectEqual(@as(u32, 91), chunks);
    try std.testing.expectEqual(metal_policy.max_draws, budget.config.max_draws);
    try std.testing.expectEqual(metal_policy.risk_ns, budget.config.risk_ns);
    _ = budget.noteOutstanding(metal_policy.risk_ns, .none);
    const reduced = budget.sample_work_cap;
    for (0..1000) |_| budget.noteChunk(2, work * 2, work, 1000);
    try std.testing.expect(budget.sample_work_cap <= reduced);
    // Disabling/failing hardening retracts the larger work budget immediately.
    budget.setShaderBoundsVerified(false);
    try std.testing.expect(budget.sample_work_cap <= metal_policy.max_sample_work);
}

fn fsiRecoveryQualify(budget: *Budget) void {
    for (0..metal_policy.recovery_samples) |_| {
        budget.noteChunk(2, budget.sample_work_cap, budget.sample_work_cap / 2, ns_per_ms);
    }
}

test "FSI severe recovery earns only the original work quantum after representative fast completions" {
    var budget = Budget.init(.{});
    budget.setShaderBoundsVerified(true);
    _ = budget.noteOutstanding(metal_policy.severe_ns, .none);
    for (0..metal_policy.recovery_samples - 1) |_| {
        budget.noteChunk(2, metal_policy.min_sample_work, metal_policy.min_sample_work / 2, ns_per_ms);
    }
    try std.testing.expectEqual(metal_policy.min_sample_work, budget.sample_work_cap);
    budget.noteChunk(2, metal_policy.min_sample_work, metal_policy.min_sample_work / 2, ns_per_ms);
    try std.testing.expectEqual(metal_policy.min_sample_work * 2, budget.sample_work_cap);
    fsiRecoveryQualify(&budget);
    try std.testing.expectEqual(metal_policy.recovery_max_sample_work, budget.sample_work_cap);
    fsiRecoveryQualify(&budget);
    try std.testing.expectEqual(metal_policy.recovery_max_sample_work, budget.sample_work_cap);
    try std.testing.expectEqual(@as(u64, 2), budget.recovery_growths);
    try std.testing.expectEqual(metal_policy.min_draws, budget.cap);
    try std.testing.expectEqual(metal_policy.risk_ns, budget.config.risk_ns);
    try std.testing.expectEqual(metal_policy.severe_ns, budget.config.severe_ns);
    try std.testing.expect(budget.emergency);
}

test "FSI recovery does not earn work from tiny or empty groups and tolerates frame tails" {
    var budget = Budget.init(.{});
    budget.setShaderBoundsVerified(true);
    _ = budget.noteOutstanding(metal_policy.severe_ns, .none);
    for (0..metal_policy.recovery_samples * 2) |_| budget.noteChunk(4, 256, 64, 1);
    try std.testing.expectEqual(@as(u32, 0), budget.recovery_fast_groups);
    const ignored = [_]struct { draws: u32, work: u64, ns: u64 }{
        .{ .draws = 1, .work = 1, .ns = 1 },
        .{ .draws = 0, .work = 0, .ns = ns_per_ms },
        .{ .draws = 1, .work = 0, .ns = ns_per_ms },
        .{ .draws = 2, .work = metal_policy.min_sample_work, .ns = 0 },
    };
    for (0..metal_policy.recovery_samples - 1) |index| {
        budget.noteChunk(2, budget.sample_work_cap, 1, ns_per_ms);
        for (ignored) |group| budget.noteChunk(group.draws, group.work, 1, group.ns);
        try std.testing.expectEqual(@as(u32, @intCast(index + 1)), budget.recovery_fast_groups);
        try std.testing.expectEqual(metal_policy.min_sample_work, budget.sample_work_cap);
    }
    budget.noteChunk(2, budget.sample_work_cap, 1, ns_per_ms);
    try std.testing.expectEqual(metal_policy.min_sample_work * 2, budget.sample_work_cap);
    budget.noteChunk(2, budget.sample_work_cap, 1, ns_per_ms);
    budget.noteChunk(2, budget.sample_work_cap, 1, metal_policy.target_chunk_ns / 2 + 1);
    try std.testing.expectEqual(@as(u32, 0), budget.recovery_fast_groups);
}

test "FSI recovery retracts on slow work, renewed risk and incomplete shader protection" {
    var budget = Budget.init(.{});
    budget.setShaderBoundsVerified(true);
    _ = budget.noteOutstanding(metal_policy.severe_ns, .none);
    fsiRecoveryQualify(&budget);
    fsiRecoveryQualify(&budget);
    budget.noteChunk(2, budget.sample_work_cap, 1, metal_policy.target_chunk_ns + 1);
    try std.testing.expectEqual(metal_policy.recovery_max_sample_work / 2, budget.sample_work_cap);
    fsiRecoveryQualify(&budget);
    _ = budget.noteOutstanding(metal_policy.risk_ns, .none);
    try std.testing.expectEqual(metal_policy.min_sample_work, budget.sample_work_cap);
    fsiRecoveryQualify(&budget);
    budget.setShaderBoundsVerified(false);
    try std.testing.expectEqual(metal_policy.min_sample_work, budget.sample_work_cap);
    fsiRecoveryQualify(&budget);
    try std.testing.expectEqual(metal_policy.min_sample_work, budget.sample_work_cap);
    try std.testing.expectEqual(@as(u32, 0), budget.recovery_fast_groups);
    budget.setShaderBoundsVerified(true);
    fsiRecoveryQualify(&budget);
    _ = budget.noteOutstanding(metal_policy.severe_ns, .none);
    try std.testing.expectEqual(metal_policy.min_sample_work, budget.sample_work_cap);
}

test "FSI conservative recovery halves chunks for full-screen one-sample draws while MSAA stays isolated" {
    var budget = Budget.init(.{});
    budget.setShaderBoundsVerified(true);
    _ = budget.noteOutstanding(metal_policy.severe_ns, .none);
    const one_sample: u64 = 1152 * 640;
    try std.testing.expect(budget.shouldSplit(1, one_sample, one_sample));
    fsiRecoveryQualify(&budget);
    fsiRecoveryQualify(&budget);
    var chunks: u32 = 1;
    var draws: u32 = 0;
    var work: u64 = 0;
    for (0..1000) |_| {
        if (budget.shouldSplit(draws, work, one_sample)) {
            chunks += 1;
            draws = 0;
            work = 0;
        }
        draws += 1;
        work += one_sample;
    }
    try std.testing.expectEqual(@as(u32, 500), chunks);
    try std.testing.expect(budget.shouldSplit(1, one_sample * 4, one_sample * 4));
}
