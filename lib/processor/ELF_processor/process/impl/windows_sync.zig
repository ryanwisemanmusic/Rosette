const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_heap = @import("guest_heap.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_instruction_decode = @import("instruction_decode.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_windows_wake = @import("windows_sync/wake_router.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const process_impl_windows_ui = @import("windows_ui.zig");
const process_impl_windows_mutex = @import("windows_mutex.zig");
const __process_HookPoints = __ProcessInternals._HookPoints;
const __process_NativeConditionLock = __ProcessInternals._NativeConditionLock;
const __process_PARALLEL_WORKER_STEP_BATCH = __ProcessInternals._PARALLEL_WORKER_STEP_BATCH;
const __process_PPC_CONTEXT_VIRTUAL_MEMBASE = __ProcessInternals._PPC_CONTEXT_VIRTUAL_MEMBASE;
const __process_SYNTHETIC_WINDOWS_APC_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_APC_RETURN;
const __process_SYNTHETIC_WINDOWS_THREAD_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_THREAD_RETURN;
const __process_WINDOWS_CLOCK_POLL_YIELD_READS = __ProcessInternals._WINDOWS_CLOCK_POLL_YIELD_READS;
const __process_WINDOWS_CURRENT_THREAD_PSEUDO_HANDLE = __ProcessInternals._WINDOWS_CURRENT_THREAD_PSEUDO_HANDLE;
const __process_WINDOWS_FILETIME_UNIX_EPOCH = __ProcessInternals._WINDOWS_FILETIME_UNIX_EPOCH;
const __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY = __ProcessInternals._WINDOWS_FILE_READ_PROVENANCE_CAPACITY;
const __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND = __ProcessInternals._WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
const __process_WINDOWS_GUEST_SPIN_MAX_BACKOFF = __ProcessInternals._WINDOWS_GUEST_SPIN_MAX_BACKOFF;
const __process_WINDOWS_GUEST_SPIN_PROBE_AT = __ProcessInternals._WINDOWS_GUEST_SPIN_PROBE_AT;
const __process_WINDOWS_GUEST_SPIN_PROBE_SPAN = __ProcessInternals._WINDOWS_GUEST_SPIN_PROBE_SPAN;
const __process_WINDOWS_GUEST_THREAD_ENTRY_RESERVE = __ProcessInternals._WINDOWS_GUEST_THREAD_ENTRY_RESERVE;
const __process_WINDOWS_GUEST_THREAD_MAX_STACK_SIZE = __ProcessInternals._WINDOWS_GUEST_THREAD_MAX_STACK_SIZE;
const __process_WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE = __ProcessInternals._WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE;
const __process_WINDOWS_GUEST_THREAD_SERVICE_SLICE = __ProcessInternals._WINDOWS_GUEST_THREAD_SERVICE_SLICE;
const __process_WINDOWS_GUEST_THREAD_STACK_GUARD = __ProcessInternals._WINDOWS_GUEST_THREAD_STACK_GUARD;
const __process_WINDOWS_GUEST_THREAD_STACK_SIZE = __ProcessInternals._WINDOWS_GUEST_THREAD_STACK_SIZE;
const __process_WINDOWS_GUEST_YIELD_MINIMUM_SLICE = __ProcessInternals._WINDOWS_GUEST_YIELD_MINIMUM_SLICE;
const __process_WINDOWS_MAXIMUM_SUSPEND_COUNT = __ProcessInternals._WINDOWS_MAXIMUM_SUSPEND_COUNT;
const __process_WINDOWS_PAGE_SIZE = __ProcessInternals._WINDOWS_PAGE_SIZE;
const __process_WINDOWS_PTHREAD_ETIMEDOUT = __ProcessInternals._WINDOWS_PTHREAD_ETIMEDOUT;
const __process_WINDOWS_TEB_BYTES = __ProcessInternals._WINDOWS_TEB_BYTES;
const __process_WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET = __ProcessInternals._WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET;
const __process_WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET = __ProcessInternals._WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET;
const __process_WINDOWS_TEB_LAST_ERROR_OFFSET = __ProcessInternals._WINDOWS_TEB_LAST_ERROR_OFFSET;
const __process_WINDOWS_TEB_PEB_OFFSET = __ProcessInternals._WINDOWS_TEB_PEB_OFFSET;
const __process_WINDOWS_TEB_SELF_OFFSET = __ProcessInternals._WINDOWS_TEB_SELF_OFFSET;
const __process_WINDOWS_TEB_STACK_BASE_OFFSET = __ProcessInternals._WINDOWS_TEB_STACK_BASE_OFFSET;
const __process_WINDOWS_TEB_STACK_LIMIT_OFFSET = __ProcessInternals._WINDOWS_TEB_STACK_LIMIT_OFFSET;
const __process_WINDOWS_TEB_TLS_POINTER_OFFSET = __ProcessInternals._WINDOWS_TEB_TLS_POINTER_OFFSET;
const __process_WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT = __ProcessInternals._WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT;
const __process_WINDOWS_TIMED_WAIT_SITE_CAPACITY = __ProcessInternals._WINDOWS_TIMED_WAIT_SITE_CAPACITY;
const __process_WINDOWS_TLS_BLOCK_BYTES = __ProcessInternals._WINDOWS_TLS_BLOCK_BYTES;
const __process_WINDOWS_TLS_SLOT_COUNT = __ProcessInternals._WINDOWS_TLS_SLOT_COUNT;
const __process_WINDOWS_WAIT_IO_COMPLETION = __ProcessInternals._WINDOWS_WAIT_IO_COMPLETION;
const __process_WINDOWS_WAIT_MULTIPLE_CAPACITY = __ProcessInternals._WINDOWS_WAIT_MULTIPLE_CAPACITY;
const __process_WindowsApcQueue = __ProcessInternals._WindowsApcQueue;
const __process_WindowsFileReadProvenance = __ProcessInternals._WindowsFileReadProvenance;
const __process_WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const __process_WindowsGuestThreadContext = __ProcessInternals._WindowsGuestThreadContext;
const __process_WindowsGuestThreadEnvironment = __ProcessInternals._WindowsGuestThreadEnvironment;
const __process_WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const __process_WindowsMultiWaitResult = __ProcessInternals._WindowsMultiWaitResult;
const __process_WindowsRuntimeLockGuard = __ProcessInternals._WindowsRuntimeLockGuard;
const __process_WindowsSrwLock = __ProcessInternals._WindowsSrwLock;
const __process_WindowsWaitObject = __ProcessInternals._WindowsWaitObject;
const __process_XENIA_GLOBAL_MUTEX_OWNER_OFFSET = __ProcessInternals._XENIA_GLOBAL_MUTEX_OWNER_OFFSET;
const __process_XENIA_GLOBAL_MUTEX_RECURSION_OFFSET = __ProcessInternals._XENIA_GLOBAL_MUTEX_RECURSION_OFFSET;
const __process_XeniaGlobalLend = __ProcessInternals._XeniaGlobalLend;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_classifyWindowsTimedWaitSite = __ProcessInternals._classifyWindowsTimedWaitSite;
const __process_concurrency = __ProcessInternals._concurrency;
const __process_context_integrity = __ProcessInternals._context_integrity;
const __process_guest_clock = __ProcessInternals._guest_clock;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_host_fp_control = __ProcessInternals._host_fp_control;
const __process_host_profile = __ProcessInternals._host_profile;
const __process_log = __ProcessInternals._log;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_parallel_diagnostics = __ProcessInternals._parallel_diagnostics;
const __process_parallel_metrics = __ProcessInternals._parallel_metrics;
const __process_parallel_workers = __ProcessInternals._parallel_workers;
const __process_ppcContextGpr = __ProcessInternals._ppcContextGpr;
const __process_std = __ProcessInternals._std;
const __process_tso_memory = __ProcessInternals._tso_memory;
const __process_wait_cost = __ProcessInternals._wait_cost;
const __process_windowsTimedWaitPercent = __ProcessInternals._windowsTimedWaitPercent;
const __process_windows_guest_execution_binding = __ProcessInternals._windows_guest_execution_binding;
const __process_windows_srw_owner_stack_depth = __ProcessInternals._windows_srw_owner_stack_depth;
const __process_xbox_critical_section = __ProcessInternals._xbox_critical_section;
const __state_NativeConditionResult = __StateInternals._NativeConditionResult;
const __state_TimedWaitOutcome = __StateInternals._TimedWaitOutcome;
const __state_WindowsConditionWaitResult = __StateInternals._WindowsConditionWaitResult;
const __state_WindowsPthreadMutexAcquireResult = __StateInternals._WindowsPthreadMutexAcquireResult;
const __state_WindowsPthreadMutexReleaseResult = __StateInternals._WindowsPthreadMutexReleaseResult;
const __state_WindowsSrwAcquireResult = __StateInternals._WindowsSrwAcquireResult;
const __state_WindowsWaitResult = __StateInternals._WindowsWaitResult;
const __state_XboxCriticalSectionCall = __StateInternals._XboxCriticalSectionCall;
const __state_XboxSectionAccess = __StateInternals._XboxSectionAccess;
const __state_XboxWait = __StateInternals._XboxWait;

pub fn noteWindowsGuestClockRead(self: *ElfState) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null) return;
    process_impl_lifecycle.guestContextField(self, "windows_slice_clock_reads").* +|= 1;
    if (process_impl_lifecycle.guestContextField(self, "windows_slice_clock_reads").* == __process_WINDOWS_CLOCK_POLL_YIELD_READS) {
        if (!self.parallel_guest_execution) self.windows_clock_poll_yields +|= 1;
        process_impl_lifecycle.requestWindowsGuestSliceYield(self);
    }
}

pub fn beginWindowsWaitAccounting(
    self: *ElfState,
    thread: *__process_WindowsGuestThread,
    key: u64,
    kind: __process_wait_cost.WaitKind,
    timeout_milliseconds: u64,
    deadline: u64,
) void {
    if (thread.wait_cost_site != 0) return;
    const accounting_step = process_impl_run_reporting.totalInterpretedSteps(self);
    const ticks = process_impl_lifecycle.windowsGuestClockTicks(self);
    thread.wait_cost_site = self.windows_wait_cost.begin(key, kind, accounting_step, ticks, timeout_milliseconds);
    thread.wait_cost_start_step = accounting_step;
    thread.wait_cost_start_ticks = ticks;
    thread.wait_cost_deadline = deadline;
    thread.blocked_since_total_steps = accounting_step;
    thread.blocked_since_guest_ticks = ticks;
}

pub fn endWindowsWaitAccounting(self: *ElfState, thread: *__process_WindowsGuestThread, outcome: __process_wait_cost.Outcome) void {
    if (thread.wait_cost_site != 0) {
        self.windows_wait_cost.end(
            thread.wait_cost_site,
            outcome,
            thread.wait_cost_start_step,
            thread.wait_cost_start_ticks,
            process_impl_run_reporting.totalInterpretedSteps(self),
            process_impl_lifecycle.windowsGuestClockTicks(self),
            thread.wait_cost_deadline,
        );
    }
    thread.wait_cost_site = 0;
    thread.wait_cost_start_step = 0;
    thread.wait_cost_start_ticks = 0;
    thread.wait_cost_deadline = 0;
    thread.blocked_since_total_steps = 0;
    thread.blocked_since_guest_ticks = 0;
}

pub fn endWindowsWaitAccountingIfKind(
    self: *ElfState,
    thread: *__process_WindowsGuestThread,
    kind: __process_wait_cost.WaitKind,
    outcome: __process_wait_cost.Outcome,
) void {
    if (thread.wait_cost_site == 0) return;
    const index = @as(usize, thread.wait_cost_site) - 1;
    if (index >= self.windows_wait_cost.count or self.windows_wait_cost.sites[index].kind != kind) return;
    endWindowsWaitAccounting(self, thread, outcome);
}

pub fn endWindowsHandleWaitAccounting(self: *ElfState, thread: *__process_WindowsGuestThread, outcome: __process_wait_cost.Outcome) void {
    if (thread.wait_cost_site == 0) return;
    const index = @as(usize, thread.wait_cost_site) - 1;
    if (index >= self.windows_wait_cost.count) return;
    switch (self.windows_wait_cost.sites[index].kind) {
        .finite_handle, .infinite_handle, .multiple => endWindowsWaitAccounting(self, thread, outcome),
        else => {},
    }
}

pub fn noteWindowsWaitSignal(self: *ElfState, key: u64) void {
    const thread_handle = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot|
        self.windows_guest_threads[slot].handle
    else
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*;
    self.windows_wait_cost.signal(
        key,
        process_impl_run_reporting.totalInterpretedSteps(self),
        process_impl_lifecycle.windowsGuestClockTicks(self),
        .{ .thread_handle = thread_handle, .rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").* },
    );
}

pub fn endActiveWindowsSrwWaitAccounting(self: *ElfState) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
        endWindowsWaitAccountingIfKind(self, &self.windows_guest_threads[index], .srw_lock, .signaled);
    }
}

pub fn activeWindowsApcQueue(self: *ElfState) *__process_WindowsApcQueue {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| return &self.windows_guest_threads[slot].apc;
    return &self.windows_owner_apc;
}

pub fn queueWindowsApc(self: *ElfState, handle: u64, routine: u64, parameter: u64) bool {
    if (routine == 0) {
        self.windows_apc_refusals +|= 1;
        return false;
    }
    const pseudo_current_thread = __process_std.math.maxInt(u64) - 1;
    var queue: *__process_WindowsApcQueue = undefined;
    var target: ?*__process_WindowsGuestThread = null;
    var target_slot: ?usize = null;
    if (handle == pseudo_current_thread) {
        queue = activeWindowsApcQueue(self);
        if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| {
            target = &self.windows_guest_threads[slot];
            target_slot = slot;
        }
    } else {
        for (self.windows_guest_threads, 0..) |*thread, slot| {
            if (thread.status == .vacant or thread.handle != handle) continue;
            target = thread;
            target_slot = slot;
            break;
        }
        const thread = target orelse {
            self.windows_apc_refusals +|= 1;
            return false;
        };
        if (thread.status == .completed or thread.status == .failed) {
            self.windows_apc_refusals +|= 1;
            return false;
        }
        queue = &thread.apc;
    }
    if (!queue.push(routine, parameter)) {
        self.windows_apc_refusals +|= 1;
        return false;
    }
    self.windows_apcs_queued +|= 1;
    if (target) |thread| {
        if (thread.status == .blocked and thread.blocked_alertable and
            thread.blocked_srw_lock == 0 and thread.blocked_condition == 0)
        {
            endWindowsWaitAccounting(self, thread, .aborted);
            thread.status = .runnable;
            if (target_slot) |slot|
                process_impl_lifecycle.noteWindowsGuestWorkerWake(self, slot)
            else
                process_impl_lifecycle.noteWindowsThreadWake(self);
            thread.blocked_alertable = false;
            thread.blocked_wait_handle = 0;
            thread.blocked_wait_handle_count = 0;
            thread.blocked_wait_timeout = 0;
            thread.blocked_wait_deadline = 0;
            thread.multi_wait_deadline = 0;
            thread.wait_resume = false;
            thread.wait_resume_handle = 0;
            thread.wait_resume_timeout = false;
            thread.wait_resume_recheck = false;
            self.windows_thread_unblocks +|= 1;
            self.windows_apc_wakes +|= 1;
        }
    }
    return true;
}

pub fn setWindowsWaitAlertable(self: *ElfState, alertable: bool) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| self.windows_guest_threads[slot].blocked_alertable = alertable;
}

pub fn beginWindowsApcDelivery(self: *ElfState, direct_return_rip: ?u64) bool {
    const queue = activeWindowsApcQueue(self);
    if (queue.delivering or queue.count == 0) return false;
    queue.delivering = true;
    queue.saved_rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp;
    queue.continuation = direct_return_rip orelse 0;
    queue.continuation_direct = direct_return_rip != null;
    startNextWindowsApc(self, queue);
    return true;
}

pub fn startNextWindowsApc(self: *ElfState, queue: *__process_WindowsApcQueue) void {
    const apc = queue.pop() orelse return;
    var frame = (queue.saved_rsp -% 0x40) & ~@as(u64, 0xF);
    frame -%= 8;
    process_impl_guest_memory.write64(self, frame, __process_SYNTHETIC_WINDOWS_APC_RETURN);
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = frame;
    process_impl_lifecycle.guestContextField(self, "regs").*.rcx = apc.parameter;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = apc.routine;
    self.windows_apcs_delivered +|= 1;
}

pub fn continueWindowsApcDelivery(self: *ElfState) void {
    const queue = activeWindowsApcQueue(self);
    if (!queue.delivering) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        if (comptime !@import("builtin").is_test) __process_log.err("PE64 APC return without a delivery in progress at rsp=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rsp});
        return;
    }
    if (queue.count != 0) {
        startNextWindowsApc(self, queue);
        return;
    }
    queue.delivering = false;
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = queue.saved_rsp;
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_WINDOWS_WAIT_IO_COMPLETION;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = if (queue.continuation_direct) queue.continuation else process_impl_guest_memory.pop(self);
}

pub fn parkWindowsGuestSleep(self: *ElfState, milliseconds: u64) bool {
    const index = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return false;
    if (milliseconds == 0) {
        process_impl_lifecycle.requestWindowsGuestSliceYield(self);
        return true;
    }
    const thread = &self.windows_guest_threads[index];
    thread.status = .blocked;
    thread.blocked_wait_handle = 0;
    thread.blocked_srw_lock = 0;
    thread.blocked_condition = 0;
    thread.blocked_condition_mutex = 0;
    thread.blocked_wait_timeout = milliseconds;
    thread.blocked_wait_deadline = process_impl_lifecycle.windowsGuestClockTicks(self) +|
        (milliseconds *| __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND);
    beginWindowsWaitAccounting(
        self,
        thread,
        0,
        .deadline,
        milliseconds,
        thread.blocked_wait_deadline,
    );
    self.windows_thread_blocks +|= 1;
    self.windows_guest_sleep_parks +|= 1;
    return true;
}

pub fn parkWindowsGuestDelayTicks(self: *ElfState, ticks: u64) bool {
    const index = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return false;
    if (ticks == 0) {
        self.windows_nt_delay_yields +|= 1;
        process_impl_lifecycle.requestWindowsGuestSliceYield(self);
        return true;
    }
    const thread = &self.windows_guest_threads[index];
    thread.status = .blocked;
    thread.blocked_wait_handle = 0;
    thread.blocked_srw_lock = 0;
    thread.blocked_condition = 0;
    thread.blocked_condition_mutex = 0;
    thread.blocked_wait_timeout = __process_std.math.divCeil(u64, ticks, __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND) catch 0;
    thread.blocked_wait_deadline = process_impl_lifecycle.windowsGuestClockTicks(self) +| ticks;
    beginWindowsWaitAccounting(
        self,
        thread,
        0,
        .deadline,
        thread.blocked_wait_timeout,
        thread.blocked_wait_deadline,
    );
    self.windows_thread_blocks +|= 1;
    self.windows_nt_delay_parks +|= 1;
    return true;
}

pub fn windowsPthreadMutexImpl(self: *const ElfState, address: u64) ?u64 {
    if (address == 0 or process_impl_execution.guestMemoryConst(self, address, 8) == null) return null;
    const impl = process_impl_guest_memory.read64(self, address);
    if (impl < 0x1000 or process_impl_execution.guestMemoryConst(self, impl, 0x18) == null) return null;
    return impl;
}

pub fn releaseWindowsGuestPthreadMutex(self: *ElfState, address: u64) __state_WindowsPthreadMutexReleaseResult {
    const impl = windowsPthreadMutexImpl(self, address) orelse return .invalid;
    const state = process_impl_guest_memory.read32(self, impl);
    if (state == 0) return .already_unlocked;
    if (state != 1 and state != 2) return .invalid;

    const attributes = process_impl_guest_memory.read32(self, impl + 4);
    const owner = process_impl_guest_memory.read32(self, impl + 0x14);
    const current_thread_id: u32 = @truncate(process_impl_lifecycle.currentWindowsThreadId(self));
    if (attributes != 0 and owner != current_thread_id) return .invalid;

    const recursion = process_impl_guest_memory.read32(self, impl + 0x10);
    if (recursion != 0) {
        process_impl_guest_memory.write32(self, impl + 0x10, recursion - 1);
        return .released;
    }

    process_impl_guest_memory.write32(self, impl + 0x14, __process_std.math.maxInt(u32));
    process_impl_guest_memory.write32(self, impl, 0);
    if (state == 2) {
        const event = process_impl_guest_memory.read64(self, impl + 8);
        if (event != 0) {
            if (windowsWaitObjectIndex(self, event) == null) {
                registerWindowsEvent(self, event, false, false);
            }
            _ = signalWindowsWaitObject(self, event, false);
        }
    }
    return .released;
}

pub fn acquireWindowsGuestPthreadMutex(self: *ElfState, address: u64, after_contention: bool) __state_WindowsPthreadMutexAcquireResult {
    const impl = windowsPthreadMutexImpl(self, address) orelse return .invalid;
    const state = process_impl_guest_memory.read32(self, impl);
    const attributes = process_impl_guest_memory.read32(self, impl + 4);
    const current_thread_id: u32 = @truncate(process_impl_lifecycle.currentWindowsThreadId(self));
    if (state == 0) {
        process_impl_guest_memory.write32(self, impl, if (after_contention) 2 else 1);
        if (attributes != 0) process_impl_guest_memory.write32(self, impl + 0x14, current_thread_id);
        return .acquired;
    }
    if (state != 1 and state != 2) return .invalid;

    if (attributes != 0 and process_impl_guest_memory.read32(self, impl + 0x14) == current_thread_id) {
        // Attribute value 2 is the image's recursive mutex mode.  The
        // ordinary mode reports a self-lock failure in the guest; a
        // condition waiter should never need to take that path.
        if (attributes == 2) {
            process_impl_guest_memory.write32(self, impl + 0x10, process_impl_guest_memory.read32(self, impl + 0x10) +| 1);
            return .acquired;
        }
        return .invalid;
    }

    const event = process_impl_guest_memory.read64(self, impl + 8);
    if (event == 0) return .invalid;
    if (windowsWaitObjectIndex(self, event) == null) {
        registerWindowsEvent(self, event, false, false);
    }
    if (state == 1) process_impl_guest_memory.write32(self, impl, 2);
    return .{ .contended = event };
}

pub fn windowsSrwLockIndex(self: *const ElfState, address: u64) ?usize {
    return self.windows_srw_lock_index.find(address);
}

pub fn ensureWindowsSrwLock(self: *ElfState, address: u64) ?*__process_WindowsSrwLock {
    if (address == 0 or process_impl_execution.guestMemoryConst(self, address, 8) == null) return null;
    if (windowsSrwLockIndex(self, address)) |index| return &self.windows_srw_locks[index];
    for (&self.windows_srw_locks, 0..) |*lock, index| {
        if (lock.address == 0) {
            lock.* = .{ .address = address };
            if (!self.windows_srw_lock_index.insert(address, index)) {
                lock.* = .{};
                return null;
            }
            return lock;
        }
    }
    return null;
}

pub fn windowsWaitObjectIndex(self: *const ElfState, handle: u64) ?usize {
    if (handle == 0) return null;
    // Only as far as the highest slot in use. A freed slot below it is
    // the next one filled, so a run holding a few hundred objects scans
    // a few hundred entries however large the table is.
    for (self.windows_wait_objects[0..self.windows_wait_object_high_water], 0..) |*object, index| {
        if (object.handle == handle) return index;
    }
    return null;
}

pub fn ensureWindowsWaitObject(self: *ElfState, handle: u64) ?*__process_WindowsWaitObject {
    if (handle == 0) return null;
    if (windowsWaitObjectIndex(self, handle)) |index| return &self.windows_wait_objects[index];
    for (&self.windows_wait_objects, 0..) |*object, index| {
        if (object.handle == 0) {
            object.* = .{ .handle = handle };
            if (index >= self.windows_wait_object_high_water) self.windows_wait_object_high_water = index + 1;
            return object;
        }
    }
    noteWindowsWaitObjectTableFull(self, handle);
    return null;
}

pub fn noteWindowsWaitObjectCreated(self: *ElfState, object: *__process_WindowsWaitObject) void {
    object.creator_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    object.creator_thread = process_impl_lifecycle.guestContextField(self, "active_guest_thread").*;
    object.created_step = process_impl_lifecycle.observedExecutionSteps(self);
}

pub fn noteWindowsWaitObjectSignaled(self: *ElfState, object: *__process_WindowsWaitObject) void {
    object.signal_count +|= 1;
    object.last_signal_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    object.last_signal_thread = process_impl_lifecycle.guestContextField(self, "active_guest_thread").*;
    object.last_signal_step = process_impl_lifecycle.observedExecutionSteps(self);
}

pub fn closeWindowsWaitObject(self: *ElfState, handle: u64) bool {
    const index = windowsWaitObjectIndex(self, handle) orelse return false;
    if (self.windows_main_wait_handle == handle) return true;
    for (self.windows_guest_threads) |*thread| {
        if (thread.status == .blocked and thread.waitsOnHandle(handle)) return true;
    }
    self.windows_wait_objects[index] = .{};
    self.windows_wait_objects_freed +|= 1;
    while (self.windows_wait_object_high_water != 0 and
        self.windows_wait_objects[self.windows_wait_object_high_water - 1].handle == 0)
    {
        self.windows_wait_object_high_water -= 1;
    }
    return true;
}

pub fn noteWindowsFileTableFull(self: *ElfState) void {
    self.windows_file_table_full +|= 1;
    const occurrence = self.windows_file_table_full;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    if (comptime !@import("builtin").is_test) {
        if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) {
            var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.err("PE64 FATAL POINT: guest-condition label=file-handle-table-full owner=rosette:file-model occurrence={d} import={s} capacity={d} step={d} caller={s}; every file slot holds an open handle, so this open fails with ERROR_TOO_MANY_OPEN_FILES and the guest loses a file Windows would have opened. CloseHandle, fclose and _close free slots; read WINDOWS FILE FAILURES for what was being opened", .{
                occurrence,
                if (process_impl_lifecycle.guestContextField(self, "windows_current_import").*.len == 0) "<unattributed>" else process_impl_lifecycle.guestContextField(self, "windows_current_import").*,
                self.windows_files.len,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*, &caller_text),
            });
        }
    }
    process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "file-handle-table-full");
}

pub fn noteWindowsFileMappingTableFull(self: *ElfState, handle: u64) void {
    self.windows_file_mapping_table_full +|= 1;
    const occurrence = self.windows_file_mapping_table_full;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    if (comptime !@import("builtin").is_test) {
        if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) {
            __process_log.err("PE64 FATAL POINT: guest-condition label=file-mapping-table-full owner=rosette:file-model occurrence={d} handle=0x{x} capacity={d} step={d}; every mapping slot holds a mapping that is open or still has a view, so CreateFileMapping returns NULL. A mapping's slot is freed when its handle is closed and its last view unmapped", .{
                occurrence,
                handle,
                self.windows_file_mappings.len,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
    }
    process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "file-mapping-table-full");
}

pub fn noteWindowsWaitObjectTableFull(self: *ElfState, handle: u64) void {
    self.windows_wait_object_table_full +|= 1;
    const occurrence = self.windows_wait_object_table_full;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    if (comptime !@import("builtin").is_test) {
        if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) {
            var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.err("PE64 FATAL POINT: guest-condition label=wait-object-table-full owner=rosette:wait-model occurrence={d} handle=0x{x} capacity={d} freed_so_far={d} step={d} caller={s}; every slot holds an event, mutex, semaphore or thread handle that has not been closed, so this object has no wait model and any wait on it would be invented. Either the guest holds more than MAX_WINDOWS_WAIT_OBJECTS at once or a close path is not freeing them", .{
                occurrence,
                handle,
                self.windows_wait_objects.len,
                self.windows_wait_objects_freed,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*, &caller_text),
            });
        }
    }
    process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "wait-object-table-full");
}

pub fn registerWindowsTimer(self: *ElfState, handle: u64, manual_reset: bool) void {
    if (ensureWindowsWaitObject(self, handle)) |object| {
        object.* = .{ .handle = handle, .kind = .timer, .manual_reset = manual_reset };
        noteWindowsWaitObjectCreated(self, object);
        self.windows_timers_created +|= 1;
    }
}

pub fn setWindowsTimer(self: *ElfState, handle: u64, due: i64, period_ms: u64, now_filetime: u64, completion_routine: u64) bool {
    const index = windowsWaitObjectIndex(self, handle) orelse return false;
    const object = &self.windows_wait_objects[index];
    if (object.kind != .timer) return false;
    process_impl_instruction_decode.refreshWindowsGuestClock(self);
    const now = process_impl_lifecycle.windowsGuestClockTicks(self);
    const relative_100ns: u64 = if (due < 0)
        @as(u64, @bitCast(due)) *% __process_std.math.maxInt(u64)
    else if (@as(u64, @intCast(due)) > now_filetime)
        @as(u64, @intCast(due)) - now_filetime
    else
        0;
    const ticks: u64 = @intCast(@min(
        @as(u128, relative_100ns) * __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND / 10_000,
        __process_std.math.maxInt(u64) / 2,
    ));
    if (object.due_ticks == 0) self.windows_armed_timers +|= 1;
    object.due_ticks = now +| @max(ticks, 1);
    object.period_ticks = period_ms *| __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    object.signaled = false;
    self.windows_next_timer_due = @min(self.windows_next_timer_due, object.due_ticks);
    self.windows_timer_sets +|= 1;
    if (completion_routine != 0) {
        self.windows_timer_completion_routines +|= 1;
        if (self.windows_timer_completion_routines == 1 and !@import("builtin").is_test) {
            var routine_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.warn("PE64 waitable timer completion routine not delivered: handle=0x{x} routine={s} step={d}; a completion routine is an APC that runs when the thread that armed the timer next waits alertably, and Rosette has no APC delivery, so the timer signals its waiters but the routine never runs", .{
                handle,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, completion_routine, &routine_text),
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
    }
    return true;
}

pub fn cancelWindowsTimer(self: *ElfState, handle: u64) bool {
    const index = windowsWaitObjectIndex(self, handle) orelse return false;
    const object = &self.windows_wait_objects[index];
    if (object.kind != .timer) return false;
    if (object.due_ticks != 0) self.windows_armed_timers -|= 1;
    object.due_ticks = 0;
    object.period_ticks = 0;
    return true;
}

pub fn advanceWindowsTimer(self: *ElfState, object: *__process_WindowsWaitObject, now: u64) void {
    object.signaled = true;
    noteWindowsWaitObjectSignaled(self, object);
    self.windows_timer_fires +|= 1;
    if (object.period_ticks != 0) {
        const behind = (now - object.due_ticks) / object.period_ticks + 1;
        object.due_ticks +|= behind *| object.period_ticks;
    } else {
        object.due_ticks = 0;
        self.windows_armed_timers -|= 1;
    }
}

pub fn fireDueWindowsTimers(self: *ElfState, now: u64) u64 {
    if (self.windows_armed_timers == 0 or now < self.windows_next_timer_due) return 0;
    var next: u64 = __process_std.math.maxInt(u64);
    var woken: u64 = 0;
    for (self.windows_wait_objects[0..self.windows_wait_object_high_water]) |*object| {
        if (object.handle == 0 or object.kind != .timer or object.due_ticks == 0) continue;
        if (now >= object.due_ticks) {
            advanceWindowsTimer(self, object, now);
            // A notification timer releases every waiter and stays
            // signalled; a synchronization timer releases one and is
            // consumed by it.
            const released = wakeWindowsGuestThreadsForWait(self, object.handle, object.manual_reset);
            if (!object.manual_reset and released != 0) object.signaled = false;
            woken +|= released;
        }
        if (object.due_ticks != 0) next = @min(next, object.due_ticks);
    }
    self.windows_next_timer_due = next;
    return woken;
}

pub fn registerWindowsEvent(self: *ElfState, handle: u64, manual_reset: bool, initial_state: bool) void {
    if (ensureWindowsWaitObject(self, handle)) |object| {
        object.* = .{
            .handle = handle,
            .kind = .event,
            .signaled = initial_state,
            .manual_reset = manual_reset,
        };
        noteWindowsWaitObjectCreated(self, object);
        if (self.trace_windows_waits) {
            self.windows_wait_registration_trace_events +|= 1;
            const event = self.windows_wait_registration_trace_events;
            if (event <= 8 or (event & (event - 1)) == 0 or event % 16 == 0) {
                __process_log.info("PE64 wait object registered: kind=event handle=0x{x} manual_reset={} initial_state={} creator_rip=0x{x} active_thread=0x{x} step={d} event={d}", .{
                    handle,
                    manual_reset,
                    initial_state,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                    process_impl_lifecycle.observedExecutionSteps(self),
                    event,
                });
            }
        }
    }
}

pub const registerWindowsMutex = process_impl_windows_mutex.register;
pub const releaseWindowsMutex = process_impl_windows_mutex.release;
pub const windowsMutexOwner = process_impl_windows_mutex.owner;

pub fn registerWindowsSemaphore(self: *ElfState, handle: u64, initial_count: u64, maximum_count: u64) void {
    if (ensureWindowsWaitObject(self, handle)) |object| {
        const maximum: u32 = @intCast(@min(maximum_count, __process_std.math.maxInt(u32)));
        const count: u32 = @intCast(@min(@min(initial_count, maximum_count), __process_std.math.maxInt(u32)));
        object.* = .{
            .handle = handle,
            .kind = .semaphore,
            .signaled = count != 0,
            .count = count,
            .maximum = maximum,
        };
        noteWindowsWaitObjectCreated(self, object);
    }
}

pub fn registerWindowsThreadWaitObject(self: *ElfState, handle: u64) void {
    if (ensureWindowsWaitObject(self, handle)) |object| {
        object.* = .{ .handle = handle, .kind = .thread };
        noteWindowsWaitObjectCreated(self, object);
    }
}

pub fn windowsWaitObjectReady(self: *const ElfState, handle: u64) ?bool {
    for (self.windows_guest_threads) |*thread| {
        if (thread.handle == handle and thread.status != .vacant) {
            return thread.status == .completed or thread.status == .failed;
        }
    }
    if (windowsWaitObjectIndex(self, handle)) |index| {
        const object = self.windows_wait_objects[index];
        return switch (object.kind) {
            .semaphore => object.count != 0,
            .timer => object.signaled or (object.due_ticks != 0 and process_impl_lifecycle.windowsGuestClockTicks(self) >= object.due_ticks),
            .mutex => object.signaled or process_impl_windows_mutex.ownedByCaller(self, &object),
            else => object.signaled,
        };
    }
    return null;
}

pub fn noteXboxCriticalSectionWaitProvenance(
    self: *ElfState,
    thread: *__process_WindowsGuestThread,
    handle: u64,
    timeout: u64,
) void {
    if (thread.critical_section == 0 or thread.critical_section_membase == 0 or
        thread.last_import_len == 0 or
        !__process_std.mem.eql(u8, thread.lastImportText(), "NtWaitForSingleObject") or
        thread.xbox_cs_wait_provenance_handle == handle)
    {
        return;
    }
    thread.xbox_cs_wait_provenance_handle = handle;

    const last_call = self.guest_kernel_calls.slotAt(thread.last_kernel_slot);
    const kernel_export = if (last_call) |call| call.export_name else "<unavailable>";
    const kernel_is_enter = if (last_call) |call|
        call.kind == .trampoline and __process_std.mem.eql(u8, call.export_name, "RtlEnterCriticalSection")
    else
        false;

    if (comptime !@import("builtin").is_test) {
        if (windowsWaitObjectIndex(self, handle)) |object_index| {
            const object = &self.windows_wait_objects[object_index];
            __process_log.info("PE64 XBOX CRITICAL SECTION WAIT PROVENANCE: thread=0x{x} name='{s}' event=0x{x} kind={s} manual_reset={} signaled={} creator_thread=0x{x} creator_rip=0x{x} created_step={d} signal_count={d} last_signal_thread=0x{x} last_signal_rip=0x{x} last_signal_step={d} section=0x{x} membase=0x{x} kernel_export={s} kernel_is_enter={} enter_step={d} wait_step={d} timeout={d}; Xenia's own RtlEnterCriticalSection is waiting on the event embedded in the section", .{
                thread.handle,
                if (thread.name_len != 0) thread.nameText() else "<unnamed>",
                handle,
                @tagName(object.kind),
                object.manual_reset,
                object.signaled,
                object.creator_thread,
                object.creator_rip,
                object.created_step,
                object.signal_count,
                object.last_signal_thread,
                object.last_signal_rip,
                object.last_signal_step,
                thread.critical_section,
                thread.critical_section_membase,
                kernel_export,
                kernel_is_enter,
                thread.last_kernel_step,
                thread.last_import_step,
                timeout,
            });
        } else {
            __process_log.info("PE64 XBOX CRITICAL SECTION WAIT PROVENANCE: thread=0x{x} name='{s}' event=0x{x} kind=unregistered section=0x{x} membase=0x{x} kernel_export={s} kernel_is_enter={} enter_step={d} wait_step={d} timeout={d}; the wait handle has no registered producer model", .{
                thread.handle,
                if (thread.name_len != 0) thread.nameText() else "<unnamed>",
                handle,
                thread.critical_section,
                thread.critical_section_membase,
                kernel_export,
                kernel_is_enter,
                thread.last_kernel_step,
                thread.last_import_step,
                timeout,
            });
        }
        process_impl_kernel_services.logCriticalSectionWait(self, thread);
    }
}

pub fn windowsWaitObjectKindName(self: *const ElfState, handle: u64) []const u8 {
    for (self.windows_guest_threads) |*thread| {
        if (thread.handle == handle and thread.status != .vacant) return "thread";
    }
    if (windowsWaitObjectIndex(self, handle)) |index| return @tagName(self.windows_wait_objects[index].kind);
    return "unknown";
}

pub fn windowsGuestWaitServiceSlice(self: *const ElfState) u64 {
    if (self.windows_scheduler.enabled and self.windows_scheduler.slice != 0) {
        return self.windows_scheduler.slice;
    }
    return __process_WINDOWS_GUEST_THREAD_SERVICE_SLICE;
}

pub fn serviceWindowsGuestBoundary(self: *ElfState, max_steps: u64) u64 {
    if (max_steps == 0 or process_impl_lifecycle.isTerminated(self) or process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null) return 0;
    if (!self.windows_scheduler.enabled) return serviceWindowsGuestThreads(self, max_steps);
    const policy = &self.windows_scheduler;
    if (process_impl_lifecycle.observedExecutionSteps(self) < policy.next_explicit_service_step) {
        policy.explicit_service_skips +|= 1;
        return 0;
    }
    const stride = if (policy.explicit_stride != 0)
        policy.explicit_stride
    else
        __process_WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE;
    policy.next_explicit_service_step = process_impl_lifecycle.observedExecutionSteps(self) +| stride;
    const serviced = serviceWindowsGuestThreads(self, max_steps);
    policy.explicit_service_calls +|= 1;
    policy.explicit_serviced_steps +|= serviced;
    return serviced;
}

pub fn traceWindowsWaitDecision(self: *ElfState, handle: u64, timeout: u64, result: __state_WindowsWaitResult) void {
    if (!self.trace_windows_waits) return;
    if (result == .signaled) return;
    self.windows_wait_trace_events +|= 1;
    const event = self.windows_wait_trace_events;
    if (event > 8 and (event & (event - 1)) != 0) return;
    const active_slot = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| @as(u64, @intCast(index)) else __process_std.math.maxInt(u64);
    var first_runnable_handle: u64 = 0;
    var first_blocked_handle: u64 = 0;
    var first_blocked_wait: u64 = 0;
    var first_blocked_lock: u64 = 0;
    var first_blocked_condition: u64 = 0;
    var first_blocked_condition_mutex: u64 = 0;
    for (self.windows_guest_threads) |*thread| {
        if (first_runnable_handle == 0 and (thread.status == .runnable or thread.status == .pending)) {
            first_runnable_handle = thread.handle;
        }
        if (first_blocked_handle == 0 and thread.status == .blocked) {
            first_blocked_handle = thread.handle;
            first_blocked_wait = thread.blocked_wait_handle;
            first_blocked_lock = thread.blocked_srw_lock;
            first_blocked_condition = thread.blocked_condition;
            first_blocked_condition_mutex = thread.blocked_condition_mutex;
        }
    }
    __process_log.info("PE64 guest wait decision: result={s} handle=0x{x} kind={s} timeout=0x{x} active_thread=0x{x} active_slot=0x{x} rip=0x{x} return_rip=0x{x} rsp=0x{x} owner_service_steps={d} workers(pending/runnable/blocked)={d}/{d}/{d} first_runnable=0x{x} first_blocked=0x{x} blocked_wait=0x{x} blocked_lock=0x{x} blocked_condition=0x{x} blocked_condition_mutex=0x{x} step={d} event={d}", .{
        @tagName(result),
        handle,
        windowsWaitObjectKindName(self, handle),
        timeout,
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
        active_slot,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        self.windows_wait_last_owner_service_steps,
        process_impl_run_reporting.countWindowsWorkers(self, .pending),
        process_impl_run_reporting.countWindowsWorkers(self, .runnable),
        process_impl_run_reporting.countWindowsWorkers(self, .blocked),
        first_runnable_handle,
        first_blocked_handle,
        first_blocked_wait,
        first_blocked_lock,
        first_blocked_condition,
        first_blocked_condition_mutex,
        process_impl_lifecycle.observedExecutionSteps(self),
        event,
    });
}

pub fn windowsWaitObjectSignaled(self: *const ElfState, handle: u64) bool {
    return windowsWaitObjectReady(self, handle) orelse false;
}

pub fn windowsWaitObjectKnown(self: *const ElfState, handle: u64) bool {
    if (handle == 0) return false;
    if (windowsWaitObjectIndex(self, handle) != null) return true;
    for (self.windows_guest_threads) |*thread| {
        if (thread.handle == handle and thread.status != .vacant) return true;
    }
    return false;
}

pub fn windowsWaitObjectSemaphoreCount(self: *const ElfState, handle: u64) ?u32 {
    const index = windowsWaitObjectIndex(self, handle) orelse return null;
    const object = self.windows_wait_objects[index];
    return if (object.kind == .semaphore) object.count else null;
}

pub fn consumeWindowsWaitObject(self: *ElfState, handle: u64) void {
    const index = windowsWaitObjectIndex(self, handle) orelse return;
    const object = &self.windows_wait_objects[index];
    switch (object.kind) {
        .event => {
            if (!object.manual_reset) object.signaled = false;
        },
        .mutex => process_impl_windows_mutex.take(self, object),
        .semaphore => {
            if (object.count != 0) object.count -= 1;
            object.signaled = object.count != 0;
        },
        .thread, .generic => {},
        .timer => {
            // Satisfied because its due tick passed before any sweep
            // fired it: fire it here, then a synchronization timer is
            // consumed and a notification timer stays signalled.
            const now = process_impl_lifecycle.windowsGuestClockTicks(self);
            if (object.due_ticks != 0 and now >= object.due_ticks) advanceWindowsTimer(self, object, now);
            object.signaled = object.manual_reset;
        },
    }
}

pub fn wakeWindowsGuestThreadsForWait(self: *ElfState, handle: u64, wake_all: bool) u64 {
    var woken: u64 = 0;
    for (self.windows_guest_threads, 0..) |*thread, slot| {
        const recheck = process_impl_windows_wake.wakeWindowsGuestWaiterForHandle(self, thread, slot, handle) orelse continue;
        // A wait-all waiter only looks again; it takes nothing with it,
        // so it is not a transfer the caller should account for.
        if (recheck) continue;
        woken +|= 1;
        if (!wake_all) break;
    }
    return woken;
}

pub fn wakeExpiredWindowsGuestWaits(self: *ElfState) u64 {
    // Refresh the clock here as well as in `step`. A deadline is only
    // reached because time passed, and with the clock read from the host
    // rather than counted from instructions there is a state where no
    // instruction runs: every worker parked on a deadline and the owner
    // in this service loop. The clock would then never advance, nothing
    // would ever wake, and a run that was merely asleep would look
    // deadlocked. Sampling at the point of the question removes the
    // possibility entirely.
    process_impl_instruction_decode.refreshWindowsGuestClock(self);
    var woken: u64 = 0;
    const now = process_impl_lifecycle.windowsGuestClockTicks(self);
    // A timer that fires wins over a timeout falling due in the same sweep.
    woken +|= fireDueWindowsTimers(self, now);
    for (self.windows_guest_threads, 0..) |*thread, slot| {
        if (thread.status != .blocked or thread.blocked_wait_deadline == 0 or
            now < thread.blocked_wait_deadline)
        {
            continue;
        }
        if (thread.blocked_condition != 0) {
            // A timed condition wait ran out. It resumes the way a
            // signalled waiter does, through its mutex, and returns
            // ETIMEDOUT instead of zero.
            noteWindowsTimedConditionTimeout(self, thread, slot, now);
            thread.status = .runnable;
            process_impl_lifecycle.noteWindowsGuestWorkerWake(self, slot);
            thread.blocked_condition = 0;
            thread.blocked_wait_deadline = 0;
            thread.condition_resume = true;
            thread.condition_resume_timeout = true;
            thread.wait_resume_timeout = false;
            self.windows_thread_unblocks +|= 1;
            self.windows_condition_timeouts +|= 1;
            woken +|= 1;
            continue;
        }
        const handle = thread.blocked_wait_handle;
        thread.status = .runnable;
        process_impl_lifecycle.noteWindowsGuestWorkerWake(self, slot);
        thread.blocked_wait_handle = 0;
        thread.blocked_wait_deadline = 0;
        thread.blocked_srw_lock = 0;
        thread.blocked_condition = 0;
        thread.blocked_condition_mutex = 0;
        thread.blocked_wait_handle_count = 0;
        thread.blocked_wait_all = false;
        thread.wait_resume_recheck = false;
        // A `Sleep` park has no wait object: it already returned to the
        // guest, so it resumes at the instruction after the call and must
        // not be handed a wait result it never asked for.
        thread.wait_resume = handle != 0;
        thread.wait_resume_handle = handle;
        thread.wait_resume_timeout = handle != 0;
        if (handle == 0) endWindowsWaitAccountingIfKind(self, thread, .deadline, .timed_out);
        self.windows_thread_unblocks +|= 1;
        self.windows_wait_unblocks +|= 1;
        woken +|= 1;
    }
    return woken;
}

pub fn signalWindowsWaitObject(self: *ElfState, handle: u64, pulse: bool) u64 {
    const index = windowsWaitObjectIndex(self, handle) orelse return 0;
    const object = &self.windows_wait_objects[index];
    noteWindowsWaitSignal(self, handle);
    noteWindowsWaitObjectSignaled(self, object);
    object.signaled = true;
    // The owner's own waits poll signalled objects from the run loop, so
    // a signal is a wake even when no worker was parked on it.
    process_impl_lifecycle.noteWindowsThreadWake(self);
    const woken = wakeWindowsGuestThreadsForWait(self, handle, object.manual_reset);
    if (woken == 0) handOffToWaitingOwner(self, handle);
    if (object.kind == .semaphore and object.count == 0) object.count = 1;
    if (pulse or (object.kind == .event and !object.manual_reset and woken != 0)) object.signaled = false;
    if (self.trace_windows_waits) {
        self.windows_wait_signal_trace_events +|= 1;
        const event = self.windows_wait_signal_trace_events;
        if (event <= 8 or (event & (event - 1)) == 0) {
            __process_log.info("PE64 wait object signaled: handle=0x{x} kind={s} pulse={} woken={d} signaled_after={} signal_rip=0x{x} active_thread=0x{x} step={d} event={d}", .{
                handle,
                @tagName(object.kind),
                pulse,
                woken,
                object.signaled,
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                process_impl_lifecycle.observedExecutionSteps(self),
                event,
            });
        }
    }
    return woken;
}

pub fn handOffToWaitingOwner(self: *ElfState, handle: u64) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null) return;
    for (self.windows_owner_wait_handles[0..self.windows_owner_wait_handle_count]) |waiting| {
        if (waiting != handle) continue;
        if (!process_impl_lifecycle.guestContextField(self, "windows_guest_handoff_requested").*) {
            process_impl_lifecycle.guestContextField(self, "windows_guest_handoff_requested").* = true;
            self.windows_owner_wait_handoffs +|= 1;
        }
        return;
    }
}

pub fn setOwnerWaitHandles(self: *ElfState, handles: []const u64) void {
    const count = @min(handles.len, self.windows_owner_wait_handles.len);
    @memcpy(self.windows_owner_wait_handles[0..count], handles[0..count]);
    self.windows_owner_wait_handle_count = @intCast(count);
}

pub fn resetWindowsWaitObject(self: *ElfState, handle: u64) bool {
    const index = windowsWaitObjectIndex(self, handle) orelse return false;
    const object = &self.windows_wait_objects[index];
    object.signaled = false;
    if (object.kind == .semaphore) object.count = 0;
    return true;
}

pub fn releaseWindowsSemaphore(self: *ElfState, handle: u64, release_count: u64) bool {
    const index = windowsWaitObjectIndex(self, handle) orelse return false;
    const object = &self.windows_wait_objects[index];
    if (object.kind != .semaphore or release_count == 0) return false;
    noteWindowsWaitSignal(self, handle);
    noteWindowsWaitObjectSignaled(self, object);
    const maximum = if (object.maximum == 0) __process_std.math.maxInt(u32) else object.maximum;
    const increment: u32 = @intCast(@min(release_count, __process_std.math.maxInt(u32)));
    object.count = @min(maximum, object.count +| increment);
    // Each woken waiter takes one count with it. A resumed wait returns
    // WAIT_OBJECT_0 without consuming, so leaving the count behind let a
    // single release satisfy the waiter it woke and then the next caller
    // too - a semaphore that over-grants is a lock that admits two.
    while (object.count != 0) {
        if (wakeWindowsGuestThreadsForWait(self, handle, false) == 0) break;
        object.count -= 1;
    }
    object.signaled = object.count != 0;
    if (object.signaled) handOffToWaitingOwner(self, handle);
    return true;
}

pub fn waitWindowsGuestObject(self: *ElfState, handle: u64, timeout: u64) __state_WindowsWaitResult {
    if (handle == 0) return .invalid;
    self.windows_wait_calls +|= 1;

    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
        const thread = &self.windows_guest_threads[index];
        if (thread.wait_resume and thread.wait_resume_handle == handle) {
            const resumed_by_timeout = thread.wait_resume_timeout;
            const waited_timeout = thread.blocked_wait_timeout;
            thread.wait_resume = false;
            thread.wait_resume_handle = 0;
            thread.wait_resume_timeout = false;
            thread.blocked_wait_timeout = 0;
            self.windows_wait_resumes +|= 1;
            if (resumed_by_timeout) {
                endWindowsHandleWaitAccounting(self, thread, .timed_out);
                self.windows_wait_timeouts +|= 1;
                traceWindowsWaitDecision(self, handle, waited_timeout, .timeout);
                return .timeout;
            }
            endWindowsHandleWaitAccounting(self, thread, .signaled);
            return .signaled;
        }
    }

    const ready = windowsWaitObjectReady(self, handle) orelse {
        self.windows_wait_unknown_objects +|= 1;
        traceWindowsWaitDecision(self, handle, timeout, .unknown);
        return .unknown;
    };
    if (ready) {
        if (self.windows_main_wait_handle == handle) self.windows_main_wait_handle = 0;
        consumeWindowsWaitObject(self, handle);
        return .signaled;
    }
    if (timeout == 0) {
        self.windows_wait_timeouts +|= 1;
        traceWindowsWaitDecision(self, handle, timeout, .timeout);
        return .timeout;
    }

    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
        const thread = &self.windows_guest_threads[index];
        if (thread.status != .running) return .invalid;
        if (self.windows_guest_wait_compatibility) {
            self.windows_wait_compatibility_yields +|= 1;
            traceWindowsWaitDecision(self, handle, timeout, .yielded);
            return .yielded;
        }
        thread.status = .blocked;
        thread.blocked_wait_handle = handle;
        thread.blocked_wait_timeout = timeout;
        thread.blocked_wait_handle_count = 0;
        thread.blocked_wait_all = false;
        // A Win32 timeout is in guest milliseconds, and Rosetta already
        // publishes a guest clock: one tick per interpreted instruction
        // at `WINDOWS_GUEST_CLOCK_HZ`. Convert through that, so the wait
        // and the guest's own `QueryPerformanceCounter` reading of it
        // measure the same millisecond.
        thread.blocked_wait_deadline = if (timeout == __process_std.math.maxInt(u32))
            0
        else
            process_impl_lifecycle.windowsGuestClockTicks(self) +|
                (@max(timeout, @as(u64, 1)) *| __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND);
        thread.blocked_srw_lock = 0;
        thread.blocked_condition = 0;
        thread.blocked_condition_mutex = 0;
        thread.condition_resume = false;
        thread.wait_resume_timeout = false;
        beginWindowsWaitAccounting(
            self,
            thread,
            handle,
            if (timeout == __process_std.math.maxInt(u32)) .infinite_handle else .finite_handle,
            timeout,
            thread.blocked_wait_deadline,
        );
        self.windows_thread_blocks +|= 1;
        self.windows_wait_blocks +|= 1;
        noteXboxCriticalSectionWaitProvenance(self, thread, handle, timeout);
        traceWindowsWaitDecision(self, handle, timeout, .blocked);
        return .blocked;
    }

    // Parallel mode: every other guest thread has its own host thread,
    // so the owner can sleep like any of them. It used to take the
    // cooperative path below, which answers a finite wait WAIT_TIMEOUT
    // at once and retries an infinite one as fast as the interpreter
    // can - a spin on the main thread that took the runtime lock every
    // lap.
    if (self.parallel_guest_execution) {
        if (process_impl_windows_ui.ownerParallelWait(self, &.{handle}, false, timeout)) |outcome| {
            switch (outcome) {
                .signaled => {
                    consumeWindowsWaitObject(self, handle);
                    return .signaled;
                },
                .timeout => {
                    self.windows_wait_timeouts +|= 1;
                    traceWindowsWaitDecision(self, handle, timeout, .timeout);
                    return .timeout;
                },
                .retry => return .retry,
            }
        }
    }
    // The owner is also Rosetta's UI-loop executor. A host-thread block
    // would strand the deferred UI callback that is supposed to signal
    // this event (Xenia's emulator_thread_event_ is the canonical case).
    // Give queued workers one bounded turn, then complete this boundary
    // as a cooperative yield. The next owner instruction re-enters the
    // wait naturally, while the outer loop remains able to pump the
    // message-only window and execute the callback that will eventually
    // signal the event. Parking the owner here prevents that callback
    // from ever running on the single Rosetta interpreter.
    setOwnerWaitHandles(self, &.{handle});
    const serviced = serviceWindowsGuestBoundary(self, windowsGuestWaitServiceSlice(self));
    self.windows_owner_wait_handle_count = 0;
    self.windows_wait_last_owner_service_steps = serviced;
    if (serviced != 0) {
        self.windows_wait_owner_yields +|= 1;
    }

    traceWindowsWaitDecision(self, handle, timeout, .yielded);
    return .yielded;
}

pub fn waitWindowsGuestObjects(self: *ElfState, handles: []const u64, wait_all: bool, timeout: u64) __process_WindowsMultiWaitResult {
    if (handles.len == 0 or handles.len > __process_WINDOWS_WAIT_MULTIPLE_CAPACITY) return .invalid;
    for (handles) |handle| {
        if (handle == 0) return .invalid;
    }
    self.windows_wait_multiple_calls +|= 1;
    self.windows_wait_calls +|= 1;

    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
        const thread = &self.windows_guest_threads[index];
        if (thread.wait_resume) {
            if (__process_std.mem.indexOfScalar(u64, handles, thread.wait_resume_handle)) |woken_index| {
                const by_timeout = thread.wait_resume_timeout;
                const recheck = thread.wait_resume_recheck;
                thread.wait_resume = false;
                thread.wait_resume_handle = 0;
                thread.wait_resume_timeout = false;
                thread.wait_resume_recheck = false;
                thread.blocked_wait_timeout = 0;
                self.windows_wait_resumes +|= 1;
                if (by_timeout) {
                    endWindowsWaitAccountingIfKind(self, &self.windows_guest_threads[index], .multiple, .timed_out);
                    thread.multi_wait_deadline = 0;
                    self.windows_wait_timeouts +|= 1;
                    return .timeout;
                }
                if (!recheck) {
                    endWindowsWaitAccountingIfKind(self, &self.windows_guest_threads[index], .multiple, .signaled);
                    thread.multi_wait_deadline = 0;
                    return .{ .signaled = @intCast(woken_index) };
                }
                // A wait-all waiter looks again below, keeping its deadline.
            }
        }
    }

    if (takeReadyWindowsWaitObjects(self, handles, wait_all)) |result| {
        if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
            switch (result) {
                .signaled => endWindowsWaitAccountingIfKind(self, &self.windows_guest_threads[index], .multiple, .signaled),
                else => {},
            }
        }
        clearActiveMultiWaitDeadline(self);
        return result;
    }
    if (timeout == 0) {
        clearActiveMultiWaitDeadline(self);
        self.windows_wait_timeouts +|= 1;
        return .timeout;
    }

    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
        const thread = &self.windows_guest_threads[index];
        if (thread.status != .running) return .invalid;
        const deadline = if (thread.multi_wait_deadline != 0)
            thread.multi_wait_deadline
        else if (timeout == __process_std.math.maxInt(u32))
            0
        else
            process_impl_lifecycle.windowsGuestClockTicks(self) +| (@max(timeout, @as(u64, 1)) *| __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND);
        thread.status = .blocked;
        thread.blocked_wait_handle = handles[0];
        thread.blocked_wait_timeout = timeout;
        thread.blocked_wait_deadline = deadline;
        thread.multi_wait_deadline = deadline;
        @memcpy(thread.blocked_wait_handles[0..handles.len], handles);
        thread.blocked_wait_handle_count = @intCast(handles.len);
        thread.blocked_wait_all = wait_all;
        thread.blocked_srw_lock = 0;
        thread.blocked_condition = 0;
        thread.blocked_condition_mutex = 0;
        thread.condition_resume = false;
        thread.wait_resume_timeout = false;
        beginWindowsWaitAccounting(self, thread, handles[0], .multiple, timeout, deadline);
        self.windows_thread_blocks +|= 1;
        self.windows_wait_blocks +|= 1;
        self.windows_wait_multiple_blocks +|= 1;
        return .blocked;
    }

    // Parallel mode: the owner sleeps like a worker (see
    // `waitWindowsGuestObject`).
    if (self.parallel_guest_execution) {
        if (process_impl_windows_ui.ownerParallelWait(self, handles, wait_all, timeout)) |outcome| {
            switch (outcome) {
                .signaled => if (takeReadyWindowsWaitObjects(self, handles, wait_all)) |result| return result,
                .timeout => {
                    self.windows_wait_timeouts +|= 1;
                    return .timeout;
                },
                .retry => return .retry,
            }
            return .retry;
        }
    }
    // The owner cannot park (see `waitWindowsGuestObject`). Give workers
    // a turn, then look again: that turn may have signalled one.
    setOwnerWaitHandles(self, handles);
    const serviced = serviceWindowsGuestBoundary(self, windowsGuestWaitServiceSlice(self));
    self.windows_owner_wait_handle_count = 0;
    if (serviced != 0) self.windows_wait_owner_yields +|= 1;
    if (takeReadyWindowsWaitObjects(self, handles, wait_all)) |result| return result;
    if (timeout != __process_std.math.maxInt(u32)) {
        self.windows_wait_timeouts +|= 1;
        return .timeout;
    }
    self.windows_wait_multiple_owner_yields +|= 1;
    return .yielded;
}

pub fn takeReadyWindowsWaitObjects(self: *ElfState, handles: []const u64, wait_all: bool) ?__process_WindowsMultiWaitResult {
    var first_ready: ?usize = null;
    var all_ready = true;
    for (handles, 0..) |handle, handle_index| {
        const ready = windowsWaitObjectReady(self, handle) orelse {
            self.windows_wait_unknown_objects +|= 1;
            return .{ .unknown = handle };
        };
        if (ready) {
            if (first_ready == null) first_ready = handle_index;
        } else {
            all_ready = false;
        }
    }
    if (wait_all) {
        if (!all_ready) return null;
        for (handles) |handle| consumeWindowsWaitObject(self, handle);
        return .{ .signaled = 0 };
    }
    const found = first_ready orelse return null;
    consumeWindowsWaitObject(self, handles[found]);
    return .{ .signaled = @intCast(found) };
}

pub fn clearActiveMultiWaitDeadline(self: *ElfState) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| self.windows_guest_threads[slot].multi_wait_deadline = 0;
}

pub fn faultWindowsWaitUnknownHandle(self: *ElfState, handle: u64, api: []const u8) void {
    self.windows_wait_unknown_faults +|= 1;
    const occurrence = self.windows_wait_unknown_faults;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    if (comptime !@import("builtin").is_test) {
        if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) {
            var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            const slot_plus_one: u8 = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| @intCast(@min(slot + 1, 255)) else 0;
            __process_log.err("PE64 FATAL POINT: guest-condition label=wait-unknown-handle owner=rosette:wait-model occurrence={d} api={s} handle=0x{x} step={d} caller={s} thread={s}; Rosette has no event, mutex, semaphore or thread behind this handle, so any wait result it returned would be invented. Find the call that created the handle and give that object a wait model", .{
                occurrence,
                api,
                handle,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*, &caller_text),
                process_impl_guest_diagnostics.guestThreadLabel(self, slot_plus_one),
            });
        }
    }
    process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "wait-unknown-handle");
}

pub fn noteWindowsTimedWaitSite(self: *ElfState, caller: u64, slot: usize, milliseconds: u64) u8 {
    for (self.windows_timed_wait_sites[0..self.windows_timed_wait_site_count], 0..) |*site, index| {
        if (site.caller != caller) continue;
        site.waits +|= 1;
        site.last_milliseconds = milliseconds;
        return @intCast(index + 1);
    }
    if (self.windows_timed_wait_site_count == self.windows_timed_wait_sites.len) {
        self.windows_timed_wait_site_overflow +|= 1;
        return 0;
    }
    const index = self.windows_timed_wait_site_count;
    self.windows_timed_wait_sites[index] = .{
        .caller = caller,
        .first_thread_slot_plus_one = @intCast(@min(slot + 1, 255)),
        .waits = 1,
        .last_milliseconds = milliseconds,
    };
    self.windows_timed_wait_site_count += 1;
    return @intCast(index + 1);
}

pub fn countWindowsTimedWaitOutcome(self: *ElfState, site: u8, outcome: __state_TimedWaitOutcome) void {
    if (site == 0 or site > self.windows_timed_wait_site_count) return;
    const record = &self.windows_timed_wait_sites[site - 1];
    switch (outcome) {
        .timeout => record.timeouts +|= 1,
        .signalled => record.signalled +|= 1,
        .immediate => record.immediate +|= 1,
    }
}

pub fn rememberWindowsTimedWaitContext(
    self: *ElfState,
    site: u8,
    slot: usize,
    condition: u64,
    mutex: u64,
) void {
    if (site == 0 or site > self.windows_timed_wait_site_count) return;
    const record = &self.windows_timed_wait_sites[site - 1];
    record.last_condition = condition;
    record.last_mutex = mutex;
    record.last_thread_handle = self.windows_guest_threads[slot].handle;
    record.last_thread_id = self.windows_guest_threads[slot].thread_id;
}

pub fn noteWindowsTimedConditionTimeout(self: *ElfState, thread: *const __process_WindowsGuestThread, slot: usize, now: u64) void {
    if (self.windows_condition_timeout_samples >= __process_WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT) return;
    self.windows_condition_timeout_samples += 1;
    if (comptime @import("builtin").is_test) return;

    const site = thread.timed_wait_site;
    const site_index: ?usize = if (site != 0 and @as(usize, site) <= self.windows_timed_wait_site_count)
        @as(usize, site) - 1
    else
        null;
    const caller_address = if (site_index) |index| self.windows_timed_wait_sites[index].caller else 0;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var rip_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const caller = if (caller_address == 0)
        if (site == 0) "<site-table-full>" else "<unknown>"
    else
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_address, &caller_text);
    const rip = if (thread.context.last_instruction_rip != 0)
        thread.context.last_instruction_rip
    else
        thread.context.regs.rip;
    const thread_name = if (thread.name_len != 0) thread.nameText() else "<unnamed>";
    const last_import = if (thread.last_import_len != 0) thread.lastImportText() else "<none>";
    __process_log.info("PE64 TIMED WAIT TIMEOUT SAMPLE: sample={d}/{d} slot={d} caller={s} thread={s} handle=0x{x} thread_id={d} condition=0x{x} mutex=0x{x} timeout_ms={d} deadline_ticks={d} now_ticks={d} overdue_ticks={d} rip=0x{x} at={s} last_import={s} last_import_step={d} owner_step={d} wait_model=guest_clock_deadline safe_action=return_ETIMEDOUT synthetic_signal=0", .{
        self.windows_condition_timeout_samples,
        __process_WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT,
        slot,
        caller,
        thread_name,
        thread.handle,
        thread.thread_id,
        thread.blocked_condition,
        thread.blocked_condition_mutex,
        thread.timed_wait_milliseconds,
        thread.blocked_wait_deadline,
        now,
        now -| thread.blocked_wait_deadline,
        rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, rip, &rip_text),
        last_import,
        thread.last_import_step,
        process_impl_lifecycle.observedExecutionSteps(self),
    });
}

pub fn reportWindowsTimedWaitSites(self: *const ElfState, limit: usize) void {
    if (self.windows_timed_wait_site_count == 0) return;
    var timeouts: u64 = 0;
    for (self.windows_timed_wait_sites[0..self.windows_timed_wait_site_count]) |site| timeouts +|= site.timeouts;
    __process_log.info("PE64 TIMED WAIT SITES: {d} site(s), {d} timed condition wait(s), {d} timed out, first_timeout_samples={d}/{d}, suppressed={d}; inspect each site's classification and action: timeout-dominant short waits are polling candidates, while unsignalled long waits need a lost-wakeup investigation", .{
        self.windows_timed_wait_site_count,
        self.windows_condition_timed_waits,
        timeouts,
        self.windows_condition_timeout_samples,
        __process_WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT,
        self.windows_condition_timeouts -| @as(u64, self.windows_condition_timeout_samples),
    });
    var printed = [_]bool{false} ** __process_WINDOWS_TIMED_WAIT_SITE_CAPACITY;
    var shown: usize = 0;
    while (shown < @min(limit, self.windows_timed_wait_site_count)) : (shown += 1) {
        var best: ?usize = null;
        for (self.windows_timed_wait_sites[0..self.windows_timed_wait_site_count], 0..) |site, index| {
            if (printed[index]) continue;
            if (best == null or site.waits > self.windows_timed_wait_sites[best.?].waits) best = index;
        }
        const index = best orelse break;
        printed[index] = true;
        const site = self.windows_timed_wait_sites[index];
        const classification = __process_classifyWindowsTimedWaitSite(site);
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 TIMED WAIT SITES:   caller={s} thread={s} waits={d} timeouts={d} ({d}%) signalled={d} already_past={d} last_timeout_ms={d} condition=0x{x} mutex=0x{x} last_handle=0x{x} last_thread_id={d} classification={s} action={s}{s}", .{
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, site.caller, &caller_text),
            process_impl_guest_diagnostics.guestThreadLabel(self, site.first_thread_slot_plus_one),
            site.waits,
            site.timeouts,
            __process_windowsTimedWaitPercent(site.timeouts, site.waits),
            site.signalled,
            site.immediate,
            site.last_milliseconds,
            site.last_condition,
            site.last_mutex,
            site.last_thread_handle,
            site.last_thread_id,
            classification.label(),
            classification.action(),
            if (site.waits != 0 and site.timeouts == site.waits) " every-wait-timed-out" else "",
        });
    }
    if (self.windows_timed_wait_site_overflow != 0) {
        __process_log.info("PE64 TIMED WAIT SITES:   {d} wait(s) came from sites past the table's {d}", .{ self.windows_timed_wait_site_overflow, self.windows_timed_wait_sites.len });
    }
}

pub fn configureWindowsTimedConditionEntry(self: *ElfState, entry: ?u64) void {
    self.windows_pthread_cond_timedwait_entry = entry;
    if (entry) |address| {
        __process_log.info("PE64 guest synchronization hooks: pthread_cond_timedwait_impl=0x{x} source=executable-signature; timed condition waits park on the guest clock and the signal and broadcast hooks wake them", .{address});
    }
}

pub fn windowsPthreadTimespecMilliseconds(self: *const ElfState, timespec: u64, relative: bool) ?u64 {
    if (process_impl_execution.guestMemoryConst(self, timespec, 12) == null) return null;
    const seconds = process_impl_guest_memory.read64(self, timespec);
    const nanoseconds: i32 = @bitCast(process_impl_guest_memory.read32(self, timespec +| 8));
    // `addl $0xf423f, %eax; cltq; divq`: a 32-bit add, sign-extended,
    // divided unsigned.
    const rounded: u64 = @bitCast(@as(i64, nanoseconds +% 999_999));
    const requested = (seconds *% 1000) +% (rounded / 1_000_000);
    if (relative) return requested;
    const now = (process_impl_lifecycle.windowsGuestFileTime(self) -% __process_WINDOWS_FILETIME_UNIX_EPOCH) / 10_000;
    return if (requested >= now) requested - now else 0;
}

pub fn shimWindowsPthreadTimedCondition(self: *ElfState, return_rip: ?u64) bool {
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return false;
    const condition = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
    const mutex = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
    if (condition == 0 or mutex == 0) return false;
    var deadline: u64 = 0;
    if (!self.windows_guest_threads[slot].condition_resume) {
        const relative = (process_impl_lifecycle.guestContextField(self, "regs").*.r9 & 0xFFFF_FFFF) != 0;
        const milliseconds = windowsPthreadTimespecMilliseconds(self, process_impl_lifecycle.guestContextField(self, "regs").*.r8, relative) orelse return false;
        self.windows_condition_timed_waits +|= 1;
        const site = noteWindowsTimedWaitSite(self, return_rip orelse process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp), slot, milliseconds);
        self.windows_guest_threads[slot].timed_wait_site = site;
        self.windows_guest_threads[slot].timed_wait_milliseconds = milliseconds;
        rememberWindowsTimedWaitContext(self, site, slot, condition, mutex);
        if (milliseconds == 0) {
            // Already past: ETIMEDOUT with the mutex still held, as the
            // image returns it, and the rest of the slice to someone else.
            self.windows_condition_timed_immediate +|= 1;
            countWindowsTimedWaitOutcome(self, site, .immediate);
            self.windows_condition_hook_events +|= 1;
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_WINDOWS_PTHREAD_ETIMEDOUT;
            completeWindowsPthreadConditionReturn(self, return_rip);
            process_impl_lifecycle.requestWindowsGuestSliceYield(self);
            return true;
        }
        // The image treats more than 0xFFFFFFFE milliseconds as INFINITE.
        if (milliseconds <= 0xFFFF_FFFE) {
            deadline = process_impl_lifecycle.windowsGuestClockTicks(self) +| (milliseconds *| __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND);
        }
    }
    switch (waitWindowsGuestPthreadCondition(self, condition, mutex, deadline)) {
        .invalid => return false,
        .blocked => {
            self.windows_condition_hook_events +|= 1;
            return true;
        },
        // An INFINITE timed wait has no deadline and ends only by a
        // signal, so it returns 0 through the image's lock as well.
        .relock => {
            self.windows_condition_hook_events +|= 1;
            countWindowsTimedWaitOutcome(self, self.windows_guest_threads[slot].timed_wait_site, .signalled);
            completeWindowsPthreadConditionRelock(self, mutex, return_rip);
            return true;
        },
        .resumed => {
            self.windows_condition_hook_events +|= 1;
            const timed_out = self.windows_guest_threads[slot].condition_resume_timeout;
            self.windows_guest_threads[slot].condition_resume_timeout = false;
            countWindowsTimedWaitOutcome(self, self.windows_guest_threads[slot].timed_wait_site, if (timed_out) .timeout else .signalled);
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = if (timed_out) __process_WINDOWS_PTHREAD_ETIMEDOUT else 0;
            completeWindowsPthreadConditionReturn(self, return_rip);
            return true;
        },
    }
}

pub fn configureWindowsUtf8FindAnyOfEntry(self: *ElfState, entry: ?u64) void {
    self.windows_utf8_find_any_of_entry = entry;
    rebuildWindowsCompatHookBox(self);
}

pub fn configureWindowsUtf8CountEntry(self: *ElfState, entry: ?u64) void {
    self.windows_utf8_count_entry = entry;
    rebuildWindowsCompatHookBox(self);
}

pub fn noteWindowsUtf8CountObserved(self: *ElfState) u64 {
    self.windows_utf8_count_events +|= 1;
    return self.windows_utf8_count_events;
}

pub fn configureWindowsFmtEntries(self: *ElfState, vformat: ?u64, vformat_to: ?u64) void {
    self.windows_fmt_vformat_entry = vformat;
    self.windows_fmt_vformat_to_entry = vformat_to;
    process_impl_block_jit.rebuildBlockJitHookFilter(self);
}

pub fn noteWindowsFmtProbeInstruction(self: *ElfState) void {
    const regs = &process_impl_lifecycle.guestContextField(self, "regs").*;
    const rip = regs.rip;
    if (self.windows_fmt_vformat_entry == rip) {
        const return_address = if (process_impl_execution.guestMemoryConst(self, regs.rsp, 8) != null) process_impl_guest_memory.read64(self, regs.rsp) else 0;
        var return_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const return_description = if (return_address == 0)
            "<unreadable return address>"
        else
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, return_address, &return_text);
        if (__process_std.mem.indexOf(u8, return_description, "SaveConfig") != null) {
            self.windows_fmt_probe_active = true;
            self.windows_fmt_probe_calls +|= 1;
            self.windows_fmt_probe_current_call = self.windows_fmt_probe_calls;
            self.windows_fmt_vformat_return = return_address;
            self.windows_fmt_vformat_result = regs.rcx;
            if (self.windows_fmt_probe_current_call <= 8) {
                __process_log.info("PE64 FMT VFORMAT ENTRY: call={d} entry=0x{x} return=0x{x} ({s}) result_object=0x{x} format_view=0x{x} format_args=0x{x} thread=0x{x} step={d}; tracing the first eight formatter invocations through argument decode, output-buffer return, and std::string construction", .{
                    self.windows_fmt_probe_current_call,
                    rip,
                    return_address,
                    return_description,
                    regs.rcx,
                    regs.rdx,
                    regs.r8,
                    process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                    process_impl_lifecycle.observedExecutionSteps(self),
                });
                logWindowsFmtArguments(self, "vformat entry", regs.rdx, regs.r8, regs.rcx);
            }
        }
        return;
    }
    if (!self.windows_fmt_probe_active) return;

    if (self.windows_fmt_vformat_to_entry == rip) {
        const return_address = if (process_impl_execution.guestMemoryConst(self, regs.rsp, 8) != null) process_impl_guest_memory.read64(self, regs.rsp) else 0;
        self.windows_fmt_vformat_to_return = return_address;
        self.windows_fmt_vformat_to_buffer = regs.rcx;
        if (self.windows_fmt_probe_current_call <= 8) {
            __process_log.info("PE64 FMT VFORMAT_TO ENTRY: call={d} entry=0x{x} return=0x{x} buffer=0x{x} format_view=0x{x} format_args=0x{x} locale=0x{x} step={d}; this is the buffer writer called by the already-identified SaveConfig vformat", .{
                self.windows_fmt_probe_current_call,
                rip,
                return_address,
                regs.rcx,
                regs.rdx,
                regs.r8,
                regs.r9,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
            logWindowsFmtArguments(self, "vformat_to entry", regs.rdx, regs.r8, regs.rcx);
        }
        return;
    }

    if (self.windows_fmt_vformat_to_return == rip) {
        if (self.windows_fmt_probe_current_call <= 8) logWindowsFmtBuffer(self, "vformat_to return", self.windows_fmt_vformat_to_buffer);
        self.windows_fmt_vformat_to_return = null;
        self.windows_fmt_vformat_to_buffer = 0;
        return;
    }

    if (self.windows_fmt_vformat_return == rip) {
        if (self.windows_fmt_probe_current_call <= 8) logWindowsFmtString(self, "vformat return", self.windows_fmt_vformat_result);
        self.windows_fmt_vformat_return = null;
        self.windows_fmt_vformat_result = 0;
        self.windows_fmt_probe_active = false;
        self.windows_fmt_probe_current_call = 0;
    }
}

pub fn logWindowsFmtArguments(self: *ElfState, stage: []const u8, view_address: u64, args_address: u64, output_address: u64) void {
    var view: [16]u8 = [_]u8{0} ** 16;
    const view_readable = view_address != 0 and process_impl_execution.copyFromGuest(self, &view, view_address);
    const format_data = if (view_readable) __process_std.mem.readInt(u64, view[0..8], .little) else 0;
    const format_length = if (view_readable) __process_std.mem.readInt(u64, view[8..16], .little) else 0;
    var format_bytes: [32]u8 = [_]u8{0} ** 32;
    const format_sample_length: usize = @intCast(@min(format_length, format_bytes.len));
    const format_bytes_readable = format_sample_length == 0 or (format_data != 0 and process_impl_execution.copyFromGuest(self, format_bytes[0..format_sample_length], format_data));

    var args: [16]u8 = [_]u8{0} ** 16;
    const args_readable = args_address != 0 and process_impl_execution.copyFromGuest(self, &args, args_address);
    const descriptor = if (args_readable) __process_std.mem.readInt(u64, args[0..8], .little) else 0;
    const values_address = if (args_readable) __process_std.mem.readInt(u64, args[8..16], .little) else 0;
    var values: [32]u8 = [_]u8{0} ** 32;
    const values_readable = values_address != 0 and process_impl_execution.copyFromGuest(self, &values, values_address);
    const arg0_data = if (values_readable) __process_std.mem.readInt(u64, values[0..8], .little) else 0;
    const arg0_length = if (values_readable) __process_std.mem.readInt(u64, values[8..16], .little) else 0;
    const arg1_data = if (values_readable) __process_std.mem.readInt(u64, values[16..24], .little) else 0;
    const arg1_length = if (values_readable) __process_std.mem.readInt(u64, values[24..32], .little) else 0;
    var arg0_bytes: [64]u8 = [_]u8{0} ** 64;
    var arg1_bytes: [64]u8 = [_]u8{0} ** 64;
    const arg0_sample_length: usize = @intCast(@min(arg0_length, arg0_bytes.len));
    const arg1_sample_length: usize = @intCast(@min(arg1_length, arg1_bytes.len));
    const arg0_readable = arg0_sample_length == 0 or (arg0_data != 0 and process_impl_execution.copyFromGuest(self, arg0_bytes[0..arg0_sample_length], arg0_data));
    const arg1_readable = arg1_sample_length == 0 or (arg1_data != 0 and process_impl_execution.copyFromGuest(self, arg1_bytes[0..arg1_sample_length], arg1_data));
    __process_log.info("PE64 FMT ARGUMENT SNAPSHOT: stage={s} output_object_or_buffer=0x{x} format_view=0x{x} view_readable={} format_data=0x{x} format_length={d} format_bytes_readable={} format_sample={any} args=0x{x} args_readable={} descriptor=0x{x} unpacked={} has_named_args={} arg_types=[0x{x},0x{x}] values=0x{x} values_readable={} arg0={{data=0x{x},length={d},readable={},sample={any},truncated={}}} arg1={{data=0x{x},length={d},readable={},sample={any},truncated={}}} step={d}", .{
        stage,
        output_address,
        view_address,
        view_readable,
        format_data,
        format_length,
        format_bytes_readable,
        format_bytes[0..format_sample_length],
        args_address,
        args_readable,
        descriptor,
        (descriptor >> 63) != 0,
        (descriptor & (@as(u64, 1) << 62)) != 0,
        descriptor & 0xF,
        (descriptor >> 4) & 0xF,
        values_address,
        values_readable,
        arg0_data,
        arg0_length,
        arg0_readable,
        arg0_bytes[0..arg0_sample_length],
        arg0_length > arg0_bytes.len,
        arg1_data,
        arg1_length,
        arg1_readable,
        arg1_bytes[0..arg1_sample_length],
        arg1_length > arg1_bytes.len,
        process_impl_lifecycle.observedExecutionSteps(self),
    });
}

pub fn logWindowsFmtBuffer(self: *ElfState, stage: []const u8, buffer_address: u64) void {
    var header: [32]u8 = [_]u8{0} ** 32;
    const readable = buffer_address != 0 and process_impl_execution.copyFromGuest(self, &header, buffer_address);
    const data_address = if (readable) __process_std.mem.readInt(u64, header[0..8], .little) else 0;
    const length = if (readable) __process_std.mem.readInt(u64, header[8..16], .little) else 0;
    const capacity = if (readable) __process_std.mem.readInt(u64, header[16..24], .little) else 0;
    var bytes: [256]u8 = [_]u8{0} ** 256;
    const sample_length: usize = @intCast(@min(length, bytes.len));
    const bytes_readable = sample_length == 0 or (data_address != 0 and process_impl_execution.copyFromGuest(self, bytes[0..sample_length], data_address));
    __process_log.info("PE64 FMT BUFFER SNAPSHOT: stage={s} buffer=0x{x} header_readable={} data=0x{x} length={d} capacity={d} sample_readable={} sample={any} truncated={}; buffer layout is {{data,size,capacity,grow,inline-data}} from fmt::basic_memory_buffer", .{
        stage,
        buffer_address,
        readable,
        data_address,
        length,
        capacity,
        bytes_readable,
        bytes[0..sample_length],
        length > bytes.len,
    });
}

pub fn logWindowsFmtString(self: *ElfState, stage: []const u8, string_address: u64) void {
    var header: [24]u8 = [_]u8{0} ** 24;
    const readable = string_address != 0 and process_impl_execution.copyFromGuest(self, &header, string_address);
    const data_address = if (readable) __process_std.mem.readInt(u64, header[0..8], .little) else 0;
    const length = if (readable) __process_std.mem.readInt(u64, header[8..16], .little) else 0;
    const storage_word = if (readable) __process_std.mem.readInt(u64, header[16..24], .little) else 0;
    const inline_storage = data_address == string_address +| 16;
    var bytes: [256]u8 = [_]u8{0} ** 256;
    const sample_length: usize = @intCast(@min(length, bytes.len));
    const bytes_readable = sample_length == 0 or (data_address != 0 and process_impl_execution.copyFromGuest(self, bytes[0..sample_length], data_address));
    __process_log.info("PE64 FMT STRING SNAPSHOT: stage={s} string_object=0x{x} header_readable={} data=0x{x} length={d} inline_storage={} storage_or_capacity=0x{x} sample_readable={} sample={any} truncated={}; this is the std::string returned to SaveConfig before it appends the line", .{
        stage,
        string_address,
        readable,
        data_address,
        length,
        inline_storage,
        storage_word,
        bytes_readable,
        bytes[0..sample_length],
        length > bytes.len,
    });
}

pub fn reportWindowsFmtProbeDiagnostics(self: *const ElfState) void {
    if (self.windows_fmt_vformat_entry == null and self.windows_fmt_vformat_to_entry == null) return;
    __process_log.info("PE64 FMT PROBE: vformat_entry=0x{x} vformat_to_entry=0x{x} SaveConfig_invocations_interpreted={d} detailed_snapshots_emitted={d} probe_still_active={} pending_vformat_return=0x{x} pending_vformat_to_return=0x{x}; detailed input/buffer/output snapshots are limited to the first eight calls, while every matching SaveConfig formatter call uses the interpreter guard", .{
        self.windows_fmt_vformat_entry orelse 0,
        self.windows_fmt_vformat_to_entry orelse 0,
        self.windows_fmt_probe_calls,
        @min(self.windows_fmt_probe_calls, 8),
        self.windows_fmt_probe_active,
        self.windows_fmt_vformat_return orelse 0,
        self.windows_fmt_vformat_to_return orelse 0,
    });
}

pub fn configureWindowsCxaThrowEntry(self: *ElfState, entry: ?u64) void {
    self.windows_cxa_throw_entry = entry;
    rebuildWindowsCompatHookBox(self);
}

pub fn noteWindowsCxaThrowObserved(self: *ElfState) void {
    self.windows_cxa_throw_events +|= 1;
    // __cxa_throw(object, type_info*, destructor): the Itanium type_info
    // keeps its mangled name at +8, and [rsp] is the throw site. An
    // uncaught throw becomes std::terminate and then abort, so this is
    // the event an abort's report most often needs.
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    const throw_site = process_impl_guest_memory.read64(self, regs.rsp);
    var type_name: [96]u8 = undefined;
    const name_pointer = if (regs.rdx != 0) process_impl_guest_memory.read64(self, regs.rdx +| 8) else 0;
    const name_len = if (name_pointer != 0) process_impl_execution.copyGuestCString(self, name_pointer, type_name.len, &type_name) orelse 0 else 0;
    var site_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    process_impl_execution.noteNotableEvent(self, .cxx_throw, throw_site, "__cxa_throw type={s} object=0x{x} from 0x{x} ({s})", .{
        if (name_len != 0) type_name[0..name_len] else "<unreadable type name>",
        regs.rcx,
        throw_site,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, throw_site, &site_text),
    });
}

pub fn noteWindowsFileReadProvenance(
    self: *ElfState,
    guest_start: u64,
    byte_count: u64,
    file_offset: u64,
    api: []const u8,
    path: []const u8,
) void {
    if (guest_start == 0 or byte_count == 0) return;
    var record: __process_WindowsFileReadProvenance = .{
        .guest_start = guest_start,
        .byte_count = byte_count,
        .file_offset = file_offset,
        .step = process_impl_lifecycle.observedExecutionSteps(self),
    };
    record.setApi(api);
    record.setPath(path);
    self.windows_file_read_provenance[self.windows_file_read_provenance_next] = record;
    self.windows_file_read_provenance_next = (self.windows_file_read_provenance_next + 1) % __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY;
    self.windows_file_read_provenance_count = @min(
        self.windows_file_read_provenance_count + 1,
        __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY,
    );
    self.windows_file_read_provenance_total +|= 1;
}

pub fn windowsFileReadProvenanceAt(self: *const ElfState, address: u64) ?__process_WindowsFileReadProvenance {
    var age: usize = 0;
    while (age < self.windows_file_read_provenance_count) : (age += 1) {
        const index = (self.windows_file_read_provenance_next + __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY - 1 - age) % __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY;
        const record = self.windows_file_read_provenance[index];
        if (record.contains(address)) return record;
    }
    return null;
}

pub fn reportWindowsFileReadCandidates(self: *const ElfState) void {
    if (self.windows_file_read_provenance_count == 0) {
        __process_log.info("PE64 C++ invalid UTF-8 source candidates: no successful guest file reads were retained", .{});
        return;
    }
    var age: usize = 0;
    while (age < self.windows_file_read_provenance_count) : (age += 1) {
        const index = (self.windows_file_read_provenance_next + __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY - 1 - age) % __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY;
        const record = self.windows_file_read_provenance[index];
        __process_log.info("PE64 C++ invalid UTF-8 source candidate: newest_rank={d} api={s} path='{s}' guest=[0x{x},+0x{x}) file_offset=0x{x} read_step={d}", .{
            age,
            record.apiText(),
            record.pathText(),
            record.guest_start,
            record.byte_count,
            record.file_offset,
            record.step,
        });
    }
}

pub fn noteWindowsInvalidUtf8Throw(
    self: *ElfState,
    thrown_object: u64,
    type_name: []const u8,
    invalid_octet: u8,
    throw_site: u64,
    iterator_ref: u64,
    source_address: u64,
    source_readable: bool,
    source_byte: u8,
    source_byte_matches_exception: bool,
    consumer: u64,
    iterator_ref_consistent: bool,
    live_rsi: u64,
    saved_rsi_slot: u64,
    saved_rsi_readable: bool,
    saved_rsi: u64,
    saved_source_address: u64,
    saved_source_readable: bool,
    saved_source_byte: u8,
    saved_source_matches_exception: bool,
    live_source_address: u64,
    live_source_readable: bool,
    live_source_byte: u8,
    live_source_matches_exception: bool,
) void {
    self.windows_invalid_utf8_throw_events +|= 1;
    self.windows_invalid_utf8_last_source_address = source_address;
    self.windows_invalid_utf8_last_source_byte = source_byte;
    self.windows_invalid_utf8_last_source_byte_matches_exception = source_byte_matches_exception;
    self.windows_invalid_utf8_last_iterator_ref_consistent = iterator_ref_consistent;
    self.windows_invalid_utf8_last_saved_cursor_matches_exception = saved_source_matches_exception;
    self.windows_invalid_utf8_last_live_cursor_matches_exception = live_source_matches_exception;
    self.windows_invalid_utf8_last_consumer = consumer;
    var throw_text_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    var consumer_text_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const throw_text = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, throw_site, &throw_text_storage);
    const consumer_text = if (consumer == 0)
        "<not recovered>"
    else
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, consumer, &consumer_text_storage);
    const provenance = if (source_readable) windowsFileReadProvenanceAt(self, source_address) else null;
    if (provenance) |record| {
        self.windows_invalid_utf8_source_matches +|= 1;
        self.windows_invalid_utf8_last_file_offset = record.fileOffsetAt(source_address);
    }

    var sample: [32]u8 = [_]u8{0} ** 32;
    const sample_start = source_address -| 12;
    const sample_length: usize = if (source_readable) sample.len else 0;
    const sample_readable = sample_length != 0 and process_impl_execution.copyFromGuest(self, sample[0..sample_length], sample_start);
    __process_log.info("PE64 C++ invalid UTF-8 cursor candidates: live_rsi=0x{x} saved_rsi_slot=0x{x} saved_rsi_readable={} saved_rsi=0x{x} saved_source=0x{x} saved_source_readable={} saved_source_byte=0x{x} saved_source_matches_exception={} live_source=0x{x} live_source_readable={} live_source_byte=0x{x} live_source_matches_exception={}", .{
        live_rsi,
        saved_rsi_slot,
        saved_rsi_readable,
        saved_rsi,
        saved_source_address,
        saved_source_readable,
        saved_source_byte,
        saved_source_matches_exception,
        live_source_address,
        live_source_readable,
        live_source_byte,
        live_source_matches_exception,
    });
    if (provenance) |record| {
        __process_log.warn("PE64 C++ invalid UTF-8 provenance: type={s} invalid_octet=0x{x} selected_source_byte=0x{x} selected_source_matches_exception={} selected_source_readable={} selected_source=0x{x} selected_iterator_ref=0x{x} iterator_ref_consistent={} throw_site=0x{x} ({s}) consumer=0x{x} ({s}) file='{s}' api={s} file_offset=0x{x} read_step={d} sample_start=0x{x} sample_readable={} sample_bytes={any} thrown_object=0x{x} step={d}; diagnostic observer leaves __cxa_throw and guest control flow unchanged", .{
            type_name,
            invalid_octet,
            source_byte,
            source_byte_matches_exception,
            source_readable,
            source_address,
            iterator_ref,
            iterator_ref_consistent,
            throw_site,
            throw_text,
            consumer,
            consumer_text,
            record.pathText(),
            record.apiText(),
            record.fileOffsetAt(source_address),
            record.step,
            sample_start,
            sample_readable,
            if (sample_readable) sample[0..sample_length] else &.{},
            thrown_object,
            process_impl_lifecycle.observedExecutionSteps(self),
        });
    } else {
        __process_log.warn("PE64 C++ invalid UTF-8 provenance: type={s} invalid_octet=0x{x} selected_source_byte=0x{x} selected_source_matches_exception={} selected_source_readable={} selected_source=0x{x} selected_iterator_ref=0x{x} iterator_ref_consistent={} throw_site=0x{x} ({s}) consumer=0x{x} ({s}) file=<no matching recent guest file read> sample_start=0x{x} sample_readable={} sample_bytes={any} thrown_object=0x{x} step={d}; diagnostic observer leaves __cxa_throw and guest control flow unchanged", .{
            type_name,
            invalid_octet,
            source_byte,
            source_byte_matches_exception,
            source_readable,
            source_address,
            iterator_ref,
            iterator_ref_consistent,
            throw_site,
            throw_text,
            consumer,
            consumer_text,
            sample_start,
            sample_readable,
            if (sample_readable) sample[0..sample_length] else &.{},
            thrown_object,
            process_impl_lifecycle.observedExecutionSteps(self),
        });
    }
    if (provenance == null and self.windows_invalid_utf8_throw_events == 1) {
        reportWindowsFileReadCandidates(self);
    }
}

pub fn reportWindowsCxaThrowDiagnostics(self: *const ElfState) void {
    if (self.windows_cxa_throw_entry == null) return;
    __process_log.info("PE64 C++ THROW OBSERVER: entry=0x{x} calls={d} invalid_utf8_throws={d} source_matches_to_recent_file_reads={d} file_reads_seen={d} file_reads_retained={d}/{d} last_source=0x{x} last_source_byte=0x{x} last_source_byte_matches_exception={} last_iterator_ref_consistent={} last_saved_cursor_matches_exception={} last_live_cursor_matches_exception={} last_consumer=0x{x} last_file_offset_valid={} last_file_offset=0x{x}; observer is read-only and lets every original throw proceed", .{
        self.windows_cxa_throw_entry.?,
        self.windows_cxa_throw_events,
        self.windows_invalid_utf8_throw_events,
        self.windows_invalid_utf8_source_matches,
        self.windows_file_read_provenance_total,
        self.windows_file_read_provenance_count,
        __process_WINDOWS_FILE_READ_PROVENANCE_CAPACITY,
        self.windows_invalid_utf8_last_source_address,
        self.windows_invalid_utf8_last_source_byte,
        self.windows_invalid_utf8_last_source_byte_matches_exception,
        self.windows_invalid_utf8_last_iterator_ref_consistent,
        self.windows_invalid_utf8_last_saved_cursor_matches_exception,
        self.windows_invalid_utf8_last_live_cursor_matches_exception,
        self.windows_invalid_utf8_last_consumer,
        self.windows_invalid_utf8_last_file_offset != null,
        self.windows_invalid_utf8_last_file_offset orelse 0,
    });
}

pub fn noteWindowsUtf8CountInvalidInput(
    self: *ElfState,
    call_number: u64,
    view_address: u64,
    view_word0: u64,
    view_word1: u64,
    data_address: u64,
    length: u64,
    byte_offset: u64,
    invalid_byte: u8,
    caller: u64,
    caller_rsp: u64,
) void {
    self.windows_utf8_count_invalid_events +|= 1;
    var sample: [32]u8 = [_]u8{0} ** 32;
    const sample_offset = byte_offset -| 12;
    const sample_length: usize = @intCast(@min(@as(u64, sample.len), length -| sample_offset));
    const sample_readable = sample_length == 0 or process_impl_execution.copyFromGuest(
        self,
        sample[0..sample_length],
        data_address +| sample_offset,
    );
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const caller_description = if (caller == 0)
        "<unknown caller>"
    else
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller, &caller_text);
    if (call_number <= 8) __process_log.warn("PE64 XENIA UTF-8 INPUT: call={d} function=xe::utf8::count layout=length-data view=0x{x} raw_words=[0x{x},0x{x}] data=0x{x} length={d} invalid_byte=0x{x} byte_offset={d} caller=0x{x} ({s}) sample_offset={d} sample_readable={} sample_bytes={any} step={d}; captured before the original guest counter executes", .{
        call_number,
        view_address,
        view_word0,
        view_word1,
        data_address,
        length,
        invalid_byte,
        byte_offset,
        caller,
        caller_description,
        sample_offset,
        sample_readable,
        sample[0..sample_length],
        process_impl_lifecycle.observedExecutionSteps(self),
    });

    // In this Xenia binary, SaveConfig builds the `fmt::format` line at
    // [rsp+0xa0], passes its string_view at [rsp+0x150], and the view
    // reaches us with caller_rsp+0x158 == view_address. Preserve the raw
    // return-frame and vformat argument storage to show whether the
    // malformed bytes were already present in the produced std::string
    // or entered afterward. This is a bounded, fault-only snapshot.
    if (__process_std.mem.indexOf(u8, caller_description, "config::SaveConfig") != null) {
        const caller_frame_rsp = caller_rsp +| 8;
        const line_object_address = caller_frame_rsp +| 0xa0;
        const format_storage_address = caller_frame_rsp +| 0x1b0;
        const format_values_address = caller_frame_rsp +| 0x30;
        const config_value_address = caller_frame_rsp +| 0x170;
        const format_view_address = caller_frame_rsp +| 0x1c0;
        var line_object: [32]u8 = [_]u8{0} ** 32;
        var format_storage: [96]u8 = [_]u8{0} ** 96;
        var format_values: [32]u8 = [_]u8{0} ** 32;
        var config_value_object: [32]u8 = [_]u8{0} ** 32;
        var format_view: [16]u8 = [_]u8{0} ** 16;
        const line_object_readable = process_impl_execution.copyFromGuest(self, &line_object, line_object_address);
        const format_storage_readable = process_impl_execution.copyFromGuest(self, &format_storage, format_storage_address);
        const format_values_readable = process_impl_execution.copyFromGuest(self, &format_values, format_values_address);
        const config_value_readable = process_impl_execution.copyFromGuest(self, &config_value_object, config_value_address);
        const format_view_readable = process_impl_execution.copyFromGuest(self, &format_view, format_view_address);
        __process_log.warn("PE64 XENIA UTF-8 CALLER FRAME: caller_rsp=0x{x} caller_frame_rsp=0x{x} view_delta=0x{x} line_object=0x{x} readable={} bytes={any} vformat_storage=0x{x} readable={} bytes={any} format_values=0x{x} readable={} words=[0x{x},0x{x},0x{x},0x{x}] config_value=0x{x} readable={} words=[0x{x},0x{x},0x{x},0x{x}] format_view=0x{x} readable={} words=[0x{x},0x{x}] step={d}; SaveConfig offsets are from the loaded Xenia callsite disassembly", .{
            caller_rsp,
            caller_frame_rsp,
            view_address -| caller_rsp,
            line_object_address,
            line_object_readable,
            line_object,
            format_storage_address,
            format_storage_readable,
            format_storage,
            format_values_address,
            format_values_readable,
            __process_std.mem.readInt(u64, format_values[0..8], .little),
            __process_std.mem.readInt(u64, format_values[8..16], .little),
            __process_std.mem.readInt(u64, format_values[16..24], .little),
            __process_std.mem.readInt(u64, format_values[24..32], .little),
            config_value_address,
            config_value_readable,
            __process_std.mem.readInt(u64, config_value_object[0..8], .little),
            __process_std.mem.readInt(u64, config_value_object[8..16], .little),
            __process_std.mem.readInt(u64, config_value_object[16..24], .little),
            __process_std.mem.readInt(u64, config_value_object[24..32], .little),
            format_view_address,
            format_view_readable,
            __process_std.mem.readInt(u64, format_view[0..8], .little),
            __process_std.mem.readInt(u64, format_view[8..16], .little),
            process_impl_lifecycle.observedExecutionSteps(self),
        });
    }
}

pub fn reportWindowsUtf8CountDiagnostics(self: *const ElfState) void {
    if (self.windows_utf8_count_entry == null) return;
    __process_log.info("PE64 XENIA UTF-8 COUNT: entry=0x{x} calls_observed={d} malformed_inputs={d} entry_views_logged={d}; first eight string_view layouts, readability and UTF-8 scans are logged before the guest function runs unchanged", .{
        self.windows_utf8_count_entry.?,
        self.windows_utf8_count_events,
        self.windows_utf8_count_invalid_events,
        @min(self.windows_utf8_count_events, 8),
    });
}

pub fn configureWindowsCodecvtInEntry(self: *ElfState, entry: ?u64) void {
    self.windows_codecvt_in_entry = entry;
    rebuildWindowsCompatHookBox(self);
}

pub fn rebuildWindowsCompatHookBox(self: *ElfState) void {
    var points: __process_HookPoints = .{};
    if (self.windows_pthread_cond_wait_entry) |entry| points.add(entry);
    if (self.windows_pthread_cond_signal_entry) |entry| points.add(entry);
    if (self.windows_pthread_cond_broadcast_entry) |entry| points.add(entry);
    if (self.windows_utf8_find_any_of_entry) |entry| points.add(entry);
    if (self.windows_codecvt_in_entry) |entry| points.add(entry);
    if (self.windows_utf8_count_entry) |entry| points.add(entry);
    if (self.windows_cxa_throw_entry) |entry| points.add(entry);
    self.windows_compat_hook_points = points;
    if (self.block_jit != null and !self.block_jit_hook_filter_rebuilding) process_impl_block_jit.rebuildBlockJitHookFilter(self);
}

pub fn configureWindowsMutexLockEntry(self: *ElfState, entry: ?u64) void {
    self.windows_pthread_mutex_lock_intern_entry = entry;
    if (entry) |address| {
        __process_log.info("PE64 guest synchronization hooks: pthread_mutex_lock_intern=0x{x} source=executable-signature; a signalled condition waiter retakes its mutex through the image's own lock", .{address});
    }
}

pub fn configureWindowsConditionEntries(
    self: *ElfState,
    wait_entry: ?u64,
    signal_entry: ?u64,
    broadcast_entry: ?u64,
) void {
    self.windows_pthread_cond_wait_entry = wait_entry;
    self.windows_pthread_cond_signal_entry = signal_entry;
    self.windows_pthread_cond_broadcast_entry = broadcast_entry;
    rebuildWindowsCompatHookBox(self);
    if (wait_entry != null or signal_entry != null or broadcast_entry != null) {
        __process_log.info("PE64 guest synchronization hooks: pthread_cond_wait=0x{x} pthread_cond_signal=0x{x} pthread_cond_broadcast=0x{x} source=executable-signature", .{
            wait_entry orelse 0,
            signal_entry orelse 0,
            broadcast_entry orelse 0,
        });
    }
}

pub fn completeWindowsPthreadConditionRelock(self: *ElfState, mutex: u64, return_rip: ?u64) void {
    const entry = self.windows_pthread_mutex_lock_intern_entry.?;
    if (return_rip) |rip| process_impl_guest_memory.push(self, rip);
    process_impl_lifecycle.guestContextField(self, "regs").*.rcx = mutex;
    process_impl_lifecycle.guestContextField(self, "regs").*.rdx = 0xFFFF_FFFF;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = entry;
}

pub fn completeWindowsPthreadConditionReturn(self: *ElfState, return_rip: ?u64) void {
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = return_rip orelse process_impl_execution.readMemVal(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp, .bits64);
    // A tail-jump into the pthread routine inherits the caller's return
    // slot.  Since the shim returns directly to that caller, consume the
    // slot exactly as a real `ret` would.  Direct call sites are
    // intercepted before the executor pushes their return address and
    // must leave RSP unchanged.
    if (return_rip == null) process_impl_lifecycle.guestContextField(self, "regs").*.rsp +|= 8;
}

pub fn tryWindowsPthreadConditionShim(self: *ElfState, target: u64, return_rip: ?u64) bool {
    if (!self.windows_runtime_enabled or !self.windows_pthread_cond_native) return false;

    const owns_target = (self.windows_pthread_cond_timedwait_entry != null and target == (self.windows_pthread_cond_timedwait_entry orelse 0)) or
        (self.windows_pthread_cond_wait_entry != null and target == (self.windows_pthread_cond_wait_entry orelse 0)) or
        (self.windows_pthread_cond_signal_entry != null and target == (self.windows_pthread_cond_signal_entry orelse 0)) or
        (self.windows_pthread_cond_broadcast_entry != null and target == (self.windows_pthread_cond_broadcast_entry orelse 0));
    if (!owns_target) return false;
    // A dispatch level: an owner that must wait for the condition may
    // release the lock while it sleeps (`waitOwnerOnPthreadCondition`).
    var runtime_guard: ?__process_WindowsRuntimeLockGuard = if (self.parallel_guest_execution) process_impl_lifecycle.lockWindowsRuntimeForDispatch(self) else null;
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }

    if (self.windows_pthread_cond_timedwait_entry) |timed_entry| {
        if (target == timed_entry) return shimWindowsPthreadTimedCondition(self, return_rip);
    }

    if (self.windows_pthread_cond_wait_entry) |wait_entry| {
        if (target == wait_entry) {
            const result = waitWindowsGuestPthreadCondition(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx, process_impl_lifecycle.guestContextField(self, "regs").*.rdx, 0);
            switch (result) {
                .invalid => return false,
                .relock => {
                    self.windows_condition_hook_events +|= 1;
                    completeWindowsPthreadConditionRelock(self, process_impl_lifecycle.guestContextField(self, "regs").*.rdx, return_rip);
                    return true;
                },
                .blocked => {
                    self.windows_condition_hook_events +|= 1;
                    if (self.trace_windows_conditions) {
                        __process_log.info("PE64 guest condition shim: wait blocked cond=0x{x} mutex=0x{x} thread=0x{x} step={d}", .{
                            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                            process_impl_lifecycle.observedExecutionSteps(self),
                        });
                    }
                    return true;
                },
                .resumed => {
                    self.windows_condition_hook_events +|= 1;
                    process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
                    completeWindowsPthreadConditionReturn(self, return_rip);
                    if (self.trace_windows_conditions) {
                        __process_log.info("PE64 guest condition shim: wait resumed cond=0x{x} mutex=0x{x} thread=0x{x} step={d}", .{
                            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                            process_impl_lifecycle.observedExecutionSteps(self),
                        });
                    }
                    return true;
                },
            }
        }
    }

    if (self.windows_pthread_cond_signal_entry) |signal_entry| {
        if (target == signal_entry) {
            const woken = signalWindowsGuestCondition(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx, false);
            self.windows_condition_hook_events +|= 1;
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
            completeWindowsPthreadConditionReturn(self, return_rip);
            if (self.trace_windows_conditions) {
                __process_log.info("PE64 guest condition shim: signal cond=0x{x} woken={d} thread=0x{x} step={d}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                    woken,
                    process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                    process_impl_lifecycle.observedExecutionSteps(self),
                });
            }
            return true;
        }
    }

    if (self.windows_pthread_cond_broadcast_entry) |broadcast_entry| {
        if (target == broadcast_entry) {
            const woken = signalWindowsGuestCondition(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx, true);
            self.windows_condition_hook_events +|= 1;
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
            completeWindowsPthreadConditionReturn(self, return_rip);
            if (self.trace_windows_conditions) {
                __process_log.info("PE64 guest condition shim: broadcast cond=0x{x} woken={d} thread=0x{x} step={d}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                    woken,
                    process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                    process_impl_lifecycle.observedExecutionSteps(self),
                });
            }
            return true;
        }
    }

    return false;
}

pub fn initializeWindowsSrwLock(self: *ElfState, address: u64) bool {
    const lock = ensureWindowsSrwLock(self, address) orelse return false;
    lock.owner_thread_id = 0;
    process_impl_guest_memory.write64(self, address, 0);
    wakeWindowsGuestThreadsForSrwLock(self, address);
    return true;
}

pub fn windowsGuestStackCodeAddresses(self: *const ElfState, rsp: u64, out: *[__process_windows_srw_owner_stack_depth]u64) void {
    out.* = @splat(0);
    const words = 192;
    const bytes = process_impl_execution.guestMemoryConst(self, rsp, words * 8) orelse return;
    var found: usize = 0;
    var index: usize = 0;
    while (index < words and found < out.len) : (index += 1) {
        const value = __process_std.mem.readInt(u64, bytes[index * 8 ..][0..8], .little);
        if (value < self.image_low or value >= self.image_high) continue;
        if (!process_impl_guest_memory.windowsImageRangeOverlapsCode(self, value, 1)) continue;
        out[found] = value;
        found += 1;
    }
}

pub fn captureWindowsSrwOwnerStack(self: *ElfState, lock: *__process_WindowsSrwLock, rsp: u64) void {
    // Do not label a previous acquisition's frames as the current owner's.
    lock.owner_stack = @splat(0);
    lock.owner_stack_sampled = self.windows_srw_stack_capture_all or (lock.acquire_calls & 1023) == 1;
    if (lock.owner_stack_sampled) {
        windowsGuestStackCodeAddresses(self, rsp, &lock.owner_stack);
        self.windows_srw_stack_captures +|= 1;
    } else {
        self.windows_srw_stack_skipped +|= 1;
    }
}

pub fn tryWindowsSrwImport(self: *ElfState, name: []const u8, return_rip: ?u64) bool {
    if (!self.windows_srw_import_lane or return_rip == null or return_rip.? == 0 or
        process_impl_block_jit.blockJitTracingActive(self) or self.trace_calls or self.trace_windows_threads or self.trace_windows_messages or
        !process_impl_lifecycle.windowsFastCrtImportMayBypassRuntimeLock(self)) return false;
    const acquire = __process_std.mem.eql(u8, name, "AcquireSRWLockExclusive");
    const release = __process_std.mem.eql(u8, name, "ReleaseSRWLockExclusive");
    if (!acquire and !release) return false;
    var guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
    defer guard.unlock();
    const regs = process_impl_lifecycle.guestContextField(self, "regs");
    const address = regs.rcx;
    if (address == 0 or process_impl_execution.guestMemoryConst(self, address, 8) == null) return false;
    if (acquire) {
        const lock = ensureWindowsSrwLock(self, address) orelse return false;
        const me = process_impl_lifecycle.currentWindowsThreadId(self);
        if (lock.owner_thread_id != me and (lock.owner_thread_id != 0 or process_impl_guest_memory.read64(self, address) != 0)) return false;
        if (acquireWindowsSrwLock(self, address) != .acquired) return false;
        _ = self.windows_srw_fast_acquires.fetchAdd(1, .monotonic);
    } else {
        releaseWindowsSrwLock(self, address);
        regs.rax = 0;
        _ = self.windows_srw_fast_releases.fetchAdd(1, .monotonic);
    }
    regs.rip = return_rip.?;
    return true;
}

pub fn acquireWindowsSrwLock(self: *ElfState, address: u64) __state_WindowsSrwAcquireResult {
    const lock = ensureWindowsSrwLock(self, address) orelse return .invalid;
    const thread_id = process_impl_lifecycle.currentWindowsThreadId(self);
    if (lock.owner_thread_id == thread_id) {
        // Either a handoff this thread is now collecting, or the owner
        // context finishing a wait it queued for.
        if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null) lock.owner_waiting = false;
        // A waiter reaches this path after Rosette has granted ownership.
        // Keep later guest memory accesses after that grant in TSO mode.
        __process_tso_memory.memoryFence();
        lock.acquire_calls +|= 1;
        lock.last_acquire_step = process_impl_lifecycle.observedExecutionSteps(self);
        lock.last_acquire_thread_id = thread_id;
        endActiveWindowsSrwWaitAccounting(self);
        return .acquired;
    }
    if (lock.owner_thread_id != 0 or process_impl_guest_memory.read64(self, address) != 0) {
        self.windows_srw_lock_contentions +|= 1;
        lock.contentions +|= 1;
        if (self.windows_guest_wait_compatibility) {
            // Xenia's startup worker uses this lock boundary as a
            // cooperative scheduling point. Keep Rosetta moving while
            // retaining one authoritative owner record for the worker
            // that proceeds; ReleaseSRWLockExclusive accepts the same
            // policy below if the image-side owner was not observable.
            lock.owner_thread_id = thread_id;
            process_impl_guest_memory.write64(self, address, 1);
            self.windows_srw_compatibility_acquires +|= 1;
            __process_tso_memory.memoryFence();
            lock.acquire_calls +|= 1;
            lock.owner_acquired_step = process_impl_lifecycle.observedExecutionSteps(self);
            lock.last_acquire_step = lock.owner_acquired_step;
            lock.last_acquire_thread_id = thread_id;
            endActiveWindowsSrwWaitAccounting(self);
            return .acquired;
        }
        return .contended;
    }
    lock.owner_thread_id = thread_id;
    process_impl_guest_memory.write64(self, address, 1);
    __process_tso_memory.memoryFence();
    lock.acquire_calls +|= 1;
    lock.owner_acquired_step = process_impl_lifecycle.observedExecutionSteps(self);
    lock.last_acquire_step = lock.owner_acquired_step;
    lock.last_acquire_thread_id = thread_id;
    captureWindowsSrwOwnerStack(self, lock, process_impl_lifecycle.guestContextField(self, "regs").*.rsp);
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null) lock.owner_waiting = false;
    endActiveWindowsSrwWaitAccounting(self);
    return .acquired;
}

pub fn noteWindowsOwnerSrwWait(self: *ElfState, address: u64) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null) return;
    const index = windowsSrwLockIndex(self, address) orelse return;
    const lock = &self.windows_srw_locks[index];
    if (lock.owner_waiting) return;
    self.windows_srw_wait_sequence +|= 1;
    lock.owner_waiting = true;
    lock.owner_wait_sequence = self.windows_srw_wait_sequence;
}

pub fn windowsCriticalSectionIndex(self: *const ElfState, address: u64) ?usize {
    for (self.windows_critical_sections, 0..) |section, index| {
        if (section.address == address) return index;
    }
    return null;
}

pub fn ensureCriticalSection(self: *ElfState, address: u64, layout: __process_xbox_critical_section.Layout) ?*__process_WindowsSrwLock {
    const structure = __process_xbox_critical_section.fields(layout);
    if (address == 0 or process_impl_execution.guestMemoryConst(self, address, structure.size) == null) return null;
    if (windowsCriticalSectionIndex(self, address)) |index| {
        const section = &self.windows_critical_sections[index];
        if (section.critical_section_layout != layout) return null;
        return section;
    }
    var used: usize = 0;
    var free: ?*__process_WindowsSrwLock = null;
    for (&self.windows_critical_sections) |*section| {
        if (section.address != 0) {
            used += 1;
        } else if (free == null) {
            free = section;
        }
    }
    const section = free orelse return null;
    section.* = .{ .address = address, .critical_section_layout = layout };
    self.windows_critical_section_high_water = @max(self.windows_critical_section_high_water, used + 1);
    return section;
}

pub fn ensureWindowsCriticalSection(self: *ElfState, address: u64) ?*__process_WindowsSrwLock {
    return ensureCriticalSection(self, address, .windows);
}

pub fn publishCriticalSection(self: *ElfState, section: *const __process_WindowsSrwLock) void {
    const layout = section.critical_section_layout orelse return;
    const structure = __process_xbox_critical_section.fields(layout);
    if (process_impl_execution.guestMemoryConst(self, section.address, structure.size) == null) return;
    const waiters = windowsSrwWaiterCount(self, section.*);
    const depth = if (section.recursion == 0) 0 else section.recursion - 1;
    const lock_count: i32 = if (section.owner_thread_id == 0)
        -1
    else
        @intCast(@min(@as(u64, depth) + waiters, __process_std.math.maxInt(i32)));
    process_impl_guest_memory.write32(self, section.address + structure.lock_count, @bitCast(lock_count));
    switch (layout) {
        .windows => {
            process_impl_guest_memory.write32(self, section.address + structure.recursion, section.recursion);
            process_impl_guest_memory.write64(self, section.address + structure.owner, section.owner_thread_id);
        },
        .xbox360 => {
            process_impl_guest_memory.write32(self, section.address + structure.recursion, @byteSwap(section.recursion));
            process_impl_guest_memory.write32(self, section.address + structure.owner, @byteSwap(@as(u32, @truncate(section.owner_thread_id))));
        },
    }
}

pub fn retireIdleWindowsCriticalSection(self: *ElfState, section: *__process_WindowsSrwLock) void {
    if (section.owner_thread_id != 0 or section.owner_waiting) return;
    if (windowsSrwWaiterCount(self, section.*) != 0) return;
    section.* = .{};
}

pub fn enterWindowsCriticalSection(self: *ElfState, address: u64) __state_WindowsSrwAcquireResult {
    // Entry is an acquire: publish this executor's older stores before
    // claiming ownership, and the owner/recursion mirror before returning.
    __process_tso_memory.memoryFence();
    const section = ensureWindowsCriticalSection(self, address) orelse {
        self.windows_critical_section_untracked +|= 1;
        return .invalid;
    };
    const thread_id = process_impl_lifecycle.currentWindowsThreadId(self);
    const is_owner_context = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null;
    if (section.owner_thread_id == thread_id) {
        if (section.recursion == 0) {
            // A handoff this thread is collecting, or the owner context
            // finishing a wait it queued for.
            if (is_owner_context) section.owner_waiting = false;
            endActiveWindowsSrwWaitAccounting(self);
        }
        section.recursion +|= 1;
        self.windows_critical_section_enters +|= 1;
        publishCriticalSection(self, section);
        __process_tso_memory.memoryFence();
        return .acquired;
    }
    if (section.owner_thread_id != 0) {
        section.contentions +|= 1;
        self.windows_critical_section_contentions +|= 1;
        __process_tso_memory.memoryFence();
        return .contended;
    }
    section.owner_thread_id = thread_id;
    section.recursion = 1;
    if (is_owner_context) section.owner_waiting = false;
    self.windows_critical_section_enters +|= 1;
    publishCriticalSection(self, section);
    __process_tso_memory.memoryFence();
    return .acquired;
}

pub fn tryEnterWindowsCriticalSection(self: *ElfState, address: u64) bool {
    return switch (enterWindowsCriticalSection(self, address)) {
        .acquired => true,
        // Untracked: run unexcluded, as an untracked Enter does.
        .invalid => true,
        .contended => false,
    };
}

pub fn noteWindowsOwnerCriticalSectionWait(self: *ElfState, address: u64) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null) return;
    const index = windowsCriticalSectionIndex(self, address) orelse return;
    const section = &self.windows_critical_sections[index];
    if (section.owner_waiting) return;
    self.windows_srw_wait_sequence +|= 1;
    section.owner_waiting = true;
    section.owner_wait_sequence = self.windows_srw_wait_sequence;
}

pub fn leaveWindowsCriticalSection(self: *ElfState, address: u64) void {
    const index = windowsCriticalSectionIndex(self, address) orelse {
        // Never entered through Rosette (an untracked enter, or a leave
        // without an enter): nothing to release.
        self.windows_critical_section_release_mismatches +|= 1;
        return;
    };
    const section = &self.windows_critical_sections[index];
    if (section.critical_section_layout != .windows or
        section.owner_thread_id != process_impl_lifecycle.currentWindowsThreadId(self) or section.recursion == 0)
    {
        self.windows_critical_section_release_mismatches +|= 1;
        return;
    }
    // A release must make protected guest writes visible before waking or
    // handing ownership to another executor.
    __process_tso_memory.memoryFence();
    section.recursion -= 1;
    if (section.recursion != 0) {
        publishCriticalSection(self, section);
        __process_tso_memory.memoryFence();
        return;
    }
    handOffWindowsSrwLock(self, section, address);
    publishCriticalSection(self, section);
    retireIdleWindowsCriticalSection(self, section);
    __process_tso_memory.memoryFence();
}

pub fn xboxHostBacked(self: *ElfState, address: u64, count: u64) bool {
    if (process_impl_guest_memory.addrToOffset(self, address)) |offset| return offset <= self.mem.len and count <= self.mem.len - offset;
    return process_impl_guest_memory.windowsMappedMemory(self, address, count) != null;
}

pub fn xboxLockWord(self: *ElfState, section: u64) ?[]u8 {
    const address = section + __process_xbox_critical_section.Offset.lock_count;
    if (process_impl_guest_memory.addrToOffset(self, address)) |offset| {
        const begin: usize = @intCast(offset);
        if (begin > self.mem.len or 4 > self.mem.len - begin) return null;
        return self.mem[begin .. begin + 4];
    }
    return process_impl_guest_memory.windowsMappedMemory(self, address, 4);
}

pub fn xboxLockFetchAdd(self: *ElfState, section: u64, delta: i32) i32 {
    const address = section + __process_xbox_critical_section.Offset.lock_count;
    const addend: u32 = @bitCast(delta);
    if (xboxLockWord(self, section)) |bytes| {
        if (__process_tso_memory.fetchAddAny(u32, bytes, addend)) |previous| {
            process_impl_execution.noteAtomicMemoryWrite(self, address, .bits32, previous +% addend);
            return @bitCast(previous);
        }
    }
    // The call was decoded only for a backed section, so this is the
    // serialized path any atomic takes when a host atomic cannot run.
    var fallback_guard = process_impl_execution.beginSerializedAtomicFallback(self);
    defer if (fallback_guard) |*guard| guard.unlock();
    const previous = process_impl_guest_memory.read32(self, address);
    process_impl_guest_memory.write32(self, address, previous +% addend);
    return @bitCast(previous);
}

pub fn xboxLockCompareExchange(self: *ElfState, section: u64, expected: i32, desired: i32) bool {
    const address = section + __process_xbox_critical_section.Offset.lock_count;
    if (xboxLockWord(self, section)) |bytes| {
        if (__process_tso_memory.compareExchangeAny(u32, bytes, @bitCast(expected), @bitCast(desired))) |result| {
            if (result.exchanged) process_impl_execution.noteAtomicMemoryWrite(self, address, .bits32, @as(u32, @bitCast(desired)));
            return result.exchanged;
        }
    }
    var fallback_guard = process_impl_execution.beginSerializedAtomicFallback(self);
    defer if (fallback_guard) |*guard| guard.unlock();
    if (process_impl_guest_memory.read32(self, address) != @as(u32, @bitCast(expected))) return false;
    process_impl_guest_memory.write32(self, address, @bitCast(desired));
    return true;
}

pub fn decodeXboxCriticalSectionCall(self: *ElfState) ?__state_XboxCriticalSectionCall {
    const context = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
    if (!xboxHostBacked(self, context, __process_PPC_CONTEXT_VIRTUAL_MEMBASE + 8)) return null;
    const membase = process_impl_guest_memory.read64(self, context + __process_PPC_CONTEXT_VIRTUAL_MEMBASE);
    if (membase == 0) return null;
    const guest: u32 = @truncate(process_impl_guest_memory.read64(self, context + __process_ppcContextGpr(3)));
    const argument: u32 = @truncate(process_impl_guest_memory.read64(self, context + __process_ppcContextGpr(4)));
    var section: u64 = 0;
    if (guest != 0) {
        section = process_impl_kernel_services.xeniaGuestVirtualAddress(membase, guest);
        if (!xboxHostBacked(self, section, __process_xbox_critical_section.Offset.size)) return null;
    }
    return .{ .context = context, .membase = membase, .guest = guest, .argument = argument, .section = section };
}

pub fn xboxCurrentKthread(self: *ElfState, call: __state_XboxCriticalSectionCall) u32 {
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    if (slot) |index| {
        const thread = &self.windows_guest_threads[index];
        if (thread.xbox_kthread != 0 and thread.xbox_kthread_context == call.context) return thread.xbox_kthread;
    }
    const pcr: u32 = @truncate(process_impl_guest_memory.read64(self, call.context + __process_ppcContextGpr(13)));
    if (pcr != 0) {
        const address = process_impl_kernel_services.xeniaGuestVirtualAddress(call.membase, pcr +% __process_xbox_critical_section.pcr_current_thread);
        if (xboxHostBacked(self, address, 4)) {
            const kthread = @byteSwap(process_impl_guest_memory.read32(self, address));
            if (kthread != 0) {
                if (slot) |index| {
                    const thread = &self.windows_guest_threads[index];
                    thread.xbox_kthread = kthread;
                    thread.xbox_kthread_context = call.context;
                }
                return kthread;
            }
        }
    }
    // No readable PCR: a stable identity no guest pointer can be, so
    // recursion and ownership still work for this thread.
    __process_xbox_critical_section.Stats.bump(&self.xbox_critical_section_stats.synthetic_owners);
    return if (slot) |index| 0xFFFF_F000 | @as(u32, @intCast(index)) else 0xFFFF_FFFE;
}

pub fn xboxPendingWait(self: *ElfState) u64 {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| return self.windows_guest_threads[index].xbox_cs_wait;
    return self.owner_xbox_cs_wait;
}

pub fn storeXboxCallResult(self: *ElfState, call: __state_XboxCriticalSectionCall, value: u32) void {
    const widened: i64 = @as(i32, @bitCast(value));
    process_impl_guest_memory.write64(self, call.context + __process_ppcContextGpr(3), @bitCast(widened));
}

pub fn awaitXboxCriticalSection(self: *ElfState, call: __state_XboxCriticalSectionCall, me: u32) __state_XboxWait {
    const access: __state_XboxSectionAccess = .{ .state = self, .section = call.section };
    const stats = &self.xbox_critical_section_stats;
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
        const thread = &self.windows_guest_threads[index];
        const granted = thread.xbox_cs_granted;
        if (granted or __process_xbox_critical_section.consumeSignal(access)) {
            if (!granted) __process_xbox_critical_section.Stats.bump(&stats.signals_consumed);
            thread.xbox_cs_granted = false;
            thread.xbox_cs_wait = 0;
            endActiveWindowsSrwWaitAccounting(self);
            __process_xbox_critical_section.take(access, me);
            return .acquired;
        }
        thread.xbox_cs_wait = call.section;
        if (!blockWindowsGuestThreadOnSrwLock(self, call.section)) return .unparkable;
        __process_xbox_critical_section.Stats.bump(&stats.parks);
        return .parked;
    }
    const granted = self.owner_xbox_cs_granted;
    if (granted or __process_xbox_critical_section.consumeSignal(access)) {
        if (!granted) __process_xbox_critical_section.Stats.bump(&stats.signals_consumed);
        self.owner_xbox_cs_granted = false;
        self.owner_xbox_cs_wait = 0;
        self.owner_xbox_cs_sequence = 0;
        __process_xbox_critical_section.take(access, me);
        return .acquired;
    }
    if (self.owner_xbox_cs_wait != call.section) {
        self.owner_xbox_cs_wait = call.section;
        self.windows_srw_wait_sequence +|= 1;
        self.owner_xbox_cs_sequence = self.windows_srw_wait_sequence;
        __process_xbox_critical_section.Stats.bump(&stats.parks);
    }
    return .owner_parked;
}

pub fn releaseXboxCriticalSectionWaiter(self: *ElfState, section: u64) void {
    const stats = &self.xbox_critical_section_stats;
    var chosen: ?usize = null;
    var chosen_sequence: u64 = __process_std.math.maxInt(u64);
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status != .blocked or thread.blocked_srw_lock != section or
            thread.xbox_cs_wait != section or thread.xbox_cs_granted)
        {
            continue;
        }
        if (thread.srw_wait_sequence < chosen_sequence) {
            chosen = index;
            chosen_sequence = thread.srw_wait_sequence;
        }
    }
    if (self.owner_xbox_cs_wait == section and !self.owner_xbox_cs_granted and
        self.owner_xbox_cs_sequence < chosen_sequence)
    {
        self.owner_xbox_cs_granted = true;
        __process_xbox_critical_section.Stats.bump(&stats.grants);
        process_impl_lifecycle.noteWindowsThreadWake(self);
        return;
    }
    if (chosen) |index| {
        const thread = &self.windows_guest_threads[index];
        thread.xbox_cs_granted = true;
        thread.status = .runnable;
        thread.blocked_srw_lock = 0;
        thread.srw_wait_sequence = 0;
        process_impl_lifecycle.noteWindowsGuestWorkerWake(self, index);
        self.windows_thread_unblocks +|= 1;
        __process_xbox_critical_section.Stats.bump(&stats.grants);
        return;
    }
    __process_xbox_critical_section.setSignal(__state_XboxSectionAccess{ .state = self, .section = section });
    __process_xbox_critical_section.Stats.bump(&stats.signals);
}

pub fn completeXboxCriticalSectionCall(self: *ElfState, api: __process_xbox_critical_section.Export, return_rip: u64) bool {
    const regs = process_impl_lifecycle.guestContextField(self, "regs");
    regs.rip = return_rip;
    regs.rsp +%= 8;
    self.xbox_critical_section_hooks.noteHandled(api);
    return true;
}

pub fn handleXboxCriticalSectionExport(self: *ElfState, api: __process_xbox_critical_section.Export) bool {
    const rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp;
    const return_rip = if (xboxHostBacked(self, rsp, 8)) process_impl_guest_memory.read64(self, rsp) else 0;
    const decoded = if (return_rip != 0) decodeXboxCriticalSectionCall(self) else null;
    const call = decoded orelse {
        self.xbox_critical_section_hooks.noteFallback(api);
        return false;
    };
    const stats = &self.xbox_critical_section_stats;
    if (call.section == 0) {
        if (api == .initialize or api == .initialize_and_spin_count) {
            self.xbox_critical_section_hooks.noteFallback(api);
            return false;
        }
        // Xenia logs a null section and returns; TryEnter pretends.
        __process_xbox_critical_section.Stats.bump(&stats.null_sections);
        if (api == .try_enter) storeXboxCallResult(self, call, 1);
        return completeXboxCriticalSectionCall(self, api, return_rip);
    }
    const access: __state_XboxSectionAccess = .{ .state = self, .section = call.section };
    switch (api) {
        .initialize, .initialize_and_spin_count => {
            __process_xbox_critical_section.initialize(access, if (api == .initialize) 0 else call.argument);
            __process_xbox_critical_section.Stats.bump(&stats.initializations);
            if (api == .initialize_and_spin_count) storeXboxCallResult(self, call, 0); // X_STATUS_SUCCESS
        },
        .enter => {
            const me = xboxCurrentKthread(self, call);
            if (xboxPendingWait(self) != call.section) {
                switch (__process_xbox_critical_section.enter(access, me)) {
                    .acquired => {
                        __process_xbox_critical_section.Stats.bump(&stats.acquired);
                        return completeXboxCriticalSectionCall(self, api, return_rip);
                    },
                    .recursed => {
                        __process_xbox_critical_section.Stats.bump(&stats.recursed);
                        return completeXboxCriticalSectionCall(self, api, return_rip);
                    },
                    .counted => __process_xbox_critical_section.Stats.bump(&stats.counted),
                }
            }
            // Counted into lock_count: the wait is the scheduler's.
            var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
            defer runtime_guard.unlock();
            switch (awaitXboxCriticalSection(self, call, me)) {
                .acquired => {},
                // RIP and RSP stay at the trampoline; the call re-runs
                // when this thread wakes and collects its grant.
                .parked, .unparkable => return true,
                .owner_parked => {
                    _ = process_impl_windows_ui.parkForGuestWait(self, null, .wake);
                    return true;
                },
            }
        },
        .try_enter => {
            const acquired = __process_xbox_critical_section.tryEnter(access, xboxCurrentKthread(self, call));
            if (!acquired) __process_xbox_critical_section.Stats.bump(&stats.try_failures);
            storeXboxCallResult(self, call, @intFromBool(acquired));
        },
        .leave => {
            const result = __process_xbox_critical_section.leave(access, xboxCurrentKthread(self, call));
            if (!result.owner_matched) __process_xbox_critical_section.Stats.bump(&stats.leave_mismatches);
            if (result.release == .waiters) {
                var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
                defer runtime_guard.unlock();
                releaseXboxCriticalSectionWaiter(self, call.section);
            }
        },
    }
    return completeXboxCriticalSectionCall(self, api, return_rip);
}

pub fn windowsThreadForXboxKthread(self: *const ElfState, kthread: u32) ?*const __process_WindowsGuestThread {
    if (kthread == 0) return null;
    for (self.windows_guest_threads) |*thread| {
        if (thread.status != .vacant and thread.xbox_kthread == kthread) return thread;
    }
    return null;
}

pub fn initializeWindowsCriticalSection(self: *ElfState, address: u64) void {
    if (windowsCriticalSectionIndex(self, address)) |index| {
        const section = &self.windows_critical_sections[index];
        if (section.critical_section_layout != .windows) return;
        section.owner_thread_id = 0;
        section.recursion = 0;
        retireIdleWindowsCriticalSection(self, section);
    }
    if (address != 0 and process_impl_execution.guestMemoryConst(self, address, 24) != null) {
        const lock_count: i32 = -1;
        process_impl_guest_memory.write32(self, address + 8, @bitCast(lock_count));
        process_impl_guest_memory.write32(self, address + 12, 0);
        process_impl_guest_memory.write64(self, address + 16, 0);
    }
}

pub fn deleteWindowsCriticalSection(self: *ElfState, address: u64) void {
    const index = windowsCriticalSectionIndex(self, address) orelse return;
    const section = &self.windows_critical_sections[index];
    if (section.critical_section_layout != .windows) return;
    section.owner_thread_id = 0;
    section.recursion = 0;
    section.owner_waiting = false;
    wakeWindowsGuestThreadsForSrwLock(self, address);
    section.* = .{};
}

pub fn handOffWindowsSrwLock(self: *ElfState, lock: *__process_WindowsSrwLock, address: u64) void {
    noteWindowsWaitSignal(self, address);
    var chosen: ?usize = null;
    var chosen_sequence: u64 = __process_std.math.maxInt(u64);
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status != .blocked or thread.blocked_srw_lock != address) continue;
        if (thread.thread_id == 0) {
            // No identity to hand ownership to. Wake it to race, which
            // is what every waiter did before.
            thread.status = .runnable;
            process_impl_lifecycle.noteWindowsGuestWorkerWake(self, index);
            thread.blocked_srw_lock = 0;
            self.windows_thread_unblocks +|= 1;
            continue;
        }
        if (thread.srw_wait_sequence < chosen_sequence) {
            chosen = index;
            chosen_sequence = thread.srw_wait_sequence;
        }
    }
    // A critical section's first word is a dispatch header, not an SRW
    // owner word; publish its ABI-specific owner through the common CS
    // mirror instead.
    const address_is_guest = lock.critical_section_layout == null and process_impl_execution.guestMemoryConst(self, address, 8) != null;
    if (lock.owner_waiting and lock.owner_wait_sequence < chosen_sequence) {
        lock.owner_thread_id = 1;
        lock.owner_waiting = false;
        lock.owner_acquired_step = process_impl_lifecycle.observedExecutionSteps(self);
        captureWindowsSrwOwnerStack(self, lock, self.regs.rsp);
        if (address_is_guest) process_impl_guest_memory.write64(self, address, 1);
        lock.handoffs +|= 1;
        noteWindowsLockHandoff(self, lock, false);
        // In parallel mode the owner may be asleep in `parkForGuestWait`
        // waiting for exactly this.
        process_impl_lifecycle.noteWindowsThreadWake(self);
        return;
    }
    if (chosen) |index| {
        const thread = &self.windows_guest_threads[index];
        lock.owner_thread_id = thread.thread_id;
        lock.owner_acquired_step = process_impl_lifecycle.observedExecutionSteps(self);
        // Parked at its AcquireSRWLockExclusive call, so its saved stack
        // is the one it will hold the lock from.
        captureWindowsSrwOwnerStack(self, lock, thread.context.regs.rsp);
        if (address_is_guest) process_impl_guest_memory.write64(self, address, 1);
        thread.status = .runnable;
        process_impl_lifecycle.noteWindowsGuestWorkerWake(self, index);
        thread.blocked_srw_lock = 0;
        thread.blocked_wait_handle = 0;
        thread.blocked_wait_timeout = 0;
        thread.blocked_wait_deadline = 0;
        thread.wait_resume_timeout = false;
        thread.srw_wait_sequence = 0;
        lock.handoffs +|= 1;
        noteWindowsLockHandoff(self, lock, true);
        self.windows_thread_unblocks +|= 1;
        // Run the new owner next. It holds the lock from this instant,
        // and every other contender now waits on a thread the circular
        // scan might not reach for a whole rotation. On the 2026-09-13
        // run Xenia's global mutex changed hands 67,362 times and four
        // threads sat queued on it at exit: a short critical section
        // turned into a convoy that every kernel call joined.
        self.windows_preferred_next_guest_thread = index;
        process_impl_lifecycle.requestWindowsGuestSliceYield(self);
        return;
    }
    lock.owner_thread_id = 0;
    if (address_is_guest) process_impl_guest_memory.write64(self, address, 0);
}

pub fn noteWindowsLockHandoff(self: *ElfState, lock: *const __process_WindowsSrwLock, directed: bool) void {
    // Only Win32 sections have records; an Xbox section's handoff is a
    // grant, counted by `releaseXboxCriticalSectionWaiter`.
    if (lock.critical_section_layout != null) {
        self.windows_critical_section_handoffs +|= 1;
        return;
    }
    self.windows_srw_handoffs +|= 1;
    if (directed) self.windows_srw_directed_handoffs +|= 1;
}

pub fn describeWindowsSrwOwner(self: *const ElfState, owner_thread_id: u64, buffer: []u8) []const u8 {
    if (owner_thread_id == 0) return "none";
    if (owner_thread_id == 1) return "owner-context (the process's initial thread)";
    for (self.windows_guest_threads) |*thread| {
        if (thread.status == .vacant or thread.thread_id != owner_thread_id) continue;
        return __process_std.fmt.bufPrint(buffer, "'{s}' {s}", .{
            if (thread.name_len != 0) thread.nameText() else "<unnamed by the guest>",
            @tagName(thread.status),
        }) catch "a thread whose name did not fit";
    }
    return "a thread id no live record carries";
}

pub fn windowsSrwWaiterCount(self: *const ElfState, lock: __process_WindowsSrwLock) u32 {
    var waiters: u32 = @intFromBool(lock.owner_waiting);
    for (self.windows_guest_threads) |thread| {
        if (thread.status == .blocked and thread.blocked_srw_lock == lock.address) waiters += 1;
    }
    return waiters;
}

pub fn releaseWindowsSrwLock(self: *ElfState, address: u64) void {
    const thread_id = process_impl_lifecycle.currentWindowsThreadId(self);
    // Publish the guest mutex's owner/recursion updates before making
    // another execution context runnable.
    __process_tso_memory.memoryFence();
    if (windowsSrwLockIndex(self, address)) |index| {
        const lock = &self.windows_srw_locks[index];
        lock.release_calls +|= 1;
        lock.last_release_step = process_impl_lifecycle.observedExecutionSteps(self);
        lock.last_release_thread_id = thread_id;
        if (lock.owner_thread_id == 0 or lock.owner_thread_id == thread_id or self.windows_guest_wait_compatibility) {
            handOffWindowsSrwLock(self, lock, address);
        } else {
            lock.release_mismatches +|= 1;
            self.windows_srw_lock_release_mismatches +|= 1;
        }
        __process_tso_memory.memoryFence();
        return;
    }
    // A lock can be released after an image-side zeroing operation that
    // Rosetta did not observe. Keep the guest word recoverable, but do
    // not manufacture an ownership record for it.
    if (process_impl_execution.guestMemoryConst(self, address, 8) != null) {
        process_impl_guest_memory.write64(self, address, 0);
        wakeWindowsGuestThreadsForSrwLock(self, address);
    }
    __process_tso_memory.memoryFence();
}

pub fn yieldXeniaGlobalMutexForBackoff(self: *ElfState) bool {
    if (!self.parallel_guest_execution or self.windows_guest_wait_compatibility) return false;
    const address = self.xenia_global_mutex_address orelse return false;
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return false;
    if (slot >= self.windows_guest_threads.len) return false;
    const thread = &self.windows_guest_threads[slot];
    if (thread.thread_id == 0) return false;
    if (thread.xenia_global_lend) |lend| return collectXeniaGlobalMutex(self, address, thread, lend);
    const index = windowsSrwLockIndex(self, address) orelse return false;
    const lock = &self.windows_srw_locks[index];
    if (lock.owner_thread_id != thread.thread_id) return false;
    if (windowsSrwWaiterCount(self, lock.*) == 0) return false;
    if (process_impl_execution.guestMemoryConst(self, address, 16) == null) return false;
    const owner = process_impl_guest_memory.read32(self, address + __process_XENIA_GLOBAL_MUTEX_OWNER_OFFSET);
    const recursion = process_impl_guest_memory.read32(self, address + __process_XENIA_GLOBAL_MUTEX_RECURSION_OFFSET);
    if (owner != @as(u32, @truncate(thread.thread_id)) or recursion == 0) return false;
    // Only the loops that mean to release the lock while they wait. A
    // critical section that happens to sleep keeps its lock.
    if (!xeniaWaitLoopOnStack(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp)) return false;

    const lend: __process_XeniaGlobalLend = .{ .owner = owner, .recursion = recursion };
    thread.xenia_global_lend = lend;
    // What `xe_global_mutex::unlock` leaves behind at depth zero, so the
    // borrower's `lock` starts from a released mutex.
    process_impl_guest_memory.write32(self, address + __process_XENIA_GLOBAL_MUTEX_RECURSION_OFFSET, 0);
    process_impl_guest_memory.write32(self, address + __process_XENIA_GLOBAL_MUTEX_OWNER_OFFSET, 0);
    self.xenia_global_mutex_lends +|= 1;
    if (self.xenia_global_mutex_lends == 1 or self.xenia_global_mutex_lends & (self.xenia_global_mutex_lends - 1) == 0) {
        var name_text: [96]u8 = undefined;
        __process_log.info("PE64 XENIA GLOBAL MUTEX LEND: thread='{s}' (id {d}) backed off at depth {d} with {d} waiter(s); lent the lock for the back-off and restores depth {d} when it is handed back. lends={d} returned={d}; see the owner_stack lines under PE64 LOCK CONTENTION for the frame that held it", .{
            describeWindowsSrwOwner(self, thread.thread_id, &name_text),
            thread.thread_id,
            recursion,
            windowsSrwWaiterCount(self, lock.*),
            recursion,
            self.xenia_global_mutex_lends,
            self.xenia_global_mutex_lend_returns,
        });
    }
    releaseWindowsSrwLock(self, address);
    return collectXeniaGlobalMutex(self, address, thread, lend);
}

pub fn xeniaWaitLoopOnStack(self: *const ElfState, rsp: u64) bool {
    if (self.guest_symbol_resolver == null) return true;
    const words = 64;
    const bytes = process_impl_execution.guestMemoryConst(self, rsp, words * 8) orelse return false;
    var name_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    for (0..words) |index| {
        const value = __process_std.mem.readInt(u64, bytes[index * 8 ..][0..8], .little);
        if (value < self.image_low or value >= self.image_high) continue;
        const symbol = process_impl_kernel_services.guestSymbolAt(self, value, &name_storage) orelse continue;
        inline for (.{ "EntryTable::GetOrCreate", "EntryTable11GetOrCreate", "Module::LookupSymbol", "Module12LookupSymbol", "Module::DeclareSymbol", "Module13DeclareSymbol", "Module::DefineSymbol", "Module12DefineSymbol" }) |loop| {
            if (__process_std.mem.indexOf(u8, symbol.name, loop) != null) return true;
        }
    }
    return false;
}

pub fn collectXeniaGlobalMutex(self: *ElfState, address: u64, thread: *__process_WindowsGuestThread, lend: __process_XeniaGlobalLend) bool {
    switch (acquireWindowsSrwLock(self, address)) {
        .acquired => {
            process_impl_guest_memory.write32(self, address + __process_XENIA_GLOBAL_MUTEX_OWNER_OFFSET, lend.owner);
            process_impl_guest_memory.write32(self, address + __process_XENIA_GLOBAL_MUTEX_RECURSION_OFFSET, lend.recursion);
            __process_tso_memory.memoryFence();
            thread.xenia_global_lend = null;
            self.xenia_global_mutex_lend_returns +|= 1;
            return false;
        },
        .contended => {
            // Queued like any other acquirer; the handoff that wakes it
            // makes it the owner, and the retried call lands above.
            if (blockWindowsGuestThreadOnSrwLock(self, address)) return true;
            // A worker that cannot block retries the call: the depth it
            // lent must not run without the lock.
            process_impl_lifecycle.requestWindowsGuestSliceYield(self);
            return true;
        },
        .invalid => {
            thread.xenia_global_lend = null;
            return false;
        },
    }
}

pub fn blockWindowsGuestThreadOnSrwLock(self: *ElfState, address: u64) bool {
    const index = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return false;
    const thread = &self.windows_guest_threads[index];
    if (thread.status != .running) return false;
    thread.status = .blocked;
    thread.blocked_srw_lock = address;
    self.windows_srw_wait_sequence +|= 1;
    thread.srw_wait_sequence = self.windows_srw_wait_sequence;
    thread.blocked_condition = 0;
    thread.blocked_condition_mutex = 0;
    thread.blocked_wait_handle = 0;
    thread.blocked_wait_timeout = 0;
    thread.blocked_wait_deadline = 0;
    thread.wait_resume = false;
    thread.wait_resume_handle = 0;
    thread.wait_resume_timeout = false;
    beginWindowsWaitAccounting(self, thread, address, .srw_lock, 0, 0);
    self.windows_thread_blocks +|= 1;
    if (self.trace_windows_threads and
        (self.windows_thread_blocks <= 8 or self.windows_thread_blocks % 1024 == 0))
    {
        __process_log.info("Windows guest worker blocked on SRW lock: handle=0x{x} thread_id={d} lock=0x{x} rip=0x{x} blocks={d}", .{
            thread.handle,
            thread.thread_id,
            address,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            self.windows_thread_blocks,
        });
    }
    return true;
}

pub fn waitWindowsGuestCondition(self: *ElfState, address: u64, mutex_address: u64) __state_WindowsConditionWaitResult {
    return waitWindowsGuestConditionUntil(self, address, mutex_address, 0);
}

pub fn waitWindowsGuestConditionUntil(self: *ElfState, address: u64, mutex_address: u64, deadline: u64) __state_WindowsConditionWaitResult {
    return waitWindowsGuestConditionFor(self, address, mutex_address, deadline, false);
}

pub fn waitWindowsGuestPthreadCondition(self: *ElfState, address: u64, mutex_address: u64, deadline: u64) __state_WindowsConditionWaitResult {
    return waitWindowsGuestConditionFor(self, address, mutex_address, deadline, true);
}

pub fn waitWindowsGuestConditionFor(self: *ElfState, address: u64, mutex_address: u64, deadline: u64, allow_relock: bool) __state_WindowsConditionWaitResult {
    const index = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse
        return waitOwnerOnPthreadCondition(self, address, mutex_address, deadline, allow_relock);
    if (address == 0 or self.windows_guest_threads[index].status != .running) return .invalid;
    self.windows_condition_wait_calls +|= 1;

    if (self.windows_guest_threads[index].condition_resume) {
        const mutex = self.windows_guest_threads[index].blocked_condition_mutex;
        // An untimed wait on a normal mutex retakes it through the
        // image's own `pthread_mutex_lock`. Emulating that acquisition
        // here parked the waiter on the mutex's event outside a real
        // wait, where a signal already given could not reach it, and on
        // 2026-09-21 the Shader Storage Writer and Xenia's GPU thread
        // ended up asleep on the same event with nobody left to set it.
        if (allow_relock and mutex != 0 and deadline == 0 and !self.windows_guest_threads[index].condition_resume_timeout and
            self.windows_pthread_mutex_lock_intern_entry != null)
        {
            if (windowsPthreadMutexImpl(self, mutex)) |impl| {
                if (process_impl_guest_memory.read32(self, impl + 4) == 0) {
                    self.windows_guest_threads[index].condition_resume = false;
                    self.windows_guest_threads[index].condition_mutex_contended = false;
                    self.windows_guest_threads[index].blocked_condition_mutex = 0;
                    self.windows_condition_wait_resumes +|= 1;
                    self.windows_condition_relocks +|= 1;
                    endWindowsWaitAccounting(self, &self.windows_guest_threads[index], .signaled);
                    return .relock;
                }
            }
        }
        if (mutex == 0) {
            const timed_out = self.windows_guest_threads[index].condition_resume_timeout;
            self.windows_guest_threads[index].condition_resume = false;
            self.windows_condition_wait_resumes +|= 1;
            endWindowsWaitAccounting(
                self,
                &self.windows_guest_threads[index],
                if (timed_out) .timed_out else .signaled,
            );
            return .resumed;
        }

        switch (acquireWindowsGuestPthreadMutex(self, mutex, self.windows_guest_threads[index].condition_mutex_contended)) {
            .acquired => {
                const timed_out = self.windows_guest_threads[index].condition_resume_timeout;
                self.windows_guest_threads[index].condition_mutex_contended = false;
                self.windows_guest_threads[index].condition_resume = false;
                self.windows_guest_threads[index].blocked_condition_mutex = 0;
                self.windows_guest_threads[index].wait_resume = false;
                self.windows_guest_threads[index].wait_resume_handle = 0;
                self.windows_condition_wait_resumes +|= 1;
                self.windows_condition_mutex_reacquires +|= 1;
                endWindowsWaitAccounting(
                    self,
                    &self.windows_guest_threads[index],
                    if (timed_out) .timed_out else .signaled,
                );
                return .resumed;
            },
            .invalid => {
                self.windows_guest_threads[index].condition_mutex_contended = false;
                self.windows_condition_mutex_release_failures +|= 1;
                return .invalid;
            },
            .contended => |wait_handle| {
                // A mutex release may have woken this worker between the
                // condition notification and this retry.  Consume that
                // one-shot marker before testing the mutex again; if it
                // is still contended below, the next SetEvent will arm a
                // fresh marker.
                if (self.windows_guest_threads[index].wait_resume and
                    self.windows_guest_threads[index].wait_resume_handle == wait_handle)
                {
                    self.windows_guest_threads[index].wait_resume = false;
                    self.windows_guest_threads[index].wait_resume_handle = 0;
                }
                self.windows_guest_threads[index].condition_mutex_contended = true;
                // A real wait on an auto-reset event that is already set
                // takes the signal and returns at once, and the image's
                // lock loop tries again. Parking here would wait for a
                // *next* SetEvent that the unlock already spent, so take
                // the signal and retry on the next turn instead.
                if (windowsWaitObjectIndex(self, wait_handle)) |object_index| {
                    const object = &self.windows_wait_objects[object_index];
                    if (object.signaled) {
                        if (!object.manual_reset) object.signaled = false;
                        self.windows_guest_threads[index].status = .runnable;
                        process_impl_lifecycle.noteWindowsGuestWorkerWake(self, index);
                        self.windows_condition_mutex_reacquire_blocks +|= 1;
                        return .blocked;
                    }
                }
                self.windows_guest_threads[index].status = .blocked;
                self.windows_guest_threads[index].blocked_srw_lock = 0;
                self.windows_guest_threads[index].blocked_condition = 0;
                self.windows_guest_threads[index].blocked_wait_handle = wait_handle;
                self.windows_guest_threads[index].blocked_wait_timeout = 0;
                self.windows_guest_threads[index].blocked_wait_deadline = 0;
                self.windows_guest_threads[index].wait_resume_timeout = false;
                self.windows_thread_blocks +|= 1;
                self.windows_condition_mutex_reacquire_blocks +|= 1;
                return .blocked;
            },
        }
    }

    // POSIX condition waits release their mutex as part of entering the
    // wait.  The old Rosetta hook only recorded the condition address,
    // leaving the MinGW mutex in the acquired state and making the owner
    // thread's later pthread_mutex_lock wait forever on its event.
    switch (releaseWindowsGuestPthreadMutex(self, mutex_address)) {
        .invalid => {
            self.windows_condition_mutex_release_failures +|= 1;
            return .invalid;
        },
        .released, .already_unlocked => {
            self.windows_condition_mutex_releases +|= 1;
        },
    }

    const thread = &self.windows_guest_threads[index];
    thread.status = .blocked;
    thread.blocked_srw_lock = 0;
    thread.blocked_condition = address;
    thread.blocked_condition_mutex = mutex_address;
    thread.blocked_wait_handle = 0;
    thread.blocked_wait_timeout = 0;
    thread.blocked_wait_deadline = deadline;
    thread.condition_resume_timeout = false;
    thread.wait_resume = false;
    thread.wait_resume_handle = 0;
    thread.wait_resume_timeout = false;
    beginWindowsWaitAccounting(
        self,
        thread,
        address,
        if (deadline != 0) .timed_condition else .condition,
        if (deadline == 0) 0 else thread.timed_wait_milliseconds,
        deadline,
    );
    self.windows_thread_blocks +|= 1;
    self.windows_condition_wait_blocks +|= 1;
    if (self.trace_windows_threads and
        (self.windows_thread_blocks <= 8 or self.windows_thread_blocks % 1024 == 0))
    {
        __process_log.info("Windows guest worker blocked on condition variable: handle=0x{x} thread_id={d} condition=0x{x} mutex=0x{x} rip=0x{x} blocks={d}", .{
            thread.handle,
            thread.thread_id,
            address,
            mutex_address,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            self.windows_thread_blocks,
        });
    }
    return .blocked;
}

pub fn sleepWindowsNativeCondition(self: *ElfState, condition: u64, lock: u64, kind: __process_NativeConditionLock, milliseconds: u64) __state_NativeConditionResult {
    if (condition == 0 or lock == 0 or kind == .none) {
        self.windows_native_condition_unmodelled +|= 1;
        return .invalid;
    }
    const result = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |index|
        sleepWorkerOnNativeCondition(self, index, condition, lock, kind, milliseconds)
    else
        sleepOwnerOnNativeCondition(self, condition, lock, kind, milliseconds);
    switch (result) {
        .invalid => self.windows_native_condition_unmodelled +|= 1,
        .woken => self.windows_native_condition_resumes +|= 1,
        .timed_out => self.windows_native_condition_timeouts +|= 1,
        .blocked, .retry => {},
    }
    return result;
}

pub fn sleepWorkerOnNativeCondition(self: *ElfState, index: usize, condition: u64, lock: u64, kind: __process_NativeConditionLock, milliseconds: u64) __state_NativeConditionResult {
    const thread = &self.windows_guest_threads[index];
    if (thread.status != .running) return .invalid;
    if (thread.condition_resume and thread.native_condition_lock == lock) {
        // Woken or timed out: the lock comes back before the call returns.
        const timed_out = thread.condition_resume_timeout;
        endWindowsWaitAccounting(self, thread, if (timed_out) .timed_out else .signaled);
        switch (retakeNativeConditionLock(self, lock, kind, thread.native_condition_recursion)) {
            .acquired, .invalid => {
                thread.condition_resume = false;
                thread.condition_resume_timeout = false;
                thread.native_condition_lock = 0;
                thread.native_condition_kind = .none;
                thread.native_condition_recursion = 0;
                return if (timed_out) .timed_out else .woken;
            },
            // Someone else holds it: park on the lock itself. The release
            // that hands it over wakes this thread, which asks again.
            .contended => return if (blockWindowsGuestThreadOnSrwLock(self, lock)) .blocked else .invalid,
        }
    }
    if ((milliseconds & 0xFFFF_FFFF) == 0) return .timed_out;
    const recursion = releaseNativeConditionLock(self, lock, kind) orelse return .invalid;
    thread.native_condition_lock = lock;
    thread.native_condition_kind = kind;
    thread.native_condition_recursion = recursion;
    const infinite = (milliseconds & 0xFFFF_FFFF) == 0xFFFF_FFFF;
    const deadline = if (infinite) 0 else process_impl_lifecycle.windowsGuestClockTicks(self) +| ((milliseconds & 0xFFFF_FFFF) *| __process_WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND);
    thread.status = .blocked;
    thread.blocked_srw_lock = 0;
    thread.blocked_condition = condition;
    thread.blocked_condition_mutex = 0;
    thread.blocked_wait_handle = 0;
    thread.blocked_wait_timeout = if (infinite) 0 else milliseconds & 0xFFFF_FFFF;
    thread.blocked_wait_deadline = deadline;
    thread.condition_resume = false;
    thread.condition_resume_timeout = false;
    thread.wait_resume = false;
    thread.wait_resume_handle = 0;
    thread.wait_resume_timeout = false;
    beginWindowsWaitAccounting(self, thread, condition, if (deadline != 0) .timed_condition else .condition, thread.blocked_wait_timeout, deadline);
    self.windows_thread_blocks +|= 1;
    self.windows_native_condition_waits +|= 1;
    return .blocked;
}

pub fn sleepOwnerOnNativeCondition(self: *ElfState, condition: u64, lock: u64, kind: __process_NativeConditionLock, milliseconds: u64) __state_NativeConditionResult {
    if (!self.parallel_guest_execution) return .invalid;
    if (self.owner_native_condition != condition or self.owner_native_condition_lock != lock) {
        if ((milliseconds & 0xFFFF_FFFF) == 0) return .timed_out;
        const recursion = releaseNativeConditionLock(self, lock, kind) orelse return .invalid;
        const infinite = (milliseconds & 0xFFFF_FFFF) == 0xFFFF_FFFF;
        self.owner_native_condition = condition;
        self.owner_native_condition_lock = lock;
        self.owner_native_condition_kind = kind;
        self.owner_native_condition_recursion = recursion;
        self.owner_native_condition_deadline_ns = if (infinite) 0 else __process_monotonicNanoseconds() +| (milliseconds & 0xFFFF_FFFF) *| __process_std.time.ns_per_ms;
        self.owner_native_condition_signaled = false;
        self.owner_native_condition_timed_out = false;
        self.windows_native_condition_waits +|= 1;
    }
    const deadline = self.owner_native_condition_deadline_ns;
    if (!self.owner_native_condition_signaled and !self.owner_native_condition_timed_out) {
        if (deadline != 0 and __process_monotonicNanoseconds() >= deadline) {
            self.owner_native_condition_timed_out = true;
        } else {
            _ = serviceWindowsGuestThreads(self, windowsGuestWaitServiceSlice(self));
            _ = process_impl_windows_ui.parkForGuestWait(self, if (deadline != 0) deadline else null, .wake);
            if (!self.owner_native_condition_signaled) {
                if (deadline == 0 or __process_monotonicNanoseconds() < deadline) return .retry;
                self.owner_native_condition_timed_out = true;
            }
        }
    }
    switch (retakeNativeConditionLock(self, lock, kind, self.owner_native_condition_recursion)) {
        .acquired, .invalid => {
            const timed_out = self.owner_native_condition_timed_out and !self.owner_native_condition_signaled;
            self.owner_native_condition = 0;
            self.owner_native_condition_lock = 0;
            self.owner_native_condition_kind = .none;
            self.owner_native_condition_recursion = 0;
            self.owner_native_condition_signaled = false;
            self.owner_native_condition_timed_out = false;
            return if (timed_out) .timed_out else .woken;
        },
        .contended => {
            switch (kind) {
                .critical_section => noteWindowsOwnerCriticalSectionWait(self, lock),
                .srw => noteWindowsOwnerSrwWait(self, lock),
                .none => {},
            }
            _ = process_impl_windows_ui.parkForGuestWait(self, null, .wake);
            return .retry;
        },
    }
}

pub fn releaseNativeConditionLock(self: *ElfState, lock: u64, kind: __process_NativeConditionLock) ?u32 {
    const thread_id = process_impl_lifecycle.currentWindowsThreadId(self);
    switch (kind) {
        .critical_section => {
            const index = windowsCriticalSectionIndex(self, lock) orelse return null;
            const section = &self.windows_critical_sections[index];
            if (section.owner_thread_id != thread_id or section.recursion == 0) return null;
            const recursion = section.recursion;
            section.recursion = 1;
            leaveWindowsCriticalSection(self, lock);
            return recursion;
        },
        .srw => {
            const index = windowsSrwLockIndex(self, lock) orelse return null;
            if (self.windows_srw_locks[index].owner_thread_id != thread_id) return null;
            releaseWindowsSrwLock(self, lock);
            return 1;
        },
        .none => return null,
    }
}

pub fn retakeNativeConditionLock(self: *ElfState, lock: u64, kind: __process_NativeConditionLock, recursion: u32) __state_WindowsSrwAcquireResult {
    switch (kind) {
        .critical_section => {
            const result = enterWindowsCriticalSection(self, lock);
            if (result == .acquired and recursion > 1) {
                if (windowsCriticalSectionIndex(self, lock)) |index| {
                    self.windows_critical_sections[index].recursion = recursion;
                    publishCriticalSection(self, &self.windows_critical_sections[index]);
                }
            }
            return result;
        },
        .srw => return acquireWindowsSrwLock(self, lock),
        .none => return .invalid,
    }
}

pub fn waitOwnerOnPthreadCondition(self: *ElfState, address: u64, mutex_address: u64, deadline: u64, allow_relock: bool) __state_WindowsConditionWaitResult {
    if (!self.parallel_guest_execution or address == 0) return .invalid;
    if (self.owner_pthread_condition != address) {
        // Entering: give the mutex up, as pthread_cond_wait does.
        if (mutex_address != 0) {
            switch (releaseWindowsGuestPthreadMutex(self, mutex_address)) {
                .invalid => {
                    self.windows_condition_mutex_release_failures +|= 1;
                    return .invalid;
                },
                .released, .already_unlocked => self.windows_condition_mutex_releases +|= 1,
            }
        }
        self.owner_pthread_condition = address;
        self.owner_pthread_condition_mutex = mutex_address;
        self.owner_pthread_condition_deadline = deadline;
        self.owner_pthread_condition_signaled = false;
        self.owner_pthread_condition_timed_out = false;
        self.owner_pthread_condition_mutex_contended = false;
        self.windows_condition_wait_calls +|= 1;
        self.windows_condition_wait_blocks +|= 1;
        self.windows_owner_condition_waits +|= 1;
    }
    if (!self.owner_pthread_condition_signaled and !self.owner_pthread_condition_timed_out) {
        const deadline_ticks = self.owner_pthread_condition_deadline;
        if (deadline_ticks != 0 and process_impl_lifecycle.windowsGuestClockTicks(self) >= deadline_ticks) {
            self.owner_pthread_condition_timed_out = true;
        } else {
            _ = serviceWindowsGuestThreads(self, windowsGuestWaitServiceSlice(self));
            const deadline_ns = if (deadline_ticks != 0) windowsGuestTicksToHostNanoseconds(self, deadline_ticks) else null;
            if (!process_impl_windows_ui.parkForGuestWait(self, deadline_ns, .wake)) return .blocked;
            if (!self.owner_pthread_condition_signaled) {
                if (deadline_ticks == 0 or process_impl_lifecycle.windowsGuestClockTicks(self) < deadline_ticks) return .blocked;
                self.owner_pthread_condition_timed_out = true;
            }
        }
    }
    // Woken or timed out: the mutex comes back before the call returns.
    const timed_out = self.owner_pthread_condition_timed_out and !self.owner_pthread_condition_signaled;
    const mutex = self.owner_pthread_condition_mutex;
    if (mutex == 0) {
        finishOwnerPthreadCondition(self);
        return .resumed;
    }
    if (allow_relock and deadline == 0 and !timed_out and self.windows_pthread_mutex_lock_intern_entry != null) {
        if (windowsPthreadMutexImpl(self, mutex)) |impl| {
            if (process_impl_guest_memory.read32(self, impl + 4) == 0) {
                finishOwnerPthreadCondition(self);
                self.windows_condition_wait_resumes +|= 1;
                self.windows_condition_relocks +|= 1;
                return .relock;
            }
        }
    }
    switch (acquireWindowsGuestPthreadMutex(self, mutex, self.owner_pthread_condition_mutex_contended)) {
        .acquired => {
            finishOwnerPthreadCondition(self);
            self.windows_condition_wait_resumes +|= 1;
            self.windows_condition_mutex_reacquires +|= 1;
            return .resumed;
        },
        .invalid => {
            finishOwnerPthreadCondition(self);
            self.windows_condition_mutex_release_failures +|= 1;
            return .invalid;
        },
        .contended => {
            self.owner_pthread_condition_mutex_contended = true;
            _ = process_impl_windows_ui.parkForGuestWait(self, null, .wake);
            return .blocked;
        },
    }
}

pub fn finishOwnerPthreadCondition(self: *ElfState) void {
    self.owner_pthread_condition = 0;
    self.owner_pthread_condition_mutex = 0;
    self.owner_pthread_condition_deadline = 0;
    self.owner_pthread_condition_signaled = false;
    self.owner_pthread_condition_timed_out = false;
    self.owner_pthread_condition_mutex_contended = false;
}

pub fn signalWindowsGuestCondition(self: *ElfState, address: u64, broadcast: bool) u64 {
    if (address == 0) return 0;
    if (broadcast) {
        self.windows_condition_broadcast_calls +|= 1;
    } else {
        self.windows_condition_signal_calls +|= 1;
    }
    noteWindowsWaitSignal(self, address);
    var woken: u64 = 0;
    // The owner waits on a native condition outside the thread table.
    // Any signal of its condition ends its wait - a single signal that
    // also wakes a worker is a spurious wakeup, which condition variables
    // allow, and it keeps workers that queue first from starving it.
    if (self.owner_native_condition == address and !self.owner_native_condition_signaled) {
        self.owner_native_condition_signaled = true;
        process_impl_lifecycle.noteWindowsThreadWake(self);
        woken +|= 1;
    }
    if (self.owner_pthread_condition == address and !self.owner_pthread_condition_signaled) {
        self.owner_pthread_condition_signaled = true;
        process_impl_lifecycle.noteWindowsThreadWake(self);
        self.windows_condition_unblocks +|= 1;
        woken +|= 1;
    }
    for (self.windows_guest_threads, 0..) |*thread, slot| {
        if (thread.status != .blocked or thread.blocked_condition != address) continue;
        thread.status = .runnable;
        process_impl_lifecycle.noteWindowsGuestWorkerWake(self, slot);
        thread.blocked_condition = 0;
        thread.blocked_srw_lock = 0;
        thread.blocked_wait_handle = 0;
        thread.blocked_wait_timeout = 0;
        thread.blocked_wait_deadline = 0;
        thread.condition_resume = true;
        thread.condition_resume_timeout = false;
        thread.wait_resume_timeout = false;
        self.windows_thread_unblocks +|= 1;
        self.windows_condition_unblocks +|= 1;
        woken +|= 1;
        if (!broadcast) break;
    }
    return woken;
}

pub fn wakeWindowsGuestThreadsForSrwLock(self: *ElfState, address: u64) void {
    for (self.windows_guest_threads, 0..) |*thread, slot| {
        if (thread.status != .blocked or thread.blocked_srw_lock != address) continue;
        thread.status = .runnable;
        process_impl_lifecycle.noteWindowsGuestWorkerWake(self, slot);
        thread.blocked_srw_lock = 0;
        thread.blocked_wait_handle = 0;
        thread.blocked_wait_timeout = 0;
        thread.blocked_wait_deadline = 0;
        thread.wait_resume_timeout = false;
        self.windows_thread_unblocks +|= 1;
    }
}

pub fn configureWindowsStaticTls(
    self: *ElfState,
    module_index: u32,
    template_start: u64,
    template_length: u64,
    block_bytes: u64,
) bool {
    if (module_index >= __process_WINDOWS_TLS_SLOT_COUNT or template_length > block_bytes) return false;
    if (process_impl_execution.guestMemoryConst(self, template_start, template_length) == null) return false;
    self.windows_static_tls_index = module_index;
    self.windows_static_tls_template_start = template_start;
    self.windows_static_tls_template_length = template_length;
    self.windows_static_tls_block_bytes = @max(__process_WINDOWS_TLS_BLOCK_BYTES, block_bytes);
    self.windows_next_tls = @max(self.windows_next_tls, @as(u32, module_index) + 1);
    return true;
}

pub fn allocateWindowsGuestThreadEnvironment(
    self: *ElfState,
    stack_base: u64,
    stack_limit: u64,
    thread_id: u64,
) ?__process_WindowsGuestThreadEnvironment {
    if (self.windows_process_peb == 0) {
        __process_log.err("Windows guest thread environment rejected: process PEB is not initialized thread_id={d}", .{thread_id});
        return null;
    }
    const teb = process_impl_guest_heap.guestAlloc(self, __process_WINDOWS_TEB_BYTES, __process_WINDOWS_PAGE_SIZE) orelse return null;
    const tls_block = process_impl_guest_heap.guestAlloc(self, self.windows_static_tls_block_bytes, __process_WINDOWS_PAGE_SIZE) orelse return null;
    const tls_vector = teb + 0x1000;
    // The thread's slots start empty. A switch no longer rewrites them
    // from a saved copy, so the vector itself has to begin zeroed rather
    // than inherit whatever the heap block last held.
    if (!process_impl_execution.fillGuestMemory(self, tls_vector, __process_WINDOWS_TLS_SLOT_COUNT * 8, 0)) return null;

    if (self.windows_static_tls_template_length != 0) {
        const source = process_impl_execution.guestMemoryConst(
            self,
            self.windows_static_tls_template_start,
            self.windows_static_tls_template_length,
        ) orelse return null;
        if (!process_impl_execution.copyToGuest(self, tls_block, source)) return null;
    }

    process_impl_guest_memory.write64(self, teb + __process_WINDOWS_TEB_STACK_BASE_OFFSET, stack_base);
    process_impl_guest_memory.write64(self, teb + __process_WINDOWS_TEB_STACK_LIMIT_OFFSET, stack_limit);
    process_impl_guest_memory.write64(self, teb + __process_WINDOWS_TEB_SELF_OFFSET, teb);
    process_impl_guest_memory.write64(self, teb + __process_WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET, 1);
    process_impl_guest_memory.write64(self, teb + __process_WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET, thread_id);
    process_impl_guest_memory.write64(self, teb + __process_WINDOWS_TEB_TLS_POINTER_OFFSET, tls_vector);
    if (self.windows_static_tls_index) |index| {
        process_impl_guest_memory.write64(self, tls_vector + @as(u64, index) * 8, tls_block);
    }
    process_impl_guest_memory.write64(self, teb + __process_WINDOWS_TEB_PEB_OFFSET, self.windows_process_peb);
    process_impl_guest_memory.write32(self, teb + __process_WINDOWS_TEB_LAST_ERROR_OFFSET, 0);
    return .{ .teb = teb, .tls_block = tls_block };
}

pub fn enqueueWindowsGuestThread(
    self: *ElfState,
    handle: u64,
    start_routine: u64,
    argument: u64,
    requested_stack_size: u64,
    preferred: bool,
) bool {
    if (handle == 0 or start_routine == 0 or process_impl_guest_memory.addrToOffset(self, start_routine) == null) return false;
    for (self.windows_guest_threads) |*slot| {
        if (slot.status != .vacant and slot.handle == handle) return false;
    }

    var free_index: ?usize = null;
    for (self.windows_guest_threads, 0..) |*slot, index| {
        if (slot.status == .vacant) {
            free_index = index;
            break;
        }
    }
    const index = free_index orelse recycleFinishedWindowsGuestThreadSlot(self) orelse {
        noteWindowsGuestThreadTableFull(self, start_routine, argument, handle);
        return false;
    };

    const stack_size = if (requested_stack_size == 0)
        __process_WINDOWS_GUEST_THREAD_STACK_SIZE
    else
        __process_std.math.clamp(requested_stack_size, 64 * 1024, __process_WINDOWS_GUEST_THREAD_MAX_STACK_SIZE);
    const thread_id = self.windows_next_thread_id;
    self.windows_next_thread_id +|= 1;
    const cached_tlb = self.windows_guest_thread_tlbs[index];
    if (cached_tlb) |tlb| tlb.flush(true, true);
    self.windows_guest_threads[index] = .{
        .status = .pending,
        .handle = handle,
        .start_routine = start_routine,
        .argument = argument,
        .thread_id = thread_id,
        .stack_size = stack_size,
        .preferred = preferred,
        .created_step = process_impl_lifecycle.observedExecutionSteps(self),
        .creator_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
        .creator_slot = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| @intCast(@min(slot + 1, 255)) else 0,
    };
    registerWindowsThreadWaitObject(self, handle);
    if (self.trace_windows_threads) {
        self.windows_thread_queue_trace_events +|= 1;
        const event = self.windows_thread_queue_trace_events;
        if (event <= 8 or (event & (event - 1)) == 0) {
            __process_log.info("Windows guest thread queued: handle=0x{x} start=0x{x} argument=0x{x} stack_size={d} preferred={} slot={d} creator_rip=0x{x} active_thread=0x{x} step={d} event={d}", .{
                handle,
                start_routine,
                argument,
                stack_size,
                preferred,
                index,
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                process_impl_lifecycle.observedExecutionSteps(self),
                event,
            });
        }
    }
    return true;
}

pub fn recycleFinishedWindowsGuestThreadSlot(self: *ElfState) ?usize {
    var oldest: ?usize = null;
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status != .completed and thread.status != .failed) continue;
        if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |active| {
            if (active == index) continue;
        }
        if (oldest) |current| {
            if (thread.created_step >= self.windows_guest_threads[current].created_step) continue;
        }
        oldest = index;
    }
    const index = oldest orelse return null;
    const finished = &self.windows_guest_threads[index];
    // The guest context, its stack and its store-buffer slot all share
    // this table index with the persistent host executor. Status becomes
    // completed inside `step`, slightly before the callback drains its
    // final stores and returns, so wait for that callback before reuse.
    finished.parallel_worker.requestStop();
    finished.parallel_worker.join();
    // Its host thread has returned, so nothing runs its translated code.
    if (finished.parallel_block_jit) |jit| {
        jit.destroy(self.allocator);
        finished.parallel_block_jit = null;
    }
    finished.parallel_block_jit_refused = false;
    if (windowsWaitObjectIndex(self, finished.handle)) |wait_index| {
        noteWindowsWaitObjectSignaled(self, &self.windows_wait_objects[wait_index]);
        self.windows_wait_objects[wait_index].signaled = true;
    }
    _ = releaseWindowsGuestThreadStack(self, finished);
    for ([_]u64{ finished.teb, finished.tls_block }) |base| {
        if (base != 0) _ = process_impl_guest_heap.releaseGuestAllocation(self, base);
    }
    if (self.windows_guest_thread_tlbs[index]) |tlb| tlb.flush(true, true);
    finished.call_stack.deinit(self.allocator);
    self.windows_guest_threads[index] = .{};
    self.windows_thread_slots_recycled +|= 1;
    return index;
}

pub fn noteWindowsGuestThreadTableFull(self: *ElfState, start_routine: u64, argument: u64, handle: u64) void {
    self.windows_thread_table_full +|= 1;
    const occurrence = self.windows_thread_table_full;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    if (comptime !@import("builtin").is_test) {
        if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) {
            var start_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.err("PE64 FATAL POINT: guest-condition label=guest-thread-table-full owner=rosette:scheduler occurrence={d} start={s} argument=0x{x} handle=0x{x} capacity={d} reused_so_far={d} step={d}; every slot holds a thread that has not finished, so CreateThread returns NULL and the caller's thread never exists. Raise MAX_WINDOWS_GUEST_THREADS, or read PE64 GUEST THREADS for threads that should have exited", .{
                occurrence,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, start_routine, &start_text),
                argument,
                handle,
                self.windows_guest_threads.len,
                self.windows_thread_slots_recycled,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
    }
    process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "guest-thread-table-full");
}

pub fn suspendWindowsGuestThreadAtCreation(self: *ElfState, handle: u64) void {
    const index = windowsGuestThreadIndex(self, handle) orelse return;
    self.windows_guest_threads[index].suspend_count = 1;
    self.windows_thread_suspended_creations +|= 1;
}

pub fn windowsGuestThreadId(self: *const ElfState, handle: u64) ?u64 {
    const index = windowsGuestThreadIndex(self, handle) orelse return null;
    return self.windows_guest_threads[index].thread_id;
}

pub fn windowsGuestThreadIndex(self: *const ElfState, handle: u64) ?usize {
    if (handle == __process_WINDOWS_CURRENT_THREAD_PSEUDO_HANDLE) return process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status != .vacant and thread.handle == handle) return index;
    }
    return null;
}

pub fn changeWindowsGuestThreadSuspension(self: *ElfState, handle: u64, suspending: bool) u64 {
    const failure: u64 = __process_std.math.maxInt(u32);
    const index = windowsGuestThreadIndex(self, handle) orelse {
        process_impl_lifecycle.guestContextField(self, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
        return failure;
    };
    const thread = &self.windows_guest_threads[index];
    const previous = thread.suspend_count;
    if (suspending) {
        if (previous >= __process_WINDOWS_MAXIMUM_SUSPEND_COUNT) {
            process_impl_lifecycle.guestContextField(self, "windows_last_error").* = 156; // ERROR_SIGNAL_REFUSED
            return failure;
        }
        thread.suspend_count = previous + 1;
        self.windows_thread_suspend_calls +|= 1;
        if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == index) process_impl_lifecycle.requestWindowsGuestSliceYield(self);
    } else {
        if (previous != 0) thread.suspend_count = previous - 1;
        self.windows_thread_resume_calls +|= 1;
    }
    process_impl_lifecycle.guestContextField(self, "windows_last_error").* = 0;
    return previous;
}

pub fn windowsGuestRegisterDigest(self: *const ElfState) u64 {
    const r = process_impl_lifecycle.guestContextField(self, "regs").*;
    var digest: u64 = r.rflags;
    for ([_]u64{ r.rax, r.rbx, r.rcx, r.rdx, r.rsi, r.rdi, r.rbp, r.rsp, r.r8, r.r9, r.r10, r.r11, r.r12, r.r13, r.r14, r.r15 }) |value| {
        digest = (digest ^ value) *% 0x9E37_79B9_7F4A_7C15;
    }
    return digest;
}

pub fn noteWindowsGuestSliceShape(self: *ElfState, index: usize, repeated_state: bool, kernel_calls_before: u64) void {
    const thread = &self.windows_guest_threads[index];
    if (!repeated_state or thread.kernel_calls != kernel_calls_before) {
        thread.spin_backoff = 0;
        return;
    }
    self.windows_spin_slices +|= 1;
    thread.spin_backoff = if (thread.spin_backoff == 0) 1 else @min(thread.spin_backoff *| 2, __process_WINDOWS_GUEST_SPIN_MAX_BACKOFF);
    thread.spin_skip_remaining = thread.spin_backoff;
}

pub fn nextWindowsGuestThread(self: *const ElfState) ?usize {
    if (self.windows_preferred_next_guest_thread) |preferred| {
        if (preferred < self.windows_guest_threads.len and
            self.windows_guest_threads[preferred].status == .runnable and
            self.windows_guest_threads[preferred].suspend_count == 0)
        {
            return preferred;
        }
    }
    const start = if (self.windows_last_serviced_guest_thread_slot) |last|
        (last + 1) % self.windows_guest_threads.len
    else
        0;

    // Give a freshly-created Win32 worker the first service opportunity
    // so Xenia's graphics setup thread is not behind CRT bookkeeping.
    // Once one slot has run, use a true circular scan: a worker that
    // parks in a loop must not starve the other graphics workers forever.
    if (self.windows_last_serviced_guest_thread_slot == null) {
        for (0..self.windows_guest_threads.len) |offset| {
            const index = (start + offset) % self.windows_guest_threads.len;
            const slot = &self.windows_guest_threads[index];
            if ((slot.status == .pending or slot.status == .runnable) and slot.preferred and slot.suspend_count == 0) return index;
        }
    }
    for (0..self.windows_guest_threads.len) |offset| {
        const index = (start + offset) % self.windows_guest_threads.len;
        const slot = &self.windows_guest_threads[index];
        if ((slot.status == .pending or slot.status == .runnable) and slot.suspend_count == 0) return index;
    }
    return null;
}

pub fn releaseWindowsGuestThreadStack(self: *ElfState, thread: *__process_WindowsGuestThread) bool {
    if (thread.stack_base == 0) return false;
    // A store still queued for this stack would land in whatever the heap
    // hands these bytes to next.
    const slot = (@intFromPtr(thread) - @intFromPtr(self.windows_guest_threads.ptr)) / @sizeOf(__process_WindowsGuestThread);
    self.guest_store_buffers.drainContext(slot, .thread_exit);
    const allocation = if (thread.stack_guard_base != 0) thread.stack_guard_base else thread.stack_base;
    if (thread.stack_guard_base != 0) {
        if (!process_impl_guest_memory.clearGuestPageProtectionAndReportInvalidation(self, thread.stack_guard_base, __process_WINDOWS_GUEST_THREAD_STACK_GUARD)) {
            process_impl_block_jit.blockJitTlbInvalidate(self, thread.stack_guard_base, __process_WINDOWS_GUEST_THREAD_STACK_GUARD);
        }
    }
    if (!process_impl_guest_heap.releaseGuestAllocation(self, allocation)) return false;
    thread.stack_base = 0;
    thread.stack_guard_base = 0;
    return true;
}

pub fn windowsStackGuardOwner(self: *const ElfState, address: u64) ?usize {
    for (self.windows_guest_threads, 0..) |thread, index| {
        if (thread.stack_guard_base == 0 or thread.status == .vacant) continue;
        if (address >= thread.stack_guard_base and address < thread.stack_guard_base + __process_WINDOWS_GUEST_THREAD_STACK_GUARD) return index;
    }
    return null;
}

pub fn finishWindowsGuestThread(self: *ElfState) void {
    const index = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("Windows guest thread return without an active thread context at rip=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rip});
        return;
    };
    // Completion releases a stack back to the process heap and wakes
    // peers waiting on this handle: runtime tables, so the runtime lock
    // (reentrant - the exit import already holds it). It used to stop
    // the world; nothing here changes what guest memory is (the stack
    // guard's protection goes through the address-space lock itself).
    var completion_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (completion_guard) |*guard| guard.unlock();
    // Thread termination is a release boundary: a successful join or
    // wait on this handle must not complete ahead of stores the worker
    // performed before returning. Those are this thread's own stores, in
    // its own queue; other threads' queues are theirs. The slot's buffer
    // is drained by index because this runs from the service loop too,
    // where no buffer is bound.
    __process_tso_memory.flushActiveStoreBufferFor(.thread_exit);
    self.guest_store_buffers.drainContext(index, .thread_exit);
    endWindowsWaitAccounting(self, &self.windows_guest_threads[index], .aborted);
    process_impl_windows_mutex.abandonOwnedBy(self, self.windows_guest_threads[index].thread_id);
    self.windows_guest_threads[index].status = .completed;
    self.windows_thread_completions +|= 1;
    if (windowsWaitObjectIndex(self, self.windows_guest_threads[index].handle)) |wait_index| {
        noteWindowsWaitSignal(self, self.windows_guest_threads[index].handle);
        noteWindowsWaitObjectSignaled(self, &self.windows_wait_objects[wait_index]);
        self.windows_wait_objects[wait_index].signaled = true;
        _ = wakeWindowsGuestThreadsForWait(self, self.windows_guest_threads[index].handle, true);
    }
    process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* = null;
    // Nothing runs on a finished thread's stack, and Windows frees it at
    // exit. Holding it until the slot was reused kept megabytes per
    // finished thread out of the guest heap; on 2026-09-14 the heap ran
    // out and the title's next thread never got a stack at all.
    if (releaseWindowsGuestThreadStack(self, &self.windows_guest_threads[index])) {
        self.windows_thread_stacks_released +|= 1;
    }
    if (self.diagnose_abi or self.trace_windows_threads) {
        __process_log.info("Windows guest thread complete handle=0x{x} start=0x{x} steps={d} rip=0x{x}", .{
            self.windows_guest_threads[index].handle,
            self.windows_guest_threads[index].start_routine,
            process_impl_lifecycle.windowsGuestThreadSteps(self, &self.windows_guest_threads[index]),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
    if (self.parallel_guest_execution) self.parallel_guest_wake_hub.notify();
}

pub fn terminateActiveWindowsGuestThread(self: *ElfState, exit_code: u64) bool {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null) return false;
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = exit_code;
    finishWindowsGuestThread(self);
    return true;
}

pub fn auditOwnerContextAfterSlice(self: *ElfState, snapshot: *const __process_WindowsGuestThreadContext, slot: usize) void {
    const difference = __process_context_integrity.compare(snapshot, self);
    if (!difference.any()) return;
    self.owner_context_violations +|= 1;
    __process_context_integrity.restoreArchitecturalState(self, snapshot);
    reportOwnerContextViolation(self, difference, slot, "slice");
}

pub fn auditOwnerContextAfterStep(self: *ElfState, snapshot: *__process_WindowsGuestThreadContext, slot: usize) void {
    const difference = __process_context_integrity.compare(snapshot, self);
    if (!difference.any()) return;
    self.owner_context_step_violations +|= 1;
    __process_context_integrity.restoreArchitecturalState(self, snapshot);
    reportOwnerContextViolation(self, difference, slot, "instruction");
}

pub fn reportOwnerContextViolation(self: *ElfState, difference: __process_context_integrity.Difference, slot: usize, scope: []const u8) void {
    const occurrences = self.owner_context_violations +| self.owner_context_step_violations;
    var fields_text: [256]u8 = undefined;
    const fields = difference.format(&fields_text);
    var at_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const worker_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    const first_gpr_name = if (difference.first_gpr) |index|
        __process_context_integrity.gpr_names[@intCast(index)]
    else
        "<none>";
    const owner_regs_pointer = @intFromPtr(&self.regs);
    const worker_regs_pointer = if (slot < self.windows_guest_threads.len)
        @intFromPtr(&self.windows_guest_threads[slot].context.regs)
    else
        0;
    process_impl_execution.noteNotableEvent(self, .context_violation, 0, "worker '{s}' {s} changed the owner's {s}", .{
        process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
        scope,
        fields,
    });
    if (!process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrences)) return;
    if (comptime @import("builtin").is_test) return;
    __process_log.err("PE64 CONTEXT INTEGRITY: worker '{s}' (slot {d}) {s} changed the process owner's register file: fields={s} owner_regs=0x{x} worker_regs=0x{x} owner_rip=0x{x}->0x{x} first_gpr={s}:0x{x}->0x{x} first_vector={?d} vector_before={any} vector_after={any} worker_last_rip=0x{x} ({s}) op={s} step={d} occurrence={d} recovery=owner_register_file_restored. The slice boundary restored the owner snapshot; a nonzero count still names a missed context-aware helper. ROSETTE_PE64_CONTEXT_AUDIT=step names the exact instruction", .{
        process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
        slot,
        scope,
        fields,
        owner_regs_pointer,
        worker_regs_pointer,
        difference.rip_before,
        difference.rip_after,
        first_gpr_name,
        difference.first_gpr_before,
        difference.first_gpr_after,
        difference.first_vector,
        difference.first_vector_before,
        difference.first_vector_after,
        worker_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, worker_rip, &at_text),
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_run_reporting.totalInterpretedSteps(self),
        occurrences,
    });
}

pub fn serviceWindowsGuestThreads(self: *ElfState, max_steps: u64) u64 {
    if (max_steps == 0 or process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null or process_impl_lifecycle.isTerminated(self)) return 0;
    // In parallel mode the dispatcher builds the new worker's context -
    // stack, TEB, registers - in runtime tables and in memory no guest
    // thread can reach yet, so the runtime lock is enough. It used to stop
    // the world, and this runs from every GetMessage and PeekMessage.
    // The worker's host thread starts under the lock; its first runtime
    // call waits until the context is published and the lock released.
    var dispatch_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (dispatch_guard) |*guard| guard.unlock();
    _ = wakeExpiredWindowsGuestWaits(self);
    var index = (if (self.parallel_guest_execution)
        nextUnstartedWindowsGuestThread(self)
    else
        nextWindowsGuestThread(self)) orelse return 0;
    // A thread backing off from a user-mode spin gives its turn to the
    // next runnable thread. Bounded by the table, so a run in which every
    // runnable thread spins still runs one of them.
    var passes: usize = 0;
    while (!self.parallel_guest_execution and self.windows_guest_threads[index].spin_skip_remaining != 0 and passes < self.windows_guest_threads.len) : (passes += 1) {
        self.windows_guest_threads[index].spin_skip_remaining -= 1;
        self.windows_spin_turns_given +|= 1;
        self.windows_last_serviced_guest_thread_slot = index;
        self.windows_preferred_next_guest_thread = null;
        index = nextWindowsGuestThread(self) orelse return 0;
    }
    // A preference is for one scheduling decision only.
    self.windows_preferred_next_guest_thread = null;
    self.windows_thread_service_calls +|= 1;
    self.windows_last_serviced_guest_thread_slot = index;
    self.windows_last_service_owner_step = process_impl_lifecycle.observedExecutionSteps(self);
    const owner_context = process_impl_lifecycle.captureWindowsGuestContext(self);
    // What the owner's registers must still be when this slice ends.
    var owner_audit = owner_context;

    const worker_tlb = process_impl_block_jit.ensureWindowsGuestThreadTlb(self, index) orelse {
        self.windows_guest_threads[index].status = .failed;
        self.windows_thread_failures +|= 1;
        return 0;
    };

    const first_run = self.windows_guest_threads[index].status == .pending;
    if (first_run) {
        const guard_base = process_impl_guest_heap.guestAlloc(self, self.windows_guest_threads[index].stack_size + __process_WINDOWS_GUEST_THREAD_STACK_GUARD, 0x1000) orelse {
            self.windows_guest_threads[index].status = .failed;
            self.windows_thread_failures +|= 1;
            __process_log.err("Windows guest thread stack allocation failed: handle=0x{x} start=0x{x} size={d}", .{
                self.windows_guest_threads[index].handle,
                self.windows_guest_threads[index].start_routine,
                self.windows_guest_threads[index].stack_size,
            });
            return 0;
        };
        process_impl_guest_memory.noteGuestPageProtection(self, guard_base, __process_WINDOWS_GUEST_THREAD_STACK_GUARD, 0x01, "stack guard", process_impl_lifecycle.guestContextField(self, "regs").*.rip);
        self.windows_guest_threads[index].stack_guard_base = guard_base;
        const stack_base = guard_base + __process_WINDOWS_GUEST_THREAD_STACK_GUARD;
        const allocated_stack_end = stack_base + self.windows_guest_threads[index].stack_size;
        const stack_top = allocated_stack_end - __process_WINDOWS_GUEST_THREAD_ENTRY_RESERVE;
        const initial_parent = owner_context;
        var context = initial_parent;
        context.block_jit_tlb = worker_tlb;
        context.guest_clock_sample_steps = 0;
        // Process/thread callback frames are continuation state, not
        // process-global scratch. A new CreateThread starts with empty
        // stacks even if its creator is currently inside a callback.
        context.windows_initterm_frame_count = 0;
        context.windows_qsort_frame_count = 0;
        context.windows_bsearch_frame_count = 0;
        context.windows_message_dispatch_frame_count = 0;
        context.windows_audio_callback_frame_count = 0;
        context.regs = .{};
        context.regs.segments = initial_parent.regs.segments;
        const environment = allocateWindowsGuestThreadEnvironment(
            self,
            allocated_stack_end,
            stack_base,
            self.windows_guest_threads[index].thread_id,
        ) orelse {
            self.windows_guest_threads[index].status = .failed;
            self.windows_thread_failures +|= 1;
            __process_log.err("Windows guest thread environment allocation failed: handle=0x{x} start=0x{x} thread_id={d}", .{
                self.windows_guest_threads[index].handle,
                self.windows_guest_threads[index].start_routine,
                self.windows_guest_threads[index].thread_id,
            });
            return 0;
        };
        context.regs.segments.gs.base = environment.teb;
        context.regs.mxcsr = initial_parent.regs.mxcsr;
        context.regs.rflags = 2;
        context.regs.rcx = self.windows_guest_threads[index].argument;
        context.windows_last_error = 0;
        context.windows_errno_storage = 0;
        // RSP must be 8 mod 16 at a normal Windows x64 callee entry:
        // [RSP] is the synthetic return address and [RSP+8..+0x27] is
        // the four-slot home area.  The reserved cushion keeps all of
        // those addresses below allocated_stack_end.
        context.regs.rsp = (stack_top & ~@as(u64, 0xF)) - 8;
        context.regs.rip = self.windows_guest_threads[index].start_routine;
        context.active_guest_thread = self.windows_guest_threads[index].handle;
        context.windows_active_guest_thread_slot = null;
        context.windows_thread_id = self.windows_guest_threads[index].thread_id;
        context.active_idle_source = initial_parent.active_idle_source;
        self.windows_guest_threads[index].stack_base = stack_base;
        self.windows_guest_threads[index].teb = environment.teb;
        self.windows_guest_threads[index].tls_block = environment.tls_block;
        self.windows_guest_threads[index].synthetic_return_slot = context.regs.rsp;
        self.windows_guest_threads[index].context = context;
        process_impl_guest_memory.write64(self, context.regs.rsp, __process_SYNTHETIC_WINDOWS_THREAD_RETURN);
    }

    self.windows_guest_threads[index].context.block_jit_tlb = worker_tlb;
    self.windows_guest_threads[index].status = .running;
    // Publish owner stores before the worker can enter its context. In
    // serial mode this also preserves the old context-switch boundary;
    // parallel workers publish through their per-context TSO buffers.
    self.guest_store_buffers.drainContext(null, .context_switch);
    const previous_binding = __ProcessInternals._windows_guest_execution_binding().*;
    __ProcessInternals._windows_guest_execution_binding().* = .{
        .owner = @ptrCast(self),
        .context = &self.windows_guest_threads[index].context,
    };
    defer __ProcessInternals._windows_guest_execution_binding().* = previous_binding;
    process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* = index;
    const context = &self.windows_guest_threads[index].context;
    if (self.parallel_guest_execution) {
        context.windows_active_guest_thread_slot = index;
        context.windows_guest_slice_yield_requested = false;
        context.windows_guest_handoff_requested = false;
        context.windows_slice_pause_yield = false;
        // Stack/TEB/TLS setup used the owner's store queue. Publish it
        // before the worker can enter the guest context.
        self.guest_store_buffers.drainContext(null, .context_switch);
        const worker = &self.windows_guest_threads[index].parallel_worker;
        worker.start(@ptrCast(self), index, &self.parallel_guest_wake_hub, parallelWindowsGuestThreadEntry) catch |err| {
            self.windows_guest_threads[index].status = .failed;
            self.windows_thread_failures +|= 1;
            __process_log.err("parallel Windows guest worker could not start: slot={d} handle=0x{x} error={s}", .{
                index,
                self.windows_guest_threads[index].handle,
                @errorName(err),
            });
            return 0;
        };
        return 0;
    }
    if (self.diagnose_abi or self.trace_windows_threads) {
        // The Win32 wrapper receives two different opaque start records:
        // xe::threading::ThreadStartRoutine stores its std::function
        // invoker at +0x18, while the MinGW pthread wrapper stores the
        // pthread entry at +0x10 and its argument at +0x08.  Reporting
        // those targets makes a cooperative worker trace actionable
        // without walking an incomplete host stack.
        const dispatch_target = if (self.windows_guest_threads[index].start_routine == 0x1401310f0)
            process_impl_guest_memory.read64(self, context.regs.rcx +| 0x18)
        else if (self.windows_guest_threads[index].start_routine == 0x14051502b)
            process_impl_guest_memory.read64(self, context.regs.rcx +| 0x10)
        else
            0;
        const dispatch_argument = if (self.windows_guest_threads[index].start_routine == 0x14051502b)
            process_impl_guest_memory.read64(self, context.regs.rcx +| 0x08)
        else
            0;
        const dispatch_vtable = if (dispatch_argument != 0) process_impl_guest_memory.read64(self, dispatch_argument) else 0;
        __process_log.info("Windows guest thread service start handle=0x{x} start=0x{x} argument=0x{x} dispatch=0x{x} dispatch_argument=0x{x} dispatch_vtable=0x{x} resumed={} rip=0x{x} rsp=0x{x} return_slot=0x{x} return_value=0x{x} stack=[0x{x},0x{x})", .{
            self.windows_guest_threads[index].handle,
            self.windows_guest_threads[index].start_routine,
            self.windows_guest_threads[index].argument,
            dispatch_target,
            dispatch_argument,
            dispatch_vtable,
            !first_run,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            self.windows_guest_threads[index].synthetic_return_slot,
            process_impl_guest_memory.read64(self, self.windows_guest_threads[index].synthetic_return_slot),
            self.windows_guest_threads[index].stack_base,
            self.windows_guest_threads[index].stack_base +| self.windows_guest_threads[index].stack_size,
        });
    }

    var executed: u64 = 0;
    process_impl_lifecycle.guestContextField(self, "windows_guest_slice_yield_requested").* = false;
    process_impl_lifecycle.guestContextField(self, "windows_guest_handoff_requested").* = false;
    process_impl_lifecycle.guestContextField(self, "windows_slice_clock_reads").* = 0;
    process_impl_lifecycle.guestContextField(self, "windows_slice_pause_yield").* = false;
    const slice_kernel_calls = self.windows_guest_threads[index].kernel_calls;
    var spin_probe_rip: u64 = 0;
    var spin_probe_state: u64 = 0;
    var spin_probe_at: u64 = 0;
    var spin_probe_taken = false;
    var slice_repeated_state = false;
    var next_code_sample: u64 = 0;
    // A step retires one interpreted instruction or a whole translated
    // block, so `executed` moves in strides and every threshold below is
    // a `>=`, never an `==`.
    while (!process_impl_lifecycle.isTerminated(self) and process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null and executed < max_steps) : (executed += process_impl_lifecycle.guestContextField(self, "step_retired").*) {
        const continue_running = process_impl_block_jit.step(self);
        if (self.owner_context_audit_steps) auditOwnerContextAfterStep(self, &owner_audit, index);
        if (!spin_probe_taken and executed >= __process_WINDOWS_GUEST_SPIN_PROBE_AT) {
            spin_probe_taken = true;
            spin_probe_at = executed;
            spin_probe_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
            spin_probe_state = windowsGuestRegisterDigest(self);
        } else if (spin_probe_taken and !slice_repeated_state and executed > spin_probe_at and
            executed <= spin_probe_at + __process_WINDOWS_GUEST_SPIN_PROBE_SPAN and
            process_impl_lifecycle.guestContextField(self, "regs").*.rip == spin_probe_rip and windowsGuestRegisterDigest(self) == spin_probe_state)
        {
            slice_repeated_state = true;
        }
        // A yield boundary ends the slice here rather than inside the
        // import handler, so the tail below still saves this worker's
        // context and restores the owner's.
        //
        // Not on the first instruction, though: a switch costs two
        // register-file copies, and a spin-wait whose inner loop is a
        // dozen instructions would otherwise pay that every dozen. The
        // floor keeps the yield meaningful - a spinner gets a couple of
        // hundred instructions instead of ten thousand - without letting
        // the switch dominate what it saved.
        // A handoff to the waiting owner has no floor: the point is to
        // run the owner before this worker takes the object back.
        if (process_impl_lifecycle.guestContextField(self, "windows_guest_handoff_requested").*) {
            process_impl_lifecycle.guestContextField(self, "windows_guest_handoff_requested").* = false;
            process_impl_lifecycle.guestContextField(self, "windows_guest_slice_yield_requested").* = false;
            break;
        }
        if (process_impl_lifecycle.guestContextField(self, "windows_guest_slice_yield_requested").* and executed >= __process_WINDOWS_GUEST_YIELD_MINIMUM_SLICE) {
            process_impl_lifecycle.guestContextField(self, "windows_guest_slice_yield_requested").* = false;
            break;
        }
        self.windows_guest_threads[index].executed_steps +|= process_impl_lifecycle.guestContextField(self, "step_retired").*;
        self.windows_worker_executed_steps +|= process_impl_lifecycle.guestContextField(self, "step_retired").*;
        // Every sixty-fourth instruction, note where this thread is. See
        // `code_low` for why a per-thread code window is the measurement
        // and a per-thread rip is not.
        if (executed >= next_code_sample) {
            next_code_sample = executed + 64;
            self.windows_guest_threads[index].code.sample(process_impl_lifecycle.guestContextField(self, "regs").*.rip);
        }
        if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0) {
            if (process_impl_lifecycle.guestContextField(self, "last_decoded_op").* == .ret) {
                // A worker entry is given a synthetic return slot.  A
                // guest routine that consumes that slot and returns
                // without a caller has completed its Windows thread; it
                // must not turn the scheduler's next decode into a
                // process-wide failure at address zero.
                const thread = self.windows_guest_threads[index];
                __process_log.info("Windows guest thread returned through null RIP; completing worker locally: handle=0x{x} start=0x{x} steps={d}", .{
                    thread.handle,
                    thread.start_routine,
                    process_impl_lifecycle.windowsGuestThreadSteps(self, &self.windows_guest_threads[index]),
                });
                finishWindowsGuestThread(self);
                break;
            }
            const thread = self.windows_guest_threads[index];
            __process_log.err("Windows guest thread reached null RIP: handle=0x{x} start=0x{x} last_op={s} last_len={d} rsp=0x{x} rsp_value=0x{x} rbp=0x{x} entry_slot=0x{x} entry_value=0x{x} stack=[0x{x},0x{x}) call_depth={d}", .{
                thread.handle,
                thread.start_routine,
                @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
                process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
                process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
                process_impl_lifecycle.guestContextField(self, "regs").*.rbp,
                thread.synthetic_return_slot,
                process_impl_guest_memory.read64(self, thread.synthetic_return_slot),
                thread.stack_base,
                thread.stack_base +| thread.stack_size,
                process_impl_execution.activeCallStack(self).frames.items.len,
            });
        }
        if (self.windows_guest_threads[index].status == .blocked) break;
        if (!continue_running) break;
        // A spin proven by a repeated state gains nothing from the rest
        // of its slice: 2026-09-16 spent ~8% of every instruction running
        // detected spins out to the full quantum. Hand the turn back now.
        if (slice_repeated_state and self.windows_guest_threads[index].kernel_calls == slice_kernel_calls) break;
    }
    self.guest_store_buffers.drainContext(index, .context_switch);
    auditOwnerContextAfterSlice(self, &owner_audit, index);

    if (process_impl_lifecycle.isTerminated(self)) {
        self.exit_fault_regs = process_impl_lifecycle.guestContextField(self, "regs").*;
        self.exit_fault_thread_slot = index;
        self.exit_fault_op = process_impl_lifecycle.guestContextField(self, "last_decoded_op").*;
        self.exit_fault_len = process_impl_lifecycle.guestContextField(self, "last_decoded_len").*;
        self.windows_guest_threads[index].status = .failed;
        self.windows_thread_failures +|= 1;
        process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* = null;
        return executed;
    }
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null) {
        const blocked = self.windows_guest_threads[index].status == .blocked;
        if (!blocked) {
            self.windows_guest_threads[index].status = .runnable;
            process_impl_lifecycle.noteWindowsGuestWorkerWake(self, index);
            self.windows_thread_yields +|= 1;
            if (process_impl_lifecycle.guestContextField(self, "windows_slice_pause_yield").* and !slice_repeated_state and
                self.windows_guest_threads[index].kernel_calls == slice_kernel_calls)
            {
                self.windows_pause_spin_slices +|= 1;
            }
            noteWindowsGuestSliceShape(self, index, slice_repeated_state or process_impl_lifecycle.guestContextField(self, "windows_slice_pause_yield").*, slice_kernel_calls);
        }
        process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* = null;
        if ((self.diagnose_abi or self.trace_windows_threads) and !blocked) {
            __process_log.info("Windows guest thread service yield handle=0x{x} slice={d} rip=0x{x} rsp=0x{x}", .{
                self.windows_guest_threads[index].handle,
                executed,
                self.windows_guest_threads[index].context.regs.rip,
                self.windows_guest_threads[index].context.regs.rsp,
            });
        } else if (self.trace_windows_threads and blocked and
            (self.windows_thread_blocks <= 8 or self.windows_thread_blocks % 1024 == 0))
        {
            if (self.windows_guest_threads[index].blocked_srw_lock != 0) {
                __process_log.info("Windows guest thread service block handle=0x{x} lock=0x{x} rip=0x{x} rsp=0x{x}", .{
                    self.windows_guest_threads[index].handle,
                    self.windows_guest_threads[index].blocked_srw_lock,
                    self.windows_guest_threads[index].context.regs.rip,
                    self.windows_guest_threads[index].context.regs.rsp,
                });
            } else {
                __process_log.info("Windows guest thread service block handle=0x{x} condition=0x{x} rip=0x{x} rsp=0x{x}", .{
                    self.windows_guest_threads[index].handle,
                    self.windows_guest_threads[index].blocked_condition,
                    self.windows_guest_threads[index].context.regs.rip,
                    self.windows_guest_threads[index].context.regs.rsp,
                });
            }
        }
    }
    return executed;
}

pub fn nextUnstartedWindowsGuestThread(self: *ElfState) ?usize {
    const ready = struct {
        fn matches(thread: *const __process_WindowsGuestThread) bool {
            return (thread.status == .pending or thread.status == .runnable) and
                thread.suspend_count == 0 and !thread.parallel_worker.isStarted();
        }
    }.matches;
    if (self.windows_preferred_next_guest_thread) |preferred| {
        if (preferred < self.windows_guest_threads.len and ready(&self.windows_guest_threads[preferred])) return preferred;
    }
    const start = if (self.windows_last_serviced_guest_thread_slot) |last|
        (last + 1) % self.windows_guest_threads.len
    else
        0;
    if (self.windows_last_serviced_guest_thread_slot == null) {
        for (0..self.windows_guest_threads.len) |offset| {
            const index = (start + offset) % self.windows_guest_threads.len;
            const thread = &self.windows_guest_threads[index];
            if (ready(thread) and thread.preferred) return index;
        }
    }
    for (0..self.windows_guest_threads.len) |offset| {
        const index = (start + offset) % self.windows_guest_threads.len;
        if (ready(&self.windows_guest_threads[index])) return index;
    }
    return null;
}

pub fn parallelWindowsGuestThreadEntry(raw: *anyopaque, worker: *__process_parallel_workers.Worker) void {
    const self: *ElfState = @ptrCast(@alignCast(raw));
    runParallelWindowsGuestThread(self, worker.slot, worker);
}

pub fn runParallelWindowsGuestThread(self: *ElfState, slot: usize, worker: *__process_parallel_workers.Worker) void {
    if (slot >= self.windows_guest_threads.len) return;
    var watch_name: [__process_concurrency.watch.name_bytes]u8 = undefined;
    _ = __process_concurrency.watch.registerCurrentThread(parallelWorkerWatchName(self, slot, &watch_name));
    defer __process_concurrency.watch.unregisterCurrentThread();
    // The gate record goes back when this host thread ends, so a run that
    // creates and finishes many guest threads never fills the gate.
    defer self.guest_execution_gate.unregisterCurrentThread();
    const prior_coordinated_access = __process_tso_memory.setCoordinatedGuestAccess(true);
    defer _ = __process_tso_memory.setCoordinatedGuestAccess(prior_coordinated_access);
    const previous_binding = __ProcessInternals._windows_guest_execution_binding().*;
    __ProcessInternals._windows_guest_execution_binding().* = .{
        .owner = @ptrCast(self),
        .context = &self.windows_guest_threads[slot].context,
    };
    defer __ProcessInternals._windows_guest_execution_binding().* = previous_binding;
    const context = &self.windows_guest_threads[slot].context;
    context.windows_active_guest_thread_slot = slot;
    // This host thread runs this guest thread for its whole life: its
    // FPCR carries the guest's MXCSR from here on.
    __process_host_fp_control.applyGuestMxcsr(context.regs.mxcsr);
    defer __process_host_fp_control.restoreDefault();
    const thread = &self.windows_guest_threads[slot];
    // The wall-time sampler follows this host thread by guest slot.
    __process_host_profile.registerWorkerWithGuestHandle(slot, thread.handle);
    defer __process_host_profile.unregisterWorker(slot);
    var pending_steps: u64 = 0;
    defer publishParallelWorkerSteps(self, thread, &pending_steps);
    // This thread's registers as it left its last step. While it runs,
    // nobody else writes them; while it is parked a waker may finish its
    // call, so the tripwire is disarmed across every park and resume.
    var tripwire: __process_parallel_diagnostics.register_tripwire.Tripwire = .{};

    var qos_generation: u32 = __process_std.math.maxInt(u32);
    while (!worker.shouldStop() and !self.parallel_guest_termination.load(.acquire)) {
        // The guest can rename this thread while it runs. QoS is host
        // scheduling metadata, so poll for changes at the existing bounded
        // progress-publication boundary instead of loading an atomic on
        // every translated block.
        if (pending_steps == 0) {
            const name_generation = @atomicLoad(u32, &thread.name_generation, .acquire);
            if (name_generation != qos_generation) {
                qos_generation = name_generation;
                process_impl_guest_diagnostics.applyParallelWorkerQos(self, thread);
            }
        }
        switch (@atomicLoad(__process_WindowsGuestThreadStatus, &thread.status, .acquire)) {
            .blocked => {
                tripwire.disarm();
                publishParallelWorkerSteps(self, thread, &pending_steps);
                parkParallelWorker(self, slot, worker);
                continue;
            },
            .completed, .failed, .vacant => break,
            .pending, .runnable => {
                tripwire.disarm();
                var resume_guard = process_impl_lifecycle.lockWindowsRuntime(self);
                if (thread.status == .runnable or thread.status == .pending) {
                    @atomicStore(__process_WindowsGuestThreadStatus, &thread.status, .running, .release);
                }
                resume_guard.unlock();
            },
            .running => {},
        }

        context.windows_guest_slice_yield_requested = false;
        context.windows_guest_handoff_requested = false;
        context.windows_slice_pause_yield = false;
        if (tripwire.check(context.regs.rip, context.regs.rsp)) |finding| {
            process_impl_block_jit.noteContextRace(self, thread.handle, slot, finding);
        }
        const continue_running = process_impl_block_jit.step(self);
        tripwire.arm(context.regs.rip, context.regs.rsp);
        const retired: u64 = @max(context.step_retired, 1);
        pending_steps += retired;
        if (pending_steps >= __process_PARALLEL_WORKER_STEP_BATCH) publishParallelWorkerSteps(self, thread, &pending_steps);

        if (!continue_running) {
            self.parallel_guest_termination.store(true, .release);
            break;
        }
        // `finishWindowsGuestThread` clears this thread-local slot under
        // the runtime lock and drains this thread's queue. Exit here
        // without taking the lock again: a creator may already hold it
        // while recycling this completed slot and joining the worker.
        if (context.windows_active_guest_thread_slot == null) break;
        if (context.windows_guest_handoff_requested or context.windows_guest_slice_yield_requested or
            context.windows_slice_pause_yield)
        {
            if (context.windows_slice_pause_yield) {
                _ = __process_parallel_metrics.saturatingAdd(u64, &thread.pause_host_yields, 1);
            }
            context.windows_guest_handoff_requested = false;
            context.windows_guest_slice_yield_requested = false;
            context.windows_slice_pause_yield = false;
            __process_std.Thread.yield() catch __process_std.atomic.spinLoopHint();
        }
    }
}

pub fn parallelWorkerWatchName(self: *const ElfState, slot: usize, buffer: []u8) []const u8 {
    const label = process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255)));
    const text = __process_std.fmt.bufPrint(buffer, "guest {d} {s}", .{ slot, label }) catch return label;
    return text;
}

pub fn publishParallelWorkerSteps(self: *ElfState, thread: *__process_WindowsGuestThread, pending: *u64) void {
    if (pending.* == 0) return;
    // Each worker is the sole writer of its own progress counter. Publish it
    // with the shared totals so diagnostics still see exact counts at every
    // batch, park, and exit while avoiding one atomic read/write per block.
    _ = __process_parallel_metrics.saturatingAdd(u64, &thread.executed_steps, pending.*);
    _ = __process_parallel_metrics.saturatingAdd(u64, &self.windows_worker_executed_steps, pending.*);
    __process_concurrency.watch.noteProgress(pending.*);
    pending.* = 0;
}

pub fn parkParallelWorker(self: *ElfState, slot: usize, worker: *__process_parallel_workers.Worker) void {
    drainParallelWorkerStoreBuffer(self, slot, .context_switch);
    const thread = &self.windows_guest_threads[slot];
    const observed = worker.epoch();
    if (@atomicLoad(__process_WindowsGuestThreadStatus, &thread.status, .acquire) != .blocked) return;
    const deadline_ticks = @atomicLoad(u64, &thread.blocked_wait_deadline, .acquire);
    const deadline_ns = if (deadline_ticks != 0) windowsGuestTicksToHostNanoseconds(self, deadline_ticks) else null;
    const outcome = worker.waitForChange(observed, deadline_ns);
    if (outcome == .stopping) return;
    if (deadline_ns) |deadline| {
        if (__process_concurrency.monotonicNanoseconds() >= deadline) {
            // This thread's own timeout fell due. Expire it - and anything
            // else due - now, rather than waiting for the owner's sweep,
            // which may be asleep in GetMessage.
            var guard = process_impl_lifecycle.lockWindowsRuntime(self);
            _ = wakeExpiredWindowsGuestWaits(self);
            guard.unlock();
            return;
        }
    }
    if (outcome == .timed_out and @atomicLoad(__process_WindowsGuestThreadStatus, &thread.status, .acquire) != .blocked) {
        worker.noteLostWakeup();
    }
}

pub fn windowsGuestTicksToHostNanoseconds(self: *const ElfState, ticks: u64) ?u64 {
    const clock = process_impl_lifecycle.windowsGuestClockSnapshot(self);
    if (clock.source != .host_monotonic or clock.base_nanos == 0) return null;
    return clock.base_nanos +| (ticks *| __process_guest_clock.nanos_per_tick);
}

pub fn drainParallelWorkerStoreBuffer(self: *ElfState, slot: usize, boundary: __process_tso_memory.Boundary) void {
    const buffer = self.guest_store_buffers.forContext(slot) orelse return;
    if (buffer.isEmpty()) return;
    var lease = self.guest_execution_gate.enterStep();
    defer lease.unlock();
    self.guest_store_buffers.drainContext(slot, boundary);
}

pub fn maybeRunWindowsGuestScheduler(self: *ElfState) void {
    const policy = &self.windows_scheduler;
    if (!policy.enabled or !self.windows_runtime_enabled or process_impl_lifecycle.isTerminated(self) or
        process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null)
    {
        return;
    }
    if (process_impl_lifecycle.observedExecutionSteps(self) < policy.next_service_step) return;

    policy.next_service_step = process_impl_lifecycle.observedExecutionSteps(self) +| policy.quantum;
    // In parallel mode the selection itself must happen under the
    // mutation lease held by serviceWindowsGuestThreads: worker status
    // changes are live while the owner is running.
    if (!self.parallel_guest_execution and nextWindowsGuestThread(self) == null) return;

    const serviced = serviceWindowsGuestThreads(self, policy.slice);
    policy.service_calls +|= 1;
    policy.serviced_steps +|= serviced;
    if (self.trace_windows_threads and
        (policy.service_calls <= 8 or policy.service_calls % 1024 == 0))
    {
        __process_log.info(
            "Windows guest scheduler quantum: owner_step={d} serviced_steps={d} scheduler_calls={d} scheduler_steps={d} worker_calls={d} worker_yields={d} runnable={d}",
            .{
                process_impl_lifecycle.observedExecutionSteps(self),
                serviced,
                policy.service_calls,
                policy.serviced_steps,
                self.windows_thread_service_calls,
                self.windows_thread_yields,
                process_impl_run_reporting.countWindowsWorkers(self, .runnable) + process_impl_run_reporting.countWindowsWorkers(self, .pending),
            },
        );
    }
}
