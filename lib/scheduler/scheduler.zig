const std = @import("std");
const thread_interceptor = @import("thread_interceptor.zig");
const thread_registry = @import("thread_registry.zig");
const scheduler_policy = @import("scheduler_policy.zig");
const spin_parking = @import("spin_parking.zig");
const polling_detection = @import("polling_detection.zig");
const wait_graph = @import("wait_graph.zig");
// const native_thread_backend = @import("native_thread_backend.zig");

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

    /// Whether main thread handle has been verified via thread creation
    main_thread_verified: bool = false,

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

    /// Spin parking manager
    spin_parking: ?spin_parking.SpinParkingManager = null,

    /// Polling detection manager
    polling_detection: ?polling_detection.PollingDetectionManager = null,

    /// Wait-for graph
    wait_graph: ?wait_graph.WaitForGraph = null,

    /// Native thread backend (commented out for now due to threading complexity)
    // native_backend: ?native_thread_backend.NativeThreadBackend = null,

    /// Initialize the global scheduler
    pub fn init(self: *GlobalScheduler, allocator: std.mem.Allocator) void {
        self.registry.init();
        self.interceptor.enable();
        self.initialized = true;
        self.current_step = 0;
        
        // Initialize spin parking manager
        self.spin_parking = spin_parking.SpinParkingManager.init(allocator);
        
        // Initialize polling detection manager
        self.polling_detection = polling_detection.PollingDetectionManager.init(allocator);
        
        // Initialize wait-for graph
        self.wait_graph = wait_graph.WaitForGraph.init(allocator);
        
        // Initialize native thread backend (commented out for now)
        // const native_config = native_thread_backend.NativeThreadConfig{
        //     .enabled = false,
        // };
        // self.native_backend = native_thread_backend.NativeThreadBackend.init(allocator, native_config);

        std.debug.print("scheduler: global scheduler initialized\n", .{});
    }

    /// Shutdown the global scheduler
    pub fn shutdown(self: *GlobalScheduler) void {
        self.interceptor.disable();
        self.initialized = false;
        
        // Deinitialize spin parking manager
        if (self.spin_parking) |*manager| {
            manager.deinit();
            self.spin_parking = null;
        }
        
        // Deinitialize polling detection manager
        if (self.polling_detection) |*manager| {
            manager.deinit();
            self.polling_detection = null;
        }
        
        // Deinitialize wait-for graph
        if (self.wait_graph) |*graph| {
            graph.clear();
            self.wait_graph = null;
        }
        
        // Deinitialize native thread backend (commented out for now)
        // if (self.native_backend) |*backend| {
        //     backend.deinit();
        //     self.native_backend = null;
        // }

        std.debug.print("scheduler: global scheduler shutdown\n", .{});
    }

    /// Update current step
    pub fn updateStep(self: *GlobalScheduler, step: u64) void {
        self.current_step = step;
    }

    /// Diagnose potential hang: dumps full state if a running thread has
    /// made no progress for `stall_threshold` steps.
    pub fn diagnoseHang(
        self: *GlobalScheduler,
        active_handle: u64,
        active_rip: u64,
        stall_threshold: u64,
    ) void {
        self.registry.diagnoseHang(self.current_step, stall_threshold, active_handle, active_rip);
    }

    /// Record a thread switch in the audit trail
    pub fn recordSwitch(
        self: *GlobalScheduler,
        from_handle: u64,
        to_handle: u64,
        rip: u64,
        reason: []const u8,
    ) void {
        self.registry.recordSwitch(from_handle, to_handle, self.current_step, rip, reason);
    }

    /// Register progress checkpoint for the active thread
    pub fn registerProgress(self: *GlobalScheduler, handle: u64, rip: u64) void {
        self.registry.registerProgress(handle, self.current_step, rip);
    }

    /// Reset continuous run counter (on yield/suspend)
    pub fn resetContinuousRun(self: *GlobalScheduler, handle: u64) void {
        self.registry.resetContinuousRun(handle);
    }

    /// Dump full scheduler state snapshot
    pub fn dumpState(self: *GlobalScheduler, label: []const u8) void {
        self.summary();
        self.registry.dumpState(label);
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

        // Verify main thread handle on the first started thread
        if (!self.main_thread_verified) {
            if (handle == self.main_thread_handle) {
                self.main_thread_verified = true;
            } else {
                std.debug.print(
                    "scheduler: warning — first started thread handle 0x{x} does not match expected main_thread_handle 0x{x}\n",
                    .{ handle, self.main_thread_handle },
                );
            }
        }
    }

    /// Mark thread as completed
    pub fn threadCompleted(self: *GlobalScheduler, handle: u64) void {
        if (!self.initialized) return;
        const join_waiter = if (self.registry.findByHandle(handle)) |entry| entry.join_waiter else 0;
        self.registry.markCompleted(handle, self.current_step);
        if (join_waiter != 0 and self.resumeThread(join_waiter)) {
            self.recordSwitch(handle, join_waiter, 0, "thread_join_complete");
        }
    }

    /// Suspend current thread
    pub fn suspendThread(self: *GlobalScheduler, handle: u64, reason: []const u8, rip: u64) bool {
        if (!self.initialized) return false;

        const success = self.registry.suspendThread(handle, reason, rip, self.current_step);
        if (success) {
            self.total_suspensions +|= 1;
        }

        return success;
    }

    /// Resume a suspended thread
    pub fn resumeThread(self: *GlobalScheduler, handle: u64) bool {
        if (!self.initialized) return false;

        const success = self.registry.resumeThread(handle, self.current_step);
        if (success) {
            self.total_resumptions +|= 1;
        }

        return success;
    }

    /// Get next thread to run
    pub fn getNextThread(self: *GlobalScheduler, current_thread: u64, current_rip: u64) ?u64 {
        if (!self.initialized) return null;

        const context = self.buildSchedulingContext(current_thread, current_rip);
        return self.policy.selectNextThread(&self.registry, context);
    }

    /// Make scheduling decision for current thread
    pub fn makeSchedulingDecision(self: *GlobalScheduler, current_thread: u64, current_rip: u64) scheduler_policy.SchedulingDecision {
        if (!self.initialized) return .run;

        self.registry.accountExecution(current_thread, self.current_step, current_rip);

        const context = self.buildSchedulingContext(current_thread, current_rip);
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
        if (from_handle == to_handle) return true;

        // Suspend current thread
        const from_entry = self.registry.findByHandle(from_handle);
        if (from_entry) |entry| {
            self.recordSwitch(from_handle, to_handle, entry.rip, "switch_thread");
            _ = self.suspendThread(from_handle, "thread_switch", entry.rip);
        }

        // Resume target thread
        const success = self.resumeThread(to_handle);
        if (success) {
            self.total_switches +|= 1;
            self.resetContinuousRun(to_handle);
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
        const next_thread = self.getNextThread(current_thread, rip);
        if (next_thread) |handle| {
            // A peer may already be runnable; only suspended peers require an
            // explicit lifecycle transition before the context switch.
            const already_running = if (self.registry.findByHandle(handle)) |entry| entry.state == .running else false;
            if (already_running or self.resumeThread(handle)) {
                self.total_switches +|= 1;
                self.recordSwitch(current_thread, handle, rip, "coop_yield");
                self.resetContinuousRun(handle);
                return handle;
            }
        }

        // If no next thread, resume current thread
        _ = self.resumeThread(current_thread);
        return current_thread;
    }

    /// Handle thread waiting on condition variable
    pub fn handleCondvarWait(self: *GlobalScheduler, handle: u64, condvar: u64, mutex: u64, rip: u64) bool {
        if (!self.initialized) return false;
        const success = self.registry.setWaitingCondvar(handle, condvar, mutex, rip, self.current_step);
        if (success) self.total_suspensions +|= 1;
        return success;
    }

    /// Handle thread being signaled from condition variable wait
    pub fn handleCondvarSignal(self: *GlobalScheduler, signaler_handle: u64, handle: u64) bool {
        if (!self.initialized) return false;

        if (!self.registry.clearWaiting(handle)) return false;
        const result = self.resumeThread(handle);
        if (result) {
            self.recordSwitch(signaler_handle, handle, 0, "condvar_signal");
            self.resetContinuousRun(handle);
        }
        return result;
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
            if (!self.suspendThread(waiter_handle, "thread_join", 0)) return false;
            // Re-check after the state transition so a completion observed at
            // the scheduling boundary cannot strand the waiter.
            if (entry.state == .completed) {
                entry.join_waiter = 0;
                _ = self.resumeThread(waiter_handle);
                return true;
            }
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
    fn buildSchedulingContext(self: *GlobalScheduler, current_thread: u64, current_rip: u64) scheduler_policy.SchedulingContext {
        const suspended_count = self.registry.countByState(.suspended);
        const waiting_count = self.registry.countByState(.waiting);
        const load_factor = if (self.registry.active_count > 0)
            @as(f64, @floatFromInt(suspended_count + waiting_count)) / @as(f64, @floatFromInt(self.registry.active_count))
        else
            0.0;

        return .{
            .current_step = self.current_step,
            .current_thread = current_thread,
            .current_rip = current_rip,
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

        self.registry.diagnoseStuckThreads(self.current_step, self.policy.config.stuck_diagnostic_threshold);
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
        
        if (self.spin_parking) |*manager| {
            manager.logSummary();
        }
        
        if (self.polling_detection) |*manager| {
            manager.logSummary();
        }
        
        if (self.wait_graph) |*graph| {
            graph.logSummary();
        }
    }


    /// Detect spin loop for a thread
    pub fn detectSpinLoop(
        self: *GlobalScheduler,
        thread_handle: u64,
        current_rip: u64,
        steps_per_second: u64,
    ) bool {
        if (!self.initialized or self.spin_parking == null) return false;
        
        return self.spin_parking.?.detectSpinLoop(
            thread_handle,
            current_rip,
            self.current_step,
            steps_per_second,
        );
    }

    /// Record memory read during spin detection
    pub fn recordSpinMemoryRead(
        self: *GlobalScheduler,
        thread_handle: u64,
        address: u64,
        value: u64,
    ) void {
        if (!self.initialized or self.spin_parking == null) return;
        
        self.spin_parking.?.recordMemoryRead(thread_handle, address, value);
    }

    /// Record memory write during spin detection
    pub fn recordSpinMemoryWrite(
        self: *GlobalScheduler,
        thread_handle: u64,
        address: u64,
    ) void {
        if (!self.initialized or self.spin_parking == null) return;
        
        self.spin_parking.?.recordMemoryWrite(thread_handle, address);
    }

    /// Set up address watch for a thread
    pub fn setupAddressWatch(
        self: *GlobalScheduler,
        thread_handle: u64,
        address: u64,
        expected_value: u64,
        width: spin_parking.OperandWidth,
        deadline: ?u64,
    ) !void {
        if (!self.initialized or self.spin_parking == null) return error.NotInitialized;
        
        try self.spin_parking.?.setupAddressWatch(
            thread_handle,
            address,
            expected_value,
            width,
            deadline,
            self.current_step,
        );
    }

    /// Check if memory write triggers any address watches
    pub fn checkMemoryWriteWakeup(
        self: *GlobalScheduler,
        address: u64,
        new_value: u64,
    ) ?u64 {
        if (!self.initialized or self.spin_parking == null) return null;
        
        return self.spin_parking.?.checkMemoryWrite(address, new_value, self.current_step);
    }

    /// Check for expired watches
    pub fn checkExpiredWatches(self: *GlobalScheduler) ?[]const u64 {
        if (!self.initialized or self.spin_parking == null) return null;
        
        return self.spin_parking.?.checkExpiredWatches(self.current_step);
    }

    /// Clear spin state for a thread
    pub fn clearSpinState(self: *GlobalScheduler, thread_handle: u64) void {
        if (!self.initialized or self.spin_parking == null) return;
        
        self.spin_parking.?.clearSpinState(thread_handle);
    }

    /// Get polling address for a thread
    pub fn getPollingAddress(
        self: *GlobalScheduler,
        thread_handle: u64,
    ) ?struct {
        address: u64,
        expected_value: u64,
        width: spin_parking.OperandWidth,
    } {
        if (!self.initialized or self.spin_parking == null) return null;
        
        return self.spin_parking.?.getPollingAddress(thread_handle);
    }

    /// Start polling detection for a thread
    pub fn startPollingDetection(
        self: *GlobalScheduler,
        thread_handle: u64,
        current_rip: u64,
    ) void {
        if (!self.initialized or self.polling_detection == null) return;
        
        self.polling_detection.?.startDetection(thread_handle, current_rip, self.current_step);
    }

    /// Record memory access for polling detection
    pub fn recordPollingMemoryAccess(
        self: *GlobalScheduler,
        thread_handle: u64,
        address: u64,
        value: u64,
        width: u8,
        is_write: bool,
    ) void {
        if (!self.initialized or self.polling_detection == null) return;
        
        self.polling_detection.?.recordMemoryAccess(
            thread_handle,
            address,
            value,
            width,
            is_write,
            self.current_step,
        );
    }

    /// Classify if thread is polling
    pub fn classifyPolling(
        self: *GlobalScheduler,
        thread_handle: u64,
        current_rip: u64,
    ) ?polling_detection.PollingClassification {
        if (!self.initialized or self.polling_detection == null) return null;
        
        return self.polling_detection.?.classifyPolling(thread_handle, self.current_step, current_rip);
    }

    /// Add wait-for graph node
    pub fn addWaitGraphNode(
        self: *GlobalScheduler,
        node_type: wait_graph.WaitNodeType,
        id: u64,
        data: u64,
    ) !void {
        if (!self.initialized or self.wait_graph == null) return error.NotInitialized;
        
        _ = try self.wait_graph.?.addNode(node_type, id, data);
    }

    /// Add wait-for graph edge
    pub fn addWaitGraphEdge(
        self: *GlobalScheduler,
        from_id: u64,
        to_id: u64,
    ) !void {
        if (!self.initialized or self.wait_graph == null) return error.NotInitialized;
        
        try self.wait_graph.?.addEdge(from_id, to_id);
    }

    /// Remove wait-for graph node
    pub fn removeWaitGraphNode(self: *GlobalScheduler, id: u64) void {
        if (!self.initialized or self.wait_graph == null) return;
        
        self.wait_graph.?.removeNode(id);
    }

    /// Classify blocking for a thread
    pub fn classifyBlocking(
        self: *GlobalScheduler,
        thread_handle: u64,
    ) ?wait_graph.BlockingClassification {
        if (!self.initialized or self.wait_graph == null) return null;
        
        return self.wait_graph.?.classifyBlocking(thread_handle);
    }

    /// Generate wait-for graph diagnostic dump
    pub fn generateWaitGraphDiagnostic(
        self: *GlobalScheduler,
        thread_states: ?std.AutoHashMap(u64, wait_graph.ThreadStateInfo),
    ) ![]const u8 {
        if (!self.initialized or self.wait_graph == null) return error.NotInitialized;
        
        return self.wait_graph.?.generateDiagnosticDump(thread_states);
    }

    /// Detect cycles in wait-for graph
    pub fn detectWaitGraphCycles(self: *GlobalScheduler) ![]const []const u64 {
        if (!self.initialized or self.wait_graph == null) return error.NotInitialized;
        
        return self.wait_graph.?.detectCycles();
    }
};

/// Global scheduler instance
var global_scheduler: GlobalScheduler = .{};
var global_scheduler_initialized: bool = false;

/// Get global scheduler instance
pub fn getGlobalScheduler() *GlobalScheduler {
    return &global_scheduler;
}

/// Initialize global scheduler
pub fn initGlobalScheduler(allocator: std.mem.Allocator) void {
    if (!global_scheduler_initialized) {
        global_scheduler.init(allocator);
        global_scheduler_initialized = true;
    }
}

/// Shutdown global scheduler
pub fn shutdownGlobalScheduler() void {
    if (global_scheduler_initialized) {
        global_scheduler.shutdown();
        global_scheduler_initialized = false;
    }
}

test "global scheduler basic operations" {
    const allocator = std.testing.allocator;
    initGlobalScheduler(allocator);
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
    const allocator = std.testing.allocator;
    initGlobalScheduler(allocator);
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
    const allocator = std.testing.allocator;
    initGlobalScheduler(allocator);
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

test "scheduling decision uses caller thread identity and elapsed work" {
    const allocator = std.testing.allocator;
    var scheduler = GlobalScheduler{};
    scheduler.init(allocator);
    defer scheduler.shutdown();
    const context = thread_interceptor.ThreadCreationContext{
        .level = .pthread,
        .thread_type = .worker,
        .start_routine = 0x1000,
        .argument = 0,
        .stack_size = 4096,
        .creator_handle = 1,
        .creation_step = 100,
    };
    const handle = try scheduler.handleThreadCreation(context, 0x2000, 4096);
    scheduler.updateStep(100);
    scheduler.threadStarted(handle);
    scheduler.updatePendingIdle(1);
    scheduler.updateStep(350);
    const decision = scheduler.makeSchedulingDecision(handle, 0x1008);
    try std.testing.expectEqual(scheduler_policy.SchedulingDecision.yield, decision);
    try std.testing.expectEqual(@as(u64, 250), scheduler.registry.findByHandle(handle).?.execution_steps);
}

test "self switch is a no-op" {
    const allocator = std.testing.allocator;
    var scheduler = GlobalScheduler{};
    scheduler.init(allocator);
    defer scheduler.shutdown();
    try std.testing.expect(scheduler.switchThread(0x1234, 0x1234));
    try std.testing.expectEqual(@as(u64, 0), scheduler.total_switches);
}
