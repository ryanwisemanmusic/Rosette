const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_heap = @import("guest_heap.zig");
const process_impl_instruction_decode = @import("instruction_decode.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const process_impl_windows_ui = @import("windows_ui.zig");
const __process_BlockJitState = __ProcessInternals._BlockJitState;
const __process_FrameHostSampleCategory = __ProcessInternals._FrameHostSampleCategory;
const __process_FrameHostSampleCounts = __ProcessInternals._FrameHostSampleCounts;
const __process_PE_DECODE_CACHE_ENTRIES = __ProcessInternals._PE_DECODE_CACHE_ENTRIES;
const __process_PE_DECODE_CACHE_SETS = __ProcessInternals._PE_DECODE_CACHE_SETS;
const __process_PE_DECODE_CACHE_VICTIM_ENTRIES = __ProcessInternals._PE_DECODE_CACHE_VICTIM_ENTRIES;
const __process_PE_DECODE_CACHE_VICTIM_SETS = __ProcessInternals._PE_DECODE_CACHE_VICTIM_SETS;
const __process_PE_DECODE_CACHE_VICTIM_WAYS = __ProcessInternals._PE_DECODE_CACHE_VICTIM_WAYS;
const __process_PE_DECODE_CACHE_WAYS = __ProcessInternals._PE_DECODE_CACHE_WAYS;
const __process_WINDOWS_GUEST_CLOCK_HZ = __ProcessInternals._WINDOWS_GUEST_CLOCK_HZ;
const __process_WINDOWS_GUEST_THREAD_SERVICE_SLICE = __ProcessInternals._WINDOWS_GUEST_THREAD_SERVICE_SLICE;
const __process_WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD = __ProcessInternals._WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD;
const __process_WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS = __ProcessInternals._WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS;
const __process_WINDOWS_TIMED_WAIT_SITE_CAPACITY = __ProcessInternals._WINDOWS_TIMED_WAIT_SITE_CAPACITY;
const __process_WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const __process_WindowsProgressSample = __ProcessInternals._WindowsProgressSample;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_envText = __ProcessInternals._envText;
const __process_envU64 = __ProcessInternals._envU64;
const __process_frame_attribution = __ProcessInternals._frame_attribution;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_host_profile = __ProcessInternals._host_profile;
const __process_instructionRate = __ProcessInternals._instructionRate;
const __process_isLiveWindowsGuestThread = __ProcessInternals._isLiveWindowsGuestThread;
const __process_log = __ProcessInternals._log;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_parallel_metrics = __ProcessInternals._parallel_metrics;
const __process_std = __ProcessInternals._std;
const __process_trimAddressOffset = __ProcessInternals._trimAddressOffset;
const __process_windowsTimedWaitPercent = __ProcessInternals._windowsTimedWaitPercent;
const __process_xenia_clock_probe = __ProcessInternals._xenia_clock_probe;

pub fn run(self: *ElfState) void {
    process_impl_execution.runWithLimit(self, 2_000_000);
}

pub fn sampleWindowsProgress(self: *const ElfState) __process_WindowsProgressSample {
    const graphics = &self.windows_graphics;
    var vacant: u64 = 0;
    var pending: u64 = 0;
    var runnable: u64 = 0;
    var running: u64 = 0;
    var blocked: u64 = 0;
    var completed: u64 = 0;
    var failed: u64 = 0;
    for (self.windows_guest_threads) |*thread| {
        switch (thread.status) {
            .vacant => vacant += 1,
            .pending => pending += 1,
            .runnable => runnable += 1,
            .running => running += 1,
            .blocked => blocked += 1,
            .completed => completed += 1,
            .failed => failed += 1,
        }
    }
    return .{
        .import_calls = process_impl_lifecycle.windowsImportCallCount(self) +% self.windows_unknown_import_calls,
        .graphics_calls = graphics.vulkan_calls +% graphics.native_vulkan_calls +% graphics.command_calls,
        .graphics_frames = graphics.queue_submits +% graphics.presents,
        .message_traffic = process_impl_windows_ui.windowsMessagePostCount(self),
        .paint_traffic = self.windows_paint_requests,
        .worker_traffic = self.windows_thread_service_calls +% self.windows_thread_yields +%
            self.windows_thread_blocks +% self.windows_thread_unblocks +%
            self.windows_thread_completions +% self.windows_thread_failures,
        .file_traffic = self.windows_file_open_calls +% self.windows_file_read_calls +%
            self.windows_file_write_calls,
        .worker_states = (vacant << 56) | (pending << 48) | (runnable << 40) |
            (running << 32) | (blocked << 24) | (completed << 16) | (failed << 8),
        .rip_low = self.windows_progress.window_rip_low,
        .rip_high = self.windows_progress.window_rip_high,
    };
}

pub fn countWindowsWorkers(self: *const ElfState, status: __process_WindowsGuestThreadStatus) usize {
    var total: usize = 0;
    for (self.windows_guest_threads) |*thread| {
        if (thread.status == status) total += 1;
    }
    return total;
}

pub fn reportWindowsStall(self: *ElfState, sample: __process_WindowsProgressSample) void {
    const watchdog = &self.windows_progress;
    const frozen_steps = @as(u64, watchdog.frozen_samples) *| watchdog.interval;
    const graphics = &self.windows_graphics;
    __process_log.warn(
        "PE64 STALL: no observable progress for {d} steps ({d} samples) episode={d} step={d} rip=0x{x} last_op={s} active_thread_slot={?d}",
        .{
            frozen_steps,
            watchdog.frozen_samples,
            watchdog.episodes,
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
            process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*,
        },
    );
    __process_log.warn(
        "PE64 STALL:   code visited in the last window: [0x{x},0x{x}] span={d} bytes",
        .{ sample.rip_low, sample.rip_high, sample.rip_high -| sample.rip_low },
    );
    __process_log.warn(
        "PE64 STALL:   frozen axes: imports={d} vulkan_calls={d} submits={d} presents={d} messages={d} paint(requests/deliveries)={d}/{d} workers(service/yield/complete/fail)={d}/{d}/{d}/{d} file_io={d}",
        .{
            sample.import_calls,
            sample.graphics_calls,
            graphics.queue_submits,
            graphics.presents,
            sample.message_traffic,
            self.windows_paint_requests,
            self.windows_paint_deliveries,
            self.windows_thread_service_calls,
            self.windows_thread_yields,
            self.windows_thread_completions,
            self.windows_thread_failures,
            sample.file_traffic,
        },
    );
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status == .vacant) continue;
        __process_log.warn(
            "PE64 STALL:   worker[{d}] handle=0x{x} start=0x{x} status={s} steps={d}",
            .{ index, thread.handle, thread.start_routine, @tagName(thread.status), process_impl_lifecycle.windowsGuestThreadSteps(self, thread) },
        );
    }

    // Verdicts.  Each is a rule about Rosetta's own boundaries, so they
    // apply to any PE, and each one names who is accountable rather than
    // just restating the symptom.
    const waiting_workers = countWindowsWorkers(self, .pending) + countWindowsWorkers(self, .runnable);
    const blocked_workers = countWindowsWorkers(self, .blocked);
    if (waiting_workers != 0 and process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null) {
        __process_log.warn(
            "PE64 STALL:   VERDICT worker starvation: {d} queued guest thread(s) are runnable and the main thread has not reached a cooperative service point (PAUSE, Wait*, or the message pump) in this window. Rosetta is servicing them now as a backstop; if that unblocks the run, the real fix is a service point on whatever the main thread is spinning on.",
            .{waiting_workers},
        );
    }
    if (blocked_workers != 0) {
        __process_log.warn(
            "PE64 STALL:   VERDICT {d} worker(s) are blocked on Rosetta-owned synchronization objects; SRW contentions={d} unblocks={d}. This is a synchronization wait, not an instruction decode failure.",
            .{ blocked_workers, self.windows_srw_lock_contentions, self.windows_thread_unblocks },
        );
    }
    if (self.windows_paint_requests != 0 and self.windows_paint_deliveries == 0) {
        __process_log.warn(
            "PE64 STALL:   VERDICT paint requests are not being delivered: the guest asked for {d} repaint(s) and the pump generated none. Check that the requesting window has a registered WndProc and that the guest is pumping messages.",
            .{self.windows_paint_requests},
        );
    }
    if (self.windows_paint_deliveries != 0 and graphics.presents == 0) {
        __process_log.warn(
            "PE64 STALL:   VERDICT the guest is being painted but never presents: {d} WM_PAINT delivered, {d} queue submits, 0 presents. The break is inside the guest's painter or the Vulkan surface it acquired, not in message delivery.",
            .{ self.windows_paint_deliveries, graphics.queue_submits },
        );
    }
    if (!self.windows_import_fallbacks.isEmpty()) {
        __process_log.warn(
            "PE64 STALL:   NOTE {d} import name(s) completed through an explicit ABI contract refusal in this run ({d} calls). If the stalled code is waiting on something one of them should have produced, the IMPORT CONTRACT REFUSALS block above names them.",
            .{ self.windows_import_fallbacks.count, self.windows_import_fallbacks.total_calls },
        );
    }
    if (waiting_workers == 0 and self.windows_paint_requests == 0) {
        __process_log.warn(
            "PE64 STALL:   VERDICT the guest is executing inside a {d}-byte code window without crossing any boundary Rosetta instruments. That is either a compute loop or a spin on guest memory; run with ROSETTE_ELF_TRACE_RIP=0x{x} to see what it reads.",
            .{ sample.rip_high -| sample.rip_low, process_impl_lifecycle.guestContextField(self, "regs").*.rip },
        );
    }
    __process_log.warn(
        "PE64 STALL: this report repeats on an escalating schedule and stops as soon as any axis moves. Set ROSETTE_PE64_STALL_WATCHDOG=0 to silence it, ROSETTE_PE64_STALL_SAMPLE_STEPS / ROSETTE_PE64_STALL_SAMPLES to retune it.",
        .{},
    );
}

pub fn checkWindowsPaintReachesScreen(self: *ElfState) void {
    const delivered = self.windows_paint_deliveries;
    if (delivered < __process_WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD) return;
    if (self.windows_graphics.presents != 0) return;
    const watchdog = &self.windows_progress;
    const due = if (watchdog.paint_without_present_reported_at == 0)
        __process_WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD
    else
        watchdog.paint_without_present_reported_at *| 4;
    if (delivered < due) return;
    watchdog.paint_without_present_reported_at = delivered;
    __process_log.warn(
        "PE64 PAINT NEVER REACHES THE SCREEN: {d} WM_PAINT delivered, {d} guest paint requests, {d} queue submits, 0 presents, step={d}. Message delivery is working; the break is downstream of the guest's WndProc -- its painter, the surface it acquired, or the swapchain it presents to.",
        .{ delivered, self.windows_paint_requests, self.windows_graphics.queue_submits, process_impl_lifecycle.observedExecutionSteps(self) },
    );
}

pub fn checkWindowsProgress(self: *ElfState) void {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    const watchdog = &self.windows_progress;
    if (!watchdog.enabled or !self.windows_runtime_enabled) return;
    if (process_impl_lifecycle.observedExecutionSteps(self) < watchdog.next_sample_step) return;
    watchdog.next_sample_step = process_impl_lifecycle.observedExecutionSteps(self) +| watchdog.interval;

    const sample = sampleWindowsProgress(self);
    watchdog.window_rip_low = __process_std.math.maxInt(u64);
    watchdog.window_rip_high = 0;
    checkWindowsPaintReachesScreen(self);

    const frozen = watchdog.have_previous and sample.matches(watchdog.previous);
    watchdog.previous = sample;
    watchdog.have_previous = true;

    if (!frozen) {
        if (watchdog.reported) {
            __process_log.info(
                "PE64 STALL CLEARED: progress resumed at step {d} rip=0x{x} after {d} frozen sample(s)",
                .{ process_impl_lifecycle.observedExecutionSteps(self), process_impl_lifecycle.guestContextField(self, "regs").*.rip, watchdog.frozen_samples },
            );
        }
        watchdog.frozen_samples = 0;
        watchdog.reported = false;
        watchdog.next_report_at = 0;
        return;
    }

    watchdog.frozen_samples +|= 1;
    if (watchdog.frozen_samples < watchdog.threshold) return;
    if (!watchdog.reported) {
        watchdog.episodes +|= 1;
        watchdog.next_report_at = watchdog.frozen_samples;
    }
    if (watchdog.frozen_samples < watchdog.next_report_at) return;

    watchdog.reported = true;
    watchdog.next_report_at = watchdog.frozen_samples *| 2;
    reportWindowsStall(self, sample);

    // Starvation backstop.  The cooperative scheduler normally runs a
    // worker at a PAUSE, a Wait, or a message-pump call.  A main thread
    // that reaches none of those starves every worker forever, and no
    // amount of diagnostics fixes that -- so give the queue a slice here.
    // This is bounded, happens only inside a declared stall, and is
    // reported, so it can never quietly paper over a scheduling defect.
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null and process_impl_windows_sync.nextWindowsGuestThread(self) != null) {
        const serviced = process_impl_windows_sync.serviceWindowsGuestThreads(self, __process_WINDOWS_GUEST_THREAD_SERVICE_SLICE);
        watchdog.backstop_services +|= 1;
        __process_log.warn(
            "PE64 STALL:   starvation backstop serviced a queued worker for {d} step(s) (backstop activations: {d})",
            .{ serviced, watchdog.backstop_services },
        );
    }
}

pub fn runBudgetSteps(owner_steps: u64, worker_steps_at_start: u64, worker_steps: u64) u64 {
    return owner_steps +| (worker_steps -| worker_steps_at_start);
}

pub fn totalInterpretedSteps(self: *const ElfState) u64 {
    // The scheduler's slice totals miss every worker turn served from a
    // wait, a sleep or an idle GetMessage. On 2026-09-14 that was 97% of
    // the run: 6.8B worker instructions against a denominator of 240M,
    // and a thread share of 2843%.
    if (self.parallel_guest_execution) return process_impl_lifecycle.observedExecutionSteps(self);
    return self.executed_steps +| self.windows_worker_executed_steps;
}

pub fn logStepBudget(self: *ElfState, steps: u64) void {
    printStepBudget(self, steps, true);
}

pub fn printStepBudget(self: *ElfState, steps: u64, include_jit: bool) void {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    _ = steps;
    const now = __process_monotonicNanoseconds();
    if (now == 0) return;
    const interpreted = totalInterpretedSteps(self);
    if (self.run_first_checkpoint_nanos == 0) {
        self.run_first_checkpoint_nanos = now;
        self.run_last_checkpoint_nanos = now;
        self.run_last_checkpoint_steps = interpreted;
        return;
    }
    const total_nanos = now -| self.run_first_checkpoint_nanos;
    const window_nanos = now -| self.run_last_checkpoint_nanos;
    const owner_steps = process_impl_lifecycle.ownerExecutedSteps(self);
    const worker_steps = interpreted -| owner_steps;
    const window_steps = interpreted -| self.run_last_checkpoint_steps;
    self.run_last_checkpoint_nanos = now;
    self.run_last_checkpoint_steps = interpreted;
    if (total_nanos == 0) return;

    const nanos_per_second: u64 = 1_000_000_000;
    // A 1e9 multiplier saturates u64 after 18.4B instructions. The latest
    // run retired 25.7B, so its printed lifetime rate falsely fell to 10M
    // while the window remained 13-14M. Widen before multiplying.
    const total_rate = __process_instructionRate(interpreted, total_nanos);
    const window_rate = if (window_nanos == 0) total_rate else __process_instructionRate(window_steps, window_nanos);
    const worker_percent = if (interpreted == 0) 0 else @divTrunc(worker_steps *| 100, interpreted);
    const pump_nanos = self.windows_graphics.event_pump_nanos;
    const pump_percent = if (total_nanos == 0) 0 else @divTrunc(pump_nanos *| 100, total_nanos);
    const guest_clock_snapshot = process_impl_lifecycle.windowsGuestClockSnapshot(self);
    const guest_ticks = guest_clock_snapshot.ticks;
    const guest_nanos = @divTrunc(guest_ticks *| nanos_per_second, __process_WINDOWS_GUEST_CLOCK_HZ);
    const dilation_tenths = if (total_nanos == 0) 0 else @divTrunc(guest_nanos *| 10, total_nanos);
    __process_log.info("PE64 STEP BUDGET: interpreted={d} (owner={d} workers={d}, {d}% of the run is worker threads) elapsed={d}s window={d} in {d}ms rate(window/run)={d}/{d} instructions/s host_event_pump=serviced={d} requests={d} stride_declined={d} {d}ms ({d}%); guest_clock={d}s of {d}s real (x{d}.{d} dilation, source={s}, instructions_per_tick={d}); the owner's own step counter is not the run's work, so read this rate and not the checkpoint's steps=", .{
        interpreted,
        owner_steps,
        worker_steps,
        worker_percent,
        @divTrunc(total_nanos, nanos_per_second),
        window_steps,
        @divTrunc(window_nanos, 1_000_000),
        window_rate,
        total_rate,
        self.windows_graphics.event_pump_calls,
        self.windows_graphics.event_pump_calls +| self.windows_graphics.event_pump_skips,
        self.windows_graphics.event_pump_skips,
        @divTrunc(pump_nanos, 1_000_000),
        pump_percent,
        // What the guest believes has elapsed, against what has. Every
        // timed wait the guest makes is denominated in this clock, so a
        // large gap either way is the reason a frame limiter, a timeout
        // or a watchdog behaves nothing like it does on hardware.
        @divTrunc(guest_ticks, __process_WINDOWS_GUEST_CLOCK_HZ),
        @divTrunc(total_nanos, nanos_per_second),
        // Reported to one decimal, in integers: a dilation the run does
        // not state is a dilation nobody accounts for, and it is the
        // multiplier on how often every repeating guest timer runs.
        @divTrunc(dilation_tenths, 10),
        dilation_tenths % 10,
        guest_clock_snapshot.sourceLabel(),
        guest_clock_snapshot.instructions_per_tick,
    });
    reportXeniaClock(self, now);
    // What the per-instruction machinery cost the run: the decode cache
    // (a miss is a fresh decode, a rearm is a byte comparison after a
    // generation moved) and how often the RIP boxes admitted an address
    // no handler then claimed.
    const decode_counts = process_impl_instruction_decode.decodeCacheCounts(self);
    const decode_total = decode_counts.hits +| decode_counts.rearms +| decode_counts.misses;
    const decode_miss_rate_ppm = if (decode_total == 0) 0 else @divTrunc(decode_counts.misses *| 1_000_000, decode_total);
    const decode_conflict_rate_ppm = if (decode_total == 0) 0 else @divTrunc(decode_counts.conflict_fills *| 1_000_000, decode_total);
    __process_log.info("PE64 STEP OVERHEAD: decode_cache(entries/sets/ways hits/rearms/misses/collisions)={d}/{d}/{d} {d}/{d}/{d}/{d} miss_causes(vacant/conflict/stale)={d}/{d}/{d} conflict_sources(generated/image)={d}/{d} rates(lookups/miss_ppm/conflict_ppm)={d}/{d}/{d} replacements={d} victim(entries/sets/ways hits/fills/stale)={d}/{d}/{d}/{d}/{d}/{d} hit_percent={d} hook_false_positives(total/synthetic/stub/compat)={d}/{d}/{d}/{d} generated_code_fetches={d}; victim hits recover short eviction bursts, while primary full-set conflicts and stale-byte refills remain visible and fatal under the default PE policy", .{
        __process_PE_DECODE_CACHE_ENTRIES,
        __process_PE_DECODE_CACHE_SETS,
        __process_PE_DECODE_CACHE_WAYS,
        decode_counts.hits,
        decode_counts.rearms,
        decode_counts.misses,
        decode_counts.collisions,
        decode_counts.vacant_fills,
        decode_counts.conflict_fills,
        decode_counts.stale_refills,
        decode_counts.generated_conflict_fills,
        decode_counts.image_conflict_fills,
        decode_total,
        decode_miss_rate_ppm,
        decode_conflict_rate_ppm,
        decode_counts.replacements,
        __process_PE_DECODE_CACHE_VICTIM_ENTRIES,
        __process_PE_DECODE_CACHE_VICTIM_SETS,
        __process_PE_DECODE_CACHE_VICTIM_WAYS,
        decode_counts.victim_hits,
        decode_counts.victim_fills,
        decode_counts.victim_stale_rejections,
        __process_windowsTimedWaitPercent(decode_counts.hits +| decode_counts.rearms, decode_total),
        self.step_hook_box_false_positives,
        self.step_synthetic_hook_false_positives,
        self.step_windows_stub_false_positives,
        self.step_windows_compat_hook_false_positives,
        self.windows_generated_code_fetches,
    });
    process_impl_instruction_decode.logWorkerLocalDecodeCache(self, decode_counts, decode_total);
    if (include_jit) process_impl_block_jit.reportBlockJit(self);
}

pub fn reportXeniaClock(self: *ElfState, now: u64) void {
    const snapshot = __process_xenia_clock_probe.Snapshot.read(self, self.xenia_clock.symbols) orelse {
        __process_log.info("PE64 XENIA TIME PLANE: status=unavailable required_clock_symbols_or_bytes_missing=true; Windows guest_clock alone cannot prove Xbox clock progress", .{});
        return;
    };
    const observation = self.xenia_clock.observe(snapshot, now);
    __process_log.info("PE64 XENIA TIME PLANE: status={s} frequency={d} ticks={d} host_ticks={d} ratio={d}/{d} scalar={d} no_scaling={} raw_source={} window(host_ms/xbox_ms)={d}/{d} xbox_speed={d}.{d:0>3} host_tick_delta={d}; read_only=true; stalled means inspect UpdateGuestClock/lock owner, not synthesize time or interrupts", .{
        @tagName(observation.status),      snapshot.frequency,          snapshot.guest_ticks, snapshot.host_ticks,
        snapshot.ratio_num,                snapshot.ratio_den,          snapshot.scalar,      snapshot.no_scaling,
        snapshot.raw_source,               observation.host_ms,         observation.guest_ms, observation.speed_permille / 1000,
        observation.speed_permille % 1000, observation.host_tick_delta,
    });
}

pub fn logRunHeartbeat(self: *ElfState, steps: u64) void {
    const interpreted = steps +| process_impl_lifecycle.windowsWorkerSteps(self);
    self.run_next_heartbeat_instructions = interpreted +| __process_WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS;
    self.run_heartbeats +|= 1;
    __process_log.info("PE64 HEARTBEAT: #{d} interpreted={d} owner_steps={d} workers={d}; one every {d} instructions whichever thread runs them, because the owner's checkpoint stops arriving once the owner is mostly serving workers", .{
        self.run_heartbeats,
        interpreted,
        steps,
        process_impl_lifecycle.windowsWorkerSteps(self),
        __process_WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS,
    });
    logStepBudget(self, steps);
    process_impl_guest_diagnostics.logGuestThreadShare(self);
    logGuestSchedulingHealth(self);
    process_impl_windows_sync.reportWindowsTimedWaitSites(self, 4);
    process_impl_guest_diagnostics.reportWindowsBlockedDiagnostics(self, 8);
    process_impl_guest_diagnostics.reportWindowsWaitFindings(self);
    process_impl_guest_diagnostics.reportRunChainsIfChanged(self, steps);
}

pub fn startHostProfile(self: *ElfState) void {
    if (self.host_profile_started) return;
    if (!__process_host_profile.enabledSetting(__process_envText("ROSETTE_HOST_PROFILE"))) {
        __process_log.info("PE64 HOST PROFILE: disabled (sampling suspends the owner and each guest worker; set ROSETTE_HOST_PROFILE=1 for a diagnostic profile)", .{});
        return;
    }
    beginHostProfileSampling(self);
}

pub fn beginHostProfileSampling(self: *ElfState) void {
    if (self.host_profile_started) return;
    const interval_us = @max(__process_envU64("ROSETTE_HOST_PROFILE_US") orelse 1000, 100);
    if (!__process_host_profile.startOnCurrentThread(interval_us * __process_std.time.ns_per_us)) return;
    self.host_profile_started = true;
    __process_log.info("PE64 HOST PROFILE: sampling the owner thread and every parallel worker's host thread once every {d}us; exit reports include per-thread wall-time owners and the last 8 VdSwap intervals correlated with guest instructions and input activity (PE64 FRAME ATTRIBUTION; diagnostic only)", .{interval_us});
}

pub fn reportHostProfile(self: *ElfState) void {
    if (!self.host_profile_started) return;
    __process_host_profile.stop();
    self.host_profile_started = false;
    const summary = __process_host_profile.totals();
    if (summary.samples == 0) {
        __process_log.info("PE64 HOST PROFILE: no samples (failures={d}); nothing to attribute", .{summary.failures});
    } else {
        reportHostProfileSamples(self, "PE64 HOST PROFILE", "the emulation thread's", __process_host_profile.entries(), summary, self.block_jit, 24);
    }
    // Every worker the sampler followed: in a parallel run these are the
    // title's threads, and the owner above is mostly parked.
    for (self.windows_guest_threads, 0..) |*thread, slot| {
        if (slot >= __process_host_profile.max_workers) break;
        const worker_summary = __process_host_profile.workerTotals(slot);
        if (worker_summary.samples == 0) continue;
        var label_text: [96]u8 = undefined;
        const label = __process_std.fmt.bufPrint(&label_text, "PE64 HOST PROFILE THREAD slot={d} '{s}'", .{
            slot,
            if (thread.name_len != 0) thread.nameText() else "<unnamed by the guest>",
        }) catch "PE64 HOST PROFILE THREAD";
        reportHostProfileSamples(self, label, "this worker's", __process_host_profile.workerEntries(slot), worker_summary, thread.parallel_block_jit, 8);
    }
    reportFrameHostAttribution(self);
}

pub fn reportFrameHostAttribution(self: *ElfState) void {
    const ledger = &self.frame_attribution_ledger;
    if (ledger.count == 0) {
        __process_log.info("PE64 FRAME ATTRIBUTION: no complete sampled frame intervals; the first VdSwap is a baseline and later rows require ROSETTE_HOST_PROFILE=1", .{});
        return;
    }
    const frames_to_print = @min(ledger.count, 8);
    __process_log.info("PE64 FRAME ATTRIBUTION: intervals={d} retained={d} showing_last={d} host_sample_us={d}; frame windows are VdSwap-to-VdSwap, host samples use the sampler epoch at each thread read, and input is the latest successful native poll plus event-counter deltas", .{
        ledger.count,
        __process_frame_attribution.history_len,
        frames_to_print,
        __process_host_profile.totals().interval_ns / __process_std.time.ns_per_us,
    });
    const own_image = if (__process_host_profile.hostSymbol(@intFromPtr(&__process_monotonicNanoseconds))) |own| own.image else "";
    for (0..frames_to_print) |age| {
        const record = ledger.recent(frames_to_print - age - 1) orelse continue;
        __process_log.info("PE64 FRAME ATTRIBUTION: swap={d} host_epoch={d} interval_ms={d}.{d:0>3} guest_instructions={d} owner_instructions={d} input(polls/bridged/invalid/nonzero)=+{d}/+{d}/+{d}/+{d} keys(down/up)=+{d}/+{d} focus_events(gain/loss/rejected)=+{d}/+{d}/+{d} focused={} buttons=0x{x} triggers={d}/{d} sticks(left/right)={d},{d}/{d},{d} packet={d}", .{
            record.swap_index,
            record.host_epoch,
            record.elapsed_ns / __process_std.time.ns_per_ms,
            (record.elapsed_ns % __process_std.time.ns_per_ms) / (__process_std.time.ns_per_ms / 1000),
            record.guest_instructions,
            record.owner_instructions,
            record.input.polls,
            record.input.bridged,
            record.input.invalid,
            record.input.nonzero,
            record.input.key_down,
            record.input.key_up,
            record.input.focus_gains,
            record.input.focus_losses,
            record.input.rejected,
            record.input.focused,
            record.input.buttons,
            record.input.left_trigger,
            record.input.right_trigger,
            record.input.thumb_lx,
            record.input.thumb_ly,
            record.input.thumb_rx,
            record.input.thumb_ry,
            record.input.packet,
        });
        reportFrameHostThread(self, record, __process_host_profile.owner_frame_slot, "owner/UI event thread", "owner/UI event thread", record.owner_instructions, own_image);

        var order: [__process_frame_attribution.max_threads]usize = undefined;
        var order_count: usize = 0;
        for (record.threads, 0..) |thread, slot| {
            if (thread.handle == 0 or thread.instructions == 0) continue;
            order[order_count] = slot;
            order_count += 1;
        }
        var sorted: usize = 0;
        while (sorted < order_count) : (sorted += 1) {
            var best = sorted;
            var candidate = sorted + 1;
            while (candidate < order_count) : (candidate += 1) {
                if (record.threads[order[candidate]].instructions > record.threads[order[best]].instructions) best = candidate;
            }
            if (best != sorted) __process_std.mem.swap(usize, &order[sorted], &order[best]);
        }
        const selected_count = @min(order_count, 8);
        for (order[0..selected_count]) |slot| {
            const sample = record.threads[slot];
            const name = if (sample.name_len != 0) sample.name[0..sample.name_len] else "<unnamed guest thread>";
            reportFrameHostThread(self, record, slot, name, process_impl_guest_diagnostics.frameCostRole(name), sample.instructions, own_image);
        }
        // A worker can spend the whole interval parked and therefore have
        // no guest instruction delta. Preserve the top three such host
        // samples so an ulock/driver wait does not disappear from the
        // report just because no translated instruction ran.
        var parked_printed: usize = 0;
        for (record.threads, 0..) |sample, slot| {
            if (parked_printed == 3) break;
            if (sample.handle == 0 or sample.instructions != 0) continue;
            if (__process_host_profile.frameTotals(slot, record.host_epoch).samples == 0) continue;
            const name = if (sample.name_len != 0) sample.name[0..sample.name_len] else "<unnamed guest thread>";
            reportFrameHostThread(self, record, slot, name, process_impl_guest_diagnostics.frameCostRole(name), 0, own_image);
            parked_printed += 1;
        }
    }
    __process_log.info("PE64 FRAME ATTRIBUTION: compare guest instruction deltas with host categories: translated means generated guest code, system includes kernel waits, and Vulkan/Metal samples are host wall-time attribution; the diagnostic sampler perturbs throughput and is not a normal-run FPS measurement", .{});
}

pub fn reportFrameHostThread(
    self: *ElfState,
    record: *const __process_frame_attribution.Record,
    slot: usize,
    name: []const u8,
    role: []const u8,
    guest_instructions: u64,
    own_image: []const u8,
) void {
    const totals = __process_host_profile.frameTotals(slot, record.host_epoch);
    const entries = __process_host_profile.frameEntries(slot, record.host_epoch);
    const frame_guest_handle = if (slot < record.threads.len) record.threads[slot].handle else 0;
    const host_identity_matches_frame = slot == __process_host_profile.owner_frame_slot or totals.guest_handle == frame_guest_handle;
    var counts: __process_FrameHostSampleCounts = .{};
    var top: ?__process_host_profile.Entry = null;
    for (entries) |entry| {
        if (entry.count == 0) continue;
        const category = frameHostSampleCategory(self, slot, entry.pc, own_image);
        counts.add(category, entry.count);
        if (top == null or top.?.count < entry.count) top = entry;
    }
    if (guest_instructions == 0 and totals.samples == 0) return;
    const TopNames = struct { image: []const u8, symbol: []const u8 };
    const top_names: TopNames = if (top) |entry| blk: {
        if (frameHostSampleCategory(self, slot, entry.pc, own_image) == .translated_guest) break :blk .{ .image = "generated guest code", .symbol = "<translated block>" };
        if (__process_host_profile.hostSymbol(entry.pc)) |symbol| break :blk .{ .image = symbol.image, .symbol = symbol.symbol orelse "<no symbol>" };
        break :blk .{ .image = "<unmapped host PC>", .symbol = "<no symbol>" };
    } else .{ .image = "<no samples>", .symbol = "<no samples>" };
    const top_image = top_names.image;
    const top_symbol = top_names.symbol;
    __process_log.info("PE64 FRAME ATTRIBUTION THREAD: swap={d} slot={d} thread='{s}' role={s} guest_handle=0x{x} host_identity_matches_frame={} host_handles_mixed={} guest_instructions={d} host_samples={d} failed/dropped={d}/{d} host_pc(translated/rosette/vulkan/metal/system/other/unknown)={d}/{d}/{d}/{d}/{d}/{d}/{d} top_pc={s}!{s} (0x{x})", .{
        record.swap_index,
        slot,
        name,
        role,
        totals.guest_handle,
        host_identity_matches_frame,
        totals.mixed_guest_handles,
        guest_instructions,
        totals.samples,
        totals.failures,
        totals.dropped,
        counts.translated_guest,
        counts.rosette,
        counts.vulkan_driver,
        counts.metal,
        counts.system,
        counts.other,
        counts.unknown,
        top_image,
        top_symbol,
        if (top) |entry| entry.pc else 0,
    });
}

pub fn frameHostSampleCategory(self: *ElfState, slot: usize, pc: u64, own_image: []const u8) __process_FrameHostSampleCategory {
    const translator = if (slot == __process_host_profile.owner_frame_slot)
        self.block_jit
    else if (slot < self.windows_guest_threads.len)
        self.windows_guest_threads[slot].parallel_block_jit
    else
        null;
    if (translator) |jit| {
        const low = @intFromPtr(jit.memory.memory.ptr);
        const high = low + jit.memory.memory.len;
        if (pc >= low and pc < high) return .translated_guest;
    }
    const symbol = __process_host_profile.hostSymbol(pc) orelse return .unknown;
    return switch (__process_host_profile.ownerOfImage(symbol.image, own_image)) {
        .rosette => .rosette,
        .vulkan_driver => .vulkan_driver,
        .metal => .metal,
        .system => .system,
        .other => .other,
    };
}

pub fn reportHostProfileSamples(
    self: *ElfState,
    label: []const u8,
    whose: []const u8,
    entries: []const __process_host_profile.Entry,
    summary: __process_host_profile.Totals,
    translator: ?*__process_BlockJitState,
    ranked_lines: usize,
) void {
    var arena_state = __process_std.heap.ArenaAllocator.init(self.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const Span = struct { low: usize, high: usize, block: *const __process_block_jit.Block };
    var spans: __process_std.ArrayListUnmanaged(Span) = .empty;
    var code_low: usize = 0;
    var code_high: usize = 0;
    if (translator) |jit| {
        code_low = @intFromPtr(jit.memory.memory.ptr);
        code_high = code_low + jit.memory.memory.len;
        for (jit.blocks) |maybe| {
            const block = maybe orelse continue;
            const low = @intFromPtr(block.code.ptr);
            spans.append(arena, .{ .low = low, .high = low + block.code.len * @sizeOf(u32), .block = block }) catch break;
        }
        __process_std.mem.sort(Span, spans.items, {}, struct {
            fn lessThan(_: void, a: Span, b: Span) bool {
                return a.low < b.low;
            }
        }.lessThan);
    }

    const Owner = enum { translated_title, translated_xenia, translated_unattributed, rosette, vulkan_driver, metal, system, other, unknown };
    var owners = __process_std.enums.EnumArray(Owner, u64).initFill(0);
    var host_ranked: __process_std.StringHashMapUnmanaged(u64) = .empty;
    var guest_ranked: __process_std.StringHashMapUnmanaged(u64) = .empty;
    var block_ranked: __process_std.AutoHashMapUnmanaged(usize, u64) = .empty;
    const own_image = if (__process_host_profile.hostSymbol(@intFromPtr(&__process_monotonicNanoseconds))) |own| own.image else "";
    var counted: u64 = 0;
    for (entries) |entry| {
        if (entry.count == 0) continue;
        const count: u64 = entry.count;
        counted += count;
        const pc: usize = @intCast(entry.pc);
        if (pc >= code_low and pc < code_high) {
            // The last span starting at or below pc.
            var low: usize = 0;
            var high: usize = spans.items.len;
            while (low < high) {
                const middle = low + (high - low) / 2;
                if (spans.items[middle].low <= pc) low = middle + 1 else high = middle;
            }
            const span = if (low == 0) null else spans.items[low - 1];
            if (span == null or pc >= span.?.high) {
                owners.getPtr(.translated_unattributed).* += count;
                continue;
            }
            const rip = span.?.block.start_rip;
            const in_image = rip >= self.image_low and rip < self.image_high;
            owners.getPtr(if (in_image) .translated_xenia else .translated_title).* += count;
            if (block_ranked.getOrPut(arena, @intFromPtr(span.?.block))) |block_slot| {
                if (!block_slot.found_existing) block_slot.value_ptr.* = 0;
                block_slot.value_ptr.* += count;
            } else |_| {}
            var text: [__process_guest_symbol_text_bytes]u8 = undefined;
            const described = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, rip, &text);
            // Xenia's functions are ranked whole; the title's code has no
            // names here, so its blocks are ranked one by one.
            const name = if (in_image) __process_trimAddressOffset(described) else described;
            const key = arena.dupe(u8, name) catch continue;
            const slot = guest_ranked.getOrPut(arena, key) catch continue;
            if (!slot.found_existing) slot.value_ptr.* = 0;
            slot.value_ptr.* += count;
            continue;
        }
        const symbol = __process_host_profile.hostSymbol(entry.pc) orelse {
            owners.getPtr(.unknown).* += count;
            continue;
        };
        owners.getPtr(switch (__process_host_profile.ownerOfImage(symbol.image, own_image)) {
            .rosette => .rosette,
            .vulkan_driver => .vulkan_driver,
            .metal => .metal,
            .system => .system,
            .other => .other,
        }).* += count;
        const key = __process_std.fmt.allocPrint(arena, "{s}!{s}", .{ symbol.image, symbol.symbol orelse "?" }) catch continue;
        const slot = host_ranked.getOrPut(arena, key) catch continue;
        if (!slot.found_existing) slot.value_ptr.* = 0;
        slot.value_ptr.* += count;
    }
    if (counted == 0) return;
    const Share = struct {
        fn tenths(part: u64, whole: u64) u64 {
            return if (whole == 0) 0 else (part *| 1000) / whole;
        }
    };
    __process_log.info("{s}: samples={d} over {d}ms (interval {d}us, failures={d}, dropped={d}, distinct_pcs={d}); {s} wall time: translated_title={d}.{d}% translated_xenia={d}.{d}% translated_unattributed={d}.{d}% rosette={d}.{d}% vulkan_driver={d}.{d}% metal={d}.{d}% system_and_waits={d}.{d}% other={d}.{d}% unknown={d}.{d}%; sampled from a second thread, so time blocked in a driver or kernel wait is counted where it blocked", .{
        label,
        summary.samples,
        summary.elapsed_ns / __process_std.time.ns_per_ms,
        summary.interval_ns / __process_std.time.ns_per_us,
        summary.failures,
        summary.dropped,
        summary.distinct,
        whose,
        Share.tenths(owners.get(.translated_title), counted) / 10,
        Share.tenths(owners.get(.translated_title), counted) % 10,
        Share.tenths(owners.get(.translated_xenia), counted) / 10,
        Share.tenths(owners.get(.translated_xenia), counted) % 10,
        Share.tenths(owners.get(.translated_unattributed), counted) / 10,
        Share.tenths(owners.get(.translated_unattributed), counted) % 10,
        Share.tenths(owners.get(.rosette), counted) / 10,
        Share.tenths(owners.get(.rosette), counted) % 10,
        Share.tenths(owners.get(.vulkan_driver), counted) / 10,
        Share.tenths(owners.get(.vulkan_driver), counted) % 10,
        Share.tenths(owners.get(.metal), counted) / 10,
        Share.tenths(owners.get(.metal), counted) % 10,
        Share.tenths(owners.get(.system), counted) / 10,
        Share.tenths(owners.get(.system), counted) % 10,
        Share.tenths(owners.get(.other), counted) / 10,
        Share.tenths(owners.get(.other), counted) % 10,
        Share.tenths(owners.get(.unknown), counted) / 10,
        Share.tenths(owners.get(.unknown), counted) % 10,
    });
    inline for (.{ .{ "HOST", &host_ranked }, .{ "GUEST", &guest_ranked } }) |view| {
        const Ranked = struct { name: []const u8, samples: u64 };
        var ranked: [24]Ranked = undefined;
        var ranked_count: usize = 0;
        var iterator = view[1].iterator();
        while (iterator.next()) |item| {
            const samples = item.value_ptr.*;
            var position = ranked_count;
            while (position > 0 and ranked[position - 1].samples < samples) : (position -= 1) {}
            if (position >= ranked.len) continue;
            var cursor = @min(ranked_count, ranked.len - 1);
            while (cursor > position) : (cursor -= 1) ranked[cursor] = ranked[cursor - 1];
            ranked[position] = .{ .name = item.key_ptr.*, .samples = samples };
            if (ranked_count < ranked.len) ranked_count += 1;
        }
        for (ranked[0..@min(ranked_count, ranked_lines)], 1..) |item, rank| {
            __process_log.info("{s} " ++ view[0] ++ ": rank={d} share={d}.{d}% samples={d} at={s}", .{
                label,
                rank,
                Share.tenths(item.samples, counted) / 10,
                Share.tenths(item.samples, counted) % 10,
                item.samples,
                item.name,
            });
        }
    }
    if (translator != null and ranked_lines != 0) reportHostProfileHotBlocks(self, label, &block_ranked, counted);
}

pub fn reportHostProfileHotBlocks(self: *ElfState, label: []const u8, blocks: *const __process_std.AutoHashMapUnmanaged(usize, u64), counted: u64) void {
    const Hot = struct { block: usize, samples: u64 };
    var hot: [3]Hot = undefined;
    var hot_count: usize = 0;
    var iterator = blocks.iterator();
    while (iterator.next()) |item| {
        const samples = item.value_ptr.*;
        var position = hot_count;
        while (position > 0 and hot[position - 1].samples < samples) : (position -= 1) {}
        if (position >= hot.len) continue;
        var cursor = @min(hot_count, hot.len - 1);
        while (cursor > position) : (cursor -= 1) hot[cursor] = hot[cursor - 1];
        hot[position] = .{ .block = item.key_ptr.*, .samples = samples };
        if (hot_count < hot.len) hot_count += 1;
    }
    for (hot[0..hot_count], 1..) |item, rank| {
        const block: *const __process_block_jit.Block = @ptrFromInt(item.block);
        var text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const share = if (counted == 0) 0 else (item.samples *| 1000) / counted;
        __process_log.info("{s} HOT BLOCK: rank={d} share={d}.{d}% samples={d} rip=0x{x} at={s} instructions={d} native/fallback={d}/{d} arm64_words={d} executions={d} retired={d}", .{
            label,
            rank,
            share / 10,
            share % 10,
            item.samples,
            block.start_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, block.start_rip, &text),
            block.insns.len,
            block.native_count,
            block.fallback_count,
            block.code.len,
            block.executions,
            block.instructions_retired,
        });
        var ops: [1536]u8 = undefined;
        var used: usize = 0;
        for (block.insns, 0..) |insn, index| {
            if (index == 48) {
                used += (__process_std.fmt.bufPrint(ops[used..], " ...", .{}) catch break).len;
                break;
            }
            const name = @tagName(insn.decoded.op);
            const memory = __process_std.mem.indexOf(u8, name, "mem") != null;
            const fallback = insn.force_fallback or !__process_block_jit.isNative(insn.decoded);
            const piece = __process_std.fmt.bufPrint(ops[used..], "{s}{s}{s}{s}", .{
                if (index == 0) "" else " ",
                name,
                if (memory) "*" else "",
                if (fallback) "^" else "",
            }) catch break;
            used += piece.len;
        }
        __process_log.info("{s} HOT BLOCK:   rank={d} ops: {s}; * reads or writes memory (a TLB probe each), ^ is an interpreter fallback", .{ label, rank, ops[0..used] });
    }
}

pub fn reportRunThroughput(self: *ElfState) void {
    printStepBudget(self, process_impl_lifecycle.observedExecutionSteps(self), false);
    // The budget line returns early on a run too short to have two
    // checkpoints; the translator's account is printed regardless.
    process_impl_block_jit.reportBlockJit(self);
    reportHostProfile(self);
    __process_log.info("PE64 BLOCK JIT SWITCHES: chain={} vectors={} tlb={} internal_edges={} wide_access_watch={}; ROSETTE_X64_BLOCK_JIT_CHAIN, ROSETTE_X64_BLOCK_JIT_VECTOR, ROSETTE_X64_BLOCK_JIT_TLB, ROSETTE_X64_BLOCK_JIT_INTERNAL_EDGES and ROSETTE_X64_WIDE_ACCESS_WATCH set them; turn one off (or the watch on) per run to bisect a behaviour change", .{
        self.block_jit_chain_enabled,
        self.block_jit_vectors_enabled,
        self.block_jit_tlb_enabled,
        self.block_jit_internal_edges_enabled,
        self.wide_access_watch_enabled,
    });
    process_impl_guest_diagnostics.reportGuestAccessViolations(self);
    __process_log.info("PE64 OWNER WAKE HANDOFF: handoffs={d} owner_yields={d}; a handoff ends a worker's slice the moment it signals an object the owner is waiting on, so the owner (Xenia's UI thread) takes it before the worker can retake it; zero handoffs with a growing owner_yields and no paints is the 2026-09-19 starvation again", .{
        self.windows_owner_wait_handoffs,
        self.windows_wait_owner_yields,
    });
    process_impl_guest_diagnostics.logGuestThreadShare(self);
    logGuestSchedulingHealth(self);
    process_impl_windows_sync.reportWindowsTimedWaitSites(self, __process_WINDOWS_TIMED_WAIT_SITE_CAPACITY);
    // The heartbeat is intentionally bounded; the final report is not.
    // A live wait graph is evidence, so do not discard the last two
    // blocked workers merely because an older sample cap was sixteen.
    process_impl_guest_diagnostics.reportWindowsBlockedDiagnostics(self, self.windows_guest_threads.len);
    process_impl_guest_diagnostics.reportWindowsWaitCost(self);
    process_impl_guest_diagnostics.reportWindowsWaitFindings(self);
    process_impl_guest_diagnostics.reportWindowsUpstreamWaitPriority(self);
    process_impl_kernel_services.reportWindowsInputBridge(self);
    process_impl_guest_diagnostics.reportGpuDrawFailures(self);
    process_impl_instruction_decode.reportDecodeCacheMissSites(self);
}

pub fn logGuestSchedulingHealth(self: *const ElfState) void {
    var threads_live: usize = 0;
    var threads_created: usize = 0;
    var threads_completed: usize = 0;
    var threads_failed: usize = 0;
    var threads_vacant: usize = 0;
    var thread_pause_hints: u64 = 0;
    var pause_host_yield_calls: u64 = 0;
    for (self.windows_guest_threads) |*thread| {
        thread_pause_hints +|= __process_parallel_metrics.load(u64, &thread.pause_hints);
        pause_host_yield_calls +|= __process_parallel_metrics.load(u64, &thread.pause_host_yields);
        switch (thread.status) {
            .vacant => threads_vacant += 1,
            .completed => {
                threads_created += 1;
                threads_completed += 1;
            },
            .failed => {
                threads_created += 1;
                threads_failed += 1;
            },
            else => {
                threads_created += 1;
                if (__process_isLiveWindowsGuestThread(thread.status)) threads_live += 1;
            },
        }
    }
    var wait_objects_live: usize = 0;
    for (self.windows_wait_objects[0..self.windows_wait_object_high_water]) |*object| {
        if (object.handle != 0) wait_objects_live += 1;
    }
    __process_log.info("PE64 guest scheduling health: timed_condition_waits={d} immediate_timeouts={d} deadline_timeouts={d} nt_delay(parks/yields)={d}/{d} sleep_parks={d} clock_poll_yields={d} slice_yields={d} threads(live/capacity/reused/refused)={d}/{d}/{d}/{d} wait_objects(live/high_water/capacity/freed/refused)={d}/{d}/{d}/{d}/{d} timers(created/set/fired/armed/routines_not_delivered)={d}/{d}/{d}/{d}/{d} thread_stacks_released={d} spin(slices/turns_given)={d}/{d}; a refused thread or wait object is a fatal point, and a high water near capacity is the table the next title outgrows", .{
        self.windows_condition_timed_waits,
        self.windows_condition_timed_immediate,
        self.windows_condition_timeouts,
        self.windows_nt_delay_parks,
        self.windows_nt_delay_yields +| self.windows_fast_nt_yield.total(),
        self.windows_guest_sleep_parks,
        self.windows_clock_poll_yields,
        self.windows_guest_slice_yields,
        threads_live,
        self.windows_guest_threads.len,
        self.windows_thread_slots_recycled,
        self.windows_thread_table_full,
        wait_objects_live,
        self.windows_wait_object_high_water,
        self.windows_wait_objects.len,
        self.windows_wait_objects_freed,
        self.windows_wait_object_table_full,
        self.windows_timers_created,
        self.windows_timer_sets,
        self.windows_timer_fires,
        self.windows_armed_timers,
        self.windows_timer_completion_routines,
        self.windows_thread_stacks_released,
        self.windows_spin_slices,
        self.windows_spin_turns_given,
    });
    const worker_wakes = self.parallel_guest_wake_hub.workerNotificationCounts();
    __process_log.info("PE64 guest scheduling health: pause_hints(serial_global/thread_sum)={d}/{d} parallel_pause_host_yield_calls={d} serial_pause_spin_slices={d} targeted_worker_notify/wake={d}/{d}; targeted wake counters exclude the owner-only event", .{ self.windows_guest_pause_yields, thread_pause_hints, pause_host_yield_calls, self.windows_pause_spin_slices, worker_wakes.notifications, worker_wakes.wakes });
    @import("windows_mutex.zig").report(self);
    self.windows_idle_yield.report();
    @import("native_shader_stats.zig").report(self);
    __process_log.info("PE64 guest thread lifecycle: created={d} live={d} completed={d} failed={d} vacant={d} capacity={d}; completed is a normal one-shot exit, failed/refused is the missing-thread signal", .{
        threads_created,
        threads_live,
        threads_completed,
        threads_failed,
        threads_vacant,
        self.windows_guest_threads.len,
    });
}

pub fn logGraphicsProgress(self: *ElfState, steps: u64) void {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    logStepBudget(self, steps);
    process_impl_guest_diagnostics.logGuestThreadShare(self);
    logGuestSchedulingHealth(self);
    process_impl_guest_diagnostics.rollGuestThreadCodeWindows(self);
    var vacant: u32 = 0;
    var pending: u32 = 0;
    var runnable: u32 = 0;
    var running: u32 = 0;
    var blocked: u32 = 0;
    var completed: u32 = 0;
    var failed: u32 = 0;
    for (self.windows_guest_threads) |*thread| {
        switch (thread.status) {
            .vacant => vacant += 1,
            .pending => pending += 1,
            .runnable => runnable += 1,
            .running => running += 1,
            .blocked => blocked += 1,
            .completed => completed += 1,
            .failed => failed += 1,
        }
    }
    const active_thread = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index|
        self.windows_guest_threads[index].handle
    else
        0;
    __process_log.info("PE64 GUEST CLOCK/VBLANK: clock_ticks={d} owner_steps={d} worker_steps={d} vblanks={d} (via {s}) scheduler_calls={d} active_thread=0x{x}; worker-side time must advance independently of the owner loop", .{
        process_impl_lifecycle.windowsGuestClockTicks(self),
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.windowsWorkerSteps(self),
        process_impl_kernel_services.guestMilestoneStageHits(self, "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv"),
        process_impl_guest_diagnostics.vblankWitnessName(self),
        self.windows_thread_service_calls,
        active_thread,
    });
    __process_log.info("PE64 graphics progress: steps={d} rip=0x{x} last_op={s} active_thread=0x{x} workers(vacant/pending/runnable/running/completed/failed)={d}/{d}/{d}/{d}/{d}/{d} vk_calls={d} native_vk_calls={d} native_vk_pre_ready={d} native_vk_failures={d} commands={d} submits={d} presents={d} rijndael_accel_calls={d} heap_records={d} heap_live={d} heap_capacity={d} heap_growth_failures={d} heap_untracked={d} phase={s} last_call={s} ordering_violations={d} unmodeled={d}", .{
        steps,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        active_thread,
        vacant,
        pending,
        runnable,
        running,
        completed,
        failed,
        self.windows_graphics.vulkan_calls,
        self.windows_graphics.native_vulkan_calls,
        self.windows_graphics.native_vulkan_pre_ready_calls,
        self.windows_graphics.native_vulkan_failures,
        self.windows_graphics.command_calls,
        self.windows_graphics.queue_submits,
        self.windows_graphics.presents,
        self.xenia_rijndael_accelerated_calls,
        self.windows_heap_allocation_count,
        self.windows_heap_allocations_live,
        self.windows_heap_allocations.len,
        self.windows_heap_provenance_growth_failures,
        self.windows_heap_provenance_untracked_allocations,
        @tagName(self.windows_graphics.phase),
        __process_std.mem.sliceTo(&self.windows_graphics.last_call, 0),
        self.windows_graphics.ordering_violations,
        self.windows_graphics.unmodeled_calls,
    });
    __process_log.info("PE64 GPU/heap lifetime: gpu_wake_repairs={d} gpu_wake_repair_misses={d} heap_records={d} heap_live={d} heap_free={d} heap_reused={d} heap_capacity={d} heap_growth_failures={d} heap_free_growth_failures={d} heap_untracked={d}", .{
        self.windows_gpu_write_pointer_wake_repairs,
        self.windows_gpu_write_pointer_wake_repair_misses,
        self.windows_heap_allocation_count,
        self.windows_heap_allocations_live,
        self.windows_heap_free_count,
        self.windows_heap_reused_allocations,
        self.windows_heap_allocations.len,
        self.windows_heap_provenance_growth_failures,
        self.windows_heap_free_list_growth_failures,
        self.windows_heap_provenance_untracked_allocations,
    });
    process_impl_guest_heap.reportGuestHeapUse(self);
    // The line above says where the guest is; this one says what it is
    // doing there. Without it a reader has a hexadecimal address and no
    // way to tell an expensive computation from a stall.
    process_impl_kernel_services.sampleGuestFrontier(self);
    var frontier_text: [320]u8 = undefined;
    __process_log.info("PE64 guest frontier: steps={d} rip=0x{x} {s} named_symbols={d} image_coverage={d}%", .{
        steps,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        process_impl_kernel_services.describeGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &frontier_text),
        self.guest_symbol_count,
        self.guest_symbol_coverage_percent,
    });
    __process_log.info("PE64 guest scheduler: enabled={} quantum={d} slice={d} explicit_stride={d} scheduler_calls={d} scheduler_steps={d} explicit_calls={d} explicit_steps={d} explicit_skips={d} worker_calls={d} worker_yields={d} backstop_calls={d} blocked={d} unblocked={d}", .{
        self.windows_scheduler.enabled,
        self.windows_scheduler.quantum,
        self.windows_scheduler.slice,
        self.windows_scheduler.explicit_stride,
        self.windows_scheduler.service_calls,
        self.windows_scheduler.serviced_steps,
        self.windows_scheduler.explicit_service_calls,
        self.windows_scheduler.explicit_serviced_steps,
        self.windows_scheduler.explicit_service_skips,
        self.windows_thread_service_calls,
        self.windows_thread_yields,
        self.windows_progress.backstop_services,
        self.windows_thread_blocks,
        self.windows_thread_unblocks,
    });
    __process_log.info("PE64 guest synchronization: blocked={d} unblocked={d} lock_contentions={d} release_mismatches={d} condition_hooks={d} condition_waits={d} condition_blocks={d} condition_resumes={d} condition_signals={d} condition_broadcasts={d} condition_unblocks={d} wait_calls={d} wait_blocks={d} wait_resumes={d} wait_unblocks={d} wait_timeouts={d} wait_unknown={d} wait_owner_yields={d} wait_compat_yields={d} srw_compat_acquires={d} wait_multiple(calls/blocks/owner_yields)={d}/{d}/{d} wait_unknown_faults={d} get_message_idle(turns/steps)={d}/{d} crt_unreadable={d}", .{
        blocked,
        self.windows_thread_unblocks,
        self.windows_srw_lock_contentions,
        self.windows_srw_lock_release_mismatches,
        self.windows_condition_hook_events,
        self.windows_condition_wait_calls,
        self.windows_condition_wait_blocks,
        self.windows_condition_wait_resumes,
        self.windows_condition_signal_calls,
        self.windows_condition_broadcast_calls,
        self.windows_condition_unblocks,
        self.windows_wait_calls,
        self.windows_wait_blocks,
        self.windows_wait_resumes,
        self.windows_wait_unblocks,
        self.windows_wait_timeouts,
        self.windows_wait_unknown_objects,
        self.windows_wait_owner_yields,
        self.windows_wait_compatibility_yields,
        self.windows_srw_compatibility_acquires,
        self.windows_wait_multiple_calls,
        self.windows_wait_multiple_blocks,
        self.windows_wait_multiple_owner_yields,
        self.windows_wait_unknown_faults,
        self.windows_get_message_idle_turns,
        self.windows_get_message_idle_steps,
        self.windows_crt_unreadable_pointers,
    });
    process_impl_guest_diagnostics.reportWindowsBlockedDiagnostics(self, 16);
}

pub fn logGraphicsStop(self: *ElfState) void {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    var vacant: u32 = 0;
    var pending: u32 = 0;
    var runnable: u32 = 0;
    var running: u32 = 0;
    var blocked: u32 = 0;
    var completed: u32 = 0;
    var failed: u32 = 0;
    for (self.windows_guest_threads) |*thread| {
        switch (thread.status) {
            .vacant => vacant += 1,
            .pending => pending += 1,
            .runnable => runnable += 1,
            .running => running += 1,
            .blocked => blocked += 1,
            .completed => completed += 1,
            .failed => failed += 1,
        }
    }
    const active_thread = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index|
        self.windows_guest_threads[index].handle
    else
        0;
    __process_log.info("PE64 GUEST CLOCK/VBLANK: clock_ticks={d} owner_steps={d} worker_steps={d} vblanks={d} (via {s}) scheduler_calls={d} active_thread=0x{x}", .{
        process_impl_lifecycle.windowsGuestClockTicks(self),
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.windowsWorkerSteps(self),
        process_impl_kernel_services.guestMilestoneStageHits(self, "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv"),
        process_impl_guest_diagnostics.vblankWitnessName(self),
        self.windows_thread_service_calls,
        active_thread,
    });
    __process_log.info("PE64 execution stop: terminated={} faulted={} reason={s} exit=0x{x} steps={d} rip=0x{x} last_op={s} active_thread=0x{x} workers(vacant/pending/runnable/running/completed/failed)={d}/{d}/{d}/{d}/{d}/{d} vk_calls={d} native_vk_calls={d} native_vk_pre_ready={d} native_vk_failures={d} commands={d} submits={d} presents={d} rijndael_accel_calls={d} rijndael_accel_failures={d} heap_records={d} heap_capacity={d} heap_growth_failures={d} heap_untracked={d} phase={s} last_call={s} last_failure={s} ui_quit={} ui_quit_code=0x{x}", .{
        process_impl_lifecycle.isTerminated(self),
        self.faulted,
        @tagName(self.termination_reason),
        self.exit_code,
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        active_thread,
        vacant,
        pending,
        runnable,
        running,
        completed,
        failed,
        self.windows_graphics.vulkan_calls,
        self.windows_graphics.native_vulkan_calls,
        self.windows_graphics.native_vulkan_pre_ready_calls,
        self.windows_graphics.native_vulkan_failures,
        self.windows_graphics.command_calls,
        self.windows_graphics.queue_submits,
        self.windows_graphics.presents,
        self.xenia_rijndael_accelerated_calls,
        self.xenia_rijndael_accelerator_failures,
        self.windows_heap_allocation_count,
        self.windows_heap_allocations.len,
        self.windows_heap_provenance_growth_failures,
        self.windows_heap_provenance_untracked_allocations,
        @tagName(self.windows_graphics.phase),
        __process_std.mem.sliceTo(&self.windows_graphics.last_call, 0),
        __process_std.mem.sliceTo(&self.windows_graphics.last_failure, 0),
        self.windows_ui_quit_requested,
        self.windows_ui_quit_code,
    });
    __process_log.info("PE64 GPU/heap lifetime: gpu_wake_repairs={d} gpu_wake_repair_misses={d} heap_records={d} heap_live={d} heap_free={d} heap_reused={d} heap_capacity={d} heap_growth_failures={d} heap_free_growth_failures={d} heap_untracked={d}", .{
        self.windows_gpu_write_pointer_wake_repairs,
        self.windows_gpu_write_pointer_wake_repair_misses,
        self.windows_heap_allocation_count,
        self.windows_heap_allocations_live,
        self.windows_heap_free_count,
        self.windows_heap_reused_allocations,
        self.windows_heap_allocations.len,
        self.windows_heap_provenance_growth_failures,
        self.windows_heap_free_list_growth_failures,
        self.windows_heap_provenance_untracked_allocations,
    });
    process_impl_guest_heap.reportGuestHeapUse(self);
    process_impl_guest_diagnostics.logWindowsGuestFailurePointSummary(self);
    __process_log.info("PE64 Xenia accelerators: rijndael_calls={d} rijndael_failures={d} sha1_blocks={d} sha1_failures={d} sha1_feed_spans={d} sha1_feed_bytes={d} sha1_feed_declines={d} sha1_feed_steps_saved~={d}", .{
        self.xenia_rijndael_accelerated_calls,
        self.xenia_rijndael_accelerator_failures,
        self.xenia_sha1_accelerated_blocks,
        self.xenia_sha1_accelerator_failures,
        self.xenia_sha1_feed_spans,
        self.xenia_sha1_feed_bytes,
        self.xenia_sha1_feed_declines,
        // The interpreted loop is eleven instructions per byte; stating
        // the estimate keeps the accelerator's value measurable instead
        // of assumed.
        self.xenia_sha1_feed_bytes *| 11,
    });
    __process_log.info("PE64 Xenia metadata table accelerator: strings={d} failures={d}", .{
        self.xenia_tabulate_accelerated_strings,
        self.xenia_tabulate_accelerator_failures,
    });
    __process_log.info("PE64 Xenia kernel SHA1 feed: spans={d} bytes={d} estimated_instructions_avoided~={d} max_native_turn_bytes=262144; hash and final guest iterations are preserved, not bypassed", .{
        self.xenia_sha1_kernel_feed_spans,
        self.xenia_sha1_kernel_feed_bytes,
        self.xenia_sha1_kernel_feed_bytes *| 11,
    });
    __process_log.info("PE64 generated code: instruction_fetches={d}", .{self.windows_generated_code_fetches});
    const decode_counts = process_impl_instruction_decode.decodeCacheCounts(self);
    const decode_lookups = decode_counts.hits +| decode_counts.rearms +| decode_counts.misses;
    const decode_miss_rate_ppm = if (decode_lookups == 0) 0 else @divTrunc(decode_counts.misses *| 1_000_000, decode_lookups);
    const decode_conflict_rate_ppm = if (decode_lookups == 0) 0 else @divTrunc(decode_counts.conflict_fills *| 1_000_000, decode_lookups);
    __process_log.info("PE64 DECODE CACHE: entries={d} sets={d} ways={d} lookups={d} hits={d} generation_rearms={d} fresh_decodes={d} address_collisions={d} rates(miss_ppm/conflict_ppm)={d}/{d} miss_causes(vacant/conflict/stale)={d}/{d}/{d} conflict_sources(generated/image)={d}/{d} replacements={d} victim(entries/sets/ways hits/fills/stale)={d}/{d}/{d}/{d}/{d}/{d} hit_percent={d}; full source address/kind/index/generation checked; victim recovery is bounded and does not suppress a primary capacity finding; mapped_ranges={d} range_mutations={d} lookup=set_scan", .{
        __process_PE_DECODE_CACHE_ENTRIES,
        __process_PE_DECODE_CACHE_SETS,
        __process_PE_DECODE_CACHE_WAYS,
        decode_lookups,
        decode_counts.hits,
        decode_counts.rearms,
        decode_counts.misses,
        decode_counts.collisions,
        decode_miss_rate_ppm,
        decode_conflict_rate_ppm,
        decode_counts.vacant_fills,
        decode_counts.conflict_fills,
        decode_counts.stale_refills,
        decode_counts.generated_conflict_fills,
        decode_counts.image_conflict_fills,
        decode_counts.replacements,
        __process_PE_DECODE_CACHE_VICTIM_ENTRIES,
        __process_PE_DECODE_CACHE_VICTIM_SETS,
        __process_PE_DECODE_CACHE_VICTIM_WAYS,
        decode_counts.victim_hits,
        decode_counts.victim_fills,
        decode_counts.victim_stale_rejections,
        __process_windowsTimedWaitPercent(decode_counts.hits +| decode_counts.rearms, decode_counts.hits +| decode_counts.rearms +| decode_counts.misses),
        self.windows_mapped_ranges.count,
        self.windows_mapped_ranges.mutations,
    });
    process_impl_instruction_decode.logWorkerLocalDecodeCache(self, decode_counts, decode_lookups);
    __process_log.info("PE64 guest scheduler: enabled={} quantum={d} slice={d} explicit_stride={d} scheduler_calls={d} scheduler_steps={d} explicit_calls={d} explicit_steps={d} explicit_skips={d} worker_calls={d} worker_yields={d} backstop_calls={d} blocked={d} unblocked={d}", .{
        self.windows_scheduler.enabled,
        self.windows_scheduler.quantum,
        self.windows_scheduler.slice,
        self.windows_scheduler.explicit_stride,
        self.windows_scheduler.service_calls,
        self.windows_scheduler.serviced_steps,
        self.windows_scheduler.explicit_service_calls,
        self.windows_scheduler.explicit_serviced_steps,
        self.windows_scheduler.explicit_service_skips,
        self.windows_thread_service_calls,
        self.windows_thread_yields,
        self.windows_progress.backstop_services,
        self.windows_thread_blocks,
        self.windows_thread_unblocks,
    });
    __process_log.info("PE64 guest synchronization: blocked={d} unblocked={d} lock_contentions={d} release_mismatches={d} condition_hooks={d} condition_waits={d} condition_blocks={d} condition_resumes={d} condition_signals={d} condition_broadcasts={d} condition_unblocks={d} wait_calls={d} wait_blocks={d} wait_resumes={d} wait_unblocks={d} wait_timeouts={d} wait_unknown={d} wait_owner_yields={d} wait_compat_yields={d} srw_compat_acquires={d} wait_multiple(calls/blocks/owner_yields)={d}/{d}/{d} wait_unknown_faults={d} get_message_idle(turns/steps)={d}/{d} crt_unreadable={d}", .{
        blocked,
        self.windows_thread_unblocks,
        self.windows_srw_lock_contentions,
        self.windows_srw_lock_release_mismatches,
        self.windows_condition_hook_events,
        self.windows_condition_wait_calls,
        self.windows_condition_wait_blocks,
        self.windows_condition_wait_resumes,
        self.windows_condition_signal_calls,
        self.windows_condition_broadcast_calls,
        self.windows_condition_unblocks,
        self.windows_wait_calls,
        self.windows_wait_blocks,
        self.windows_wait_resumes,
        self.windows_wait_unblocks,
        self.windows_wait_timeouts,
        self.windows_wait_unknown_objects,
        self.windows_wait_owner_yields,
        self.windows_wait_compatibility_yields,
        self.windows_srw_compatibility_acquires,
        self.windows_wait_multiple_calls,
        self.windows_wait_multiple_blocks,
        self.windows_wait_multiple_owner_yields,
        self.windows_wait_unknown_faults,
        self.windows_get_message_idle_turns,
        self.windows_get_message_idle_steps,
        self.windows_crt_unreadable_pointers,
    });
}
