const std = @import("std");
const thread_interceptor = @import("thread_interceptor.zig");
const thread_registry = @import("thread_registry.zig");

/// Scheduling decision
pub const SchedulingDecision = enum {
    /// Run the specified thread
    run,
    /// Yield the current thread
    yield,
    /// Suspend the current thread
    @"suspend",
    /// Preempt the current thread
    preempt,
    /// Exit the scheduler
    exit,
};

/// Scheduling context for decision making
pub const SchedulingContext = struct {
    /// Current step
    current_step: u64,

    /// Current thread handle
    current_thread: u64,

    /// Current thread RIP
    current_rip: u64,

    /// Number of active threads
    active_threads: usize,

    /// Number of suspended threads
    suspended_threads: usize,

    /// Number of waiting threads
    waiting_threads: usize,

    /// Pending GTK idle callbacks
    pending_idle: usize,

    /// Deferred threads count
    deferred_threads: u64,

    /// Load factor (0.0 to 1.0)
    load_factor: f64,

    /// Whether in UI context
    in_ui_context: bool,
};

/// Scheduling policy configuration
pub const PolicyConfig = struct {
    /// Default scheduling mode
    default_mode: thread_interceptor.SchedulingMode = .cooperative,

    /// Whether to enable preemption
    enable_preemption: bool = false,

    /// Preemption interval (steps)
    preemption_interval: u64 = 50000,

    /// Whether to enable priority scheduling
    enable_priority: bool = true,

    /// Whether to enable adaptive scheduling
    enable_adaptive: bool = true,

    /// Load threshold for adaptive mode switching
    load_threshold: f64 = 0.7,

    /// Maximum quantum for cooperative threads
    max_quantum: u64 = 50000,

    /// Minimum quantum for cooperative threads
    min_quantum: u64 = 1000,

    /// Whether to enable starvation prevention
    enable_starvation_prevention: bool = true,

    /// Starvation threshold (steps)
    starvation_threshold: u64 = 100000,

    /// Adaptive mode switch cooldown (steps). Prevents oscillation.
    adaptive_cooldown_steps: u64 = 10000,

    /// Hysteresis margin for adaptive mode switch (load-factor delta).
    /// Prevents rapid mode flipping when load hovers near the threshold.
    adaptive_hysteresis: f64 = 0.05,

    /// Priority-to-quantum multipliers. Indexed by ThreadPriority ordinal.
    priority_quantum_multipliers: [6]u64 = .{ 1, 2, 4, 8, 16, 32 },

    /// Per-type starvation thresholds (steps). Indexed by ThreadType ordinal.
    /// 0 = use starvation_threshold global default.
    per_type_starvation_thresholds: [8]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },

    /// Whether to enable entropy in handle allocation
    enable_handle_entropy: bool = true,

    /// RIP stall threshold (consecutive same-IP suspensions)
    rip_stall_threshold: u64 = 3,

    /// Recursive thread creation depth limit
    max_recursion_depth: u32 = 8,

    /// Background thread deferral threshold
    background_defer_threshold: u64 = 1000,

    /// Configurable work priority order in cooperative rotation
    work_priority_order: [3]u8 = .{ 0, 1, 2 }, // gtk_idle=0, deferred=1, suspended=2

    /// Diagnostic-only threshold for a thread remaining in one blocked state.
    stuck_diagnostic_threshold: u64 = 1_000_000,

    /// Whether to favor UI threads
    favor_ui_threads: bool = true,

    /// UI thread priority boost
    ui_priority_boost: i8 = 1,
};

/// Scheduler policy engine
pub const SchedulerPolicy = struct {
    /// Policy configuration
    config: PolicyConfig = .{},

    /// Statistics
    scheduling_decisions: u64 = 0,
    yields: u64 = 0,
    suspensions: u64 = 0,
    preemptions: u64 = 0,
    mode_switches: u64 = 0,

    /// Current scheduling mode
    current_mode: thread_interceptor.SchedulingMode = .cooperative,

    /// Steps since last mode switch
    steps_since_mode_switch: u64 = 0,

    /// Make scheduling decision
    pub fn makeDecision(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext) SchedulingDecision {
        self.scheduling_decisions +|= 1;

        // Check for adaptive mode switching
        if (self.config.enable_adaptive) {
            self.adaptiveModeSwitch(context);
        }

        // Get current thread entry
        const current_entry = registry.findByHandle(context.current_thread);

        // Apply policy based on current mode
        const decision = switch (self.current_mode) {
            .cooperative => self.cooperativePolicy(registry, context, current_entry),
            .preemptive => self.preemptivePolicy(registry, context, current_entry),
            .hybrid => self.hybridPolicy(registry, context, current_entry),
            .fifo => self.fifoPolicy(registry, context, current_entry),
            .priority => self.priorityPolicy(registry, context, current_entry),
            .round_robin => self.roundRobinPolicy(registry, context, current_entry),
        };

        // Update statistics
        switch (decision) {
            .yield => self.yields +|= 1,
            .@"suspend" => self.suspensions +|= 1,
            .preempt => self.preemptions +|= 1,
            else => {},
        }

        return decision;
    }

    /// Cooperative scheduling policy
    fn cooperativePolicy(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext, entry: ?*thread_registry.ThreadEntry) SchedulingDecision {
        // Check if current thread should yield
        if (entry) |e| {
            // Yield if quantum exhausted
            if (e.quantum_remaining == 0) {
                return .yield;
            }

            // Yield if there's pending UI work and this is not a UI thread
            if (context.pending_idle > 0 and e.thread_type != .ui and self.config.favor_ui_threads) {
                return .yield;
            }

            // Yield if there are suspended threads and this thread has run long enough
            if (context.suspended_threads > 0 and e.continuous_run_steps > self.config.max_quantum) {
                return .yield;
            }

            // Yield for starvation prevention
            if (self.config.enable_starvation_prevention) {
                if (self.shouldPreventStarvation(registry, context, e)) {
                    return .yield;
                }
            }
        }

        // Run current thread
        return .run;
    }

    /// Preemptive scheduling policy
    fn preemptivePolicy(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext, entry: ?*thread_registry.ThreadEntry) SchedulingDecision {
        _ = self;
        _ = registry;
        _ = context;

        // Preempt based on time slice
        if (entry) |e| {
            if (e.quantum_remaining == 0) {
                return .preempt;
            }
        }

        return .run;
    }

    /// Hybrid scheduling policy
    fn hybridPolicy(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext, entry: ?*thread_registry.ThreadEntry) SchedulingDecision {
        // Combine cooperative and preemptive policies
        const coop_decision = self.cooperativePolicy(registry, context, entry);

        if (coop_decision == .yield) {
            return .yield;
        }

        // Add preemption points
        if (entry) |e| {
            if (e.quantum_remaining == 0) {
                return .preempt;
            }
        }

        return .run;
    }

    /// FIFO scheduling policy
    fn fifoPolicy(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext, _: ?*thread_registry.ThreadEntry) SchedulingDecision {
        // Run threads to completion unless they explicitly yield
        // Check if there are higher-priority suspended threads that should run first
        if (self.hasHigherPrioritySuspended(registry, context.current_thread)) {
            return .yield;
        }

        return .run;
    }

    /// Priority-based scheduling policy
    fn priorityPolicy(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext, entry: ?*thread_registry.ThreadEntry) SchedulingDecision {
        _ = registry;

        if (entry) |e| {
            // Boost UI thread priority
            if (self.config.favor_ui_threads and e.thread_type == .ui) {
                // UI threads get longer quanta
                if (e.quantum_remaining > 0) {
                    return .run;
                }
            }

            // Check if there's a higher priority thread waiting
            if (context.pending_idle > 0 and e.thread_type != .ui) {
                return .yield;
            }
        }

        return .run;
    }

    /// Round-robin scheduling policy
    fn roundRobinPolicy(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, _: SchedulingContext, entry: ?*thread_registry.ThreadEntry) SchedulingDecision {
        if (entry) |e| {
            // Fixed quantum for all threads
            if (e.quantum_remaining == 0) {
                return .yield;
            }
        }

        // Only yield if there are higher-or-equal-priority suspended threads
        const current = if (entry) |e| e.handle else 0;
        if (self.hasHigherOrEqualPrioritySuspended(registry, current)) {
            return .yield;
        }

        return .run;
    }

    /// Adaptive mode switching based on load
    fn adaptiveModeSwitch(self: *SchedulerPolicy, context: SchedulingContext) void {
        self.steps_since_mode_switch +|= 1;

        // Don't switch too frequently — use configurable cooldown.
        if (self.steps_since_mode_switch < self.config.adaptive_cooldown_steps) return;

        // Apply hysteresis: require load_factor to exceed the threshold by the
        // hysteresis margin before switching UP, and drop below (threshold - margin)
        // before switching DOWN. This prevents rapid mode oscillation when load
        // hovers near the boundary.
        const target_mode: thread_interceptor.SchedulingMode = if (context.load_factor > (self.config.load_threshold + self.config.adaptive_hysteresis))
            if (context.in_ui_context) .hybrid else .preemptive
        else if (context.load_factor < (self.config.load_threshold - self.config.adaptive_hysteresis))
            .cooperative
        else
            self.current_mode; // stay in current mode inside the hysteresis band

        if (target_mode != self.current_mode) {
            self.current_mode = target_mode;
            self.mode_switches +|= 1;
            self.steps_since_mode_switch = 0;

            std.debug.print(
                "scheduler: adaptive mode switch: new_mode={s} load_factor={d:.2} active_threads={d} load_threshold={d:.2} hysteresis={d:.2}\n",
                .{ @tagName(self.current_mode), context.load_factor, context.active_threads, self.config.load_threshold, self.config.adaptive_hysteresis },
            );
        }
    }

    /// Check if thread should yield for starvation prevention
    fn shouldPreventStarvation(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext, entry: *thread_registry.ThreadEntry) bool {
        // Check for suspended threads that have been waiting too long
        // Use per-type thresholds when configured, falling back to global default
        var stuck_count: usize = 0;
        for (&registry.entries) |*e| {
            if (!e.active or e.state != .suspended) continue;

            const type_index = @intFromEnum(e.thread_type);
            const type_threshold = if (type_index < self.config.per_type_starvation_thresholds.len and
                self.config.per_type_starvation_thresholds[type_index] != 0)
                self.config.per_type_starvation_thresholds[type_index]
            else
                self.config.starvation_threshold;
            const wait_duration = context.current_step -| e.state_since_step;
            if (wait_duration > type_threshold) {
                stuck_count += 1;
            }
        }

        // If there are stuck threads, yield to let them run
        if (stuck_count > 0) {
            return true;
        }

        // Check if current thread has been running too long
        if (entry.continuous_run_steps > self.config.starvation_threshold) {
            return true;
        }

        return false;
    }

    /// Check if there are higher-priority suspended threads than the current one.
    fn hasHigherPrioritySuspended(_: *const SchedulerPolicy, registry: *thread_registry.ThreadRegistry, current_handle: u64) bool {
        const current = registry.findByHandle(current_handle);
        const current_priority = if (current) |e| @intFromEnum(e.priority) else @intFromEnum(thread_interceptor.ThreadPriority.normal);
        for (&registry.entries) |*e| {
            if (!e.active or e.state != .suspended) continue;
            if (@intFromEnum(e.priority) > current_priority) return true;
        }
        return false;
    }

    /// Check if there are higher-or-equal priority suspended threads.
    fn hasHigherOrEqualPrioritySuspended(_: *const SchedulerPolicy, registry: *thread_registry.ThreadRegistry, current_handle: u64) bool {
        const current = registry.findByHandle(current_handle);
        const current_priority = if (current) |e| @intFromEnum(e.priority) else @intFromEnum(thread_interceptor.ThreadPriority.normal);
        for (&registry.entries) |*e| {
            if (!e.active or e.state != .suspended) continue;
            const ep = @intFromEnum(e.priority);
            if (ep > current_priority or (ep == current_priority and e.handle != current_handle)) return true;
        }
        return false;
    }

    /// Select next thread to run
    pub fn selectNextThread(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, context: SchedulingContext) ?u64 {
        // Priority order: UI threads > suspended threads > other threads

        // First, check for suspended UI threads
        if (context.pending_idle > 0 and self.config.favor_ui_threads) {
            // UI threads get priority
            for (&registry.entries) |*entry| {
                if (entry.active and entry.state == .suspended and entry.thread_type == .ui) {
                    return entry.handle;
                }
            }
        }

        // Prefer an already-runnable peer over the thread that was just added
        // to the suspended FIFO by a cooperative yield. Otherwise a yield can
        // immediately select itself and starve the peer it intended to run.
        for (&registry.entries) |*entry| {
            if (entry.active and entry.state == .running and entry.handle != context.current_thread) {
                return entry.handle;
            }
        }

        // Finally, resume the oldest suspended context.
        if (registry.nextSuspended()) |handle| {
            return handle;
        }

        return null;
    }

    /// Migrate thread to different scheduling mode
    pub fn migrateThreadMode(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, handle: u64, new_mode: thread_interceptor.SchedulingMode) bool {
        const entry = registry.findByHandle(handle) orelse return false;

        if (entry.scheduling_mode == new_mode) return true;

        entry.scheduling_mode = new_mode;

        // Adjust quantum based on new mode
        switch (new_mode) {
            .cooperative => {
                entry.quantum = @min(entry.quantum, self.config.max_quantum);
            },
            .preemptive => {
                entry.quantum = self.config.preemption_interval;
            },
            .hybrid => {
                entry.quantum = (self.config.max_quantum + self.config.preemption_interval) / 2;
            },
            else => {
                entry.quantum = self.config.max_quantum;
            },
        }

        entry.quantum_remaining = entry.quantum;

        std.debug.print(
            "scheduler: thread mode migration: handle=0x{x} old_mode={s} new_mode={s} quantum={d}\n",
            .{ entry.handle, @tagName(entry.scheduling_mode), @tagName(new_mode), entry.quantum },
        );

        return true;
    }

    /// Update thread priority
    pub fn updateThreadPriority(self: *SchedulerPolicy, registry: *thread_registry.ThreadRegistry, handle: u64, new_priority: thread_interceptor.ThreadPriority) bool {
        const entry = registry.findByHandle(handle) orelse return false;

        if (entry.priority == new_priority) return true;

        entry.priority = new_priority;

        // Adjust quantum based on priority
        const priority_index = @intFromEnum(new_priority) - @intFromEnum(thread_interceptor.ThreadPriority.very_low);
        const priority_multiplier = if (priority_index < self.config.priority_quantum_multipliers.len)
            self.config.priority_quantum_multipliers[priority_index]
        else
            4; // fallback to normal

        entry.quantum = @min(self.config.max_quantum, self.config.min_quantum * priority_multiplier);
        entry.quantum_remaining = entry.quantum;

        std.debug.print(
            "scheduler: thread priority update: handle=0x{x} old_priority={s} new_priority={s} quantum={d}\n",
            .{ entry.handle, @tagName(entry.priority), @tagName(new_priority), entry.quantum },
        );

        return true;
    }

    /// Log policy statistics
    pub fn logSummary(self: *const SchedulerPolicy) void {
        if (self.scheduling_decisions == 0) return;

        std.debug.print(
            "scheduler: policy: decisions={d} yields={d} suspensions={d} preemptions={d} mode_switches={d} current_mode={s}\n",
            .{ self.scheduling_decisions, self.yields, self.suspensions, self.preemptions, self.mode_switches, @tagName(self.current_mode) },
        );
    }
};

test "scheduler policy basic decision making" {
    var policy = SchedulerPolicy{};
    var registry = thread_registry.ThreadRegistry{};
    registry.init();

    const context = SchedulingContext{
        .current_step = 10000,
        .current_thread = 0x7fff2000,
        .current_rip = 0x1000,
        .active_threads = 2,
        .suspended_threads = 1,
        .waiting_threads = 0,
        .pending_idle = 0,
        .deferred_threads = 0,
        .load_factor = 0.5,
        .in_ui_context = false,
    };

    const decision = policy.makeDecision(&registry, context);
    try std.testing.expectEqual(@as(SchedulingDecision, .run), decision);
}

test "scheduler policy adaptive mode switching" {
    var policy = SchedulerPolicy{
        .config = .{
            .enable_adaptive = true,
            .load_threshold = 0.7,
        },
    };

    var registry = thread_registry.ThreadRegistry{};
    registry.init();

    const high_load_context = SchedulingContext{
        .current_step = 10000,
        .current_thread = 0x7fff2000,
        .current_rip = 0x1000,
        .active_threads = 10,
        .suspended_threads = 5,
        .waiting_threads = 2,
        .pending_idle = 3,
        .deferred_threads = 5,
        .load_factor = 0.8,
        .in_ui_context = false,
    };

    // Simulate enough steps to allow mode switch
    policy.steps_since_mode_switch = 10001;

    const decision1 = policy.makeDecision(&registry, high_load_context);
    _ = decision1;

    // After high load, should switch to preemptive
    try std.testing.expectEqual(@as(thread_interceptor.SchedulingMode, .preemptive), policy.current_mode);
}
