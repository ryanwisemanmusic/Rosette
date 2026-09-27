//! Stable host-thread lifecycle primitives for schedulers which execute guest
//! contexts outside the cooperative owner. This module does not itself make
//! a guest executor thread-safe: callers must provide isolated CPU state,
//! ordered shared-memory operations, and stop workers before mutating shared
//! mappings or destroying their address space.

const std = @import("std");

/// Synchronous host-side synchronization for worker lifecycle records. These
/// APIs intentionally avoid `std.Io` so the executor can park without an Io
/// context. Conditions use an epoch so a signal between unlock and polling is
/// not lost; parked workers yield until their lifecycle predicate changes.
const HostMutex = struct {
    state: std.atomic.Mutex = .unlocked,

    pub fn lock(self: *HostMutex) void {
        while (!self.state.tryLock()) std.atomic.spinLoopHint();
    }

    pub fn unlock(self: *HostMutex) void {
        self.state.unlock();
    }
};

const HostCondition = struct {
    epoch: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn wait(self: *HostCondition, mutex: *HostMutex) void {
        const observed = self.epoch.load(.acquire);
        mutex.unlock();
        while (self.epoch.load(.acquire) == observed) {
            std.Thread.yield() catch std.atomic.spinLoopHint();
        }
        mutex.lock();
    }

    pub fn signal(self: *HostCondition) void {
        _ = self.epoch.fetchAdd(1, .release);
    }

    pub fn broadcast(self: *HostCondition) void {
        self.signal();
    }
};

pub const ExecutionMode = enum {
    cooperative,
    native,
    hybrid,
};

pub const NativeThreadConfig = struct {
    enabled: bool = false,
    max_native_threads: usize = 8,
    stack_size: usize = 8 * 1024 * 1024,
    pin_ui_thread: bool = true,
    use_native_blocking: bool = true,
    affinity_policy: AffinityPolicy = .balanced,
};

pub const AffinityPolicy = enum {
    balanced,
    pinned,
    os_default,
};

pub const ThreadState = enum {
    created,
    running,
    suspended,
    blocked,
    completed,
    terminated,
};

pub const ThreadError = enum {
    none,
    access_violation,
    illegal_instruction,
    stack_overflow,
    timeout,
    cancellation,
};

pub const CpuContext = struct {
    regs: [16]u64 = [_]u64{0} ** 16,
    rip: u64 = 0,
    rsp: u64 = 0,
    rbp: u64 = 0,
    rflags: u64 = 0,
    cs: u64 = 0,
    ds: u64 = 0,
    es: u64 = 0,
    fs: u64 = 0,
    gs: u64 = 0,
    ss: u64 = 0,
    fpu_state: [512]u8 = [_]u8{0} ** 512,

    /// These are value copies for the current emulator callback ABI. They
    /// intentionally do not capture or restore the host CPU's registers.
    pub fn save(_: *CpuContext) void {}
    pub fn restore(_: *const CpuContext) void {}
};

/// A value-only observation of a worker. Returning the mutable context record
/// itself would let a monitor race `reapThread` and retain a pointer to freed
/// executor state.
pub const NativeThreadSnapshot = struct {
    guest_handle: u64,
    mode: ExecutionMode,
    state: ThreadState,
    /// A running callback exclusively owns its CPU context. Monitors receive
    /// it only after the callback has published a quiescent lifecycle state.
    cpu_context: ?CpuContext,
    result: ?u64,
    thread_error: ?ThreadError,
    cancel_requested: bool,
};

pub const NativeThreadContext = struct {
    guest_handle: u64 = 0,
    host_thread: ?std.Thread = null,
    mode: ExecutionMode = .cooperative,
    thread_fn: ?*const fn (context: *NativeThreadContext) void = null,
    thread_arg: ?*anyopaque = null,
    /// Architectural state is owned by the stable context record. The API
    /// accepts a seed value from the creating scheduler, but a worker never
    /// keeps a pointer into that scheduler's stack or mutable owner state.
    cpu_context: CpuContext = .{},
    guest_memory: ?[]u8 = null,
    code_cache: ?*anyopaque = null,
    state: ThreadState = .created,
    result: u64 = 0,
    thread_error: ?ThreadError = null,
    cancel_requested: bool = false,
    /// True while the callback owns `cpu_context`, `result` and
    /// `thread_error`, even if its lifecycle state was changed to terminated
    /// by an external cancellation request.
    callback_active: bool = false,
    joined: bool = false,
    mutex: HostMutex = .{},
    join_mutex: HostMutex = .{},
    condvar: HostCondition = .{},
    backend: ?*NativeThreadBackend = null,
    /// Protected by `NativeThreadBackend.mutex`; pins prevent API calls that
    /// already found this stable record from racing its final destruction.
    api_references: usize = 0,
    reaping: bool = false,

    /// Called at bounded points by a worker's execution loop. Suspension,
    /// guest waits, and cancellation are cooperative: no host thread is
    /// asynchronously interrupted while it holds guest or runtime state.
    pub fn checkpoint(self: *NativeThreadContext) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (self.state == .suspended or self.state == .blocked) {
            if (self.cancel_requested) return false;
            self.condvar.wait(&self.mutex);
        }
        return self.state == .running and !self.cancel_requested;
    }

    pub fn shouldStop(self: *NativeThreadContext) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.cancel_requested or self.state == .terminated;
    }
};

/// A bounded owner of stable per-thread records. Records are individually
/// allocated so a hash-table resize can never invalidate the pointer passed
/// to a running host thread. The backend lock protects the registry and
/// accounting; each context lock protects its lifecycle and handoff state.
pub const NativeThreadBackend = struct {
    config: NativeThreadConfig = .{},
    thread_contexts: std.AutoHashMap(u64, *NativeThreadContext),
    mutex: HostMutex = .{},
    maintenance_mutex: HostMutex = .{},
    references_changed: HostCondition = .{},
    active_native_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    allocator: std.mem.Allocator,
    guest_memory: ?[]u8 = null,
    code_cache: ?*anyopaque = null,
    code_cache_mutex: HostMutex = .{},
    total_native_threads: u64 = 0,
    total_cooperative_threads: u64 = 0,
    context_switches: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    shutting_down: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: NativeThreadConfig) NativeThreadBackend {
        return .{
            .config = config,
            .thread_contexts = std.AutoHashMap(u64, *NativeThreadContext).init(allocator),
            .allocator = allocator,
        };
    }

    /// Stops and joins every host worker before releasing its stable record.
    /// The address space and code cache must outlive this call.
    pub fn deinit(self: *NativeThreadBackend) void {
        self.maintenance_mutex.lock();
        defer self.maintenance_mutex.unlock();
        self.mutex.lock();
        self.shutting_down = true;
        var iter = self.thread_contexts.iterator();
        while (iter.next()) |entry| {
            self.mutex.unlock();
            self.stopAndJoin(entry.value_ptr.*);
            self.mutex.lock();
        }
        while (self.hasApiReferences()) self.references_changed.wait(&self.mutex);
        var destroy_iter = self.thread_contexts.valueIterator();
        while (destroy_iter.next()) |context| self.allocator.destroy(context.*);
        self.thread_contexts.deinit();
        self.mutex.unlock();
    }

    pub fn setGuestMemory(self: *NativeThreadBackend, memory: []u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.guest_memory = memory;
    }

    pub fn setCodeCache(self: *NativeThreadBackend, cache: *anyopaque) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.code_cache = cache;
    }

    pub fn createNativeThread(
        self: *NativeThreadBackend,
        guest_handle: u64,
        thread_fn: *const fn (context: *NativeThreadContext) void,
        thread_arg: ?*anyopaque,
        cpu_context: *CpuContext,
        execution_mode: ExecutionMode,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.shutting_down) return error.BackendShuttingDown;
        if (self.thread_contexts.contains(guest_handle)) return error.ThreadAlreadyExists;
        if (execution_mode != .cooperative and !self.config.enabled) return error.NativeThreadsDisabled;
        if (execution_mode != .cooperative and
            self.active_native_count.load(.acquire) >= self.config.max_native_threads)
        {
            return error.ThreadLimitExceeded;
        }

        const context = try self.allocator.create(NativeThreadContext);
        context.* = .{
            .guest_handle = guest_handle,
            .mode = execution_mode,
            .thread_fn = thread_fn,
            .thread_arg = thread_arg,
            .cpu_context = cpu_context.*,
            .guest_memory = self.guest_memory,
            .code_cache = self.code_cache,
            .backend = self,
        };
        errdefer self.allocator.destroy(context);
        try self.thread_contexts.put(guest_handle, context);
        errdefer _ = self.thread_contexts.remove(guest_handle);

        if (execution_mode == .cooperative) {
            self.total_cooperative_threads +|= 1;
            return;
        }

        _ = self.active_native_count.fetchAdd(1, .acq_rel);
        errdefer _ = self.active_native_count.fetchSub(1, .acq_rel);
        context.host_thread = try std.Thread.spawn(
            .{ .stack_size = self.config.stack_size },
            nativeThreadWrapper,
            .{context},
        );
        self.total_native_threads +|= 1;
    }

    /// Starts a native worker. A cooperative worker must be run by its owning
    /// scheduler through `runCooperativeThread` instead.
    pub fn startThread(self: *NativeThreadBackend, guest_handle: u64) !void {
        const context = self.pinContext(guest_handle) orelse return error.ThreadNotFound;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        if (context.mode == .cooperative) return error.NotNativeThread;
        if (context.state != .created) return error.InvalidState;
        context.state = .running;
        context.condvar.signal();
    }

    /// Requests cooperative cancellation and joins exactly once. Callbacks
    /// that do not call `checkpoint` or inspect `shouldStop` are allowed to
    /// finish naturally; the record remains alive until the join completes.
    pub fn stopThread(self: *NativeThreadBackend, guest_handle: u64) void {
        const context = self.pinContext(guest_handle) orelse return;
        defer self.unpinContext(context);
        self.stopAndJoin(context);
    }

    /// Release a finished guest handle so the guest can reuse its numeric
    /// identifier. The worker record stays stable through the join; only a
    /// completed, terminated, or never-started context can be reaped.
    pub fn reapThread(self: *NativeThreadBackend, guest_handle: u64) !void {
        self.maintenance_mutex.lock();
        defer self.maintenance_mutex.unlock();
        self.mutex.lock();
        if (self.shutting_down) {
            self.mutex.unlock();
            return error.BackendShuttingDown;
        }
        const context = self.thread_contexts.get(guest_handle) orelse {
            self.mutex.unlock();
            return error.ThreadNotFound;
        };
        if (context.reaping) {
            self.mutex.unlock();
            return error.ThreadStillActive;
        }
        context.reaping = true;
        self.mutex.unlock();

        self.mutex.lock();
        while (context.api_references != 0) self.references_changed.wait(&self.mutex);
        self.mutex.unlock();
        context.mutex.lock();
        const state = context.state;
        context.mutex.unlock();
        if (state == .running or state == .suspended or state == .blocked) {
            self.mutex.lock();
            context.reaping = false;
            self.mutex.unlock();
            return error.ThreadStillActive;
        }

        self.stopAndJoin(context);
        self.mutex.lock();
        _ = self.thread_contexts.remove(guest_handle);
        self.mutex.unlock();
        self.allocator.destroy(context);
    }

    pub fn suspendThread(self: *NativeThreadBackend, guest_handle: u64) !void {
        const context = self.pinContext(guest_handle) orelse return error.ThreadNotFound;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        if (context.mode == .cooperative) return error.NotNativeThread;
        if (context.state != .running) return error.InvalidState;
        context.state = .suspended;
        self.noteContextSwitch();
    }

    pub fn resumeThread(self: *NativeThreadBackend, guest_handle: u64) !void {
        const context = self.pinContext(guest_handle) orelse return error.ThreadNotFound;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        if (context.mode == .cooperative) return error.NotNativeThread;
        if (context.state != .suspended) return error.InvalidState;
        context.state = .running;
        context.condvar.signal();
        self.noteContextSwitch();
    }

    pub fn blockOnMutex(self: *NativeThreadBackend, guest_handle: u64, _: u64) !void {
        const context = self.pinContext(guest_handle) orelse return error.ThreadNotFound;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        if (context.mode == .cooperative) return error.NotNativeThread;
        if (context.state != .running) return error.InvalidState;
        context.state = .blocked;
        self.noteContextSwitch();
    }

    pub fn wakeFromMutex(self: *NativeThreadBackend, guest_handle: u64) !void {
        const context = self.pinContext(guest_handle) orelse return error.ThreadNotFound;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        if (context.mode == .cooperative) return error.NotNativeThread;
        if (context.state != .blocked) return error.InvalidState;
        context.state = .running;
        context.condvar.signal();
        self.noteContextSwitch();
    }

    /// Run one cooperative callback on the caller's host thread. It shares
    /// the same lifecycle contract as a native callback without spawning a
    /// second host thread.
    pub fn runCooperativeThread(self: *NativeThreadBackend, guest_handle: u64) !void {
        const context = self.pinContext(guest_handle) orelse return error.ThreadNotFound;
        defer self.unpinContext(context);
        context.mutex.lock();
        if (context.mode != .cooperative) {
            context.mutex.unlock();
            return error.NotCooperativeThread;
        }
        if (context.state != .created) {
            context.mutex.unlock();
            return error.InvalidState;
        }
        context.state = .running;
        context.callback_active = true;
        context.mutex.unlock();
        if (context.thread_fn) |thread_fn| thread_fn(context);
        context.mutex.lock();
        context.callback_active = false;
        if (context.state != .terminated) context.state = .completed;
        context.mutex.unlock();
    }

    pub fn getThreadContext(self: *NativeThreadBackend, guest_handle: u64) ?NativeThreadSnapshot {
        const context = self.pinContext(guest_handle) orelse return null;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        return .{
            .guest_handle = context.guest_handle,
            .mode = context.mode,
            .state = context.state,
            .cpu_context = if (context.callback_active) null else context.cpu_context,
            .result = if (context.callback_active) null else context.result,
            .thread_error = if (context.callback_active) null else context.thread_error,
            .cancel_requested = context.cancel_requested,
        };
    }

    pub fn getThreadState(self: *NativeThreadBackend, guest_handle: u64) ?ThreadState {
        const context = self.pinContext(guest_handle) orelse return null;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        return context.state;
    }

    /// This manager deliberately refuses mode changes while a worker is live.
    /// Reconstructing an emulator context during an arbitrary instruction is
    /// unsafe; callers should stop/join at a guest boundary, then create a
    /// replacement context from the saved architectural state.
    pub fn migrateThreadMode(self: *NativeThreadBackend, guest_handle: u64, _: ExecutionMode) !void {
        const context = self.pinContext(guest_handle) orelse return error.ThreadNotFound;
        defer self.unpinContext(context);
        context.mutex.lock();
        defer context.mutex.unlock();
        if (context.state == .running or context.state == .blocked or context.state == .suspended) {
            return error.ThreadMustBeQuiescent;
        }
        return error.RecreateContextRequired;
    }

    pub fn lockCodeCache(self: *NativeThreadBackend) void {
        self.code_cache_mutex.lock();
    }

    pub fn unlockCodeCache(self: *NativeThreadBackend) void {
        self.code_cache_mutex.unlock();
    }

    pub fn logSummary(self: *NativeThreadBackend) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.print(
            "scheduler: native thread backend: native={d} cooperative={d} active={d} switches={d}\n",
            .{
                self.total_native_threads,
                self.total_cooperative_threads,
                self.active_native_count.load(.acquire),
                self.context_switches.load(.acquire),
            },
        );
    }

    fn pinContext(self: *NativeThreadBackend, guest_handle: u64) ?*NativeThreadContext {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.shutting_down) return null;
        const context = self.thread_contexts.get(guest_handle) orelse return null;
        if (context.reaping) return null;
        context.api_references += 1;
        return context;
    }

    fn unpinContext(self: *NativeThreadBackend, context: *NativeThreadContext) void {
        self.mutex.lock();
        std.debug.assert(context.api_references != 0);
        context.api_references -= 1;
        if (context.api_references == 0) self.references_changed.broadcast();
        self.mutex.unlock();
    }

    fn hasApiReferences(self: *NativeThreadBackend) bool {
        var iter = self.thread_contexts.valueIterator();
        while (iter.next()) |context| {
            if (context.*.api_references != 0) return true;
        }
        return false;
    }

    fn stopAndJoin(self: *NativeThreadBackend, context: *NativeThreadContext) void {
        context.mutex.lock();
        context.cancel_requested = true;
        if (context.state != .completed) context.state = .terminated;
        context.condvar.broadcast();
        context.mutex.unlock();

        context.join_mutex.lock();
        defer context.join_mutex.unlock();
        if (context.host_thread) |*thread| {
            if (!context.joined) {
                context.joined = true;
                thread.join();
            }
            context.host_thread = null;
        }
        _ = self;
    }

    fn noteContextSwitch(self: *NativeThreadBackend) void {
        _ = self.context_switches.fetchAdd(1, .monotonic);
    }
};

fn nativeThreadWrapper(context: *NativeThreadContext) void {
    context.mutex.lock();
    while (context.state == .created or context.state == .suspended or context.state == .blocked) {
        context.condvar.wait(&context.mutex);
    }
    const should_run = context.state == .running and !context.cancel_requested;
    if (should_run) context.callback_active = true;
    context.mutex.unlock();

    if (should_run) {
        if (context.thread_fn) |thread_fn| thread_fn(context);
    }

    context.mutex.lock();
    context.callback_active = false;
    if (context.state != .terminated) context.state = .completed;
    context.mutex.unlock();
    if (context.backend) |backend| {
        _ = backend.active_native_count.fetchSub(1, .acq_rel);
    }
}

test "native worker owns a stable context until one successful join" {
    const allocator = std.testing.allocator;
    var backend = NativeThreadBackend.init(allocator, .{ .enabled = true, .max_native_threads = 2 });
    defer backend.deinit();

    var cpu = CpuContext{ .rip = 0x1234 };
    var completed = std.atomic.Value(u32).init(0);
    const Worker = struct {
        completed: *std.atomic.Value(u32),

        fn run(context: *NativeThreadContext) void {
            const state: *@This() = @ptrCast(@alignCast(context.thread_arg.?));
            while (context.checkpoint()) {
                _ = state.completed.fetchAdd(1, .monotonic);
                if (context.shouldStop()) break;
            }
        }
    };
    var worker = Worker{ .completed = &completed };
    try backend.createNativeThread(0x10, Worker.run, &worker, &cpu, .native);
    const context = backend.getThreadContext(0x10) orelse return error.TestUnexpectedResult;
    cpu.rip = 0x5678;
    try std.testing.expectEqual(@as(u64, 0x1234), context.cpu_context.?.rip);
    try backend.startThread(0x10);
    while (completed.load(.acquire) == 0) std.atomic.spinLoopHint();
    const running_snapshot = backend.getThreadContext(0x10) orelse return error.TestUnexpectedResult;
    try std.testing.expect(running_snapshot.cpu_context == null);
    try std.testing.expectError(error.ThreadStillActive, backend.reapThread(0x10));
    backend.stopThread(0x10);
    const stopped = backend.getThreadContext(0x10) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 0x10), stopped.guest_handle);
    const state = backend.getThreadState(0x10) orelse return error.TestUnexpectedResult;
    try std.testing.expect(state == .terminated or state == .completed);
    try std.testing.expectEqual(@as(usize, 0), backend.active_native_count.load(.acquire));

    const ReapRequest = struct {
        backend: *NativeThreadBackend,
        done: *std.atomic.Value(bool),
        succeeded: *std.atomic.Value(bool),

        fn run(request: *@This()) void {
            request.backend.reapThread(0x10) catch {
                request.done.store(true, .release);
                return;
            };
            request.succeeded.store(true, .release);
            request.done.store(true, .release);
        }
    };
    var done = std.atomic.Value(bool).init(false);
    var succeeded = std.atomic.Value(bool).init(false);
    var request = ReapRequest{ .backend = &backend, .done = &done, .succeeded = &succeeded };
    const pinned = backend.pinContext(0x10) orelse return error.TestUnexpectedResult;
    var reaper = try std.Thread.spawn(.{}, ReapRequest.run, .{&request});
    while (true) {
        backend.mutex.lock();
        const reaping = pinned.reaping;
        backend.mutex.unlock();
        if (reaping) break;
        std.atomic.spinLoopHint();
    }
    backend.unpinContext(pinned);
    reaper.join();
    try std.testing.expect(done.load(.acquire));
    try std.testing.expect(succeeded.load(.acquire));
    try std.testing.expect(backend.getThreadContext(0x10) == null);
}

test "native backend rejects disabled and duplicate workers before spawning" {
    const allocator = std.testing.allocator;
    var disabled = NativeThreadBackend.init(allocator, .{});
    defer disabled.deinit();
    var cpu = CpuContext{};
    const noop = struct {
        fn run(_: *NativeThreadContext) void {}
    }.run;
    try std.testing.expectError(error.NativeThreadsDisabled, disabled.createNativeThread(1, noop, null, &cpu, .native));

    var enabled = NativeThreadBackend.init(allocator, .{ .enabled = true });
    defer enabled.deinit();
    try enabled.createNativeThread(1, noop, null, &cpu, .native);
    try std.testing.expectError(error.ThreadAlreadyExists, enabled.createNativeThread(1, noop, null, &cpu, .native));
    enabled.startThread(1) catch unreachable;
    enabled.stopThread(1);
    try enabled.reapThread(1);
    try enabled.createNativeThread(1, noop, null, &cpu, .native);
}
