const std = @import("std");
const thread_interceptor = @import("thread_interceptor.zig");

/// Thread registry entry
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
    owned_mutexes: [8]u64 = [_]u64{0} ** 8,
    
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
    
    /// Whether this entry is active
    active: bool = false,
};

/// Thread registry for tracking all threads
pub const ThreadRegistry = struct {
    const MAX_THREADS = 256;
    const MAX_SUSPENDED = 64;
    
    /// Thread entries
    entries: [MAX_THREADS]ThreadEntry = [_]ThreadEntry{.{}} ** MAX_THREADS,
    
    /// Number of active threads
    active_count: usize = 0,
    
    /// Next handle to allocate
    next_handle: u64 = 0x7FFF_2000,
    
    /// Next numeric ID to allocate
    next_numeric_id: u64 = 2,
    
    /// Suspended thread queue (FIFO)
    suspended_queue: [MAX_SUSPENDED]u64 = [_]u64{0} ** MAX_SUSPENDED,
    
    /// Suspended queue head
    suspended_head: usize = 0,
    
    /// Suspended queue tail
    suspended_tail: usize = 0,
    
    /// Statistics
    total_created: u64 = 0,
    total_completed: u64 = 0,
    total_suspended: u64 = 0,
    total_resumed: u64 = 0,
    total_yields: u64 = 0,
    
    /// Initialize the thread registry
    pub fn init(self: *ThreadRegistry) void {
        self.* = .{};
        self.next_handle = 0x7FFF_2000;
        self.next_numeric_id = 2;
    }
    
    /// Allocate a new thread handle
    pub fn allocateHandle(self: *ThreadRegistry) u64 {
        const handle = self.next_handle;
        self.next_handle += 0x10;
        return handle;
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
                .quantum = self.defaultQuantumForType(context.thread_type),
                .quantum_remaining = self.defaultQuantumForType(context.thread_type),
                .creation_context = context,
            };
            
            // Set thread name from symbol if available
            if (context.start_symbol.len > 0) {
                const len = @min(context.start_symbol.len, entry.name.len - 1);
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
            entry.rip = entry.start_routine;
        }
    }
    
    /// Mark thread as completed
    pub fn markCompleted(self: *ThreadRegistry, handle: u64, completion_step: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        if (entry.state != .completed) {
            entry.state = .completed;
            entry.completion_step = completion_step;
            entry.execution_steps = completion_step - entry.start_step;
            self.active_count -= 1;
            self.total_completed +|= 1;
            
            std.debug.print(
                "scheduler: thread completed: handle=0x{x} numeric_id={d} steps={d}\n",
                .{ entry.handle, entry.numeric_id, entry.execution_steps },
            );
        }
    }
    
    /// Suspend a thread
    pub fn suspendThread(self: *ThreadRegistry, handle: u64, reason: []const u8, rip: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        if (entry.state != .running) return false;
        
        entry.state = .suspended;
        entry.suspension_count +|= 1;
        entry.suspension_reason = reason;
        entry.rip = rip;
        
        // Add to suspended queue
        const queue_pos = self.suspended_tail;
        self.suspended_queue[queue_pos] = handle;
        self.suspended_tail = (self.suspended_tail + 1) % MAX_SUSPENDED;
        
        self.total_suspended +|= 1;
        
        std.debug.print(
            "scheduler: thread suspended: handle=0x{x} numeric_id={d} reason={s} rip=0x{x} suspended_count={d}\n",
            .{ entry.handle, entry.numeric_id, reason, rip, entry.suspension_count },
        );
        
        return true;
    }
    
    /// Resume a suspended thread
    pub fn resumeThread(self: *ThreadRegistry, handle: u64) bool {
        const entry = self.findByHandle(handle) orelse return false;
        if (entry.state != .suspended) return false;
        
        entry.state = .running;
        entry.resume_count +|= 1;
        entry.quantum_remaining = entry.quantum; // Reset quantum on resume
        
        self.total_resumed +|= 1;
        
        std.debug.print(
            "scheduler: thread resumed: handle=0x{x} numeric_id={d} rip=0x{x} resume_count={d}\n",
            .{ entry.handle, entry.numeric_id, entry.rip, entry.resume_count },
        );
        
        return true;
    }
    
    /// Get next thread to resume from suspended queue (FIFO)
    pub fn nextSuspended(self: *ThreadRegistry) ?u64 {
        if (self.suspended_head == self.suspended_tail) return null;
        
        const handle = self.suspended_queue[self.suspended_head];
        self.suspended_head = (self.suspended_head + 1) % MAX_SUSPENDED;
        
        return handle;
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
    pub fn setWaitingCondvar(self: *ThreadRegistry, handle: u64, condvar: u64, mutex: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        entry.state = .waiting;
        entry.waiting_condvar = condvar;
        entry.waiting_mutex = mutex;
    }
    
    /// Clear waiting state
    pub fn clearWaiting(self: *ThreadRegistry, handle: u64) void {
        const entry = self.findByHandle(handle) orelse return;
        if (entry.state == .waiting) {
            entry.state = .running;
        }
        entry.waiting_condvar = 0;
        entry.waiting_mutex = 0;
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
        const completed = self.countByState(.completed);
        
        std.debug.print(
            "scheduler: thread registry: active={d} total_created={d} completed={d} running={d} suspended={d} waiting={d} suspended_queue={d}\n",
            .{ self.active_count, self.total_created, self.total_completed, running, suspended, waiting, ((self.suspended_tail + MAX_SUSPENDED - self.suspended_head) % MAX_SUSPENDED) },
        );
        
        std.debug.print(
            "scheduler: thread statistics: suspended={d} resumed={d} yields={d}\n",
            .{ self.total_suspended, self.total_resumed, self.total_yields },
        );
    }
    
    /// Diagnose stuck threads
    pub fn diagnoseStuckThreads(self: *ThreadRegistry, current_step: u64) void {
        for (&self.entries) |*entry| {
            if (!entry.active) continue;
            if (entry.state == .running or entry.state == .completed) continue;
            
            const stuck_duration = if (entry.state == .suspended or entry.state == .waiting)
                current_step -| entry.creation_step
            else
                0;
            
            if (stuck_duration > 1_000_000) {
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
    
    const suspended = registry.suspendThread(entry.handle, "test_yield", 0x1004);
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
