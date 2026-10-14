//! Bounded, cancellable backoff for repeated NT yields and quiet PAUSE loops.
//! NT role restrictions remain separate. Runs after the execution lease ends.
//! Never changes guest wait status, deadlines, clock or synchronization tables.
const std = @import("std");
const clock = @import("concurrency");
const pause = @import("pause_backoff.zig");

pub const Config = struct {
    warm_yields: u32 = 16,
    min_episode_ns: u64 = 2_000_000,
    max_steps_between_yields: u64 = 512,
    max_gap_ns: u64 = 200_000,
    initial_wait_ns: u64 = 100_000,
    max_wait_ns: u64 = 500_000,
};
pub const Counters = struct {
    explicit: u64 = 0,
    excluded: u64 = 0,
    progress_resets: u64 = 0,
    parks: u64 = 0,
    wait_ns: u64 = 0,
    notified: u64 = 0,
    stopped: u64 = 0,
};
pub const Ledger = struct {
    enabled: bool = true,
    pause_translated_enabled: bool = true,
    pause: pause.Ledger = .{},
    values: [7]std.atomic.Value(u64) = @splat(.init(0)),
    pub fn configure(self: *Ledger, envFalse: *const fn ([:0]const u8) bool) void {
        self.enabled = !envFalse("ROSETTE_PE64_IDLE_YIELD_BACKOFF");
        self.pause.enabled = !envFalse("ROSETTE_PE64_PAUSE_BACKOFF");
        self.pause_translated_enabled = !envFalse("ROSETTE_PE64_TRANSLATED_PAUSE");
    }
    pub fn add(self: *Ledger, c: Counters) void {
        inline for (std.meta.fields(Counters), 0..) |f, i| _ = self.values[i].fetchAdd(@field(c, f.name), .monotonic);
    }
    pub fn report(self: *const Ledger) void {
        self.pause.report();
        if (self.values[0].load(.acquire) == 0) return;
        std.log.info("PE64 WORKER YIELD BACKOFF: enabled={} explicit={d} excluded={d} progress_resets={d} parks={d} host_wait_ms={d} notified={d} stopped={d} requested_max_us=500; explicit registered zero-delay yields only; noncritical title workers; guest wait status and clocks unchanged; wait duration includes host scheduling", .{ self.enabled, self.values[0].load(.acquire), self.values[1].load(.acquire), self.values[2].load(.acquire), self.values[3].load(.acquire), self.values[4].load(.acquire) / std.time.ns_per_ms, self.values[5].load(.acquire), self.values[6].load(.acquire) });
    }
};
pub const Route = struct {
    config: Config = .{},
    eligible_role: bool = false,
    site: u64 = 0,
    stack: u64 = 0,
    steps: u64 = 0,
    frame: u64 = 0,
    last_ns: u64 = 0,
    episode_ns: u64 = 0,
    registers: [13]u64 = @splat(0),
    epoch: ?u32 = null,
    consecutive: u32 = 0,
    earned_wait_ns: u64 = 0,
    counters: Counters = .{},
    pause_route: pause.Route = .{},

    pub fn setLabel(self: *Route, name: []const u8) void {
        // For NT yields only: MAIN_THREAD, RENDER, GPU, input, timer and
        // audio service workers retain ordinary yielding.
        self.eligible_role = std.mem.startsWith(u8, name, "XThread");
        self.pause_route.reset();
        self.reset();
    }
    pub fn reset(self: *Route) void {
        self.consecutive = 0;
        self.last_ns = 0;
        self.episode_ns = 0;
        self.epoch = null;
        self.earned_wait_ns = 0;
    }
    fn matches(self: *const Route, site: u64, stack: u64, steps: u64, frame: u64, registers: [13]u64) bool {
        return site == self.site and stack == self.stack and frame == self.frame and
            steps >= self.steps and steps - self.steps <= self.config.max_steps_between_yields and
            std.mem.eql(u64, &registers, &self.registers);
    }
    pub fn observe(self: *Route, site: u64, stack: u64, steps: u64, frame: u64, registers: [13]u64, now: u64) u64 {
        self.counters.explicit +|= 1;
        if (!self.eligible_role) {
            self.counters.excluded +|= 1;
            self.reset();
            return 0;
        }
        const same = self.last_ns != 0 and now >= self.last_ns and
            now - self.last_ns <= self.config.max_gap_ns and self.matches(site, stack, steps, frame, registers);
        if (!same) {
            if (self.last_ns != 0) self.counters.progress_resets +|= 1;
            self.consecutive = 0;
            self.episode_ns = now;
            // A backoff's own elapsed wait must not erase its qualification;
            // park() advances last_ns to the actual return timestamp.
            self.earned_wait_ns = 0;
        }
        self.site = site;
        self.stack = stack;
        self.steps = steps;
        self.frame = frame;
        self.registers = registers;
        self.last_ns = now;
        self.consecutive +|= 1;
        if (self.consecutive < self.config.warm_yields or now -| self.episode_ns < self.config.min_episode_ns) return 0;
        self.consecutive = 0;
        const wait = if (self.earned_wait_ns == 0) self.config.initial_wait_ns else @min(self.config.max_wait_ns, self.earned_wait_ns *| 2);
        self.earned_wait_ns = wait;
        return wait;
    }
    pub fn park(self: *Route, worker: anytype, ns: u64) void {
        const epoch = self.epoch orelse worker.epoch();
        const start = clock.monotonicNanoseconds();
        const result = worker.waitForHostBackoff(epoch, start +| ns);
        const end = clock.monotonicNanoseconds();
        self.counters.parks +|= 1;
        self.counters.wait_ns +|= end -| start;
        if (result == .changed) self.counters.notified +|= 1;
        if (result == .stopping) self.counters.stopped +|= 1;
        self.last_ns = end;
    }
    pub fn flush(self: *Route, ledger: *Ledger) void {
        self.pause_route.flush(&ledger.pause);
        ledger.add(self.counters);
        self.counters = .{};
    }
};

pub fn handle(state: anytype, thread: anytype, context: anytype, worker: anytype, route: *Route, retired: u64, pause_allowed: bool) void {
    if (context.windows_slice_pause_yield) _ = @import("parallelism").metrics.saturatingAdd(u64, &thread.pause_host_yields, 1);
    const pause_hint = context.windows_slice_pause_yield and !context.windows_guest_handoff_requested;
    const explicit = context.windows_slice_nt_zero_yield and !context.windows_slice_pause_yield and !context.windows_guest_handoff_requested;
    context.windows_guest_handoff_requested = false;
    context.windows_guest_slice_yield_requested = false;
    context.windows_slice_pause_yield = false;
    context.windows_slice_nt_zero_yield = false;
    var wait_ns: u64 = 0;
    // Unlike NT yields, an exact PAUSE explicitly names a spin hint. All
    // roles can qualify, with a shorter deadline and all GPRs/MXCSR checked.
    if (pause_hint) {
        var wants_park = false;
        if (pause_allowed and state.windows_idle_yield.pause.enabled) {
            if (!route.pause_route.observeVectors(context)) {
                if (route.pause_route.last_ns != 0) route.pause_route.counters.resets +|= 1;
                route.pause_route.reset();
            }
            const frame = @atomicLoad(u64, &state.frame_cost.swaps, .monotonic);
            wants_park = route.pause_route.observe(context.regs.rip, context.regs.rsp, frame, retired, pause.snapshot(context.regs), clock.monotonicNanoseconds());
        } else {
            route.pause_route.counters.yields +|= 1;
            route.pause_route.counters.excluded +|= 1;
            route.pause_route.reset();
        }
        if (wants_park) route.pause_route.park(worker) else std.Thread.yield() catch {};
        route.pause_route.epoch = worker.epoch();
        route.reset();
        if (route.pause_route.counters.yields >= 4096) route.pause_route.flush(&state.windows_idle_yield.pause);
        return;
    }
    route.pause_route.reset();
    if (explicit and state.windows_idle_yield.enabled and route.eligible_role) {
        const frame = @atomicLoad(u64, &state.frame_cost.swaps, .monotonic);
        const registers = registerSnapshot(context.regs);
        // Changing productive state never pays for a clock read. Critical
        // workers skip snapshots, clocks and epoch reads altogether.
        const stable = route.matches(context.regs.rip, context.regs.rsp, retired, frame, registers);
        wait_ns = route.observe(context.regs.rip, context.regs.rsp, retired, frame, registers, if (stable) clock.monotonicNanoseconds() else 0);
    } else {
        if (explicit and state.windows_idle_yield.enabled) {
            route.counters.explicit +|= 1;
            route.counters.excluded +|= 1;
        }
        route.reset();
    }
    if (wait_ns != 0) route.park(worker, wait_ns) else std.Thread.yield() catch std.atomic.spinLoopHint();
    if (route.last_ns != 0) route.epoch = worker.epoch();
    if (route.counters.explicit >= 4096) route.flush(&state.windows_idle_yield);
}

/// Exact snapshots avoid treating changing worker state as an idle episode.
/// RAX is the NT return; RCX/RDX are call arguments, RIP/RSP are checked above.
fn registerSnapshot(regs: anytype) [13]u64 {
    return .{ regs.rbx, regs.rbp, regs.rsi, regs.rdi, regs.r8, regs.r9, regs.r10, regs.r11, regs.r12, regs.r13, regs.r14, regs.r15, regs.rflags };
}

test "worker yield backoff needs a quiet episode and resets on progress" {
    var route: Route = .{};
    route.setLabel("XThread0022 (F80000D4)");
    var now: u64 = 1;
    var steps: u64 = 0;
    const regs: [13]u64 = @splat(42);
    for (0..2000) |_| {
        try std.testing.expectEqual(@as(u64, 0), route.observe(0x1000, 0x2000, steps, 1, regs, now));
        steps += 10;
        now += 1000;
    }
    try std.testing.expectEqual(@as(u64, 100000), route.observe(0x1000, 0x2000, steps, 1, regs, now));
    for (0..5) |episode| {
        for (0..16) |i| {
            now += 1000;
            steps += 10;
            const ns = route.observe(0x1000, 0x2000, steps, 1, regs, now);
            try std.testing.expectEqual(if (i == 15) @min(@as(u64, 500000), @as(u64, 200000) << @intCast(episode)) else 0, ns);
        }
    }
    var changed = regs;
    changed[3] += 1;
    try std.testing.expectEqual(@as(u64, 0), route.observe(0x1000, 0x2000, steps, 1, changed, now + 100));
    try std.testing.expectEqual(@as(u32, 1), route.consecutive);
    const cases = .{
        .{ @as(u64, 0x1001), @as(u64, 0x2000), steps, @as(u64, 1), now + 200 },
        .{ @as(u64, 0x1001), @as(u64, 0x2000), steps + 513, @as(u64, 1), now + 300 },
        .{ @as(u64, 0x1001), @as(u64, 0x2000), steps + 520, @as(u64, 2), now + 400 },
        .{ @as(u64, 0x1001), @as(u64, 0x2001), steps + 530, @as(u64, 2), now + 500 },
        .{ @as(u64, 0x1001), @as(u64, 0x2001), steps + 540, @as(u64, 2), now + 200501 },
        .{ @as(u64, 0x1001), @as(u64, 0x2001), steps + 550, @as(u64, 2), @as(u64, 1) },
    };
    inline for (cases) |c| {
        try std.testing.expectEqual(@as(u64, 0), route.observe(c[0], c[1], c[2], c[3], changed, c[4]));
        try std.testing.expectEqual(@as(u32, 1), route.consecutive);
    }
}
test "worker yield backoff excludes critical and unnamed workers" {
    for ([_][]const u8{ "MAIN_THREAD (F8000014)", "RENDER (F800010C)", "GPU Commands", "XMA Decoder", "" }) |label| {
        var route: Route = .{};
        route.setLabel(label);
        for (0..100) |i| try std.testing.expectEqual(@as(u64, 0), route.observe(1, 2, i, 0, @splat(0), i + 1));
        try std.testing.expectEqual(@as(u64, 100), route.counters.excluded);
    }
}
