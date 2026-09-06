const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;
const execution_profile = @import("execution_profile.zig");

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
    /// Where `rip` lives, so the profile can tell generated code from a hole
    /// in the symbol table. Callers that cannot answer leave it `unstated`.
    symbol_origin: execution_profile.Origin = .unstated,
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
    /// Digest of volatile execution state (normally registers). A non-zero
    /// value distinguishes a progressing hot loop from an unchanged PC.
    execution_fingerprint: u64 = 0,
};

pub const StallPolicy = struct {
    min_repeated_samples: u64 = 3,
    min_same_state_steps: u64 = 15_000_000,
    min_same_state_ns: u64 = 10 * std.time.ns_per_s,
    diagnostic_cooldown_ns: u64 = 30 * std.time.ns_per_s,
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
    stuck_thread_id: u64 = 0,
    stuck_rip: u64 = 0,
    stuck_execution_fingerprint: u64 = 0,
    stuck_state_start_step: u64 = 0,
    stuck_state_start_wall: u64 = 0,
    last_stall_diagnostic_wall: u64 = 0,
    stall_diagnostic_due: bool = false,
    hot_symbol: []const u8 = "",
    hot_symbol_count: u64 = 0,
    hot_symbol_start_step: u64 = 0,
    hot_symbol_start_wall: u64 = 0,
    hot_symbol_start_heap: u64 = 0,
    hot_symbol_start_imports: u64 = 0,
    hot_symbol_start_fs_read: u64 = 0,
    last_hot_symbol_diagnostic_wall: u64 = 0,
    stall_policy: StallPolicy = .{},
    /// Where the sampled program counter has been landing, aggregated. The
    /// heartbeat prints one symbol per hundred million steps and nothing was
    /// keeping them, so the answer to "where does this run spend itself" had
    /// to be assembled by hand from the log.
    profile: execution_profile.Ledger = .{},
    timing_stack: [32]PhaseTiming = undefined,
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
        machoCapturePrint(
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

        const same_execution_state = self.stuck_thread_id == snapshot.thread_id and
            self.stuck_rip == snapshot.rip and
            (snapshot.execution_fingerprint == 0 or
                self.stuck_execution_fingerprint == snapshot.execution_fingerprint);
        if (same_execution_state) {
            self.stuck_pc_count += 1;
        } else {
            self.stuck_pc_symbol = snapshot.symbol;
            self.stuck_pc_count = 1;
            self.stuck_thread_id = snapshot.thread_id;
            self.stuck_rip = snapshot.rip;
            self.stuck_execution_fingerprint = snapshot.execution_fingerprint;
            self.stuck_state_start_step = snapshot.step;
            self.stuck_state_start_wall = now;
        }

        const same_state_steps = snapshot.step -| self.stuck_state_start_step;
        const same_state_ns = now -| self.stuck_state_start_wall;
        const cooldown_elapsed = self.last_stall_diagnostic_wall == 0 or
            now -| self.last_stall_diagnostic_wall >= self.stall_policy.diagnostic_cooldown_ns;
        self.stall_diagnostic_due = self.stuck_pc_count >= self.stall_policy.min_repeated_samples and
            same_state_steps >= self.stall_policy.min_same_state_steps and
            same_state_ns >= self.stall_policy.min_same_state_ns and
            cooldown_elapsed;

        if (std.mem.eql(u8, self.hot_symbol, snapshot.symbol)) {
            self.hot_symbol_count +|= 1;
        } else {
            self.hot_symbol = snapshot.symbol;
            self.hot_symbol_count = 1;
            self.hot_symbol_start_step = snapshot.step;
            self.hot_symbol_start_wall = now;
            self.hot_symbol_start_heap = snapshot.heap_next;
            self.hot_symbol_start_imports = snapshot.import_calls;
            self.hot_symbol_start_fs_read = snapshot.fs_read;
        }
        const hot_symbol_steps = snapshot.step -| self.hot_symbol_start_step;
        const hot_symbol_ns = now -| self.hot_symbol_start_wall;
        const hot_symbol_cooldown_elapsed = self.last_hot_symbol_diagnostic_wall == 0 or
            now -| self.last_hot_symbol_diagnostic_wall >= self.stall_policy.diagnostic_cooldown_ns;
        const hot_symbol_due = self.hot_symbol_count >= self.stall_policy.min_repeated_samples and
            hot_symbol_steps >= self.stall_policy.min_same_state_steps and
            hot_symbol_ns >= self.stall_policy.min_same_state_ns and
            hot_symbol_cooldown_elapsed;

        // The heartbeat already resolved the symbol. Accumulating it costs a
        // comparison per retained entry a few dozen times per run and turns
        // eighty scattered lines into one answer about where the run lives.
        self.profile.observeAt(
            snapshot.symbol,
            snapshot.symbol_origin,
            snapshot.rip,
            snapshot.step,
        );

        const phase_str = @tagName(self.phase);
        machoCapturePrint(
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
        if (self.stall_diagnostic_due) {
            self.last_stall_diagnostic_wall = now;
            machoCapturePrint(
                "info(macho): unchanged execution-state warning: thread=0x{x} rip=0x{x} {s}+0x{x} samples={d} same_state_steps={d} same_state_ms={d} at {d}steps/s\n",
                .{ snapshot.thread_id, snapshot.rip, snapshot.symbol, snapshot.symbol_offset, self.stuck_pc_count, same_state_steps, same_state_ns / std.time.ns_per_ms, steps_per_sec },
            );
        }
        if (hot_symbol_due) {
            self.last_hot_symbol_diagnostic_wall = now;
            machoCapturePrint(
                "info(macho): hot-symbol progress: phase={s} thread=0x{x} symbol={s} samples={d} duration_ms={d} translated_steps={d} rate={d}steps/s heap_delta={d} imports_delta={d} fs_read_delta={d} execution_state={s}; this is translated host-code activity, not proof of emulated-title progress\n",
                .{
                    phase_str,
                    snapshot.thread_id,
                    snapshot.symbol,
                    self.hot_symbol_count,
                    hot_symbol_ns / std.time.ns_per_ms,
                    hot_symbol_steps,
                    steps_per_sec,
                    snapshot.heap_next -| self.hot_symbol_start_heap,
                    snapshot.import_calls -| self.hot_symbol_start_imports,
                    snapshot.fs_read -| self.hot_symbol_start_fs_read,
                    if (self.stuck_pc_count > 1) "unchanged" else "changing",
                },
            );
        }
    }

    /// Consume a diagnostic request. Stall observation is intentionally
    /// non-fatal; callers may capture detail without changing guest behavior.
    pub fn takeStallDiagnostic(self: *Observer) bool {
        const due = self.stall_diagnostic_due;
        self.stall_diagnostic_due = false;
        return due;
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
        machoCapturePrint(
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
        machoCapturePrint(
            "macho-processor: startup observer: final_phase={s} checkpoints={d} phase_steps={d} depth={d}\n",
            .{ @tagName(self.phase), self.checkpoints, self.phase_start_step, self.timing_depth },
        );
    }

    pub fn timingSummary(self: *const Observer) void {
        if (self.timing_depth == 0) return;
        machoCapturePrint("macho-processor: startup phase timing report (steps):\n", .{});
        for (0..self.timing_depth) |i| {
            const t = &self.timing_stack[i];
            const elapsed_steps = if (i + 1 < self.timing_depth)
                self.timing_stack[i + 1].start_step -| t.start_step
            else
                self.phase_start_step -| t.start_step;
            machoCapturePrint(
                "  phase={s} start_step={d} duration_steps={d}\n",
                .{ @tagName(t.phase), t.start_step, elapsed_steps },
            );
        }
        machoCapturePrint(
            "  phase={s} current at step={d} (active)\n",
            .{ @tagName(self.phase), self.phase_start_step },
        );
    }
};

/// Monotonic wall clock, shared with the performance heartbeat so both report
/// against the same time base.
pub fn monotonicNanoseconds() u64 {
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

test "observer stall tracking requires unchanged execution state" {
    var observer = Observer{ .stall_policy = .{
        .min_repeated_samples = 3,
        .min_same_state_steps = 0,
        .min_same_state_ns = 0,
        .diagnostic_cooldown_ns = 0,
    } };
    var s = Snapshot{
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
        .execution_fingerprint = 7,
    };
    observer.heartbeat(s);
    try std.testing.expectEqual(@as(u64, 1), observer.stuck_pc_count);
    observer.heartbeat(s);
    try std.testing.expectEqual(@as(u64, 2), observer.stuck_pc_count);
    observer.heartbeat(s);
    try std.testing.expectEqual(@as(u64, 3), observer.stuck_pc_count);
    try std.testing.expect(observer.takeStallDiagnostic());

    s.step += 1;
    s.execution_fingerprint = 8;
    observer.heartbeat(s);
    try std.testing.expectEqual(@as(u64, 1), observer.stuck_pc_count);
    try std.testing.expect(!observer.takeStallDiagnostic());
}
