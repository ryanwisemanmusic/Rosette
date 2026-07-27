const std = @import("std");
const scheduler = @import("scheduler");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const CURRENT_THREAD_HANDLE: u64 = 0x7FFF_1000;
const SYNTHETIC_THREAD_BASE: u64 = 0x7FFF_2000;
const MAX_ATTRIBUTES = 32;
const MAX_THREADS = 64;
const MAX_MUTEXES = 128;
const MAX_CONDVARS = 64;
const ETIMEDOUT: u64 = 60;

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

/// Decision made when the cooperative scheduler considers restoring a saved
/// guest context. A runnable context has no synthetic return value: all guest
/// registers, including RAX, must be restored exactly as saved. Only a wait
/// that actually completes is allowed to replace RAX with its POSIX result.
pub const CooperativeResume = struct {
    rax_override: ?u64 = null,
    cancel_deadline_sequence: u64 = 0,

    pub fn restoredRax(self: CooperativeResume, saved_rax: u64) u64 {
        return self.rax_override orelse saved_rax;
    }
};

pub const ThreadState = enum {
    created,
    runnable,
    running,
    sleeping_until_deadline,
    sleeping_indefinitely,
    waiting_mutex,
    waiting_condvar,
    waiting_semaphore,
    waiting_event,
    waiting_futex_address,
    waiting_join,
    terminated,
    cancelled,
};

pub const WaitResult = enum {
    pending,
    signaled,
    timed_out,
    cancelled,
};

const Attribute = struct {
    active: bool = false,
    address: u64 = 0,
    stack_size: u64 = 0,
};

pub const DeferredThread = struct {
    handle: u64,
    start_routine: u64,
    argument: u64,
    stack_size: u64,
    state: ThreadState,
};

pub const ThreadSnapshot = struct {
    slot: usize,
    handle: u64,
    numeric_id: u64,
    start_routine: u64,
    stack_size: u64,
    state: ThreadState,
    started: bool,
    joined: bool,
    cancelled: bool,
    blocked_since_step: u64,
    blocked_reason: []const u8,
    waiting_condvar: u64,
    waiting_mutex: u64,
    wait_generation: u64,
    notified_generation: u64,
    wait_deadline_nanoseconds: u64,
    deadline_sequence: u64,
    wait_address: u64,
    wait_result: WaitResult,
    spurious_wake_pending: bool,
    priority: i32,
};

const CondVar = struct {
    active: bool = false,
    address: u64 = 0,
    waiters: u32 = 0,
    generation: u64 = 0,
    notifications: u64 = 0,
};

const Thread = struct {
    active: bool = false,
    handle: u64 = 0,
    start_routine: u64 = 0,
    argument: u64 = 0,
    stack_size: u64 = 0,
    joined: bool = false,
    cancelled: bool = false,
    started: bool = false,
    state: ThreadState = .runnable,
    blocked_since_step: u64 = 0,
    blocked_reason: []const u8 = "",
    waiting_condvar: u64 = 0,
    waiting_mutex: u64 = 0,
    wait_generation: u64 = 0,
    notified_generation: u64 = 0,
    timed_wait: bool = false,
    wait_deadline_nanoseconds: u64 = 0,
    deadline_sequence: u64 = 0,
    wait_address: u64 = 0,
    wait_result: WaitResult = .pending,
    spurious_wake_pending: bool = false,
    last_spurious_condvar: u64 = 0,
    last_spurious_generation: u64 = 0,
    priority: i32 = 0,
    numeric_id: u64 = 0,
};

const system_clock_epoch_nanoseconds: u64 = 1_719_000_000 * 1_000_000_000;
const cpp_infinite_time_point: u64 = @intCast(std.math.maxInt(i64));

const Mutex = struct {
    active: bool = false,
    address: u64 = 0,
    depth: u32 = 0,
    owner_thread: u64 = 0,
    contention_count: u64 = 0,
};

pub const Runtime = struct {
    attributes: [MAX_ATTRIBUTES]Attribute = [_]Attribute{.{}} ** MAX_ATTRIBUTES,
    threads: [MAX_THREADS]Thread = [_]Thread{.{}} ** MAX_THREADS,
    mutexes: [MAX_MUTEXES]Mutex = [_]Mutex{.{}} ** MAX_MUTEXES,
    condvars: [MAX_CONDVARS]CondVar = [_]CondVar{.{}} ** MAX_CONDVARS,
    created_threads: u64 = 0,
    deferred_threads: u64 = 0,
    joined_threads: u64 = 0,
    cancelled_threads: u64 = 0,
    mutex_locks: u64 = 0,
    mutex_unlocks: u64 = 0,
    mutex_contentions: u64 = 0,
    collapsed_waits: u64 = 0,
    condition_notifications: u64 = 0,
    condition_broadcasts: u64 = 0,
    timed_waits_started: u64 = 0,
    timed_waits_signaled: u64 = 0,
    timed_waits_expired: u64 = 0,
    timed_sleeps_started: u64 = 0,
    timed_sleeps_completed: u64 = 0,
    indefinite_sleeps_started: u64 = 0,
    cpp_indefinite_waits_started: u64 = 0,
    quiescence_spurious_wakes: u64 = 0,
    tls_sets: u64 = 0,
    scheduled_threads: u64 = 0,
    completed_threads: u64 = 0,
    blocked_threads: u64 = 0,
    scheduler_yields: u64 = 0,
    thread_id_queries: u64 = 0,
    next_numeric_thread_id: u64 = 2,
    main_thread_handle: u64 = CURRENT_THREAD_HANDLE,
    last_diagnostic_step: u64 = 0,
    last_reported_expected_parks: u32 = 0,
    event_log: ?*scheduler.SchedulerEventLog = null,

    pub fn attachEventLog(self: *Runtime, event_log: *scheduler.SchedulerEventLog) void {
        self.event_log = event_log;
    }

    pub fn dispatch(self: *Runtime, state: anytype, name: []const u8) ?Outcome {
        if (std.mem.eql(u8, name, "_pthread_self")) return .{ .handled = self.currentThreadHandle(state) };
        if (std.mem.eql(u8, name, "_pthread_equal")) return .{ .handled = @intFromBool(state.regs.rdi == state.regs.rsi) };
        if (std.mem.eql(u8, name, "_pthread_threadid_np")) return .{ .handled = self.threadId(state) };
        if (std.mem.eql(u8, name, "_pthread_attr_init")) return .{ .handled = self.attributeInit(state) };
        if (std.mem.eql(u8, name, "_pthread_attr_destroy")) return .{ .handled = self.attributeDestroy(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_attr_setstacksize")) return .{ .handled = self.attributeSetStackSize(state.regs.rdi, state.regs.rsi) };
        if (std.mem.eql(u8, name, "_pthread_create")) return .{ .handled = self.create(state) };
        if (std.mem.eql(u8, name, "_pthread_join")) return .{ .handled = self.join(state) };
        if (std.mem.eql(u8, name, "_pthread_cancel")) return .{ .handled = self.cancel(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_setname_np") or
            std.mem.eql(u8, name, "_pthread_setschedparam")) return .{ .handled = 0 };
        if (std.mem.eql(u8, name, "_pthread_yield_np") or
            std.mem.eql(u8, name, "_sched_yield"))
        {
            self.scheduler_yields +|= 1;
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_pthread_getname_np")) return .{ .handled = self.getName(state) };
        if (std.mem.eql(u8, name, "_pthread_getschedparam")) return .{ .handled = self.getSchedule(state) };
        if (std.mem.eql(u8, name, "_pthread_getspecific")) return .{ .handled = 0 };
        if (std.mem.eql(u8, name, "_pthread_setspecific")) {
            self.tls_sets +|= 1;
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_pthread_mutex_init")) return .{ .handled = self.mutexInit(state) };
        if (std.mem.eql(u8, name, "_pthread_mutex_destroy")) return .{ .handled = self.mutexDestroy(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_mutex_lock")) return .{ .handled = self.mutexLockForThread(state.regs.rdi, self.currentThreadHandle(state)) };
        if (std.mem.eql(u8, name, "_pthread_mutex_trylock")) return .{ .handled = self.mutexTryLockForThread(state.regs.rdi, self.currentThreadHandle(state)) };
        if (std.mem.eql(u8, name, "_pthread_mutex_unlock")) return .{ .handled = self.mutexUnlockForThread(state.regs.rdi, self.currentThreadHandle(state)) };
        if (std.mem.eql(u8, name, "_pthread_cond_init")) return .{ .handled = self.condvarInitialize(state) };
        if (std.mem.eql(u8, name, "_pthread_cond_destroy")) return .{ .handled = self.condvarDestroy(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_cond_signal")) {
            self.condition_notifications +|= 1;
            self.condvarSignal(state.regs.rdi);
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_pthread_cond_broadcast")) {
            self.condition_notifications +|= 1;
            self.condition_broadcasts +|= 1;
            self.condvarBroadcast(state.regs.rdi);
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_pthread_cond_wait")) {
            return .{ .handled = self.condvarWait(state, false) };
        }
        if (std.mem.eql(u8, name, "_pthread_cond_timedwait") or
            std.mem.eql(u8, name, "_pthread_cond_timedwait_relative_np"))
        {
            return .{ .handled = self.condvarWait(state, true) };
        }
        return null;
    }

    /// libc++ mutex and condition-variable functions are object operations,
    /// not no-op contracts. Keep them in the same ownership/wakeup model as
    /// their pthread primitives so a C++ Event::Set can wake another modeled
    /// guest thread waiting in condition_variable::__do_timed_wait.
    pub fn dispatchCppSynchronization(self: *Runtime, state: anytype, name: []const u8) ?Outcome {
        const owner = self.currentThreadHandle(state);
        if (std.mem.indexOf(u8, name, "condition_variable10notify_one") != null) {
            self.condition_notifications +|= 1;
            self.condvarSignal(state.regs.rdi);
            return .handled_void;
        }
        if (std.mem.indexOf(u8, name, "condition_variable10notify_all") != null) {
            self.condition_notifications +|= 1;
            self.condition_broadcasts +|= 1;
            self.condvarBroadcast(state.regs.rdi);
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "__ZNSt3__119__shared_mutex_baseC1Ev")) {
            // __shared_mutex_base constructor is a no-op in single-threaded execution
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "__ZNSt3__15mutex4lockEv")) {
            return .{ .handled = self.mutexLockForThread(state.regs.rdi, owner) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__15mutex6unlockEv")) {
            return .{ .handled = self.mutexUnlockForThread(state.regs.rdi, owner) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__15mutex8try_lockEv")) {
            return .{ .handled = @intFromBool(self.mutexTryLockForThread(state.regs.rdi, owner) == 0) };
        }
        return null;
    }

    pub fn logSummary(self: *const Runtime) void {
        if (self.created_threads == 0 and self.mutex_locks == 0 and self.collapsed_waits == 0 and self.tls_sets == 0) return;
        machoCapturePrint(
            "macho-processor: pthread runtime: created={d} deferred={d} scheduled={d} completed={d} joined={d} cancelled={d} blocked={d} mutex(lock/unlock/contention)={d}/{d}/{d} cond(notify/broadcast/waits/quiescence_wakes)={d}/{d}/{d}/{d} timed_waits(started/signaled/expired)={d}/{d}/{d} indefinite_wait_sentinels={d} sleeps(timed_started/timed_completed/indefinite)={d}/{d}/{d} yield_hints={d} tls_sets={d} thread_id_queries={d}\n",
            .{
                self.created_threads,
                self.deferred_threads,
                self.scheduled_threads,
                self.completed_threads,
                self.joined_threads,
                self.cancelled_threads,
                self.blocked_threads,
                self.mutex_locks,
                self.mutex_unlocks,
                self.mutex_contentions,
                self.condition_notifications,
                self.condition_broadcasts,
                self.collapsed_waits,
                self.quiescence_spurious_wakes,
                self.timed_waits_started,
                self.timed_waits_signaled,
                self.timed_waits_expired,
                self.cpp_indefinite_waits_started,
                self.timed_sleeps_started,
                self.timed_sleeps_completed,
                self.indefinite_sleeps_started,
                self.scheduler_yields,
                self.tls_sets,
                self.thread_id_queries,
            },
        );
    }

    pub fn diagnoseStuck(self: *Runtime, current_step: u64, current_rip: u64, current_nanoseconds: u64) void {
        _ = current_rip;
        if (current_step -| self.last_diagnostic_step < 5_000_000) return;
        var actionable_blocked_count: u32 = 0;
        var expected_parked_count: u32 = 0;
        var oldest_expected_park_steps: u64 = 0;
        for (&self.threads) |*thread| {
            if (!thread.active or thread.state == .runnable or thread.state == .running or
                thread.state == .terminated or thread.state == .cancelled)
            {
                continue;
            }
            const finite_deadline_pending = thread.wait_deadline_nanoseconds != 0 and
                thread.wait_deadline_nanoseconds > current_nanoseconds;
            const expected_dependency_wait = switch (thread.state) {
                .sleeping_indefinitely,
                .waiting_condvar,
                .waiting_semaphore,
                .waiting_event,
                .waiting_futex_address,
                .waiting_join,
                => thread.wait_deadline_nanoseconds == 0,
                .sleeping_until_deadline => finite_deadline_pending,
                else => false,
            };
            if (expected_dependency_wait) {
                expected_parked_count += 1;
                oldest_expected_park_steps = @max(oldest_expected_park_steps, current_step -| thread.blocked_since_step);
                continue;
            }
            actionable_blocked_count += 1;
            const blocked_steps = current_step -| thread.blocked_since_step;
            if (blocked_steps > 2_000_000) {
                const deadline_overdue_ns = if (thread.wait_deadline_nanoseconds != 0)
                    current_nanoseconds -| thread.wait_deadline_nanoseconds
                else
                    0;
                machoCapturePrint(
                    "macho-processor: actionable thread wait: handle=0x{x} state={s} blocked_for={d} steps deadline_overdue_ns={d} reason={s}\n",
                    .{ thread.handle, @tagName(thread.state), blocked_steps, deadline_overdue_ns, thread.blocked_reason },
                );
            }
        }
        if (actionable_blocked_count > 0) {
            const active = self.activeCount();
            machoCapturePrint(
                "macho-processor: scheduler health: modeled_pthreads_runnable={d} actionable_waits={d} expected_parked={d} total_created={d}\n",
                .{ active, actionable_blocked_count, expected_parked_count, self.created_threads },
            );
        }
        if (expected_parked_count != self.last_reported_expected_parks) {
            machoCapturePrint(
                "macho-processor: scheduler: expected parks={d} oldest_age={d} steps; these are pending finite deadlines or dormant dependency waits, not deadlock evidence\n",
                .{ expected_parked_count, oldest_expected_park_steps },
            );
            self.last_reported_expected_parks = expected_parked_count;
        }
        self.last_diagnostic_step = current_step;
    }

    pub fn activeCount(self: *const Runtime) u64 {
        var count: u64 = 0;
        for (&self.threads) |*thread| {
            if (thread.active and (thread.state == .runnable or thread.state == .running)) count += 1;
        }
        return count;
    }

    pub fn noteSchedulerYield(self: *Runtime) void {
        self.scheduler_yields +|= 1;
    }

    pub fn snapshotAt(self: *const Runtime, slot: usize) ?ThreadSnapshot {
        if (slot >= self.threads.len) return null;
        const thread = self.threads[slot];
        if (!thread.active) return null;
        return .{
            .slot = slot,
            .handle = thread.handle,
            .numeric_id = thread.numeric_id,
            .start_routine = thread.start_routine,
            .stack_size = thread.stack_size,
            .state = thread.state,
            .started = thread.started,
            .joined = thread.joined,
            .cancelled = thread.cancelled,
            .blocked_since_step = thread.blocked_since_step,
            .blocked_reason = thread.blocked_reason,
            .waiting_condvar = thread.waiting_condvar,
            .waiting_mutex = thread.waiting_mutex,
            .wait_generation = thread.wait_generation,
            .notified_generation = thread.notified_generation,
            .wait_deadline_nanoseconds = thread.wait_deadline_nanoseconds,
            .deadline_sequence = thread.deadline_sequence,
            .wait_address = thread.wait_address,
            .wait_result = thread.wait_result,
            .spurious_wake_pending = thread.spurious_wake_pending,
            .priority = thread.priority,
        };
    }

    pub fn snapshotForHandle(self: *const Runtime, handle: u64) ?ThreadSnapshot {
        for (0..self.threads.len) |slot| {
            const snapshot = self.snapshotAt(slot) orelse continue;
            if (snapshot.handle == handle) return snapshot;
        }
        return null;
    }

    pub fn tableCapacity(self: *const Runtime) usize {
        return self.threads.len;
    }

    pub fn takeNewestDeferred(self: *Runtime) ?DeferredThread {
        for (&self.threads) |*thread| {
            if (!thread.active or thread.started or thread.cancelled or thread.state != .runnable) continue;
            thread.started = true;
            thread.state = .runnable;
            self.deferred_threads -|= 1;
            self.scheduled_threads +|= 1;
            return .{
                .handle = thread.handle,
                .start_routine = thread.start_routine,
                .argument = thread.argument,
                .stack_size = thread.stack_size,
                .state = .runnable,
            };
        }
        return null;
    }

    pub fn markCompleted(self: *Runtime, handle: u64) void {
        const thread = self.threadForHandle(handle) orelse return;
        if (thread.state == .terminated) return;
        thread.state = .terminated;
        self.completed_threads +|= 1;
        self.emit(.{ .kind = .thread_terminated, .thread = handle, .reason = "guest_thread_returned" });
    }

    pub fn markRunning(self: *Runtime, handle: u64) void {
        const thread = self.threadForHandle(handle) orelse return;
        if (thread.state == .runnable or thread.state == .created) thread.state = .running;
    }

    pub fn markContextSuspended(self: *Runtime, handle: u64) void {
        const thread = self.threadForHandle(handle) orelse return;
        if (thread.state == .running) thread.state = .runnable;
    }

    pub fn currentThreadHandle(self: *const Runtime, state: anytype) u64 {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "currentCooperativeThreadHandle")) {
            return state.currentCooperativeThreadHandle();
        }
        if (comptime @hasField(State, "active_guest_thread")) {
            if (state.active_guest_thread != 0) return state.active_guest_thread;
        }
        return self.main_thread_handle;
    }

    pub fn mutexWouldBlock(self: *Runtime, address: u64, owner: u64) bool {
        const mutex = self.mutexForAddress(address, false) orelse return false;
        return mutex.depth != 0 and mutex.owner_thread != 0 and mutex.owner_thread != owner;
    }

    /// Models the atomic release performed by pthread_cond_wait before the
    /// caller blocks.  The Mach-O interpreter uses this at the import
    /// boundary, rather than returning from the wait while the caller still
    /// owns its mutex.
    pub fn beginCooperativeCondvarWait(self: *Runtime, state: anytype, timed_wait: bool) bool {
        const handle = self.currentThreadHandle(state);
        const cond_addr = state.regs.rdi;
        const mutex_addr = state.regs.rsi;
        const deadline = if (timed_wait) pthreadDeadlineNanoseconds(state) else 0;
        return self.beginCooperativeWait(state, handle, cond_addr, mutex_addr, deadline);
    }

    pub fn beginCooperativeCppCondvarWait(self: *Runtime, state: anytype, timed_wait: bool) bool {
        const handle = self.currentThreadHandle(state);
        const cond_addr = state.regs.rdi;
        const unique_lock = state.regs.rsi;
        const mutex_addr = readGuestU64(state, unique_lock) orelse return false;
        if (mutex_addr == 0) return false;
        const deadline = if (timed_wait) cppDeadlineNanoseconds(state) else 0;
        if (timed_wait and state.regs.rdx == cpp_infinite_time_point) {
            self.cpp_indefinite_waits_started +|= 1;
            if (self.cpp_indefinite_waits_started <= 8) {
                machoCapturePrint(
                    "macho-processor: libc++ condition wait classified indefinite: thread=0x{x} cond=0x{x} raw_time_point=INT64_MAX; no finite guest timer scheduled\n",
                    .{ handle, cond_addr },
                );
            }
        }
        return self.beginCooperativeWait(state, handle, cond_addr, mutex_addr, deadline);
    }

    fn beginCooperativeWait(
        self: *Runtime,
        state: anytype,
        handle: u64,
        cond_addr: u64,
        mutex_addr: u64,
        deadline_nanoseconds: u64,
    ) bool {
        const cv = self.condvarInit(cond_addr) orelse return false;
        const thread = self.threadForHandle(handle);

        // Registration and mutex release form one scheduler transaction. No
        // guest instruction or signal dispatch can interleave these writes.
        // Recording the observed generation before releasing the mutex makes
        // a subsequent notification visible to exactly this wait instance.
        if (thread) |waiting_thread| {
            if (waiting_thread.state != .waiting_condvar) {
                cv.waiters +|= 1;
                self.blocked_threads +|= 1;
            }
            waiting_thread.state = .waiting_condvar;
            waiting_thread.blocked_since_step = schedulerStep(state);
            waiting_thread.blocked_reason = "pthread_cond_wait";
            waiting_thread.waiting_condvar = cond_addr;
            waiting_thread.waiting_mutex = mutex_addr;
            waiting_thread.wait_generation = cv.generation;
            waiting_thread.notified_generation = 0;
            waiting_thread.timed_wait = deadline_nanoseconds != 0;
            waiting_thread.wait_deadline_nanoseconds = deadline_nanoseconds;
            waiting_thread.wait_address = cond_addr;
            waiting_thread.wait_result = .pending;
            waiting_thread.spurious_wake_pending = false;
        }
        const State = @TypeOf(state.*);
        if (deadline_nanoseconds != 0) {
            if (comptime @hasDecl(State, "scheduleGuestWaitDeadline")) {
                if (thread) |waiting_thread| {
                    waiting_thread.deadline_sequence = state.scheduleGuestWaitDeadline(handle, cond_addr, cv.generation, deadline_nanoseconds);
                }
            }
        }

        // POSIX requires the mutex to be released as part of entering the
        // wait. Ignore an untracked mutex here: libc++ mutexes may be first
        // observed through their condition-variable path.
        _ = self.mutexUnlockForThread(mutex_addr, handle);
        self.collapsed_waits +|= 1;
        if (deadline_nanoseconds != 0) self.timed_waits_started +|= 1;
        self.emit(.{
            .kind = .thread_blocked,
            .step = schedulerStep(state),
            .thread = handle,
            .object = cond_addr,
            .generation = cv.generation,
            .deadline_ns = deadline_nanoseconds,
            .reason = "pthread_cond_wait",
        });
        if (self.collapsed_waits <= 8 or self.collapsed_waits % 1000 == 0) {
            machoCapturePrint(
                "macho-processor: cooperative condvar wait #{d} cond=0x{x} released_mutex=0x{x} thread=0x{x} waiters={d} timed={} now_ns={d} deadline_ns={d}\n",
                .{ self.collapsed_waits, cond_addr, mutex_addr, handle, cv.waiters, deadline_nanoseconds != 0, monotonicNow(state), deadline_nanoseconds },
            );
        }
        return true;
    }

    /// Reacquires a mutex before a condition-waiting worker returns to guest
    /// code. `null` means an ordinary wait remains blocked; a result carries
    /// the POSIX return value that must be restored in RAX on resumption.
    pub fn resumeCooperativeWait(self: *Runtime, handle: u64, now_nanoseconds: u64) ?u64 {
        const thread = self.threadForHandle(handle) orelse return 0;
        if (thread.state != .waiting_condvar) {
            // Queue presence alone does not make a blocked/joining/completed
            // thread runnable. Only ordinary runnable contexts may re-enter
            // guest code without satisfying an additional dependency.
            return if (thread.state == .runnable) 0 else null;
        }
        const timed_wait = thread.timed_wait;
        const condvar = thread.waiting_condvar;
        var signaled = false;
        if (condvar != 0) {
            const cv = self.condvarForAddress(condvar) orelse return null;
            signaled = thread.spurious_wake_pending or
                (thread.notified_generation > thread.wait_generation and
                    thread.notified_generation <= cv.generation);
        }
        if (!signaled) {
            if (!timed_wait) return null;
            if (now_nanoseconds < thread.wait_deadline_nanoseconds) return null;
        }
        return self.completeCooperativeWait(handle, if (signaled) 0 else ETIMEDOUT);
    }

    /// Scheduler-facing form of `resumeCooperativeWait`. Unlike the legacy
    /// return-value-only API, this distinguishes "ordinary runnable context"
    /// from "completed wait returning zero" so a round-robin handoff cannot
    /// accidentally zero the guest's live RAX register.
    pub fn resumeCooperativeContext(self: *Runtime, handle: u64, now_nanoseconds: u64) ?CooperativeResume {
        const thread = self.threadForHandle(handle) orelse return .{};
        if (thread.state == .waiting_condvar) {
            const deadline_sequence = thread.deadline_sequence;
            const result = self.resumeCooperativeWait(handle, now_nanoseconds) orelse return null;
            return .{ .rax_override = result, .cancel_deadline_sequence = deadline_sequence };
        }
        if (thread.state == .sleeping_until_deadline) {
            if (now_nanoseconds < thread.wait_deadline_nanoseconds) return null;
            const deadline_sequence = thread.deadline_sequence;
            thread.state = .runnable;
            thread.blocked_reason = "";
            thread.wait_deadline_nanoseconds = 0;
            thread.deadline_sequence = 0;
            thread.wait_result = .signaled;
            self.blocked_threads -|= 1;
            self.timed_sleeps_completed +|= 1;
            self.emit(.{ .kind = .thread_resumed, .thread = handle, .reason = "virtual_sleep_deadline" });
            return .{ .cancel_deadline_sequence = deadline_sequence };
        }
        if (thread.state == .sleeping_indefinitely) return null;
        return if (thread.state == .runnable) .{} else null;
    }

    fn completeCooperativeWait(self: *Runtime, handle: u64, result: u64) ?u64 {
        const thread = self.threadForHandle(handle) orelse return result;
        if (thread.state != .waiting_condvar) return result;
        const was_timed = thread.timed_wait;
        if (thread.waiting_mutex != 0 and self.mutexTryLockForThread(thread.waiting_mutex, handle) != 0) {
            return null;
        }
        if (thread.waiting_condvar != 0) {
            if (self.condvarForAddress(thread.waiting_condvar)) |cv| {
                cv.waiters -|= 1;
            }
        }
        thread.state = .runnable;
        thread.blocked_reason = "";
        thread.waiting_condvar = 0;
        thread.waiting_mutex = 0;
        thread.wait_generation = 0;
        thread.notified_generation = 0;
        thread.timed_wait = false;
        thread.wait_deadline_nanoseconds = 0;
        thread.deadline_sequence = 0;
        thread.wait_address = 0;
        thread.wait_result = if (result == ETIMEDOUT) .timed_out else .signaled;
        const spurious = thread.spurious_wake_pending;
        thread.spurious_wake_pending = false;
        self.blocked_threads -|= 1;
        if (was_timed) {
            if (result == ETIMEDOUT) {
                self.timed_waits_expired +|= 1;
            } else {
                self.timed_waits_signaled +|= 1;
            }
        }
        self.emit(.{
            .kind = if (result == ETIMEDOUT) .wait_timeout else .thread_resumed,
            .thread = handle,
            .reason = if (result == ETIMEDOUT) "condvar_deadline" else if (spurious) "quiescence_spurious_wake" else "condvar_notification",
        });
        return result;
    }

    /// Park a cooperative guest thread without making the host interpreter
    /// sleep. A finite request becomes runnable only after its virtual
    /// deadline. An indefinite request has no synthetic deadline and requires
    /// an explicit wake/cancellation event.
    pub fn beginCooperativeSleep(
        self: *Runtime,
        handle: u64,
        current_step: u64,
        deadline_nanoseconds: ?u64,
        deadline_sequence: u64,
    ) bool {
        const thread = self.threadForHandle(handle) orelse return false;
        if (thread.state == .sleeping_until_deadline or thread.state == .sleeping_indefinitely) return true;
        thread.state = if (deadline_nanoseconds != null) .sleeping_until_deadline else .sleeping_indefinitely;
        thread.blocked_since_step = current_step;
        thread.blocked_reason = if (deadline_nanoseconds != null) "virtual_sleep_deadline" else "virtual_sleep_indefinite";
        thread.wait_deadline_nanoseconds = deadline_nanoseconds orelse 0;
        thread.deadline_sequence = deadline_sequence;
        thread.wait_result = .pending;
        self.blocked_threads +|= 1;
        if (deadline_nanoseconds != null) {
            self.timed_sleeps_started +|= 1;
        } else {
            self.indefinite_sleeps_started +|= 1;
        }
        self.emit(.{
            .kind = .thread_blocked,
            .step = current_step,
            .thread = handle,
            .deadline_ns = deadline_nanoseconds orelse 0,
            .reason = thread.blocked_reason,
        });
        return true;
    }

    pub fn wakeSleepingThread(self: *Runtime, handle: u64, reason: []const u8) bool {
        const thread = self.threadForHandle(handle) orelse return false;
        if (thread.state != .sleeping_until_deadline and thread.state != .sleeping_indefinitely) return false;
        thread.state = .runnable;
        thread.blocked_reason = "";
        thread.wait_deadline_nanoseconds = 0;
        thread.deadline_sequence = 0;
        thread.wait_result = .signaled;
        self.blocked_threads -|= 1;
        self.emit(.{ .kind = .thread_resumed, .thread = handle, .reason = reason });
        return true;
    }

    /// POSIX condition waits may return spuriously. Use that latitude only
    /// when no modeled thread is runnable and no finite deadline can make
    /// progress. A condition generation is eligible at most once per thread;
    /// repeatedly leaving and re-entering the same predicate loop without a
    /// real notification must not become a synthetic busy loop.
    pub fn wakeOldestCondvarForQuiescence(self: *Runtime, preferred_handle: u64, current_step: u64) ?u64 {
        var selected: ?*Thread = null;
        for (&self.threads) |*thread| {
            if (!thread.active or thread.state != .waiting_condvar or thread.spurious_wake_pending) continue;
            if (thread.waiting_condvar == thread.last_spurious_condvar and
                thread.wait_generation == thread.last_spurious_generation) continue;
            if (thread.waiting_mutex != 0 and self.mutexWouldBlock(thread.waiting_mutex, thread.handle)) continue;
            if (thread.handle == preferred_handle) {
                selected = thread;
                break;
            }
            if (selected == null or thread.blocked_since_step < selected.?.blocked_since_step) selected = thread;
        }
        const thread = selected orelse return null;
        thread.spurious_wake_pending = true;
        thread.last_spurious_condvar = thread.waiting_condvar;
        thread.last_spurious_generation = thread.wait_generation;
        self.quiescence_spurious_wakes +|= 1;
        self.emit(.{
            .kind = .quiescence_recovery,
            .step = current_step,
            .thread = thread.handle,
            .object = thread.waiting_condvar,
            .generation = thread.wait_generation,
            .runnable = 1,
            .blocked = self.blocked_threads,
            .reason = "global_quiescence_posix_spurious_wake",
        });
        return thread.handle;
    }

    pub fn earliestWaitDeadline(self: *const Runtime) ?u64 {
        var earliest: ?u64 = null;
        for (self.threads) |thread| {
            if (!thread.active) continue;
            const finite_condvar = thread.state == .waiting_condvar and thread.timed_wait;
            const finite_sleep = thread.state == .sleeping_until_deadline;
            if (!finite_condvar and !finite_sleep) continue;
            if (thread.wait_deadline_nanoseconds == 0) continue;
            if (earliest == null or thread.wait_deadline_nanoseconds < earliest.?) {
                earliest = thread.wait_deadline_nanoseconds;
            }
        }
        return earliest;
    }

    fn attributeInit(self: *Runtime, state: anytype) u64 {
        if (initializeOpaque(state, state.regs.rdi, 64) != 0) return 22;
        for (&self.attributes) |*attribute| {
            if (attribute.active) continue;
            attribute.* = .{ .active = true, .address = state.regs.rdi };
            return 0;
        }
        return 12;
    }

    fn attributeDestroy(self: *Runtime, address: u64) u64 {
        for (&self.attributes) |*attribute| {
            if (!attribute.active or attribute.address != address) continue;
            attribute.* = .{};
            return 0;
        }
        return 0;
    }

    fn attributeSetStackSize(self: *Runtime, address: u64, stack_size: u64) u64 {
        for (&self.attributes) |*attribute| {
            if (!attribute.active or attribute.address != address) continue;
            attribute.stack_size = stack_size;
            return 0;
        }
        return 22;
    }

    fn create(self: *Runtime, state: anytype) u64 {
        if (state.guestMemory(state.regs.rdi, 8) == null) return 14;
        for (&self.threads, 0..) |*thread, index| {
            if (thread.active) continue;
            const handle = SYNTHETIC_THREAD_BASE + @as(u64, @intCast(index)) * 0x10;
            thread.* = .{
                .active = true,
                .handle = handle,
                .numeric_id = self.allocateNumericThreadId(),
                .start_routine = state.regs.rdx,
                .argument = state.regs.rcx,
                .stack_size = self.stackSize(state.regs.rsi),
                .state = .runnable,
                .blocked_since_step = schedulerStep(state),
            };
            state.write64(state.regs.rdi, handle);
            self.created_threads +|= 1;
            self.deferred_threads +|= 1;
            self.emit(.{ .kind = .thread_created, .step = schedulerStep(state), .thread = handle, .reason = "pthread_create" });
            machoCapturePrint(
                "macho-processor: pthread runtime: deferred guest thread #{d} handle=0x{x} numeric_id={d} start=0x{x} arg=0x{x} stack={d}\n",
                .{ self.created_threads, handle, thread.numeric_id, thread.start_routine, thread.argument, thread.stack_size },
            );
            return 0;
        }
        return 11;
    }

    fn join(self: *Runtime, state: anytype) u64 {
        const thread = self.threadForHandle(state.regs.rdi) orelse return 3;
        if (thread.state != .terminated) {
            thread.state = .waiting_join;
            thread.blocked_since_step = schedulerStep(state);
            thread.blocked_reason = "pthread_join waiting";
            self.blocked_threads +|= 1;
        }
        thread.joined = true;
        self.joined_threads +|= 1;
        if (state.regs.rsi != 0 and state.guestMemory(state.regs.rsi, 8) != null) state.write64(state.regs.rsi, 0);
        return 0;
    }

    fn cancel(self: *Runtime, handle: u64) u64 {
        const thread = self.threadForHandle(handle) orelse return 3;
        thread.cancelled = true;
        thread.state = .cancelled;
        self.cancelled_threads +|= 1;
        return 0;
    }

    fn mutexInit(self: *Runtime, state: anytype) u64 {
        if (initializeOpaque(state, state.regs.rdi, 64) != 0) return 22;
        _ = self.mutexForAddress(state.regs.rdi, true) orelse return 12;
        return 0;
    }

    fn mutexDestroy(self: *Runtime, address: u64) u64 {
        if (self.mutexForAddress(address, false)) |mutex| mutex.* = .{};
        return 0;
    }

    fn mutexLock(self: *Runtime, address: u64) u64 {
        return self.mutexLockForThread(address, CURRENT_THREAD_HANDLE);
    }

    fn mutexLockForThread(self: *Runtime, address: u64, owner: u64) u64 {
        const mutex = self.mutexForAddress(address, true) orelse return 12;
        if (mutex.depth > 0 and mutex.owner_thread != 0 and mutex.owner_thread != owner) {
            mutex.contention_count +|= 1;
            self.mutex_contentions +|= 1;
            if (mutex.contention_count <= 8 or mutex.contention_count % 100 == 0) {
                machoCapturePrint(
                    "macho-processor: pthread mutex contention #{d} mutex=0x{x} depth={d} owner=0x{x}\n",
                    .{ mutex.contention_count, address, mutex.depth, mutex.owner_thread },
                );
            }
            // The Mach-O cooperative scheduler retries the import after it
            // schedules the current owner. Do not transfer ownership here.
            return 0;
        }
        mutex.depth +|= 1;
        mutex.owner_thread = owner;
        self.mutex_locks +|= 1;
        return 0;
    }

    fn mutexUnlock(self: *Runtime, address: u64) u64 {
        return self.mutexUnlockForThread(address, CURRENT_THREAD_HANDLE);
    }

    fn mutexUnlockForThread(self: *Runtime, address: u64, owner: u64) u64 {
        const mutex = self.mutexForAddress(address, false) orelse return 22;
        if (mutex.depth != 0 and mutex.owner_thread != owner) return 1;
        if (mutex.depth != 0) {
            mutex.depth -= 1;
            if (mutex.depth == 0) mutex.owner_thread = 0;
        }
        self.mutex_unlocks +|= 1;
        return 0;
    }

    fn mutexTryLock(self: *Runtime, address: u64) u64 {
        return self.mutexTryLockForThread(address, CURRENT_THREAD_HANDLE);
    }

    fn mutexTryLockForThread(self: *Runtime, address: u64, owner: u64) u64 {
        const mutex = self.mutexForAddress(address, true) orelse return 12;
        if (mutex.depth != 0) {
            mutex.contention_count +|= 1;
            self.mutex_contentions +|= 1;
            return 16; // EBUSY
        }
        mutex.depth = 1;
        mutex.owner_thread = owner;
        self.mutex_locks +|= 1;
        return 0;
    }

    pub fn cppMutexTryLock(self: *Runtime, address: u64) bool {
        return self.mutexTryLock(address) == 0;
    }

    pub fn cppMutexTryLockForThread(self: *Runtime, address: u64, owner: u64) bool {
        return self.mutexTryLockForThread(address, owner) == 0;
    }

    fn condvarInit(self: *Runtime, address: u64) ?*CondVar {
        for (&self.condvars) |*cv| {
            if (cv.active and cv.address == address) return cv;
        }
        for (&self.condvars) |*cv| {
            if (cv.active) continue;
            cv.* = .{ .active = true, .address = address };
            return cv;
        }
        return null;
    }

    fn condvarInitialize(self: *Runtime, state: anytype) u64 {
        if (initializeOpaque(state, state.regs.rdi, 48) != 0) return 22;
        _ = self.condvarInit(state.regs.rdi) orelse return 12;
        return 0;
    }

    fn condvarDestroy(self: *Runtime, address: u64) u64 {
        const cv = self.condvarForAddress(address) orelse return 0;
        if (cv.waiters != 0) return 16;
        cv.* = .{};
        // Reusing a destroyed condition object's address starts a new
        // synchronization lifetime, so old spurious-wake history must not
        // suppress the new object.
        for (&self.threads) |*thread| {
            if (thread.last_spurious_condvar != address) continue;
            thread.last_spurious_condvar = 0;
            thread.last_spurious_generation = 0;
        }
        return 0;
    }

    fn condvarSignal(self: *Runtime, address: u64) void {
        if (self.condvarForAddress(address)) |cv| {
            cv.generation +|= 1;
            cv.notifications +|= 1;
            var selected: ?*Thread = null;
            for (&self.threads) |*thread| {
                if (!thread.active or thread.state != .waiting_condvar or thread.waiting_condvar != address) continue;
                if (thread.notified_generation != 0) continue;
                if (selected == null or thread.blocked_since_step < selected.?.blocked_since_step) selected = thread;
            }
            if (selected) |thread| {
                thread.notified_generation = cv.generation;
                self.emit(.{ .kind = .condvar_signal, .thread = thread.handle, .object = address, .generation = cv.generation, .reason = "notify_one" });
                if (cv.notifications <= 8 or cv.notifications % 1000 == 0) {
                    machoCapturePrint(
                        "macho-processor: condvar signal: cond=0x{x} waiter=0x{x} waiters={d} generation={d} total_notifications={d}\n",
                        .{ address, thread.handle, cv.waiters, cv.generation, cv.notifications },
                    );
                }
            }
        }
    }

    fn condvarBroadcast(self: *Runtime, address: u64) void {
        if (self.condvarForAddress(address)) |cv| {
            cv.generation +|= 1;
            var woke: u32 = 0;
            for (&self.threads) |*thread| {
                if (!thread.active or thread.state != .waiting_condvar or thread.waiting_condvar != address) continue;
                if (thread.notified_generation != 0) continue;
                thread.notified_generation = cv.generation;
                woke +|= 1;
            }
            cv.notifications +|= woke;
            self.emit(.{ .kind = .condvar_broadcast, .object = address, .generation = cv.generation, .runnable = woke, .reason = "notify_all" });
            if (woke > 0 and (cv.notifications <= 8 or cv.notifications % 1000 == 0)) {
                machoCapturePrint(
                    "macho-processor: condvar broadcast: cond=0x{x} targeted_waiters={d} generation={d} total_notifications={d}\n",
                    .{ address, woke, cv.generation, cv.notifications },
                );
            }
        }
    }

    fn condvarWait(self: *Runtime, state: anytype, timed_wait: bool) u64 {
        if (!self.beginCooperativeCondvarWait(state, timed_wait)) return 12;
        // A non-cooperative caller cannot yield to another guest worker, so
        // collapse its wait only after restoring the mutex invariant.
        return self.resumeCooperativeWait(self.currentThreadHandle(state), monotonicNow(state)) orelse blk: {
            // There is no scheduler in this direct-call path. Preserve the
            // mutex invariant and model a spurious wake instead of leaving a
            // hostless waiter permanently armed.
            break :blk self.completeCooperativeWait(self.currentThreadHandle(state), 0) orelse 0;
        };
    }

    fn emit(self: *Runtime, event: scheduler.SchedulerEvent) void {
        if (self.event_log) |logger| logger.emit(event);
    }

    fn threadId(self: *Runtime, state: anytype) u64 {
        if (state.regs.rsi == 0 or state.guestMemory(state.regs.rsi, 8) == null) return 22;
        const handle = if (state.regs.rdi == 0) self.currentThreadHandle(state) else state.regs.rdi;
        const numeric_id = self.numericThreadId(handle);
        state.write64(state.regs.rsi, numeric_id);
        self.thread_id_queries +|= 1;
        if (self.thread_id_queries <= 16 or self.thread_id_queries % 256 == 0) {
            machoCapturePrint(
                "macho-processor: pthread thread id query #{d}: handle=0x{x} -> numeric_id={d}\n",
                .{ self.thread_id_queries, handle, numeric_id },
            );
        }
        return 0;
    }

    fn allocateNumericThreadId(self: *Runtime) u64 {
        const result = self.next_numeric_thread_id;
        self.next_numeric_thread_id +|= 1;
        return result;
    }

    fn numericThreadId(self: *Runtime, handle: u64) u64 {
        if (handle == 0 or handle == CURRENT_THREAD_HANDLE) return 1;
        for (&self.threads) |*thread| {
            if (thread.active and thread.handle == handle) {
                if (thread.numeric_id == 0) thread.numeric_id = self.allocateNumericThreadId();
                return thread.numeric_id;
            }
        }
        if (handle >= SYNTHETIC_THREAD_BASE and handle < SYNTHETIC_THREAD_BASE + 0x10000) {
            return 2 + ((handle - SYNTHETIC_THREAD_BASE) / 0x10);
        }
        return handle;
    }

    fn getName(self: *Runtime, state: anytype) u64 {
        _ = self;
        if (state.regs.rdx == 0) return 22;
        const storage = state.guestMemory(state.regs.rsi, state.regs.rdx) orelse return 14;
        const name = "rosette-guest";
        const length = @min(name.len, storage.len - 1);
        @memcpy(storage[0..length], name[0..length]);
        storage[length] = 0;
        return 0;
    }

    fn getSchedule(self: *Runtime, state: anytype) u64 {
        _ = self;
        if (state.regs.rsi != 0 and state.guestMemory(state.regs.rsi, 4) != null) state.write32(state.regs.rsi, 0);
        if (state.regs.rdx != 0 and state.guestMemory(state.regs.rdx, 8) != null) state.write64(state.regs.rdx, 0);
        return 0;
    }

    fn stackSize(self: *const Runtime, attribute_address: u64) u64 {
        if (attribute_address == 0) return 0;
        for (self.attributes) |attribute| {
            if (attribute.active and attribute.address == attribute_address) return attribute.stack_size;
        }
        return 0;
    }

    fn threadForHandle(self: *Runtime, handle: u64) ?*Thread {
        for (&self.threads) |*thread| {
            if (thread.active and thread.handle == handle) return thread;
        }
        return null;
    }

    fn mutexForAddress(self: *Runtime, address: u64, create_if_missing: bool) ?*Mutex {
        for (&self.mutexes) |*mutex| {
            if (mutex.active and mutex.address == address) return mutex;
        }
        if (!create_if_missing) return null;
        for (&self.mutexes) |*mutex| {
            if (mutex.active) continue;
            mutex.* = .{ .active = true, .address = address };
            return mutex;
        }
        return null;
    }

    fn condvarForAddress(self: *Runtime, address: u64) ?*CondVar {
        for (&self.condvars) |*cv| {
            if (cv.active and cv.address == address) return cv;
        }
        return null;
    }

    pub fn profileThreadStates(
        self: *const Runtime,
        profiler: anytype,
        current_step: u64,
        current_nanoseconds: u64,
    ) void {
        var active_buf: [64]u8 = [_]u8{0} ** 64;
        var handle_buf: [64]u64 = [_]u64{0} ** 64;
        var state_buf: [64]u8 = [_]u8{0} ** 64;
        var blocked_buf: [64]u64 = [_]u64{0} ** 64;
        var cv_buf: [64]u64 = [_]u64{0} ** 64;
        var mutex_buf: [64]u64 = [_]u64{0} ** 64;
        var deadline_buf: [64]u64 = [_]u64{0} ** 64;
        for (&self.threads, 0..) |*t, i| {
            active_buf[i] = @intFromBool(t.active);
            handle_buf[i] = t.handle;
            state_buf[i] = @intFromEnum(t.state);
            blocked_buf[i] = t.blocked_since_step;
            cv_buf[i] = t.waiting_condvar;
            mutex_buf[i] = t.waiting_mutex;
            deadline_buf[i] = t.wait_deadline_nanoseconds;
        }
        profiler.checkAndNudge(
            &active_buf,
            &handle_buf,
            &state_buf,
            &blocked_buf,
            &cv_buf,
            &mutex_buf,
            &deadline_buf,
            current_step,
            current_nanoseconds,
        );
    }
};

fn initializeOpaque(state: anytype, address: u64, size: u64) u64 {
    const storage = state.guestMemory(address, size) orelse return 14;
    @memset(storage, 0);
    return 0;
}

fn schedulerStep(state: anytype) u64 {
    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "executed_steps")) return state.executed_steps;
    return 0;
}

fn monotonicNow(state: anytype) u64 {
    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "guest_time")) return state.guest_time.now();
    if (comptime @hasField(State, "monotonic_nanoseconds")) return state.monotonic_nanoseconds;
    return 0;
}

fn readGuestU64(state: anytype, address: u64) ?u64 {
    if (address == 0) return null;
    const State = @TypeOf(state.*);
    const bytes = if (comptime @hasDecl(State, "guestMemoryConst"))
        state.guestMemoryConst(address, 8)
    else
        state.guestMemory(address, 8);
    const data = bytes orelse return null;
    return std.mem.readInt(u64, data[0..8], .little);
}

fn cppDeadlineNanoseconds(state: anytype) u64 {
    const raw = state.regs.rdx;
    if (raw == 0) return monotonicNow(state);
    return normalizeCppDeadline(raw, monotonicNow(state), wallEpochNanoseconds(state));
}

fn pthreadDeadlineNanoseconds(state: anytype) u64 {
    const pointer = state.regs.rdx;
    if (pointer == 0) return monotonicNow(state);
    const State = @TypeOf(state.*);
    const bytes = if (comptime @hasDecl(State, "guestMemoryConst"))
        state.guestMemoryConst(pointer, 16)
    else
        state.guestMemory(pointer, 16);
    const data = bytes orelse return monotonicNow(state);
    const seconds = std.mem.readInt(i64, data[0..8], .little);
    const nanoseconds = std.mem.readInt(i64, data[8..16], .little);
    if (seconds < 0 or nanoseconds < 0 or nanoseconds >= 1_000_000_000) return monotonicNow(state);
    if (seconds == std.math.maxInt(i64)) return 0;
    const absolute = std.math.mul(u64, @intCast(seconds), 1_000_000_000) catch return 0;
    const deadline = std.math.add(u64, absolute, @intCast(nanoseconds)) catch return 0;
    return normalizeAbsoluteDeadline(deadline, monotonicNow(state), wallEpochNanoseconds(state));
}

fn wallEpochNanoseconds(state: anytype) u64 {
    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "guest_time")) return state.guest_time.wall_epoch_ns;
    return system_clock_epoch_nanoseconds;
}

/// libc++ represents `time_point::max()` as INT64_MAX. It is an indefinite
/// wait sentinel, not a wall-clock date. Keeping it out of the finite timer
/// queue prevents a single wait from jumping the monotonic clock by centuries.
fn normalizeCppDeadline(raw: u64, now: u64, wall_epoch: u64) u64 {
    if (raw == cpp_infinite_time_point or raw == std.math.maxInt(u64)) return 0;
    const signed: i64 = @bitCast(raw);
    if (signed <= 0) return now;
    return normalizeAbsoluteDeadline(raw, now, wall_epoch);
}

fn normalizeAbsoluteDeadline(raw: u64, now: u64, wall_epoch: u64) u64 {
    _ = now;
    if (raw >= wall_epoch) return raw - wall_epoch;
    return raw;
}

test "C++ maximum time point is an indefinite wait, not a finite deadline" {
    try std.testing.expectEqual(@as(u64, 0), normalizeCppDeadline(cpp_infinite_time_point, 1_000, system_clock_epoch_nanoseconds));
    try std.testing.expectEqual(@as(u64, 6_000), normalizeCppDeadline(system_clock_epoch_nanoseconds + 6_000, 1_000, system_clock_epoch_nanoseconds));
    try std.testing.expectEqual(@as(u64, 1_000), normalizeCppDeadline(@bitCast(@as(i64, -2)), 1_000, system_clock_epoch_nanoseconds));
}

test "pthread runtime records deferred guest threads" {
    const TestState = struct {
        memory: [256]u8 = [_]u8{0} ** 256,
        regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},

        fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address + length > self.memory.len) return null;
            return self.memory[@intCast(address)..@intCast(address + length)];
        }

        fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.memory[@intCast(address)..][0..8], value, .little);
        }

        fn write32(self: *@This(), address: u64, value: u32) void {
            std.mem.writeInt(u32, self.memory[@intCast(address)..][0..4], value, .little);
        }
    };

    var runtime = Runtime{};
    var state = TestState{};
    state.regs.rdi = 16;
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_pthread_attr_init").?.handled);
    state.regs.rsi = 4 * 1024 * 1024;
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_pthread_attr_setstacksize").?.handled);
    state.regs.rdi = 8;
    state.regs.rsi = 16;
    state.regs.rdx = 0x1234;
    state.regs.rcx = 0x5678;
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_pthread_create").?.handled);
    try std.testing.expectEqual(@as(u64, 1), runtime.deferred_threads);
    try std.testing.expectEqual(@as(u64, 4 * 1024 * 1024), runtime.threads[0].stack_size);
    const deferred = runtime.takeNewestDeferred().?;
    try std.testing.expectEqual(@as(u64, 0x1234), deferred.start_routine);
    try std.testing.expectEqual(@as(u64, 0x5678), deferred.argument);
    try std.testing.expectEqual(@as(u64, 0), runtime.deferred_threads);
    runtime.markCompleted(deferred.handle);
    try std.testing.expectEqual(@as(u64, 1), runtime.completed_threads);
}

test "pthread mutex contention tracking" {
    var runtime = Runtime{};
    const mutex_addr: u64 = 0x1000;
    var test_state = struct {
        regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},
        fn guestMemory(self: *@This(), _: u64, _: u64) ?[]u8 {
            _ = self;
            return null;
        }
        fn write64(self: *@This(), _: u64, _: u64) void {
            _ = self;
        }
        fn write32(self: *@This(), _: u64, _: u32) void {
            _ = self;
        }
    }{ .regs = .{ .rdi = mutex_addr } };
    _ = runtime.dispatch(&test_state, "_pthread_mutex_init");
    _ = runtime.mutexLockForThread(mutex_addr, CURRENT_THREAD_HANDLE);
    _ = runtime.mutexLockForThread(mutex_addr, SYNTHETIC_THREAD_BASE);
    try std.testing.expectEqual(@as(u64, 1), runtime.mutex_contentions);
    try std.testing.expectEqual(@as(u64, 1), runtime.mutex_locks);
}

test "pthread mutex try-lock reports busy and succeeds after unlock" {
    var runtime = Runtime{};
    const address: u64 = 0x2000;
    try std.testing.expect(runtime.cppMutexTryLock(address));
    try std.testing.expect(!runtime.cppMutexTryLock(address));
    try std.testing.expectEqual(@as(u64, 0), runtime.mutexUnlock(address));
    try std.testing.expect(runtime.cppMutexTryLock(address));
}

test "cooperative condition wait releases and reacquires its mutex" {
    const worker: u64 = SYNTHETIC_THREAD_BASE;
    const mutex: u64 = 0x3000;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true };
    _ = runtime.mutexLockForThread(mutex, worker);

    var state = struct {
        active_guest_thread: u64 = worker,
        regs: struct { rdi: u64 = 0x4000, rsi: u64 = mutex, rdx: u64 = 0, rcx: u64 = 0 } = .{},
        fn guestMemory(self: *@This(), _: u64, _: u64) ?[]u8 {
            _ = self;
            return null;
        }
        fn write64(self: *@This(), _: u64, _: u64) void {
            _ = self;
        }
        fn write32(self: *@This(), _: u64, _: u32) void {
            _ = self;
        }
    }{};

    try std.testing.expect(runtime.beginCooperativeCondvarWait(&state, false));
    try std.testing.expectEqual(@as(u64, 0), runtime.mutexes[0].depth);
    try std.testing.expectEqual(ThreadState.waiting_condvar, runtime.threads[0].state);
    try std.testing.expectEqual(@as(?u64, null), runtime.resumeCooperativeWait(worker, 0));
    runtime.condvarSignal(state.regs.rdi);
    try std.testing.expectEqual(@as(?u64, 0), runtime.resumeCooperativeWait(worker, 0));
    try std.testing.expectEqual(@as(u64, 1), runtime.mutexes[0].depth);
    try std.testing.expectEqual(worker, runtime.mutexes[0].owner_thread);
    try std.testing.expectEqual(ThreadState.runnable, runtime.threads[0].state);
}

test "cooperative timed wait returns ETIMEDOUT without a signal" {
    const worker: u64 = SYNTHETIC_THREAD_BASE;
    const mutex: u64 = 0x3000;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true };
    _ = runtime.mutexLockForThread(mutex, worker);

    var state = struct {
        active_guest_thread: u64 = worker,
        regs: struct { rdi: u64 = 0x4000, rsi: u64 = mutex, rdx: u64 = 0, rcx: u64 = 0 } = .{},
        fn guestMemory(self: *@This(), _: u64, _: u64) ?[]u8 {
            _ = self;
            return null;
        }
        fn write64(self: *@This(), _: u64, _: u64) void {
            _ = self;
        }
        fn write32(self: *@This(), _: u64, _: u32) void {
            _ = self;
        }
    }{};

    try std.testing.expect(runtime.beginCooperativeWait(&state, worker, state.regs.rdi, mutex, 5_000));
    try std.testing.expectEqual(@as(?u64, null), runtime.resumeCooperativeWait(worker, 4_999));
    try std.testing.expectEqual(@as(?u64, ETIMEDOUT), runtime.resumeCooperativeWait(worker, 5_000));
    try std.testing.expectEqual(ThreadState.runnable, runtime.threads[0].state);
    try std.testing.expectEqual(worker, runtime.mutexes[0].owner_thread);
}

test "condition signal targets one waiter and cannot wake a later generation" {
    const first = SYNTHETIC_THREAD_BASE;
    const second = SYNTHETIC_THREAD_BASE + 0x10;
    const condvar: u64 = 0x4000;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = first, .started = true };
    runtime.threads[1] = .{ .active = true, .handle = second, .started = true };

    const State = struct {
        active_guest_thread: u64,
        executed_steps: u64,
        regs: struct { rdi: u64 = condvar, rsi: u64, rdx: u64 = 0, rcx: u64 = 0 },
        fn guestMemory(self: *@This(), _: u64, _: u64) ?[]u8 {
            _ = self;
            return null;
        }
        fn write64(self: *@This(), _: u64, _: u64) void {
            _ = self;
        }
        fn write32(self: *@This(), _: u64, _: u32) void {
            _ = self;
        }
    };
    var first_state = State{ .active_guest_thread = first, .executed_steps = 1, .regs = .{ .rsi = 0x5000 } };
    var second_state = State{ .active_guest_thread = second, .executed_steps = 2, .regs = .{ .rsi = 0x6000 } };
    try std.testing.expect(runtime.beginCooperativeCondvarWait(&first_state, false));
    try std.testing.expect(runtime.beginCooperativeCondvarWait(&second_state, false));

    runtime.condvarSignal(condvar);
    try std.testing.expectEqual(@as(?u64, 0), runtime.resumeCooperativeWait(first, 0));
    try std.testing.expectEqual(@as(?u64, null), runtime.resumeCooperativeWait(second, 0));

    // Re-entering after the first signal observes generation 1 and must not
    // consume that already-delivered notification.
    first_state.executed_steps = 3;
    try std.testing.expect(runtime.beginCooperativeCondvarWait(&first_state, false));
    try std.testing.expectEqual(@as(?u64, null), runtime.resumeCooperativeWait(first, 0));
    runtime.condvarBroadcast(condvar);
    try std.testing.expectEqual(@as(?u64, 0), runtime.resumeCooperativeWait(second, 0));
    try std.testing.expectEqual(@as(?u64, 0), runtime.resumeCooperativeWait(first, 0));
}

test "condition destroy rejects live waiters" {
    var runtime = Runtime{};
    const cv = runtime.condvarInit(0x7000) orelse return error.TestUnexpectedResult;
    cv.waiters = 1;
    try std.testing.expectEqual(@as(u64, 16), runtime.condvarDestroy(0x7000));
    cv.waiters = 0;
    try std.testing.expectEqual(@as(u64, 0), runtime.condvarDestroy(0x7000));
    try std.testing.expect(runtime.condvarForAddress(0x7000) == null);
}

test "libc++ timed condition wait remains blocked until notify all" {
    const worker: u64 = SYNTHETIC_THREAD_BASE;
    const condvar: u64 = 0x20;
    const mutex: u64 = 0x40;
    const unique_lock: u64 = 0x60;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true };
    _ = runtime.mutexLockForThread(mutex, worker);

    var state = struct {
        memory: [256]u8 = [_]u8{0} ** 256,
        active_guest_thread: u64 = worker,
        monotonic_nanoseconds: u64 = 1_000,
        regs: struct { rdi: u64 = condvar, rsi: u64 = unique_lock, rdx: u64 = system_clock_epoch_nanoseconds + 6_000, rcx: u64 = 0 } = .{},
        fn guestMemory(self: *@This(), address: u64, count: u64) ?[]u8 {
            const start: usize = @intCast(address);
            const length: usize = @intCast(count);
            if (start > self.memory.len or length > self.memory.len - start) return null;
            return self.memory[start .. start + length];
        }
        fn guestMemoryConst(self: *const @This(), address: u64, count: u64) ?[]const u8 {
            const start: usize = @intCast(address);
            const length: usize = @intCast(count);
            if (start > self.memory.len or length > self.memory.len - start) return null;
            return self.memory[start .. start + length];
        }
    }{};
    std.mem.writeInt(u64, state.memory[unique_lock..][0..8], mutex, .little);

    try std.testing.expect(runtime.beginCooperativeCppCondvarWait(&state, true));
    try std.testing.expectEqual(@as(?u64, null), runtime.resumeCooperativeWait(worker, 5_999));
    state.regs.rdi = condvar;
    try std.testing.expect(runtime.dispatchCppSynchronization(&state, "__ZNSt3__118condition_variable10notify_allEv") != null);
    try std.testing.expectEqual(@as(?u64, 0), runtime.resumeCooperativeWait(worker, 5_999));
    try std.testing.expectEqual(worker, runtime.mutexes[0].owner_thread);
}

test "cooperative resume rejects dependency-blocked queue entries" {
    const worker: u64 = SYNTHETIC_THREAD_BASE;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true, .state = .waiting_join };
    try std.testing.expectEqual(@as(?u64, null), runtime.resumeCooperativeWait(worker, 0));

    runtime.threads[0].state = .terminated;
    try std.testing.expectEqual(@as(?u64, null), runtime.resumeCooperativeWait(worker, 0));

    runtime.threads[0].state = .runnable;
    try std.testing.expectEqual(@as(?u64, 0), runtime.resumeCooperativeWait(worker, 0));
}

test "scheduler resume preserves RAX for ordinary runnable contexts" {
    const worker: u64 = SYNTHETIC_THREAD_BASE;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true, .state = .runnable };

    const decision = runtime.resumeCooperativeContext(worker, 0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(?u64, null), decision.rax_override);
    try std.testing.expectEqual(@as(u64, 0x4D7_AF80), decision.restoredRax(0x4D7_AF80));
}

test "scheduler resume overrides RAX only when a condition wait completes" {
    const worker: u64 = SYNTHETIC_THREAD_BASE;
    const mutex: u64 = 0x3000;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true };
    _ = runtime.mutexLockForThread(mutex, worker);

    var state = struct {
        active_guest_thread: u64 = worker,
        regs: struct { rdi: u64 = 0x4000, rsi: u64 = mutex, rdx: u64 = 0, rcx: u64 = 0 } = .{},
        fn guestMemory(self: *@This(), _: u64, _: u64) ?[]u8 {
            _ = self;
            return null;
        }
        fn write64(self: *@This(), _: u64, _: u64) void {
            _ = self;
        }
        fn write32(self: *@This(), _: u64, _: u32) void {
            _ = self;
        }
    }{};

    try std.testing.expect(runtime.beginCooperativeWait(&state, worker, state.regs.rdi, mutex, 5_000));
    const decision = runtime.resumeCooperativeContext(worker, 5_000) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(?u64, ETIMEDOUT), decision.rax_override);
    try std.testing.expectEqual(@as(u64, ETIMEDOUT), decision.restoredRax(0x4D7_AF80));
}

test "finite and indefinite virtual sleeps have distinct eligibility" {
    const worker = SYNTHETIC_THREAD_BASE;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true, .state = .running };

    try std.testing.expect(runtime.beginCooperativeSleep(worker, 10, 5_000, 7));
    try std.testing.expectEqual(ThreadState.sleeping_until_deadline, runtime.threads[0].state);
    try std.testing.expect(runtime.resumeCooperativeContext(worker, 4_999) == null);
    const finite = runtime.resumeCooperativeContext(worker, 5_000) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 7), finite.cancel_deadline_sequence);
    try std.testing.expectEqual(@as(?u64, null), finite.rax_override);

    runtime.threads[0].state = .running;
    try std.testing.expect(runtime.beginCooperativeSleep(worker, 20, null, 0));
    try std.testing.expectEqual(ThreadState.sleeping_indefinitely, runtime.threads[0].state);
    try std.testing.expect(runtime.resumeCooperativeContext(worker, std.math.maxInt(u64)) == null);
    try std.testing.expect(runtime.wakeSleepingThread(worker, "external_event"));
    try std.testing.expect(runtime.resumeCooperativeContext(worker, 0) != null);
}

test "global quiescence grants one POSIX spurious wake to oldest condvar waiter" {
    const first = SYNTHETIC_THREAD_BASE;
    const second = SYNTHETIC_THREAD_BASE + 0x10;
    var runtime = Runtime{};
    runtime.threads[0] = .{
        .active = true,
        .handle = first,
        .started = true,
        .state = .waiting_condvar,
        .waiting_condvar = 0x4000,
        .blocked_since_step = 10,
    };
    runtime.threads[1] = .{
        .active = true,
        .handle = second,
        .started = true,
        .state = .waiting_condvar,
        .waiting_condvar = 0x5000,
        .blocked_since_step = 20,
    };
    _ = runtime.condvarInit(0x4000);
    _ = runtime.condvarInit(0x5000);

    try std.testing.expectEqual(first, runtime.wakeOldestCondvarForQuiescence(0, 100).?);
    try std.testing.expect(runtime.threads[0].spurious_wake_pending);
    try std.testing.expectEqual(second, runtime.wakeOldestCondvarForQuiescence(second, 101).?);
    try std.testing.expect(runtime.threads[1].spurious_wake_pending);
    try std.testing.expect(runtime.wakeOldestCondvarForQuiescence(0, 102) == null);

    // Returning to the same predicate wait without a signal does not mint an
    // unlimited stream of artificial work.
    runtime.threads[0].spurious_wake_pending = false;
    runtime.threads[1].spurious_wake_pending = false;
    try std.testing.expect(runtime.wakeOldestCondvarForQuiescence(0, 103) == null);

    // A genuine condition generation change makes a later wait eligible.
    runtime.threads[0].wait_generation = 1;
    try std.testing.expectEqual(first, runtime.wakeOldestCondvarForQuiescence(0, 104).?);
}

test "thread state transitions" {
    var runtime = Runtime{};
    try std.testing.expectEqual(@as(u64, 0), runtime.activeCount());
}

test "cooperative execution owner overrides ambient UI callback state" {
    const worker: u64 = SYNTHETIC_THREAD_BASE + 0x30;
    var runtime = Runtime{};
    var state = struct {
        active_guest_thread: u64 = worker,

        pub fn currentCooperativeThreadHandle(self: *const @This()) u64 {
            return self.active_guest_thread;
        }
    }{};

    try std.testing.expectEqual(worker, runtime.currentThreadHandle(&state));
    state.active_guest_thread = CURRENT_THREAD_HANDLE;
    try std.testing.expectEqual(CURRENT_THREAD_HANDLE, runtime.currentThreadHandle(&state));
}

test "pthread_threadid_np assigns stable numeric ids" {
    const worker: u64 = SYNTHETIC_THREAD_BASE;
    var runtime = Runtime{};
    runtime.threads[0] = .{ .active = true, .handle = worker, .started = true, .numeric_id = runtime.allocateNumericThreadId() };

    var state = struct {
        active_guest_thread: u64 = worker,
        mem: [16]u8 = [_]u8{0} ** 16,
        regs: struct { rdi: u64 = 0, rsi: u64 = 8, rdx: u64 = 0, rcx: u64 = 0 } = .{ .rsi = 8 },
        fn guestMemory(self: *@This(), address: u64, size: u64) ?[]u8 {
            if (address + size > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + size)];
        }
        fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
        }
        fn write32(self: *@This(), _: u64, _: u32) void {
            _ = self;
        }
    }{};

    try std.testing.expectEqual(@as(u64, 0), runtime.threadId(&state));
    try std.testing.expectEqual(@as(u64, 2), std.mem.readInt(u64, state.mem[8..16], .little));
    state.regs.rdi = CURRENT_THREAD_HANDLE;
    try std.testing.expectEqual(@as(u64, 0), runtime.threadId(&state));
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, state.mem[8..16], .little));
}

test "POSIX scheduler yield is modeled as a successful scheduling hint" {
    var runtime = Runtime{};
    var test_state = struct {
        regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},
        fn guestMemory(self: *@This(), _: u64, _: u64) ?[]u8 {
            _ = self;
            return null;
        }
        fn write64(self: *@This(), _: u64, _: u64) void {
            _ = self;
        }
        fn write32(self: *@This(), _: u64, _: u32) void {
            _ = self;
        }
    }{};

    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&test_state, "_sched_yield").?.handled);
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&test_state, "_pthread_yield_np").?.handled);
    try std.testing.expectEqual(@as(u64, 2), runtime.scheduler_yields);
}
