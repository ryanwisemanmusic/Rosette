const std = @import("std");
const thread_interceptor = @import("thread_interceptor.zig");

const SwitchAuditCapacity = 128;

const SwitchAuditEntry = struct {
    from_handle: u64 = 0,
    to_handle: u64 = 0,
    step: u64 = 0,
    rip: u64 = 0,
    reason: [24]u8 = [_]u8{0} ** 24,
    active: bool = false,
};

const SwitchReasonEntry = struct {
    reason: [24]u8 = [_]u8{0} ** 24,
    count: u64 = 0,
};

fn threadName(name: *const [32]u8) []const u8 {
    const len = std.mem.indexOfScalar(u8, name, 0) orelse name.len;
    return name[0..len];
}

/// Thread entry stored in the registry
pub const ThreadEntry = struct {
    /// Thread handle (unique identifier)
    handle: u64 = 0,

    /// Numeric thread ID (POSIX-style)
    numeric_id: u64 = 0,

    /// Thread type
    thread_type: thread_interceptor.ThreadType = .unknown,

    /// Thread creation level
    creation_level: thread_interceptor.ThreadCreationLevel = .unknown,

    /// Current lifecycle state
    state: thread_interceptor.ThreadLifecycleState = .created,

    /// Current scheduling mode
    scheduling_mode: thread_interceptor.SchedulingMode = .cooperative,

    /// Thread priority
    priority: thread_interceptor.ThreadPriority = .normal,

    /// Start routine address
    start_routine: u64 = 0,

    /// Argument passed to start routine
    argument: u64 = 0,

    /// Stack base address
    stack_base: u64 = 0,

    /// Stack size
    stack_size: u64 = 0,

    /// Current stack pointer
    stack_pointer: u64 = 0,

    /// Thread creation timestamp (steps)
    creation_step: u64 = 0,

    /// Thread start timestamp (steps)
    start_step: u64 = 0,

    /// Thread completion timestamp (steps)
    completion_step: u64 = 0,

    /// Total execution steps
    execution_steps: u64 = 0,

    /// Step at which the current run slice began.
    last_resume_step: u64 = 0,

    /// Last global step incorporated into execution/quantum accounting.
    last_accounted_step: u64 = 0,

    /// Cumulative execution count at the start of the current run slice.
    execution_steps_at_resume: u64 = 0,

    /// Step at which the current lifecycle state was entered.
    state_since_step: u64 = 0,

    /// Number of times this thread was suspended
    suspension_count: u64 = 0,

    /// Number of times this thread was resumed
    resume_count: u64 = 0,

    /// Number of cooperative yields
    yield_count: u64 = 0,

    /// Last suspension reason
    suspension_reason: []const u8 = "",

    /// Current RIP (instruction pointer)
    rip: u64 = 0,

    /// Thread name (if set)
    name: [32]u8 = [_]u8{0} ** 32,

    /// Whether thread has been joined
    joined: bool = false,

    /// Whether thread was cancelled
    cancelled: bool = false,

    /// Handle of thread waiting to join this thread
    join_waiter: u64 = 0,

    /// Condition variable this thread is waiting on (if any)
    waiting_condvar: u64 = 0,

    /// Mutex this thread is waiting on (if any)
    waiting_mutex: u64 = 0,

    /// Mutexes owned by this thread
    owned_mutexes: [32]u64 = [_]u64{0} ** 32,

    /// Number of owned mutexes
    owned_mutex_count: u8 = 0,

    /// Scheduling quantum (steps)
    quantum: u64 = 10000,

    /// Steps remaining in current quantum
    quantum_remaining: u64 = 10000,

    /// Thread creation context
    creation_context: ?thread_interceptor.ThreadCreationContext = null,

    /// Register state (for cooperative threads)
    regs: ?*anyopaque = null,

    /// Step at which this thread last made scheduling progress
    last_progress_step: u64 = 0,

    /// RIP at the last progress checkpoint
    last_progress_rip: u64 = 0,

    /// Total steps this thread has been continuously running without yielding
    continuous_run_steps: u64 = 0,

    /// Number of times this thread was flagged as stalled
    stall_count: u64 = 0,

    /// Step of the most recent stall detection
    last_stall_step: u64 = 0,

    /// RIP at the last suspend (for cross-quantum progress tracking)
    last_suspend_rip: u64 = 0,

    /// Number of consecutive suspensions where RIP did not change
    suspend_same_rip_count: u64 = 0,

    /// Step of the first consecutive same-RIP detection
    suspend_same_rip_start_step: u64 = 0,

    /// Total instructions executed (accumulated across quanta)
    total_instructions: u64 = 0,

    /// Instructions executed in the most recent quantum
    quantum_instructions: u64 = 0,

    /// Switch-out reason frequency table
    switch_reasons: [32]SwitchReasonEntry = [_]SwitchReasonEntry{.{}} ** 32,

    /// Whether this entry is active
    active: bool = false,
};

/// Thread registry for tracking all threads
pub const ThreadRegistry = struct {
    const MAX_THREADS = 1024;
    const MAX_SUSPENDED = MAX_THREADS;

    /// Thread entries
    entries: [MAX_THREADS]ThreadEntry = [_]ThreadEntry{.{}} ** MAX_THREADS,

    /// Number of active threads
    active_count: usize = 0,

    /// Next handle to allocate
    next_handle: u64 = 0x7FFF_2000,

    /// Entropy offset for handle allocation — XOR'd with sequential handles
    /// to make them less trivially enumerable while remaining unique.
    handle_entropy: u32 = 0xA5C3B7D1,

    /// Next numeric ID to allocate
    next_numeric_id: u64 = 2,

    /// Suspended thread queue (FIFO)
    suspended_queue: [MAX_SUSPENDED]u64 = [_]u64{0} ** MAX_SUSPENDED,

    /// Suspended queue head
    suspended_head: usize = 0,

    /// Suspended queue tail
    suspended_tail: usize = 0,

    /// Number of occupied queue slots. Head == tail is no longer ambiguous.
    suspended_count: usize = 0,

    /// Thread switch audit trail (ring buffer)
    switch_audit: [SwitchAuditCapacity]SwitchAuditEntry = [_]SwitchAuditEntry{.{}} ** SwitchAuditCapacity,

    /// Switch audit ring buffer index
    switch_audit_index: usize = 0,

    /// Statistics
    total_created: u64 = 0,
    total_completed: u64 = 0,
    total_suspended: u64 = 0,
    total_resumed: u64 = 0,
    total_yields: u64 = 0,
    suspended_queue_rejections: u64 = 0,

    /// Initialize the thread registry
    pub fn init(self: *ThreadRegistry) void {
        self.* = .{};
        self.next_handle = 0x7FFF_2000;
        self.next_numeric_id = 2;
    }

    /// Allocate a new thread handle with mild entropy to avoid predictable
    /// enumeration while keeping handles unique within a session.
    pub fn allocateHandle(self: *ThreadRegistry) u64 {
        const base = self.next_handle;
        self.next_handle += 0x10;
        // XOR the low 32 bits with entropy while preserving the high 32-bit
        // region (0x0000_7FFF) so that handles stay collision-free with
        // hardcoded constants such as main_thread_handle (0x7FFF_1000) and
        // callback handles (0xFFFF_F900_...).
        const high = base & 0xFFFF_FFFF_0000_0000;
        const low = @as(u32, @truncate(base)) ^ self.handle_entropy;
        // Rotate entropy so the next handle gets a different mask.
        self.handle_entropy = (self.handle_entropy << 5) | (self.handle_entropy >> 27);
        return high | @as(u64, low);
    }

    /// Allocate a new numeric thread ID
    pub fn allocateNumericId(self: *ThreadRegistry) u64 {
        const id = self.next_numeric_id;
        self.next_numeric_id +|= 1;
        return id;
    }

    /// Create a new thread entry
    pub fn createThread(self: *ThreadRegistry, context: thread_interceptor.ThreadCreationContext, stack_base: u64, stack_size: u64) !*ThreadEntry {
        // Find free entry
        for (&self.entries) |*entry| {
            if (entry.active) continue;

            entry.* = .{
                .active = true,
                .handle = self.allocateHandle(),
                .numeric_id = self.allocateNumericId(),
                .thread_type = context.thread_type,
                .creation_level = context.level,
                .state = .created,
                .scheduling_mode = .cooperative,
                .priority = .normal,
                .start_routine = context.start_routine,
                .argument = context.argument,
                .stack_base = stack_base,
                .stack_size = stack_size,
                .stack_pointer = stack_base + stack_size,
                .creation_step = context.creation_step,
                .quantum = defaultQuantumForType(context.thread_type),
                .quantum_remaining = defaultQuantumForType(context.thread_type),
                .creation_context = context,
            };

            // Set thread name from symbol if available
            if (context.start_symbol.len > 0) {
                const len = @min(context.start_symbol.len, entry.name.len - 1);
                if (context.start_symbol.len > entry.name.len - 1) {
                    std.debug.print("scheduler: thread name truncated (len={d} > max={d}): {s}\n", .{ context.start_symbol.len, entry.name.len - 1, context.start_symbol[0 .. entry.name.len - 1] });
                }
                @memcpy(entry.name[0..len], context.start_symbol[0..len]);
                entry.name[len] = 0;
            }

            self.active_count += 1;
            self.total_created +|= 1;

            std.debug.print(
                "scheduler: thread created: handle=0x{x} numeric_id={d} type={s} level={s} start=0x{x} stack=0x{x}/{d}\n",
                .{ entry.handle, entry.numeric_id, @tagName(entry.thread_type), @tagName(entry.creation_level), entry.start_routine, entry.stack_base, entry.stack_size },
            );

            return entry;
        }

        return error.ThreadLimitExceeded;
    }

    /// Find thread entry by handle
    pub fn findByHandle(self: *ThreadRegistry, handle: u64) ?*ThreadEntry {
        for (&self.entries) |*entry| {
            if (entry.active and entry.handle == handle) return entry;
        }
        return null;
    }

    /// Find thread entry by numeric ID
    pub fn findByNumericId(self: *ThreadRegistry, numeric_id: u64) ?*ThreadEntry {
        for (&self.entries) |*entry| {
            if (entry.active and entry.numeric_id == numeric_id) return entry;
        }
        return null;
    }

    /// Mark thread as started
    pub fn markStarted(self: *ThreadRegistry, handle: u64, start_step: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        if (entry.state == .created) {
            entry.state = .running;
            entry.start_step = start_step;
            entry.last_resume_step = start_step;
            entry.last_accounted_step = start_step;
            entry.last_progress_step = start_step;
            entry.state_since_step = start_step;
            entry.rip = entry.start_routine;
        }
    }

    /// Mark thread as completed
    pub fn markCompleted(self: *ThreadRegistry, handle: u64, completion_step: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        if (entry.state != .completed) {
            self.accountExecution(handle, completion_step, entry.rip);
            entry.state = .completed;
            entry.completion_step = completion_step;
            entry.state_since_step = completion_step;
            self.active_count -= 1;
            self.total_completed +|= 1;

            std.debug.print(
                "scheduler: thread completed: handle=0x{x} numeric_id={d} steps={d}\n",
                .{ entry.handle, entry.numeric_id, entry.execution_steps },
            );
        }
    }

    /// Suspend a thread
    pub fn suspendThread(self: *ThreadRegistry, handle: u64, reason: []const u8, rip: u64, current_step: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        // Accept .blocked and .waiting in addition to .running so that threads
        // blocked on a primitive can still be suspended by cooperative yield.
        switch (entry.state) {
            .running, .blocked, .waiting => {},
            else => return false,
        }
        if (self.suspended_count == self.suspended_queue.len) {
            self.suspended_queue_rejections +|= 1;
            std.debug.print(
                "scheduler: suspended queue full: handle=0x{x} capacity={d} rejection={d}; thread remains running\n",
                .{ handle, self.suspended_queue.len, self.suspended_queue_rejections },
            );
            return false;
        }

        self.accountExecution(handle, current_step, rip);

        // Cross-quantum RIP progress tracking: compare RIP to last-suspend RIP
        if (entry.suspension_count > 0 and entry.last_suspend_rip == rip) {
            entry.suspend_same_rip_count +|= 1;
            if (entry.suspend_same_rip_count == 1) {
                entry.suspend_same_rip_start_step = current_step;
            }
            if (entry.suspend_same_rip_count >= 3) {
                std.debug.print(
                    "scheduler: RIP STALL: thread=0x{x} id={d} rip=0x{x} same_rip_count={d} reason={s} name={s}\n",
                    .{ entry.handle, entry.numeric_id, rip, entry.suspend_same_rip_count, reason, threadName(&entry.name) },
                );
            }
        } else {
            if (entry.suspend_same_rip_count > 0) {
                std.debug.print(
                    "scheduler: RIP progress restored: thread=0x{x} id={d} prev_rip=0x{x} new_rip=0x{x} same_rip_count={d} name={s}\n",
                    .{ entry.handle, entry.numeric_id, entry.last_suspend_rip, rip, entry.suspend_same_rip_count, threadName(&entry.name) },
                );
            }
            entry.suspend_same_rip_count = 0;
            entry.suspend_same_rip_start_step = 0;
        }
        entry.last_suspend_rip = rip;

        entry.quantum_instructions = entry.execution_steps -| entry.execution_steps_at_resume;

        // Record switch-out reason for frequency tracking
        self.recordSuspendReason(handle, reason);

        entry.state = .suspended;
        entry.suspension_count +|= 1;
        entry.suspension_reason = reason;
        entry.rip = rip;
        entry.state_since_step = current_step;

        // Add to suspended queue
        const queue_pos = self.suspended_tail;
        self.suspended_queue[queue_pos] = handle;
        self.suspended_tail = (self.suspended_tail + 1) % MAX_SUSPENDED;
        self.suspended_count += 1;

        self.total_suspended +|= 1;

        std.debug.print(
            "scheduler: thread suspended: handle=0x{x} numeric_id={d} reason={s} rip=0x{x} susp_count={d} same_rip={d} qinst={d}\n",
            .{ entry.handle, entry.numeric_id, reason, rip, entry.suspension_count, entry.suspend_same_rip_count, entry.quantum_instructions },
        );

        return true;
    }

    /// Resume a suspended thread
    pub fn resumeThread(self: *ThreadRegistry, handle: u64, current_step: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        switch (entry.state) {
            .suspended, .blocked, .waiting => {},
            else => return false,
        }

        entry.state = .running;
        entry.resume_count +|= 1;
        entry.quantum_remaining = entry.quantum; // Reset quantum on resume
        entry.last_resume_step = current_step;
        entry.last_accounted_step = current_step;
        entry.execution_steps_at_resume = entry.execution_steps;
        entry.state_since_step = current_step;
        entry.waiting_condvar = 0;
        entry.waiting_mutex = 0;

        // Check if resumed at same RIP as last suspend (no progress between cycles)
        if (entry.suspend_same_rip_count > 0) {
            std.debug.print(
                "scheduler: RESUME WITH RIP STALL: thread=0x{x} id={d} rip=0x{x} same_rip_count={d} name={s}\n",
                .{ entry.handle, entry.numeric_id, entry.rip, entry.suspend_same_rip_count, threadName(&entry.name) },
            );
        }

        self.total_resumed +|= 1;

        std.debug.print(
            "scheduler: thread resumed: handle=0x{x} numeric_id={d} rip=0x{x} resume_count={d}\n",
            .{ entry.handle, entry.numeric_id, entry.rip, entry.resume_count },
        );

        return true;
    }

    /// Get next thread to resume from suspended queue (FIFO)
    pub fn nextSuspended(self: *ThreadRegistry) ?u64 {
        while (self.suspended_count != 0) {
            const handle = self.suspended_queue[self.suspended_head];
            self.suspended_queue[self.suspended_head] = 0;
            self.suspended_head = (self.suspended_head + 1) % MAX_SUSPENDED;
            self.suspended_count -= 1;
            const entry = self.findByHandle(handle) orelse continue;
            switch (entry.state) {
                .suspended, .blocked, .waiting => return handle,
                else => continue,
            }
        }
        return null;
    }

    /// Record a cooperative yield
    pub fn recordYield(self: *ThreadRegistry, handle: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        entry.yield_count +|= 1;
        self.total_yields +|= 1;
    }

    /// Update thread RIP
    pub fn updateRip(self: *ThreadRegistry, handle: u64, rip: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        entry.rip = rip;
    }

    /// Account actual global-step progress since the prior scheduler sample.
    /// This is independent of RIP movement, so jumps and tight loops do not
    /// distort execution or quantum totals.
    pub fn accountExecution(self: *ThreadRegistry, handle: u64, current_step: u64, rip: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        if (entry.state != .running) return;
        const elapsed = current_step -| entry.last_accounted_step;
        entry.last_accounted_step = current_step;
        entry.execution_steps +|= elapsed;
        entry.total_instructions +|= elapsed;
        entry.continuous_run_steps = current_step -| entry.last_resume_step;
        entry.last_progress_step = current_step;
        entry.last_progress_rip = rip;
        entry.rip = rip;
        _ = self.consumeQuantum(handle, elapsed);
    }

    /// Consume quantum for a thread
    pub fn consumeQuantum(self: *ThreadRegistry, handle: u64, steps: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        if (entry.quantum_remaining <= steps) {
            entry.quantum_remaining = 0;
            return false; // Quantum exhausted
        }
        entry.quantum_remaining -= steps;
        return true; // Quantum remaining
    }

    /// Reset quantum for a thread
    pub fn resetQuantum(self: *ThreadRegistry, handle: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        entry.quantum_remaining = entry.quantum;
    }

    /// Add mutex ownership to thread
    pub fn addMutexOwnership(self: *ThreadRegistry, handle: u64, mutex: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        if (entry.owned_mutex_count >= entry.owned_mutexes.len) return false;

        entry.owned_mutexes[entry.owned_mutex_count] = mutex;
        entry.owned_mutex_count += 1;
        return true;
    }

    /// Remove mutex ownership from thread
    pub fn removeMutexOwnership(self: *ThreadRegistry, handle: u64, mutex: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        for (0..entry.owned_mutex_count) |i| {
            if (entry.owned_mutexes[i] == mutex) {
                // Shift remaining entries
                for (i..entry.owned_mutex_count - 1) |j| {
                    entry.owned_mutexes[j] = entry.owned_mutexes[j + 1];
                }
                entry.owned_mutex_count -= 1;
                entry.owned_mutexes[entry.owned_mutex_count] = 0;
                return;
            }
        }
    }

    /// Set thread as waiting on condition variable
    pub fn setWaitingCondvar(self: *ThreadRegistry, handle: u64, condvar: u64, mutex: u64, rip: u64, current_step: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        if (entry.state != .running or self.suspended_count == self.suspended_queue.len) return false;
        self.accountExecution(handle, current_step, rip);
        entry.state = .waiting;
        entry.waiting_condvar = condvar;
        entry.waiting_mutex = mutex;
        entry.suspension_reason = "condvar_wait";
        entry.rip = rip;
        entry.state_since_step = current_step;
        self.suspended_queue[self.suspended_tail] = handle;
        self.suspended_tail = (self.suspended_tail + 1) % MAX_SUSPENDED;
        self.suspended_count += 1;
        self.total_suspended +|= 1;
        return true;
    }

    /// Clear waiting state
    pub fn clearWaiting(self: *ThreadRegistry, handle: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        if (entry.state != .waiting and entry.state != .blocked) return false;
        entry.waiting_condvar = 0;
        entry.waiting_mutex = 0;
        return true;
    }

    /// Get default quantum for thread type
    fn defaultQuantumForType(thread_type: thread_interceptor.ThreadType) u64 {
        return switch (thread_type) {
            .main => 50000, // Main thread gets longer quanta
            .ui => 30000, // UI thread gets priority
            .worker => 10000, // Workers get standard quanta
            .io => 5000, // I/O threads get shorter quanta
            .timer => 1000, // Timer threads get very short quanta
            .network => 5000, // Network threads get short quanta
            .background => 2000, // Background threads get minimal quanta
            .unknown => 10000, // Default
        };
    }

    /// Get count of threads in specific state
    pub fn countByState(self: *const ThreadRegistry, state: thread_interceptor.ThreadLifecycleState) usize {
        var count: usize = 0;
        for (&self.entries) |*entry| {
            if (entry.active and entry.state == state) count += 1;
        }
        return count;
    }

    /// Get count of threads by type
    pub fn countByType(self: *const ThreadRegistry, thread_type: thread_interceptor.ThreadType) usize {
        var count: usize = 0;
        for (&self.entries) |*entry| {
            if (entry.active and entry.thread_type == thread_type) count += 1;
        }
        return count;
    }

    /// Log registry statistics
    pub fn logSummary(self: *const ThreadRegistry) void {
        if (self.total_created == 0) return;

        const running = self.countByState(.running);
        const suspended = self.countByState(.suspended);
        const waiting = self.countByState(.waiting);
        std.debug.print(
            "scheduler: thread registry: active={d} total_created={d} completed={d} running={d} suspended={d} waiting={d} suspended_queue={d}\n",
            .{ self.active_count, self.total_created, self.total_completed, running, suspended, waiting, self.suspended_count },
        );

        std.debug.print(
            "scheduler: thread statistics: suspended={d} resumed={d} yields={d}\n",
            .{ self.total_suspended, self.total_resumed, self.total_yields },
        );
    }

    /// Record a thread switch in the audit trail
    /// Record a thread switch in the audit trail
    pub fn recordSwitch(self: *ThreadRegistry, from_handle: u64, to_handle: u64, step: u64, rip: u64, reason: []const u8) void {
        // If the trail is completely full (all entries active), skip recording
        // rather than losing the oldest diagnostic data without warning.
        var all_full = true;
        for (&self.switch_audit) |*e| { if (!e.active) { all_full = false; break; } }
        if (all_full) {
            std.debug.print("scheduler: switch audit full ({d} entries); dropping record\n", .{SwitchAuditCapacity});
            return;
        }
        const idx = self.switch_audit_index;
        const entry = &self.switch_audit[idx];
        entry.from_handle = from_handle;
        entry.to_handle = to_handle;
        entry.step = step;
        entry.rip = rip;
        const copy_len = @min(reason.len, entry.reason.len - 1);
        if (copy_len > 0) {
            @memcpy(entry.reason[0..copy_len], reason[0..copy_len]);
        }
        entry.reason[copy_len] = 0;
        entry.active = true;
        self.switch_audit_index = (idx + 1) % SwitchAuditCapacity;
    }

    /// Record progress checkpoint for a running thread
    pub fn registerProgress(self: *ThreadRegistry, handle: u64, current_step: u64, rip: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        if (entry.state != .running) {
            entry.continuous_run_steps = 0;
            return;
        }
        self.accountExecution(handle, current_step, rip);
    }

    /// Reset continuous run counter (called on yield, suspend, or wait)
    pub fn resetContinuousRun(self: *ThreadRegistry, handle: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        entry.continuous_run_steps = 0;
    }

    /// Record a switch-out reason for frequency tracking
    pub fn recordSuspendReason(self: *ThreadRegistry, handle: u64, reason: []const u8) void {
        const entry = self.findByHandle(handle) orelse return;
        // Find existing slot or use first empty
        var empty_slot: ?usize = null;
        for (&entry.switch_reasons, 0..) |*sr, i| {
            if (sr.count == 0 and empty_slot == null) {
                empty_slot = i;
            }
            // Compare by prefix since reasons can have varying lengths
            if (sr.count > 0) {
                const sr_len = std.mem.indexOfScalar(u8, &sr.reason, 0) orelse sr.reason.len;
                if (std.mem.eql(u8, sr.reason[0..sr_len], reason)) {
                    sr.count +|= 1;
                    return;
                }
            }
        }
        // Add to empty slot
        if (empty_slot) |slot| {
            const copy_len = @min(reason.len, entry.switch_reasons[slot].reason.len - 1);
            if (copy_len > 0) {
                @memcpy(entry.switch_reasons[slot].reason[0..copy_len], reason[0..copy_len]);
            }
            entry.switch_reasons[slot].reason[copy_len] = 0;
            entry.switch_reasons[slot].count = 1;
        }
    }

    /// Diagnose a potentially hanging running thread
    pub fn diagnoseRunningHang(self: *ThreadRegistry, handle: u64, current_step: u64, stall_threshold: u64, rip: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        if (entry.state != .running) return false;

        const run_duration = current_step -| entry.last_progress_step;
        if (run_duration < stall_threshold) return false;

        entry.stall_count +|= 1;
        entry.last_stall_step = current_step;

        std.debug.print(
            "scheduler: RUNNING THREAD STALLED: handle=0x{x} numeric_id={d} type={s} rip=0x{x} current_rip=0x{x} name={s} run_steps={d} no_progress={d} stall_count={d}\n",
            .{ entry.handle, entry.numeric_id, @tagName(entry.thread_type), entry.rip, rip, entry.name, entry.continuous_run_steps, run_duration, entry.stall_count },
        );
        return true;
    }

    /// Comprehensive hang detection across all threads
    pub fn diagnoseHang(self: *ThreadRegistry, current_step: u64, stall_threshold: u64, active_handle: u64, active_rip: u64) void {
        std.debug.print(
            "scheduler: HANG DIAGNOSTIC BEGIN: step={d} threshold={d} active=0x{x} rip=0x{x}\n",
            .{ current_step, stall_threshold, active_handle, active_rip },
        );

        // Check running thread
        if (active_handle != 0) {
            _ = self.diagnoseRunningHang(active_handle, current_step, stall_threshold, active_rip);
        }

        // Check all threads
        var running_count: usize = 0;
        var suspended_count: usize = 0;
        var waiting_count: usize = 0;
        var stuck_count: usize = 0;
        for (&self.entries) |*entry| {
            if (!entry.active) continue;
            switch (entry.state) {
                .running => running_count += 1,
                .suspended => suspended_count += 1,
                .waiting => waiting_count += 1,
                else => {},
            }
            const stuck_duration = if (entry.state == .suspended or entry.state == .waiting)
                current_step -| entry.state_since_step
            else
                0;
            const rip_stall_flag = if (entry.suspend_same_rip_count >= 3) " RIP-STALL!" else "";
            if (stuck_duration > stall_threshold or entry.suspend_same_rip_count >= 3) {
                stuck_count += 1;
                std.debug.print(
                    "scheduler:   thread=0x{x} id={d} type={s} state={s} stuck={d} reason={s} rip=0x{x} quantum={d}/{d} same_rip={d}{s} name={s}\n",
                    .{ entry.handle, entry.numeric_id, @tagName(entry.thread_type), @tagName(entry.state), stuck_duration, if (entry.suspension_reason.len != 0) entry.suspension_reason else "-", entry.rip, entry.quantum_remaining, entry.quantum, entry.suspend_same_rip_count, rip_stall_flag, entry.name },
                );
            }
        }
        std.debug.print(
            "scheduler:   counts: running={d} suspended={d} waiting={d} stuck={d} audit_entries={d}\n",
            .{ running_count, suspended_count, waiting_count, stuck_count, self.switchAuditCount() },
        );

        // Dump switch audit trail
        self.dumpSwitchAudit();
        std.debug.print("scheduler: HANG DIAGNOSTIC END\n", .{});
    }

    /// Print the switch audit trail
    pub fn dumpSwitchAudit(self: *ThreadRegistry) void {
        const count = self.switchAuditCount();
        if (count == 0) {
            std.debug.print("scheduler:   switch audit: (empty)\n", .{});
            return;
        }
        std.debug.print("scheduler:   switch audit (newest to oldest):\n", .{});
        var printed: usize = 0;
        var idx = if (self.switch_audit_index > 0) self.switch_audit_index - 1 else SwitchAuditCapacity - 1;
        while (printed < count) {
            const entry = &self.switch_audit[idx];
            if (entry.active) {
                std.debug.print(
                    "scheduler:     [{d}] step={d} from=0x{x} to=0x{x} rip=0x{x} reason={s}\n",
                    .{ printed, entry.step, entry.from_handle, entry.to_handle, entry.rip, @as([]const u8, @as([*:0]u8, &entry.reason)) },
                );
            }
            printed += 1;
            idx = if (idx > 0) idx - 1 else SwitchAuditCapacity - 1;
        }
    }

    /// Return number of active audit entries
    fn switchAuditCount(self: *ThreadRegistry) usize {
        var count: usize = 0;
        for (&self.switch_audit) |*entry| {
            if (entry.active) count += 1;
        }
        return count;
    }

    /// Snapshot scheduler state to log
    pub fn dumpState(self: *ThreadRegistry, label: []const u8) void {
        std.debug.print(
            "scheduler: STATE DUMP ({s}): active={d} created={d} completed={d} suspended_queue={d}\n",
            .{ label, self.active_count, self.total_created, self.total_completed, self.suspended_count },
        );
        for (&self.entries) |*entry| {
            if (!entry.active) continue;
            const same_rip_mark = if (entry.suspend_same_rip_count >= 3) "[RIP-STALL]" else "";
            std.debug.print(
                "scheduler:   handle=0x{x} id={d} type={s} state={s} mode={s} pri={s} " ++ "rip=0x{x} quantum={d}/{d} exec={d} susp={d} yields={d} runs={d} " ++ "stall={d} same_rip={d} qinst={d} total_ins={d} {s} name={s}\n",
                .{
                    entry.handle,
                    entry.numeric_id,
                    @tagName(entry.thread_type),
                    @tagName(entry.state),
                    @tagName(entry.scheduling_mode),
                    @tagName(entry.priority),
                    entry.rip,
                    entry.quantum_remaining,
                    entry.quantum,
                    entry.execution_steps,
                    entry.suspension_count,
                    entry.yield_count,
                    entry.continuous_run_steps,
                    entry.stall_count,
                    entry.suspend_same_rip_count,
                    entry.quantum_instructions,
                    entry.total_instructions,
                    same_rip_mark,
                    threadName(&entry.name),
                },
            );
            // Show top switch-out reasons
            for (&entry.switch_reasons) |*sr| {
                if (sr.count > 0) {
                    std.debug.print(
                        "scheduler:     reason: {s} x{d}\n",
                        .{ @as([]const u8, @as([*:0]u8, &sr.reason)), sr.count },
                    );
                }
            }
        }
    }

    /// Diagnose stuck threads
    pub fn diagnoseStuckThreads(self: *ThreadRegistry, current_step: u64, threshold: u64) void {
        for (&self.entries) |*entry| {
            if (!entry.active) continue;
            if (entry.state == .running or entry.state == .completed) continue;

            const stuck_duration = if (entry.state == .suspended or entry.state == .waiting)
                current_step -| entry.state_since_step
            else
                0;

            if (stuck_duration > threshold) {
                std.debug.print(
                    "scheduler: stuck thread: handle=0x{x} numeric_id={d} state={s} stuck_for={d} steps reason={s}\n",
                    .{ entry.handle, entry.numeric_id, @tagName(entry.state), stuck_duration, entry.suspension_reason },
                );
            }
        }
    }
};

test "thread registry basic operations" {
    var registry = ThreadRegistry{};
    registry.init();

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

    const entry = registry.createThread(context, 0x10000, 512 * 1024) catch unreachable;
    try std.testing.expect(entry.active);
    try std.testing.expectEqual(@as(usize, 1), registry.active_count);

    registry.markStarted(entry.handle, 2000);
    try std.testing.expectEqual(@as(thread_interceptor.ThreadLifecycleState, .running), entry.state);

    const suspended = registry.suspendThread(entry.handle, "test_yield", 0x1004, 3000);
    try std.testing.expect(suspended);
    try std.testing.expectEqual(@as(thread_interceptor.ThreadLifecycleState, .suspended), entry.state);

    const next = registry.nextSuspended();
    try std.testing.expectEqual(entry.handle, next.?);
}

test "thread registry quantum management" {
    var registry = ThreadRegistry{};
    registry.init();

    const context = thread_interceptor.ThreadCreationContext{
        .level = .pthread,
        .thread_type = .worker,
        .start_routine = 0x1000,
        .argument = 0,
        .stack_size = 512 * 1024,
        .creator_handle = 0x7fff2000,
        .creation_step = 1000,
    };

    const entry = registry.createThread(context, 0x10000, 512 * 1024) catch unreachable;
    try std.testing.expectEqual(@as(u64, 10000), entry.quantum);

    const has_quantum = registry.consumeQuantum(entry.handle, 5000);
    try std.testing.expect(has_quantum);
    try std.testing.expectEqual(@as(u64, 5000), entry.quantum_remaining);

    const exhausted = registry.consumeQuantum(entry.handle, 6000);
    try std.testing.expect(!exhausted);
    try std.testing.expectEqual(@as(u64, 0), entry.quantum_remaining);

    registry.resetQuantum(entry.handle);
    try std.testing.expectEqual(@as(u64, 10000), entry.quantum_remaining);
}

test "execution accounting uses elapsed steps rather than RIP distance" {
    var registry = ThreadRegistry{};
    registry.init();
    const context = thread_interceptor.ThreadCreationContext{
        .level = .pthread,
        .thread_type = .worker,
        .start_routine = 0x1000,
        .argument = 0,
        .stack_size = 4096,
        .creator_handle = 1,
        .creation_step = 10,
    };
    const entry = try registry.createThread(context, 0x2000, 4096);
    registry.markStarted(entry.handle, 100);
    registry.accountExecution(entry.handle, 350, 0x1000);
    try std.testing.expectEqual(@as(u64, 250), entry.execution_steps);
    try std.testing.expectEqual(@as(u64, 250), entry.continuous_run_steps);
    try std.testing.expectEqual(@as(u64, 9750), entry.quantum_remaining);

    try std.testing.expect(registry.suspendThread(entry.handle, "loop", 0x1000, 400));
    try std.testing.expectEqual(@as(u64, 300), entry.quantum_instructions);
    try std.testing.expect(registry.resumeThread(entry.handle, 1000));
    registry.accountExecution(entry.handle, 1010, 0x8000);
    try std.testing.expectEqual(@as(u64, 10), entry.continuous_run_steps);
}

test "waiting state clears only through a valid wait transition" {
    var registry = ThreadRegistry{};
    registry.init();
    const context = thread_interceptor.ThreadCreationContext{
        .level = .pthread,
        .thread_type = .worker,
        .start_routine = 0x1000,
        .argument = 0,
        .stack_size = 4096,
        .creator_handle = 1,
        .creation_step = 0,
    };
    const entry = try registry.createThread(context, 0x2000, 4096);
    registry.markStarted(entry.handle, 0);
    try std.testing.expect(!registry.clearWaiting(entry.handle));
    try std.testing.expect(registry.setWaitingCondvar(entry.handle, 0x44, 0x55, 0x1004, 10));
    try std.testing.expect(registry.clearWaiting(entry.handle));
    try std.testing.expect(registry.resumeThread(entry.handle, 20));
    try std.testing.expectEqual(@as(u64, 0), entry.waiting_condvar);
}
