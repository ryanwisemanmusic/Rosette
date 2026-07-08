const std = @import("std");

pub const Phase = enum {
    dyld_bind,
    launch_arguments,
    logging,
    logging_ready,
    static_init,
    main_enter,
    gtk_init,
    appkit_activate,
    config_load,
    cpu_feature_detect,
    emulator_setup,
    memory_map,
    heap_init,
    gpu_create,
    module_load,
    main_loop,
};

pub const PhaseTiming = struct {
    phase: Phase,
    start_step: u64,
};

pub const Snapshot = struct {
    step: u64,
    rip: u64,
    symbol: []const u8,
    symbol_offset: u64,
    heap_next: u64,
    import_calls: u64,
    fs_open: u64,
    fs_read: u64,
    fs_write: u64,
    heap_allocations: u64,
    heap_live: usize,
    options_seen: u64,
    options_kept: u64,
    options_skipped: u64,
    logging_lines: u64,
    pthread_created: u64,
    pthread_waits_collapsed: u64,
    pthread_blocked: u64 = 0,
    diagnostic_text_runs: u64 = 0,
    diagnostic_text_lines: u64 = 0,
    thread_id: u64 = 0,
};

pub const Observer = struct {
    enabled: bool = false,
    phase: Phase = .dyld_bind,
    phase_start_step: u64 = 0,
    checkpoints: u64 = 0,
    last_symbol: []const u8 = "<unknown>",
    same_symbol_checkpoints: u64 = 0,
    heartbeat_step: u64 = 0,
    heartbeat_last_wall: u64 = 0,
    stuck_pc_symbol: []const u8 = "",
    stuck_pc_count: u64 = 0,
    timing_stack: [16]PhaseTiming = undefined,
    timing_depth: usize = 0,

    pub fn enter(self: *Observer, phase: Phase, step: u64) void {
        if (self.phase == phase) return;
        const elapsed = step -| self.phase_start_step;
        const prev = self.phase;

        if (self.timing_depth < self.timing_stack.len) {
            self.timing_stack[self.timing_depth] = .{
                .phase = prev,
                .start_step = self.phase_start_step,
            };
            self.timing_depth += 1;
        }

        self.phase = phase;
        self.phase_start_step = step;
        self.last_symbol = "<unknown>";
        self.same_symbol_checkpoints = 0;
        std.debug.print(
            "macho-processor: startup phase transition: {s} -> {s} at step {d} (+{d} steps)\n",
            .{ @tagName(prev), @tagName(phase), step, elapsed },
        );
    }

    pub fn heartbeat(self: *Observer, snapshot: Snapshot) void {
        const step_delta = snapshot.step -| self.heartbeat_step;
        self.heartbeat_step = snapshot.step;

        const now = monotonicNanoseconds();
        const interval_ns = if (self.heartbeat_last_wall == 0) 0 else now -| self.heartbeat_last_wall;
        const steps_per_sec = calculateStepsPerSecond(step_delta, interval_ns);
        self.heartbeat_last_wall = now;

        if (std.mem.eql(u8, self.stuck_pc_symbol, snapshot.symbol)) {
            self.stuck_pc_count += 1;
        } else {
            self.stuck_pc_symbol = snapshot.symbol;
            self.stuck_pc_count = 1;
        }

        const phase_str = @tagName(self.phase);
        std.debug.print(
            "info(macho): heartbeat phase={s} step={d} delta={d} {d}steps/s rip=0x{x} {s}+0x{x} thread=0x{x} heap=0x{x} imports={d} fs(r/w)={d}/{d} pthread(created/blocked/waits)={d}/{d}/{d}\n",
            .{
                phase_str,
                snapshot.step,
                step_delta,
                steps_per_sec,
                snapshot.rip,
                snapshot.symbol,
                snapshot.symbol_offset,
                snapshot.thread_id,
                snapshot.heap_next,
                snapshot.import_calls,
                snapshot.fs_read,
                snapshot.fs_write,
                snapshot.pthread_created,
                snapshot.pthread_blocked,
                snapshot.pthread_waits_collapsed,
            },
        );
        if (self.stuck_pc_count >= 3) {
            std.debug.print(
                "info(macho): stuck-pc warning: {s} for {d} heartbeats ({d}M steps) at {d}steps/s\n",
                .{ snapshot.symbol, self.stuck_pc_count, self.stuck_pc_count * step_delta / 1_000_000, steps_per_sec },
            );
        }
    }

    pub fn checkpoint(self: *Observer, snapshot: Snapshot) void {
        if (!self.enabled) return;
        self.checkpoints +|= 1;
        if (std.mem.eql(u8, self.last_symbol, snapshot.symbol)) {
            self.same_symbol_checkpoints +|= 1;
        } else {
            self.last_symbol = snapshot.symbol;
            self.same_symbol_checkpoints = 1;
        }
        std.debug.print(
            "info(macho): startup phase={s} step={d} at {s}+0x{x} rip=0x{x} heap=0x{x} imports={d} fs(open/read/write)={d}/{d}/{d} guest-heap(alloc/live)={d}/{d} options(seen/kept/skipped)={d}/{d}/{d} logging(lines)={d} pthread(created/waits-collapsed/blocked)={d}/{d}/{d} text-dump(runs/lines)={d}/{d} same-symbol={d}\n",
            .{
                @tagName(self.phase),         snapshot.step,                 snapshot.symbol,
                snapshot.symbol_offset,       snapshot.rip,                  snapshot.heap_next,
                snapshot.import_calls,        snapshot.fs_open,              snapshot.fs_read,
                snapshot.fs_write,            snapshot.heap_allocations,     snapshot.heap_live,
                snapshot.options_seen,        snapshot.options_kept,         snapshot.options_skipped,
                snapshot.logging_lines,       snapshot.pthread_created,      snapshot.pthread_waits_collapsed,
                snapshot.pthread_blocked,     snapshot.diagnostic_text_runs, snapshot.diagnostic_text_lines,
                self.same_symbol_checkpoints,
            },
        );
    }

    pub fn logSummary(self: *const Observer) void {
        std.debug.print(
            "macho-processor: startup observer: final_phase={s} checkpoints={d} phase_steps={d} depth={d}\n",
            .{ @tagName(self.phase), self.checkpoints, self.phase_start_step, self.timing_depth },
        );
    }

    pub fn timingSummary(self: *const Observer) void {
        if (self.timing_depth == 0) return;
        std.debug.print("macho-processor: startup phase timing report (steps):\n", .{});
        for (0..self.timing_depth) |i| {
            const t = &self.timing_stack[i];
            const elapsed_steps = if (i + 1 < self.timing_depth)
                self.timing_stack[i + 1].start_step -| t.start_step
            else
                self.phase_start_step -| t.start_step;
            std.debug.print(
                "  phase={s} start_step={d} duration_steps={d}\n",
                .{ @tagName(t.phase), t.start_step, elapsed_steps },
            );
        }
        std.debug.print(
            "  phase={s} current at step={d} (active)\n",
            .{ @tagName(self.phase), self.phase_start_step },
        );
    }
};

fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(timestamp.nsec));
}

fn calculateStepsPerSecond(step_delta: u64, interval_ns: u64) u64 {
    if (interval_ns == 0) return 0;
    const scaled = @as(u128, step_delta) * std.time.ns_per_s;
    return @intCast(@min(scaled / interval_ns, std.math.maxInt(u64)));
}

test "heartbeat throughput uses nanosecond interval" {
    try std.testing.expectEqual(@as(u64, 500_000), calculateStepsPerSecond(5_000_000, 10 * std.time.ns_per_s));
    try std.testing.expectEqual(@as(u64, 0), calculateStepsPerSecond(5_000_000, 0));
}

test "observer tracks repeated checkpoint symbols" {
    var observer = Observer{ .enabled = true };
    const snapshot = Snapshot{
        .step = 1,
        .rip = 0x1000,
        .symbol = "parse",
        .symbol_offset = 4,
        .heap_next = 0x2000,
        .import_calls = 3,
        .fs_open = 0,
        .fs_read = 0,
        .fs_write = 0,
        .heap_allocations = 0,
        .heap_live = 0,
        .options_seen = 0,
        .options_kept = 0,
        .options_skipped = 0,
        .logging_lines = 0,
        .pthread_created = 0,
        .pthread_waits_collapsed = 0,
    };
    observer.checkpoint(snapshot);
    observer.checkpoint(snapshot);
    try std.testing.expectEqual(@as(u64, 2), observer.same_symbol_checkpoints);
}

test "observer heartbeat tracks step delta" {
    var observer = Observer{};
    const s1 = Snapshot{
        .step = 1000,
        .rip = 0x1000,
        .symbol = "main",
        .symbol_offset = 0,
        .heap_next = 0x2000,
        .import_calls = 0,
        .fs_open = 0,
        .fs_read = 0,
        .fs_write = 0,
        .heap_allocations = 0,
        .heap_live = 0,
        .options_seen = 0,
        .options_kept = 0,
        .options_skipped = 0,
        .logging_lines = 0,
        .pthread_created = 0,
        .pthread_waits_collapsed = 0,
        .thread_id = 0x7fff2000,
    };
    observer.heartbeat(s1);
    try std.testing.expectEqual(@as(u64, 1000), observer.heartbeat_step);
}

test "observer phase transition timing" {
    var observer = Observer{};
    observer.enter(.main_enter, 1000);
    try std.testing.expectEqual(@as(u64, 1000), observer.phase_start_step);
    try std.testing.expectEqual(@as(Phase, .main_enter), observer.phase);
    observer.enter(.gtk_init, 2000);
    try std.testing.expectEqual(@as(u64, 2000), observer.phase_start_step);
    try std.testing.expectEqual(@as(Phase, .gtk_init), observer.phase);
    try std.testing.expectEqual(@as(usize, 2), observer.timing_depth);
}

test "observer stuck-pc detection fires after 3 heartbeats with same symbol" {
    var observer = Observer{};
    const s = Snapshot{
        .step = 1000,
        .rip = 0x1000,
        .symbol = "construct_at_PageEntry",
        .symbol_offset = 0,
        .heap_next = 0x2000,
        .import_calls = 0,
        .fs_open = 0,
        .fs_read = 0,
        .fs_write = 0,
        .heap_allocations = 0,
        .heap_live = 0,
        .options_seen = 0,
        .options_kept = 0,
        .options_skipped = 0,
        .logging_lines = 0,
        .pthread_created = 0,
        .pthread_waits_collapsed = 0,
    };
    observer.heartbeat(s);
    try std.testing.expectEqual(@as(u64, 1), observer.stuck_pc_count);
    observer.heartbeat(s);
    try std.testing.expectEqual(@as(u64, 2), observer.stuck_pc_count);
    observer.heartbeat(s);
    try std.testing.expectEqual(@as(u64, 3), observer.stuck_pc_count);
}
