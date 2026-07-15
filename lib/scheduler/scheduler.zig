const std = @import("std");
const thread_interceptor = @import("thread_interceptor.zig");
const thread_registry = @import("thread_registry.zig");
const scheduler_policy = @import("scheduler_policy.zig");

/// Global scheduler instance
pub const GlobalScheduler = struct {
    /// Thread interceptor
    interceptor: thread_interceptor.ThreadInterceptor = .{},

    /// Thread registry
    registry: thread_registry.ThreadRegistry = .{},

    /// Scheduler policy
    policy: scheduler_policy.SchedulerPolicy = .{},

    /// Whether scheduler is initialized
    initialized: bool = false,

    /// Current step
    current_step: u64 = 0,

    /// Main thread handle
    main_thread_handle: u64 = 0x7FFF_1000,

    /// UI thread handle
    ui_thread_handle: u64 = 0,

    /// Whether in UI context
    in_ui_context: bool = false,

    /// Pending GTK idle callbacks
    pending_idle_callbacks: usize = 0,

    /// Deferred threads count
    deferred_threads: u64 = 0,

    /// Statistics
    total_yields: u64 = 0,
    total_suspensions: u64 = 0,
    total_resumptions: u64 = 0,
    total_switches: u64 = 0,

    /// Initialize the global scheduler
    pub fn init(self: *GlobalScheduler) void {
        self.registry.init();
        self.interceptor.enable();
        self.initialized = true;
        self.current_step = 0;

        std.debug.print("scheduler: global scheduler initialized\n", .{});
    }

    /// Shutdown the global scheduler
    pub fn shutdown(self: *GlobalScheduler) void {
        self.interceptor.disable();
        self.initialized = false;

        std.debug.print("scheduler: global scheduler shutdown\n", .{});
    }

    /// Update current step
    pub fn updateStep(self: *GlobalScheduler, step: u64) void {
        self.current_step = step;
    }

    /// Update UI context state
    pub fn setUIContext(self: *GlobalScheduler, in_ui: bool) void {
        self.in_ui_context = in_ui;
    }

    /// Update pending idle callback count
    pub fn updatePendingIdle(self: *GlobalScheduler, count: usize) void {
        self.pending_idle_callbacks = count;
    }

    /// Update deferred threads count
    pub fn updateDeferredThreads(self: *GlobalScheduler, count: u64) void {
        self.deferred_threads = count;
    }

    /// Intercept and handle thread creation
    pub fn handleThreadCreation(self: *GlobalScheduler, context: thread_interceptor.ThreadCreationContext, stack_base: u64, stack_size: u64) !u64 {
        if (!self.initialized) return error.NotInitialized;

        // Detect thread type if unknown
        var detected_context = context;
        if (detected_context.thread_type == .unknown) {
            detected_context.thread_type = thread_interceptor.ThreadInterceptor.detectThreadType(detected_context);
        }

        // Intercept thread creation
        const result = self.interceptor.intercept(detected_context);

        switch (result) {
            .deny => return error.ThreadCreationDenied,
            .@"defer" => return error.ThreadCreationDeferred,
            .redirect => {
                // For now, treat redirect as allow
                // In future, this could redirect to a wrapper function
            },
            .allow => {},
        }

        // Create thread entry in registry
        const entry = try self.registry.createThread(detected_context, stack_base, stack_size);

        return entry.handle;
    }

    /// Mark thread as started
    pub fn threadStarted(self: *GlobalScheduler, handle: u64) void {
        if (!self.initialized) return;
        self.registry.markStarted(handle, self.current_step);

        // Set UI thread handle if this is a UI thread
        if (self.registry.findByHandle(handle)) |entry| {
            if (entry.thread_type == .ui) {
                self.ui_thread_handle = handle;
            }
        }
    }

    /// Mark thread as completed
    pub fn threadCompleted(self: *GlobalScheduler, handle: u64) void {
        if (!self.initialized) return;
        self.registry.markCompleted(handle, self.current_step);
    }

    /// Suspend current thread
    pub fn suspendThread(self: *GlobalScheduler, handle: u64, reason: []const u8, rip: u64) bool {
        if (!self.initialized) return false;

        const success = self.registry.suspendThread(handle, reason, rip);
        if (success) {
            self.total_suspensions +|= 1;
        }

        return success;
    }

    /// Resume a suspended thread
    pub fn resumeThread(self: *GlobalScheduler, handle: u64) bool {
        if (!self.initialized) return false;

        const success = self.registry.resumeThread(handle);
        if (success) {
            self.total_resumptions +|= 1;
        }

        return success;
    }

    /// Get next thread to run
    pub fn getNextThread(self: *GlobalScheduler) ?u64 {
        if (!self.initialized) return null;

        const context = self.buildSchedulingContext();
        return self.policy.selectNextThread(&self.registry, context);
    }

    /// Make scheduling decision for current thread
    pub fn makeSchedulingDecision(self: *GlobalScheduler, current_thread: u64, current_rip: u64) scheduler_policy.SchedulingDecision {
        if (!self.initialized) return .run;

        // Update thread RIP
        self.registry.updateRip(current_thread, current_rip);

        // Consume quantum
        if (self.registry.consumeQuantum(current_thread, 1)) {
            // Quantum remaining, check for other reasons to yield
        } else {
            // Quantum exhausted, reset and continue
            self.registry.resetQuantum(current_thread);
        }

        const context = self.buildSchedulingContext();
        const decision = self.policy.makeDecision(&self.registry, context);

        // Handle decision
        switch (decision) {
            .yield => {
                self.total_yields +|= 1;
                self.registry.recordYield(current_thread);
            },
            .@"suspend" => {
                self.total_suspensions +|= 1;
                _ = self.suspendThread(current_thread, "policy_decision", current_rip);
            },
            .preempt => {
                self.total_suspensions +|= 1;
                _ = self.suspendThread(current_thread, "preemption", current_rip);
            },
            else => {},
        }

        return decision;
    }

    /// Switch to a different thread
    pub fn switchThread(self: *GlobalScheduler, from_handle: u64, to_handle: u64) bool {
        if (!self.initialized) return false;

        // Suspend current thread
        const from_entry = self.registry.findByHandle(from_handle);
        if (from_entry) |entry| {
            _ = self.suspendThread(from_handle, "thread_switch", entry.rip);
        }

        // Resume target thread
        const success = self.resumeThread(to_handle);
        if (success) {
            self.total_switches +|= 1;
        }

        return success;
    }

    /// Handle cooperative yield from current thread
    pub fn handleCooperativeYield(self: *GlobalScheduler, current_thread: u64, reason: []const u8, rip: u64) ?u64 {
        if (!self.initialized) return null;

        // Suspend current thread
        if (!self.suspendThread(current_thread, reason, rip)) {
            return null;
        }

        self.total_yields +|= 1;

        // Get next thread to run
        const next_thread = self.getNextThread();
        if (next_thread) |handle| {
            // A peer may already be runnable; only suspended peers require an
            // explicit lifecycle transition before the context switch.
            const already_running = if (self.registry.findByHandle(handle)) |entry| entry.state == .running else false;
            if (already_running or self.resumeThread(handle)) {
                self.total_switches +|= 1;
                return handle;
            }
        }

        // If no next thread, resume current thread
        _ = self.resumeThread(current_thread);
        return current_thread;
    }

    /// Handle thread waiting on condition variable
    pub fn handleCondvarWait(self: *GlobalScheduler, handle: u64, condvar: u64, mutex: u64) void {
        if (!self.initialized) return;

        self.registry.setWaitingCondvar(handle, condvar, mutex);
        _ = self.suspendThread(handle, "condvar_wait", 0);
    }

    /// Handle thread being signaled from condition variable wait
    pub fn handleCondvarSignal(self: *GlobalScheduler, handle: u64) bool {
        if (!self.initialized) return false;

        self.registry.clearWaiting(handle);
        return self.resumeThread(handle);
    }

    /// Handle thread joining another thread
    pub fn handleThreadJoin(self: *GlobalScheduler, waiter_handle: u64, target_handle: u64) bool {
        if (!self.initialized) return false;

        const target_entry = self.registry.findByHandle(target_handle);
        if (target_entry) |entry| {
            if (entry.state == .completed) {
                // Target already completed, join succeeds immediately
                return true;
            }

            // Mark target as having a join waiter
            entry.join_waiter = waiter_handle;

            // Suspend waiter
            _ = self.suspendThread(waiter_handle, "thread_join", 0);
            return false;
        }

        return false;
    }

    /// Handle thread mutex acquisition
    pub fn handleMutexAcquire(self: *GlobalScheduler, handle: u64, mutex: u64) bool {
        if (!self.initialized) return false;

        return self.registry.addMutexOwnership(handle, mutex);
    }

    /// Handle thread mutex release
    pub fn handleMutexRelease(self: *GlobalScheduler, handle: u64, mutex: u64) void {
        if (!self.initialized) return;

        self.registry.removeMutexOwnership(handle, mutex);
    }

    /// Migrate thread to different scheduling mode
    pub fn migrateThreadMode(self: *GlobalScheduler, handle: u64, new_mode: thread_interceptor.SchedulingMode) bool {
        if (!self.initialized) return false;

        return self.policy.migrateThreadMode(&self.registry, handle, new_mode);
    }

    /// Update thread priority
    pub fn updateThreadPriority(self: *GlobalScheduler, handle: u64, new_priority: thread_interceptor.ThreadPriority) bool {
        if (!self.initialized) return false;

        return self.policy.updateThreadPriority(&self.registry, handle, new_priority);
    }

    /// Build scheduling context
    fn buildSchedulingContext(self: *GlobalScheduler) scheduler_policy.SchedulingContext {
        const suspended_count = self.registry.countByState(.suspended);
        const waiting_count = self.registry.countByState(.waiting);
        const load_factor = if (self.registry.active_count > 0)
            @as(f64, @floatFromInt(suspended_count + waiting_count)) / @as(f64, @floatFromInt(self.registry.active_count))
        else
            0.0;

        return .{
            .current_step = self.current_step,
            .current_thread = self.main_thread_handle, // This should be set by caller
            .current_rip = 0, // This should be set by caller
            .active_threads = self.registry.active_count,
            .suspended_threads = suspended_count,
            .waiting_threads = waiting_count,
            .pending_idle = self.pending_idle_callbacks,
            .deferred_threads = self.deferred_threads,
            .load_factor = load_factor,
            .in_ui_context = self.in_ui_context,
        };
    }

    /// Run scheduler diagnostics
    pub fn runDiagnostics(self: *GlobalScheduler) void {
        if (!self.initialized) return;

        self.registry.diagnoseStuckThreads(self.current_step);
    }

    /// Log scheduler summary
    pub fn logSummary(self: *const GlobalScheduler) void {
        if (!self.initialized) return;

        std.debug.print(
            "scheduler: global scheduler: yields={d} suspensions={d} resumptions={d} switches={d}\n",
            .{ self.total_yields, self.total_suspensions, self.total_resumptions, self.total_switches },
        );

        self.interceptor.logSummary();
        self.registry.logSummary();
        self.policy.logSummary();
    }
};

/// Global scheduler instance
var global_scheduler: GlobalScheduler = .{};

/// Get global scheduler instance
pub fn getGlobalScheduler() *GlobalScheduler {
    return &global_scheduler;
}

/// Initialize global scheduler
pub fn initGlobalScheduler() void {
    global_scheduler.init();
}

/// Shutdown global scheduler
pub fn shutdownGlobalScheduler() void {
    global_scheduler.shutdown();
}

test "global scheduler basic operations" {
    initGlobalScheduler();
    defer shutdownGlobalScheduler();

    const scheduler = getGlobalScheduler();
    try std.testing.expect(scheduler.initialized);

    scheduler.updateStep(1000);
    try std.testing.expectEqual(@as(u64, 1000), scheduler.current_step);

    scheduler.setUIContext(true);
    try std.testing.expect(scheduler.in_ui_context);

    scheduler.updatePendingIdle(5);
    try std.testing.expectEqual(@as(usize, 5), scheduler.pending_idle_callbacks);
}

test "global scheduler thread creation" {
    initGlobalScheduler();
    defer shutdownGlobalScheduler();

    const scheduler = getGlobalScheduler();

    const context = thread_interceptor.ThreadCreationContext{
        .level = .pthread,
        .thread_type = .worker,
        .start_routine = 0x1000,
        .argument = 0,
        .stack_size = 512 * 1024,
        .creator_handle = 0x7fff2000,
        .creation_step = 1000,
        .start_symbol = "worker_thread",
    };

    const handle = scheduler.handleThreadCreation(context, 0x10000, 512 * 1024) catch unreachable;
    try std.testing.expect(handle != 0);

    scheduler.threadStarted(handle);

    const entry = scheduler.registry.findByHandle(handle);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(thread_interceptor.ThreadLifecycleState, .running), entry.?.state);
}

test "global scheduler cooperative yield" {
    initGlobalScheduler();
    defer shutdownGlobalScheduler();

    const scheduler = getGlobalScheduler();
    scheduler.updateStep(1000);

    const context = thread_interceptor.ThreadCreationContext{
        .level = .pthread,
        .thread_type = .worker,
        .start_routine = 0x1000,
        .argument = 0,
        .stack_size = 512 * 1024,
        .creator_handle = 0x7fff2000,
        .creation_step = 1000,
    };

    const handle1 = scheduler.handleThreadCreation(context, 0x10000, 512 * 1024) catch unreachable;
    scheduler.threadStarted(handle1);

    const handle2 = scheduler.handleThreadCreation(context, 0x20000, 512 * 1024) catch unreachable;
    scheduler.threadStarted(handle2);

    // Yield from thread1
    const next = scheduler.handleCooperativeYield(handle1, "test_yield", 0x1004);
    try std.testing.expect(next != null);
    try std.testing.expect(next.? != handle1); // Should switch to different thread
}
