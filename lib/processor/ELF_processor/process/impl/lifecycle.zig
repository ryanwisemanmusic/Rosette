const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_instruction_decode = @import("instruction_decode.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const __process_DecodeCacheEntry = __ProcessInternals._DecodeCacheEntry;
const __process_DecodeCacheShard = __ProcessInternals._DecodeCacheShard;
const __process_ElfTraceEntry = __ProcessInternals._ElfTraceEntry;
const __process_GuestContextRef = __ProcessInternals._GuestContextRef;
const __process_INITIAL_WINDOWS_HEAP_ALLOCATIONS = __ProcessInternals._INITIAL_WINDOWS_HEAP_ALLOCATIONS;
const __process_MAX_WINDOWS_GUEST_THREADS = __ProcessInternals._MAX_WINDOWS_GUEST_THREADS;
const __process_MEM_BASE = __ProcessInternals._MEM_BASE;
const __process_MEM_SIZE = __ProcessInternals._MEM_SIZE;
const __process_PE_DECODE_CACHE_ENTRIES = __ProcessInternals._PE_DECODE_CACHE_ENTRIES;
const __process_PE_DECODE_CACHE_VICTIM_ENTRIES = __ProcessInternals._PE_DECODE_CACHE_VICTIM_ENTRIES;
const __process_Size = __ProcessInternals._Size;
const __process_TRACE_BUFFER_LEN = __ProcessInternals._TRACE_BUFFER_LEN;
const __process_TimeAuditSample = __ProcessInternals._TimeAuditSample;
const __process_WINDOWS_GUEST_CLOCK_HZ = __ProcessInternals._WINDOWS_GUEST_CLOCK_HZ;
const __process_WINDOWS_GUEST_FILETIME_BASE = __ProcessInternals._WINDOWS_GUEST_FILETIME_BASE;
const __process_WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const __process_WindowsGuestThreadContext = __ProcessInternals._WindowsGuestThreadContext;
const __process_WindowsHeapAllocation = __ProcessInternals._WindowsHeapAllocation;
const __process_WindowsRuntimeLockGuard = __ProcessInternals._WindowsRuntimeLockGuard;
const __process_XENIA_GLOBAL_MUTEX_OWNER_OFFSET = __ProcessInternals._XENIA_GLOBAL_MUTEX_OWNER_OFFSET;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_concurrency = __ProcessInternals._concurrency;
const __process_decode_cache_set_lock_count = __ProcessInternals._decode_cache_set_lock_count;
const __process_enterRuntimeStoreScope = __ProcessInternals._enterRuntimeStoreScope;
const __process_envEquals = __ProcessInternals._envEquals;
const __process_envFlag = __ProcessInternals._envFlag;
const __process_envPresentAndFalse = __ProcessInternals._envPresentAndFalse;
const __process_envText = __ProcessInternals._envText;
const __process_envU64 = __ProcessInternals._envU64;
const __process_execution_history = __ProcessInternals._execution_history;
const __process_gpu_stall = __ProcessInternals._gpu_stall;
const __process_guest_backtrace = __ProcessInternals._guest_backtrace;
const __process_guest_clock = __ProcessInternals._guest_clock;
const __process_guest_page_protection = __ProcessInternals._guest_page_protection;
const __process_guest_spin = __ProcessInternals._guest_spin;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_heap_guard = __ProcessInternals._heap_guard;
const __process_host_fp_control = __ProcessInternals._host_fp_control;
const __process_kuser_shared = __ProcessInternals._kuser_shared;
const __process_log = __ProcessInternals._log;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_parallel_metrics = __ProcessInternals._parallel_metrics;
const __process_runtime_lock_released_ns = __ProcessInternals._runtime_lock_released_ns;
const __process_std = __ProcessInternals._std;
const __process_tso_memory = __ProcessInternals._tso_memory;
const __process_unmapped_reads = __ProcessInternals._unmapped_reads;
const __process_windows_guest_execution_binding = __ProcessInternals._windows_guest_execution_binding;
const __process_windows_runtime_locks = __ProcessInternals._windows_runtime_locks;
const __state_ExitContextSource = __StateInternals._ExitContextSource;

pub fn deinit(self: *ElfState) void {
    stopParallelGuestWorkers(self);
    // Guest MXCSR moved this thread's FPCR; hand the thread back with
    // the host's nearest rounding and kept denormals.
    defer __process_host_fp_control.restoreDefault();
    // Pending store queues retain mapped host addresses. Publish them
    // before mappings, aliases and backing allocations are torn down.
    process_impl_block_jit.flushAllGuestStoreBuffers(self, .shutdown);
    for (self.windows_stub_storage[0..self.windows_stub_count], 0..) |stub, index| {
        if (!self.windows_stub_owned_names[index]) continue;
        self.allocator.free(stub.dll_name);
        self.allocator.free(stub.function_name);
    }
    self.guest_store_buffers.deinit(self.allocator);
    if (self.block_jit) |jit| {
        jit.destroy(self.allocator);
        self.block_jit = null;
    }
    // Every worker host thread has joined above.
    for (self.windows_guest_threads) |*thread| {
        if (thread.parallel_block_jit) |jit| jit.destroy(self.allocator);
        thread.parallel_block_jit = null;
    }
    if (self.windows_iat_stub_index.len != 0) self.allocator.free(self.windows_iat_stub_index);
    self.windows_iat_stub_index = &.{};
    if (self.code_page_generations.len != 0) self.allocator.free(self.code_page_generations);
    self.code_page_generations = &.{};
    if (self.windows_import_histogram) |histogram| self.allocator.destroy(histogram);
    self.windows_import_histogram = null;
    if (self.decode_cache.len != 0) self.allocator.free(self.decode_cache);
    self.decode_cache = &.{};
    if (self.decode_cache_victims.len != 0) self.allocator.free(self.decode_cache_victims);
    self.decode_cache_victims = &.{};
    if (self.decode_cache_shards.len != 0) self.allocator.free(self.decode_cache_shards);
    self.decode_cache_shards = &.{};
    self.guest_kernel_calls.deinit(self.allocator);
    self.guest_page_protection.deinit(self.allocator);
    self.windows_registry.deinit(self.allocator);
    for (&self.windows_guest_thread_tlbs) |*tlb_slot| {
        if (tlb_slot.*) |tlb| self.allocator.destroy(tlb);
        tlb_slot.* = null;
    }
    if (self.block_jit_tlb) |tlb| self.allocator.destroy(tlb);
    self.block_jit_tlb = null;
    for (self.windows_guest_threads) |*thread| thread.call_stack.deinit(self.allocator);
    if (self.windows_guest_threads.len != 0) {
        self.allocator.free(self.windows_guest_threads);
        self.windows_guest_threads = &.{};
    }
    if (self.windows_guest_output_governors) |governors| self.allocator.destroy(governors);
    self.windows_guest_output_governors = null;
    if (self.windows_host_io) |io| {
        for (&self.windows_files) |*slot| {
            if (slot.standard_stream == null) {
                if (slot.file) |file| file.close(io);
            }
            slot.* = .{};
        }
        for (&self.windows_finds) |*slot| {
            if (slot.dir) |dir| dir.close(io);
            slot.* = .{};
        }
    }
    for (&self.windows_file_mappings) |*mapping| {
        if (mapping.backing) |backing| __process_std.posix.munmap(backing);
        mapping.* = .{};
    }
    for (&self.windows_memory_views) |*view| view.* = .{};
    for (&self.windows_virtual_allocations) |*allocation| {
        if (allocation.backing) |backing| __process_std.posix.munmap(backing);
        allocation.* = .{};
    }
    self.windows_mapped_ranges = .{};
    // The Vulkan driver, not ElfState, owns these bytes.
    @memset(&self.native_memory_aliases, .{});
    self.native_memory_alias_count = 0;
    if (self.windows_heap_allocations.len != 0) self.allocator.free(self.windows_heap_allocations);
    if (self.windows_heap_free_indices.len != 0) self.allocator.free(self.windows_heap_free_indices);
    if (self.windows_heap_quarantine.len != 0) self.allocator.free(self.windows_heap_quarantine);
    var bins = self.windows_heap_bins.valueIterator();
    while (bins.next()) |bin| bin.indices.deinit(self.allocator);
    self.windows_heap_bins.deinit(self.allocator);
    if (self.interactive_output_path) |path| self.allocator.free(path);
    self.call_stack.deinit(self.allocator);
    if (self.trace_storage.len != 0) self.allocator.free(self.trace_storage);
    self.allocator.free(self.mem);
}

pub fn stopParallelGuestWorkers(self: *ElfState) void {
    if (self.windows_guest_threads.len == 0) return;
    self.parallel_guest_wake_hub.notify();
    for (self.windows_guest_threads) |*thread| thread.parallel_worker.requestStop();
    for (self.windows_guest_threads) |*thread| thread.parallel_worker.join();
}

pub fn windowsWorkerSteps(self: *const ElfState) u64 {
    if (self.parallel_guest_execution) {
        return __process_parallel_metrics.load(u64, &self.windows_worker_executed_steps);
    }
    return self.windows_worker_executed_steps;
}

pub fn windowsThreadServiceSteps(self: *const ElfState) u64 {
    if (self.parallel_guest_execution) {
        return __process_parallel_metrics.load(u64, &self.windows_thread_service_steps);
    }
    return self.windows_thread_service_steps;
}

pub fn windowsGuestThreadSteps(self: *const ElfState, thread: *const __process_WindowsGuestThread) u64 {
    if (self.parallel_guest_execution) return __process_parallel_metrics.load(u64, &thread.executed_steps);
    return thread.executed_steps;
}

pub fn observedExecutionSteps(self: *const ElfState) u64 {
    if (!self.parallel_guest_execution) return self.executed_steps;
    return self.parallel_owner_executed_steps.load(.acquire) +|
        windowsWorkerSteps(self);
}

pub fn runElapsedMilliseconds(self: *const ElfState) u64 {
    if (self.run_started_ns == 0) return 0;
    return (__process_monotonicNanoseconds() -| self.run_started_ns) / __process_std.time.ns_per_ms;
}

pub fn ownerExecutedSteps(self: *const ElfState) u64 {
    if (self.parallel_guest_execution) return self.parallel_owner_executed_steps.load(.acquire);
    return self.executed_steps;
}

pub fn isTerminated(self: *const ElfState) bool {
    return if (self.parallel_guest_execution)
        self.parallel_guest_termination.load(.acquire)
    else
        self.terminated;
}

pub fn markFaulted(self: *ElfState) void {
    if (self.parallel_guest_execution) {
        _ = self.parallel_fault_snapshot.capture(.{
            .regs = guestContextField(self, "regs").*,
            .thread_slot = guestContextField(self, "windows_active_guest_thread_slot").*,
            .op = guestContextField(self, "last_decoded_op").*,
            .len = guestContextField(self, "last_decoded_len").*,
        });
    }
    self.faulted = true;
}

pub fn markTerminated(self: *ElfState) void {
    if (self.parallel_guest_execution) {
        self.parallel_guest_termination.store(true, .release);
        // Whoever is asleep - a blocked GetMessage, parked workers - must
        // see the end of the run now, not at its next safety-net wake.
        self.windows_message_event.notify();
        self.parallel_guest_wake_hub.notify();
    } else {
        self.terminated = true;
    }
}

pub fn parallelTerminationRequested(self: *const ElfState) bool {
    return self.parallel_guest_termination.load(.acquire);
}

pub fn guestContextRef(self: *ElfState) __process_GuestContextRef {
    const owner: *anyopaque = @ptrCast(self);
    if (__ProcessInternals._windows_guest_execution_binding().*) |binding| {
        if (binding.owner == owner) return .{ .bound = binding.context, .state = self };
    }
    return .{ .bound = null, .state = self };
}

pub fn guestContextField(
    self: anytype,
    comptime field: []const u8,
) if (@typeInfo(@TypeOf(self)).pointer.is_const)
    *const @FieldType(__process_WindowsGuestThreadContext, field)
else
    *@FieldType(__process_WindowsGuestThreadContext, field) {
    const owner: *anyopaque = @ptrCast(@constCast(self));
    if (__ProcessInternals._windows_guest_execution_binding().*) |binding| {
        if (binding.owner == owner) {
            if (comptime @typeInfo(@TypeOf(self)).pointer.is_const) {
                return &@field(binding.context.*, field);
            } else {
                return &@field(binding.context.*, field);
            }
        }
    }
    if (comptime @typeInfo(@TypeOf(self)).pointer.is_const) {
        return &@field(self.*, field);
    } else {
        return &@field(self.*, field);
    }
}

pub fn windowsGuestContextField(
    self: anytype,
    comptime field: []const u8,
) if (@typeInfo(@TypeOf(self)).pointer.is_const)
    *const @FieldType(__process_WindowsGuestThreadContext, field)
else
    *@FieldType(__process_WindowsGuestThreadContext, field) {
    return guestContextField(self, field);
}

pub fn windowsGuestErrnoStorage(self: anytype) if (@typeInfo(@TypeOf(self)).pointer.is_const) *const u64 else *u64 {
    const owner: *anyopaque = @ptrCast(@constCast(self));
    if (__ProcessInternals._windows_guest_execution_binding().*) |binding| {
        if (binding.owner == owner) return &binding.context.windows_errno_storage;
    }
    return &self.windows_crt_globals.owner_errno_storage;
}

pub fn lockWindowsRuntime(self: *ElfState) __process_WindowsRuntimeLockGuard {
    return lockWindowsRuntimeKind(self, true);
}

pub fn lockWindowsRuntimeForDispatch(self: *ElfState) __process_WindowsRuntimeLockGuard {
    return lockWindowsRuntimeKind(self, false);
}

pub fn withWindowsRuntimeLockReleased(self: *ElfState, context: anytype, callback: anytype) @TypeOf(callback(context)) {
    return withWindowsRuntimeLockReleasedFor(self, .native_pipeline, context, callback);
}

pub fn withWindowsRuntimeLockReleasedForGpuFenceWait(self: *ElfState, context: anytype, callback: anytype) @TypeOf(callback(context)) {
    return withWindowsRuntimeLockReleasedFor(self, .gpu_fence_wait, context, callback);
}

pub fn tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(self: *ElfState, context: anytype, callback: anytype) bool {
    if (!self.parallel_guest_execution) {
        callback(context);
        return true;
    }
    const owner: *anyopaque = @ptrCast(self);
    if (__ProcessInternals._windows_runtime_locks().*.depth(owner) == 0) {
        callback(context);
        return true;
    }
    if (__ProcessInternals._windows_runtime_locks().*.pinnedDepth(owner) != 0) {
        self.runtime_lock_gpu_queue_wait_yield_refusals +|= 1;
        return false;
    }
    withWindowsRuntimeLockReleasedFor(self, .gpu_queue_wait, context, callback);
    return true;
}

pub fn withWindowsRuntimeLockReleasedFor(
    self: *ElfState,
    purpose: enum { native_pipeline, gpu_fence_wait, gpu_queue_wait },
    context: anytype,
    callback: anytype,
) @TypeOf(callback(context)) {
    if (!self.parallel_guest_execution) return callback(context);
    const owner: *anyopaque = @ptrCast(self);
    if (__ProcessInternals._windows_runtime_locks().*.depth(owner) == 0) return callback(context);
    if (__ProcessInternals._windows_runtime_locks().*.pinnedDepth(owner) != 0) {
        switch (purpose) {
            .native_pipeline => self.runtime_lock_native_pipeline_yield_refusals +|= 1,
            .gpu_fence_wait => self.runtime_lock_gpu_fence_wait_yield_refusals +|= 1,
            .gpu_queue_wait => self.runtime_lock_gpu_queue_wait_yield_refusals +|= 1,
        }
        return callback(context);
    }

    const started = __process_concurrency.monotonicNanoseconds();
    self.windows_runtime_mutex.unlock();
    var region = self.guest_execution_gate.enterSafeRegion();
    defer {
        // Reacquire under a safe region: an address-space stop may be
        // waiting for this executor while the host call is in flight.
        self.windows_runtime_mutex.lock();
        region.leave();
        const released = __process_concurrency.monotonicNanoseconds() -| started;
        __ProcessInternals._runtime_lock_released_ns().* +%= released;
        switch (purpose) {
            .native_pipeline => {
                self.runtime_lock_native_pipeline_yields +|= 1;
                self.runtime_lock_native_pipeline_yield_ns +|= released;
            },
            .gpu_fence_wait => {
                self.runtime_lock_gpu_fence_wait_yields +|= 1;
                self.runtime_lock_gpu_fence_wait_yield_ns +|= released;
            },
            .gpu_queue_wait => {
                self.runtime_lock_gpu_queue_wait_yields +|= 1;
                self.runtime_lock_gpu_queue_wait_yield_ns +|= released;
            },
        }
    }
    return callback(context);
}

pub fn lockWindowsRuntimeKind(self: *ElfState, pinned: bool) __process_WindowsRuntimeLockGuard {
    const owner: *anyopaque = @ptrCast(self);
    if (__ProcessInternals._windows_runtime_locks().*.contains(owner)) {
        const stack_index = __ProcessInternals._windows_runtime_locks().*.push(owner, pinned);
        return .{
            .mutex = &self.windows_runtime_mutex,
            .owner = owner,
            .stack_index = stack_index,
            .reentrant = true,
            .pinned = pinned,
            .prior_store_buffer = __process_enterRuntimeStoreScope(),
        };
    }
    if (self.parallel_guest_execution) {
        // Overlapping executors share the runtime's tables, not a need
        // to stop each other: take the tables' mutex and nothing else.
        // Every import used to stop the world here - on 2026-09-25 that
        // was three stops per iteration of Xenia's message loop, which
        // held the Emulator thread to 0.28M instructions a second - and a
        // worker holding that stop while it waited on the main thread
        // deadlocked the run. The caller's own buffered stores are
        // published by `enterRuntimeStoreScope`: a runtime call is a
        // serializing boundary for the thread that makes it, and other
        // threads' buffers are theirs to drain, as on real hardware.
        //
        // Waiting for the mutex is a safe region: this thread is usually
        // inside a step, and the holder may be about to stop the world,
        // which must not wait for a thread that is waiting for it.
        const prior_store_buffer = __process_enterRuntimeStoreScope();
        var region = self.guest_execution_gate.enterSafeRegion();
        self.windows_runtime_mutex.lock();
        region.leave();
        const stack_index = __ProcessInternals._windows_runtime_locks().*.push(owner, pinned);
        return .{
            .mutex = &self.windows_runtime_mutex,
            .owner = owner,
            .stack_index = stack_index,
            .reentrant = false,
            .pinned = pinned,
            .prior_store_buffer = prior_store_buffer,
            .wake_epoch_at_lock = self.windows_thread_wake_epoch,
        };
    }
    // One executor: the mutation is uncontended, and draining every
    // context's queue keeps the serial contract exactly as it was.
    const gate_guard = self.guest_execution_gate.enterMutation();
    const prior_store_buffer = __process_enterRuntimeStoreScope();
    if (self.windows_runtime_enabled) process_impl_block_jit.flushAllGuestStoreBuffers(self, .runtime_call);
    self.windows_runtime_mutex.lock();
    const stack_index = __ProcessInternals._windows_runtime_locks().*.push(owner, pinned);
    return .{
        .mutex = &self.windows_runtime_mutex,
        .gate_guard = gate_guard,
        .owner = owner,
        .stack_index = stack_index,
        .reentrant = false,
        .pinned = pinned,
        .flush_tso_on_unlock = self.windows_runtime_enabled,
        .prior_store_buffer = prior_store_buffer,
        .wake_epoch_at_lock = self.windows_thread_wake_epoch,
    };
}

pub fn lockGuestRuntimeMutationIfParallel(self: *ElfState) ?__process_WindowsRuntimeLockGuard {
    if (!self.parallel_guest_execution) return null;
    return lockWindowsRuntime(self);
}

pub fn lockGuestAddressSpaceIfParallel(self: *ElfState) ?__process_WindowsRuntimeLockGuard {
    if (!self.parallel_guest_execution) return null;
    var guard = lockWindowsRuntime(self);
    guard.gate_guard = self.guest_execution_gate.enterMutation();
    process_impl_block_jit.flushAllGuestStoreBuffers(self, .runtime_call);
    return guard;
}

pub fn noteWindowsThreadWake(self: *ElfState) void {
    self.windows_thread_wake_epoch +%= 1;
}

pub fn wakeGuestWaiters(self: *ElfState) void {
    noteWindowsThreadWake(self);
}

pub fn captureWindowsGuestContext(self: *const ElfState) __process_WindowsGuestThreadContext {
    return .{
        .regs = guestContextField(self, "regs").*,
        .xmm = guestContextField(self, "xmm").*,
        .ymm_hi = guestContextField(self, "ymm_hi").*,
        .zmm_hi = guestContextField(self, "zmm_hi").*,
        .k = guestContextField(self, "k").*,
        .x87_stack = guestContextField(self, "x87_stack").*,
        .x87_tags = guestContextField(self, "x87_tags").*,
        .x87_top = guestContextField(self, "x87_top").*,
        .x87_status = guestContextField(self, "x87_status").*,
        .x87_control = guestContextField(self, "x87_control").*,
        .windows_last_error = guestContextField(self, "windows_last_error").*,
        .windows_errno_storage = windowsGuestErrnoStorage(self).*,
        .windows_current_import = guestContextField(self, "windows_current_import").*,
        .windows_current_import_return = guestContextField(self, "windows_current_import_return").*,
        .guest_access_violation_pending = guestContextField(self, "guest_access_violation_pending").*,
        .guest_access_violation = guestContextField(self, "guest_access_violation").*,
        .windows_initterm_frames = guestContextField(self, "windows_initterm_frames").*,
        .windows_initterm_frame_count = guestContextField(self, "windows_initterm_frame_count").*,
        .windows_qsort_frames = guestContextField(self, "windows_qsort_frames").*,
        .windows_qsort_frame_count = guestContextField(self, "windows_qsort_frame_count").*,
        .windows_message_dispatch_frames = guestContextField(self, "windows_message_dispatch_frames").*,
        .windows_message_dispatch_frame_count = guestContextField(self, "windows_message_dispatch_frame_count").*,
        .windows_audio_callback_frames = guestContextField(self, "windows_audio_callback_frames").*,
        .windows_audio_callback_frame_count = guestContextField(self, "windows_audio_callback_frame_count").*,
        .block_jit_scratch = guestContextField(self, "block_jit_scratch").*,
        .block_jit_tlb = process_impl_block_jit.activeBlockJitTlb(@constCast(self)),
        .step_retired = guestContextField(self, "step_retired").*,
        .guest_clock_sample_steps = guestContextField(self, "guest_clock_sample_steps").*,
        .windows_guest_slice_yield_requested = guestContextField(self, "windows_guest_slice_yield_requested").*,
        .windows_slice_pause_yield = guestContextField(self, "windows_slice_pause_yield").*,
        .windows_guest_handoff_requested = guestContextField(self, "windows_guest_handoff_requested").*,
        .windows_slice_clock_reads = guestContextField(self, "windows_slice_clock_reads").*,
        .active_guest_thread = guestContextField(self, "active_guest_thread").*,
        .windows_active_guest_thread_slot = guestContextField(self, "windows_active_guest_thread_slot").*,
        .windows_thread_id = currentWindowsThreadId(self),
        .active_idle_source = guestContextField(self, "active_idle_source").*,
        .last_decoded_op = guestContextField(self, "last_decoded_op").*,
        .last_decoded_len = guestContextField(self, "last_decoded_len").*,
        .last_instruction_rip = guestContextField(self, "last_instruction_rip").*,
        .decode_failure_is_invalid_control_target = guestContextField(self, "decode_failure_is_invalid_control_target").*,
    };
}

pub fn restoreWindowsGuestContext(self: *ElfState, context: *const __process_WindowsGuestThreadContext) void {
    guestContextField(self, "regs").* = context.regs;
    guestContextField(self, "xmm").* = context.xmm;
    guestContextField(self, "ymm_hi").* = context.ymm_hi;
    guestContextField(self, "zmm_hi").* = context.zmm_hi;
    guestContextField(self, "k").* = context.k;
    guestContextField(self, "x87_stack").* = context.x87_stack;
    guestContextField(self, "x87_tags").* = context.x87_tags;
    guestContextField(self, "x87_top").* = context.x87_top;
    guestContextField(self, "x87_status").* = context.x87_status;
    guestContextField(self, "x87_control").* = context.x87_control;
    guestContextField(self, "windows_last_error").* = context.windows_last_error;
    windowsGuestErrnoStorage(self).* = context.windows_errno_storage;
    guestContextField(self, "windows_current_import").* = context.windows_current_import;
    guestContextField(self, "windows_current_import_return").* = context.windows_current_import_return;
    guestContextField(self, "guest_access_violation_pending").* = context.guest_access_violation_pending;
    guestContextField(self, "guest_access_violation").* = context.guest_access_violation;
    guestContextField(self, "windows_initterm_frames").* = context.windows_initterm_frames;
    guestContextField(self, "windows_initterm_frame_count").* = context.windows_initterm_frame_count;
    guestContextField(self, "windows_qsort_frames").* = context.windows_qsort_frames;
    guestContextField(self, "windows_qsort_frame_count").* = context.windows_qsort_frame_count;
    guestContextField(self, "windows_message_dispatch_frames").* = context.windows_message_dispatch_frames;
    guestContextField(self, "windows_message_dispatch_frame_count").* = context.windows_message_dispatch_frame_count;
    guestContextField(self, "windows_audio_callback_frames").* = context.windows_audio_callback_frames;
    guestContextField(self, "windows_audio_callback_frame_count").* = context.windows_audio_callback_frame_count;
    guestContextField(self, "block_jit_scratch").* = context.block_jit_scratch;
    self.block_jit_tlb_active = context.block_jit_tlb;
    guestContextField(self, "step_retired").* = context.step_retired;
    guestContextField(self, "guest_clock_sample_steps").* = context.guest_clock_sample_steps;
    guestContextField(self, "windows_guest_slice_yield_requested").* = context.windows_guest_slice_yield_requested;
    guestContextField(self, "windows_slice_pause_yield").* = context.windows_slice_pause_yield;
    guestContextField(self, "windows_guest_handoff_requested").* = context.windows_guest_handoff_requested;
    guestContextField(self, "windows_slice_clock_reads").* = context.windows_slice_clock_reads;
    guestContextField(self, "active_guest_thread").* = context.active_guest_thread;
    guestContextField(self, "windows_active_guest_thread_slot").* = context.windows_active_guest_thread_slot;
    guestContextField(self, "windows_thread_id").* = context.windows_thread_id;
    guestContextField(self, "active_idle_source").* = context.active_idle_source;
    guestContextField(self, "last_decoded_op").* = context.last_decoded_op;
    guestContextField(self, "last_decoded_len").* = context.last_decoded_len;
    guestContextField(self, "last_instruction_rip").* = context.last_instruction_rip;
    guestContextField(self, "decode_failure_is_invalid_control_target").* = context.decode_failure_is_invalid_control_target;
}

pub fn noteWindowsFastIdentityImport(self: *ElfState) void {
    _ = self.windows_fast_identity_imports.fetchAdd(1, .monotonic);
}

pub fn noteWindowsFastAffinityImport(self: *ElfState, return_rip: u64) void {
    _ = self.windows_fast_affinity_import_calls.fetchAdd(1, .monotonic);
    guestContextField(self, "windows_current_import").* = "GetProcessAffinityMask";
    guestContextField(self, "windows_current_import_return").* = return_rip;
}

pub fn windowsFastAffinityMasks(self: *const ElfState) [2]u64 {
    return .{
        self.windows_process_affinity_published.load(.acquire),
        self.windows_system_affinity_published.load(.acquire),
    };
}

pub fn noteWindowsFastSleepZeroImport(self: *ElfState, return_rip: u64) void {
    _ = self.windows_fast_sleep_zero_import_calls.fetchAdd(1, .monotonic);
    guestContextField(self, "windows_current_import").* = "Sleep";
    guestContextField(self, "windows_current_import_return").* = return_rip;
}

pub fn windowsFastSleepZeroImportAllowed(self: *ElfState) bool {
    const slot = guestContextField(self, "windows_active_guest_thread_slot").* orelse return false;
    if (slot >= self.windows_guest_threads.len) return false;
    const thread_id = self.windows_guest_threads[slot].thread_id;
    if (thread_id == 0) return false;
    const address = self.xenia_global_mutex_address orelse return true;
    if (process_impl_execution.guestMemoryConst(self, address, 12) == null) return false;
    const owner = process_impl_guest_memory.read32(self, address + __process_XENIA_GLOBAL_MUTEX_OWNER_OFFSET);
    // Treat an owner match as held even while recursion is zero. During
    // an Xenia lock handoff that is the interval before the new owner
    // collects its recursive depth; bypassing the regular Sleep handler
    // there could skip the lock's handoff/backoff protocol.
    return owner != @as(u32, @truncate(thread_id));
}

pub fn currentWindowsThreadId(self: *const ElfState) u64 {
    if (guestContextField(self, "windows_active_guest_thread_slot").*) |index| {
        const thread_id = self.windows_guest_threads[index].thread_id;
        if (thread_id != 0) return thread_id;
    }
    // The owner context is the process's initial Windows thread. Its
    // TEB uses the same stable ID, and worker contexts retain their
    // independently assigned ID when dispatched by another host thread.
    return if (guestContextField(self, "windows_thread_id").* != 0) guestContextField(self, "windows_thread_id").* else 1;
}

pub fn windowsGuestClockTicks(self: *const ElfState) u64 {
    return windowsGuestClockSnapshot(self).ticks;
}

pub fn windowsGuestFastFileTime(self: *ElfState) u64 {
    _ = windowsGuestFastClockTicks(self);
    return windowsGuestPublishedFileTime(self);
}

pub fn windowsGuestPublishedFileTime(self: *const ElfState) u64 {
    const ticks = if (self.guest_clock.source == .retired_instructions) windowsGuestClockTicks(self) else self.guest_clock_published_ticks.load();
    const seconds = ticks / __process_WINDOWS_GUEST_CLOCK_HZ;
    const remainder = ticks % __process_WINDOWS_GUEST_CLOCK_HZ;
    return __process_WINDOWS_GUEST_FILETIME_BASE +|
        (seconds *| 10_000_000) +|
        (remainder *| 10_000_000 / __process_WINDOWS_GUEST_CLOCK_HZ);
}

pub fn windowsGuestFastClockTicks(self: *ElfState) u64 {
    // Instruction-derived time changes on every step. Keep that rare
    // diagnostic mode on the coherent mutex path instead of publishing
    // an atomic for every retired guest instruction.
    if (self.guest_clock.source == .retired_instructions) return windowsGuestClockTicks(self);
    // Advance the clock first, as the locked handler does, but only when
    // nobody holds it: a reading never queues. The published snapshot
    // alone went stale. The 2026-10-02 main-menu freeze had MAIN and
    // RENDER spinning on a vblank-paced flag while every lane-served
    // QueryPerformanceCounter repeated an old tick count.
    process_impl_instruction_decode.sampleWindowsGuestClockIfFree(self);
    return self.guest_clock_published_ticks.load();
}

pub fn windowsFastImportMayBypassRuntimeLock(self: *const ElfState) bool {
    if (!self.parallel_guest_execution or self.guest_clock.source != .host_monotonic) return false;
    const owner: *anyopaque = @ptrCast(@constCast(self));
    return __ProcessInternals._windows_runtime_locks().*.depth(owner) == 0;
}

pub fn beginWindowsFastImportStoreScope(_: *ElfState) ?*__process_tso_memory.StoreBuffer {
    return __process_enterRuntimeStoreScope();
}

pub fn endWindowsFastImportStoreScope(_: *ElfState, prior: ?*__process_tso_memory.StoreBuffer) void {
    _ = __process_tso_memory.setActiveStoreBuffer(prior);
}

pub fn windowsFastCrtImportMayBypassRuntimeLock(self: *const ElfState) bool {
    if (!self.parallel_guest_execution) return false;
    const owner: *anyopaque = @ptrCast(@constCast(self));
    return __ProcessInternals._windows_runtime_locks().*.depth(owner) == 0;
}

pub fn noteWindowsFastCrtImport(self: *ElfState, op: anytype) void {
    const index: usize = @intFromEnum(op);
    _ = self.windows_fast_crt_import_calls[index].fetchAdd(1, .monotonic);
    const names = [_][]const u8{ "memcpy", "memmove", "memset" };
    guestContextField(self, "windows_current_import").* = names[index];
}

pub fn noteWindowsFastCrtStringImport(self: *ElfState, op: anytype) void {
    const index: usize = @intFromEnum(op);
    _ = self.windows_fast_crt_string_import_calls[index].fetchAdd(1, .monotonic);
    const names = [_][]const u8{ "memcmp", "strlen", "strcmp", "strxfrm" };
    guestContextField(self, "windows_current_import").* = names[index];
}

pub fn noteWindowsFastHeapImport(self: *ElfState, op: anytype) void {
    const index: usize = @intFromEnum(op);
    _ = self.windows_fast_heap_import_calls[index].fetchAdd(1, .monotonic);
    const names = [_][]const u8{ "malloc/uninitialized", "calloc/zeroed", "free" };
    guestContextField(self, "windows_current_import").* = names[index];
}

pub fn windowsFastCrtImportCalls(self: *const ElfState) u64 {
    var total: u64 = 0;
    for (&self.windows_fast_crt_import_calls) |*counter| total +|= counter.load(.acquire);
    for (&self.windows_fast_crt_string_import_calls) |*counter| total +|= counter.load(.acquire);
    return total;
}

pub fn noteWindowsFastTimeImport(self: *ElfState, return_rip: u64, query: anytype) void {
    const names = [_][]const u8{ "GetSystemTimePreciseAsFileTime", "QueryPerformanceCounter", "QueryPerformanceFrequency" };
    const index: usize = @intFromEnum(query);
    if (index == 0)
        _ = self.windows_fast_time_import_calls.fetchAdd(1, .monotonic)
    else
        _ = self.windows_fast_counter_import_calls[index - 1].fetchAdd(1, .monotonic);
    guestContextField(self, "windows_current_import").* = names[index];
    guestContextField(self, "windows_current_import_return").* = return_rip;
}

pub fn windowsFastImportCalls(self: *const ElfState) u64 {
    return self.windows_fast_time_import_calls.load(.acquire) +%
        self.windows_fast_counter_import_calls[0].load(.acquire) +%
        self.windows_fast_counter_import_calls[1].load(.acquire) +%
        self.windows_fast_affinity_import_calls.load(.acquire) +%
        self.windows_fast_sleep_zero_import_calls.load(.acquire) +%
        windowsFastCrtImportCalls(self) +%
        self.windows_fast_heap_import_calls[0].load(.acquire) +%
        self.windows_fast_heap_import_calls[1].load(.acquire) +%
        self.windows_fast_heap_import_calls[2].load(.acquire);
}

pub fn windowsImportCallCount(self: *const ElfState) u64 {
    return self.windows_import_calls +% windowsFastImportCalls(self);
}

pub fn clearWindowsFastTimeImportReturn(self: *ElfState) void {
    guestContextField(self, "windows_current_import_return").* = 0;
}

pub fn publishWindowsGuestClockTicks(self: *ElfState) void {
    if (self.guest_clock.source != .host_monotonic) return;
    self.guest_clock_published_ticks.publish(self.guest_clock.ticks);
}

pub fn windowsGuestClockSnapshot(self: *const ElfState) __process_guest_clock.Clock {
    const mutex = @constCast(&self.guest_clock_mutex);
    mutex.lock();
    defer mutex.unlock();
    return self.guest_clock;
}

pub fn windowsGuestClockHz(_: *const ElfState) u64 {
    return __process_WINDOWS_GUEST_CLOCK_HZ;
}

pub fn windowsGuestFileTime(self: *const ElfState) u64 {
    const ticks = windowsGuestClockTicks(self);
    const seconds = ticks / __process_WINDOWS_GUEST_CLOCK_HZ;
    const remainder = ticks % __process_WINDOWS_GUEST_CLOCK_HZ;
    return __process_WINDOWS_GUEST_FILETIME_BASE +|
        (seconds *| 10_000_000) +|
        (remainder *| 10_000_000 / __process_WINDOWS_GUEST_CLOCK_HZ);
}

pub fn requestWindowsGuestSliceYield(self: *ElfState) void {
    if (guestContextField(self, "windows_active_guest_thread_slot").* == null) return;
    if (!guestContextField(self, "windows_guest_slice_yield_requested").*) {
        guestContextField(self, "windows_guest_slice_yield_requested").* = true;
        if (!self.parallel_guest_execution) self.windows_guest_slice_yields +|= 1;
    }
}

pub fn noteWindowsGuestPause(self: *ElfState) void {
    const slot = guestContextField(self, "windows_active_guest_thread_slot").* orelse return;
    var yield_host = true;
    var pause_batch: u64 = 1;
    if (self.parallel_guest_execution) {
        // Only this guest thread's executor writes its PAUSE count; the
        // reporting thread merely reads it atomically. Avoid a contended
        // compare-exchange loop for every spin hint. One relaxed atomic
        // RMW supplies both the exact count and the 256-hint scheduling
        // cadence; the old load+store pair issued two atomics per PAUSE.
        const counter = &self.windows_guest_threads[slot].pause_hints;
        const hints = @atomicRmw(u64, counter, .Add, 1, .monotonic) +% 1;
        // Each guest worker already has a preemptible host thread. Halo 3
        // issued 369 million PAUSEs on RENDER in one gameplay run; a
        // pthread yield for every hint spent time in the host scheduler
        // without making another guest worker runnable. Keep the first
        // hint prompt, then yield once per 256 hints. Cooperative mode
        // still ends every PAUSE slice because it owns the only executor.
        yield_host = hints == __process_std.math.maxInt(u64) or (hints - 1) % 256 == 0;
        pause_batch = if (hints == 1) 1 else 256;
    } else {
        self.windows_guest_threads[slot].pause_hints +|= 1;
        self.windows_guest_pause_yields +|= 1;
    }
    if (yield_host) {
        requestWindowsGuestSliceYield(self);
        guestContextField(self, "windows_slice_pause_yield").* = true;
    }
    if (!self.windows_runtime_enabled) return;
    // On parallel workers, both the slice yield and guest-spin sampling
    // already run at the same 256-PAUSE boundary. Read the frame counter,
    // acquire a host timestamp and update the spin detector once per
    // batch instead of once per hint. The detector receives the batch's
    // exact pause count, so the 64K capture threshold and 256-clock stride
    // remain in guest-pause units.
    if (self.parallel_guest_execution and !yield_host) return;
    const thread = &self.windows_guest_threads[slot];
    const swaps = @atomicLoad(u64, &self.frame_cost.swaps, .monotonic);
    const wants_clock = if (pause_batch == 1)
        thread.spin.wantsClock(swaps)
    else
        thread.spin.wantsClockBatch(swaps, pause_batch);
    const now: ?u64 = if (wants_clock) __process_monotonicNanoseconds() else null;
    const triggered = if (pause_batch == 1)
        thread.spin.notePause(guestContextField(self, "regs").*.rip, swaps, now)
    else
        thread.spin.notePauseBatch(guestContextField(self, "regs").*.rip, swaps, now, pause_batch);
    if (triggered) {
        thread.spin.capture_watch_epoch = self.spin_watch.epoch.load(.acquire);
        _ = self.spin_capture_threads.fetchAdd(1, .monotonic);
        reportGuestSpinTrigger(self, slot, swaps, "pause_spin");
    }
    if (now) |now_ns| {
        if (thread.spin.assistDue(swaps, now_ns)) runStallAssist(self, slot, swaps, now_ns);
    }
}

pub fn retireParallelPauseTail(self: *ElfState) void {
    if (!self.parallel_guest_execution or !self.parallel_pause_batches_enabled or process_impl_block_jit.blockJitTracingActive(self) or
        self.guest_clock.source == .retired_instructions) return;
    const slot = guestContextField(self, "windows_active_guest_thread_slot").* orelse return;
    if (slot >= self.windows_guest_threads.len) return;
    const thread = &self.windows_guest_threads[slot];
    var additional: u64 = 0;
    while (additional < 7 and !guestContextField(self, "windows_guest_slice_yield_requested").* and
        thread.spin.capture_remaining == 0 and !isTerminated(self))
    {
        const rip = guestContextField(self, "regs").*.rip;
        if (process_impl_block_jit.blockJitTargetHooked(self, rip)) break;
        var fetched: [16]u8 = undefined;
        const bytes = process_impl_instruction_decode.guestInstructionBytes(self, rip, &fetched);
        if (bytes.len < 2 or bytes[0] != 0xF3 or bytes[1] != 0x90) break;
        // Central decoding records code-fetch evidence and verifies this
        // address's current mapping/generation.
        const pause = process_impl_instruction_decode.decodeAt(self) orelse break;
        if (pause.op != .nop or pause.len != 2) break;
        guestContextField(self, "last_instruction_rip").* = rip;
        guestContextField(self, "last_decoded_op").* = pause.op;
        guestContextField(self, "last_decoded_len").* = pause.len;
        noteWindowsGuestPause(self);
        guestContextField(self, "regs").*.rip +%= 2;
        guestContextField(self, "step_retired").* += 1;
        additional += 1;
    }
    if (additional != 0) _ = self.parallel_pause_batched_instructions.fetchAdd(additional, .monotonic);
}

pub fn noteGuestProgressStall(self: *ElfState, slot: usize) void {
    if (!self.windows_runtime_enabled) return;
    if (guestContextField(self, "windows_active_guest_thread_slot").* != slot) return;
    const thread = &self.windows_guest_threads[slot];
    if (thread.status != .running) return;
    const name = thread.nameText();
    if (!__process_std.mem.startsWith(u8, name, "RENDER ") and
        !__process_std.mem.startsWith(u8, name, "MAIN_THREAD ")) return;
    const swaps = @atomicLoad(u64, &self.frame_cost.swaps, .monotonic);
    if (thread.spin.noteProgress(guestContextField(self, "regs").*.rip, swaps, __process_monotonicNanoseconds())) {
        thread.spin.capture_watch_epoch = self.spin_watch.epoch.load(.acquire);
        _ = self.spin_capture_threads.fetchAdd(1, .monotonic);
        reportGuestSpinTrigger(self, slot, swaps, "running_no_present");
    }
}

pub fn spinRead(self: *const ElfState, comptime T: type, address: u64) ?T {
    var bytes: [@sizeOf(T)]u8 = undefined;
    if (!process_impl_execution.copyFromGuest(self, &bytes, address)) return null;
    return __process_std.mem.readInt(T, &bytes, .little);
}

pub fn spinInGeneratedCode(self: *const ElfState, rip: u64) bool {
    var text: [__process_guest_symbol_text_bytes]u8 = undefined;
    return __process_std.mem.startsWith(u8, process_impl_kernel_services.describeGuestAddress(self, rip, &text), "generated-code");
}

pub fn reportUnmappedReads(self: *const ElfState) void {
    if (comptime @import("builtin").is_test) return;
    var storage: [6]*const __process_unmapped_reads.Entry = undefined;
    const ranked = self.unmapped_read_census.top(&storage);
    for (ranked, 0..) |entry, rank| {
        var where: [__process_guest_symbol_text_bytes]u8 = undefined;
        const rip = entry.first_rip.load(.monotonic);
        __process_log.info("PE64 UNMAPPED READS: rank={d} page=0x{x} reads={d} first_address=0x{x} first_reader=0x{x} ({s}) overflow={d}; a page nothing maps reads as zero, so a structure Windows provides without a call (KUSER_SHARED_DATA, a TEB or PEB field) that Rosette does not is named here", .{
            rank + 1,
            __process_unmapped_reads.pageOf(entry),
            entry.reads.load(.monotonic),
            entry.first_address.load(.monotonic),
            rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, rip, &where),
            self.unmapped_read_census.overflow.load(.monotonic),
        });
    }
}

pub fn reportXeniaGuestCode(self: *ElfState) void {
    if (comptime @import("builtin").is_test) return;
    if (!self.windows_runtime_enabled) return;
    const raw = __process_std.c.getenv("ROSETTE_XENIA_DUMP_GUEST_CODE") orelse return;
    var list = __process_std.mem.tokenizeScalar(u8, __process_std.mem.span(raw), ',');
    var index: usize = 0;
    while (list.next()) |text| : (index += 1) {
        if (index >= self.xenia_guest_code_dumped.len) break;
        if (self.xenia_guest_code_dumped[index]) continue;
        const guest = __process_std.fmt.parseInt(u32, __process_std.mem.trim(u8, text, " "), 0) catch continue;
        const host = spinRead(self, u32, guest) orelse continue;
        const thunk = spinRead(self, u32, guest +% 4) orelse continue;
        if (host == 0 or host == thunk) continue;
        var bytes: [4096]u8 = undefined;
        if (!process_impl_execution.copyFromGuest(self, &bytes, host)) continue;
        // Xenia pads functions with int3; stop at the first long run.
        var end: usize = bytes.len;
        var padding: usize = 0;
        for (bytes, 0..) |byte, at| {
            padding = if (byte == 0xCC) padding + 1 else 0;
            if (padding == 16) {
                end = at + 1 - padding;
                break;
            }
        }
        var offset: usize = 0;
        while (offset < end) : (offset += 64) {
            __process_log.info("PE64 XENIA GUEST CODE: guest=0x{x} host=0x{x} offset=0x{x} bytes={x}", .{ guest, host, offset, bytes[offset..@min(end, offset + 64)] });
        }
        self.xenia_guest_code_dumped[index] = true;
    }
}

pub fn reportGuestTimeSources(self: *ElfState, elapsed_ns: u64) void {
    if (comptime @import("builtin").is_test) return;
    if (!self.windows_runtime_enabled) return;
    const clock = process_impl_guest_memory.kuserClock(self);
    var sample = __process_TimeAuditSample{
        .elapsed_ns = elapsed_ns,
        .guest_clock_us = clock.interrupt_100ns / 10,
        .kuser_interrupt_100ns = __process_kuser_shared.readScalar(u64, __process_kuser_shared.base + __process_kuser_shared.interrupt_time, clock),
    };
    if (process_impl_guest_diagnostics.xeniaVirtualMembase(self)) |membase| {
        const bundle = membase +% 0x8024_0EE0;
        sample.bundle_interrupt_100ns = @byteSwap(spinRead(self, u64, bundle) orelse 0);
        sample.bundle_system_filetime = @byteSwap(spinRead(self, u64, bundle +% 8) orelse 0);
        sample.bundle_tick_ms = @byteSwap(spinRead(self, u32, bundle +% 16) orelse 0);
    }
    const last = self.time_audit_last;
    self.time_audit_last = sample;
    const host_ms = (elapsed_ns -| last.elapsed_ns) / __process_std.time.ns_per_ms;
    const bundle_interrupt_ms = (sample.bundle_interrupt_100ns -% last.bundle_interrupt_100ns) / 10_000;
    const verdict: []const u8 = if (last.elapsed_ns == 0)
        "first_sample"
    else if (sample.bundle_interrupt_100ns == last.bundle_interrupt_100ns and host_ms > 100)
        "bundle_interrupt_time_frozen"
    else if (sample.bundle_tick_ms == last.bundle_tick_ms and host_ms > 100)
        "bundle_tick_count_frozen"
    else
        "advancing";
    __process_log.info("PE64 TIME SOURCES: verdict={s} host_ms+={d} guest_clock_us={d} (+{d}ms) kuser_interrupt_100ns={d} kuser_reads={d} ke_timestamp_bundle(interrupt_100ns/system_filetime/tick_ms)={d}/{d}/{d} (+{d}ms/+{d}ms); the title's KeQueryInterruptTime and timestamp-bundle reads see the bundle, which Xenia fills from KUSER_SHARED_DATA", .{
        verdict,
        host_ms,
        sample.guest_clock_us,
        (sample.guest_clock_us -| last.guest_clock_us) / 1000,
        sample.kuser_interrupt_100ns,
        self.kuser_shared_reads.load(.monotonic),
        sample.bundle_interrupt_100ns,
        sample.bundle_system_filetime,
        sample.bundle_tick_ms,
        bundle_interrupt_ms,
        sample.bundle_tick_ms -% last.bundle_tick_ms,
    });
}

pub fn runStallAssist(self: *ElfState, slot: usize, swaps: u64, now_ns: u64) void {
    const assist = self.stall_assists.fetchAdd(1, .monotonic) + 1;
    var woken: u64 = 0;
    var outcome: []const u8 = "no_command_processor_seen";
    const command_processor = self.xenia_command_processor_seen.load(.acquire);
    var guard = lockGuestRuntimeMutationIfParallel(self);
    defer if (guard) |*held| held.unlock();
    const snapshot = gpuStallSnapshot(self, command_processor);
    const thread = &self.windows_guest_threads[slot];
    const report = assist == 1 or thread.spin.assists == 1 or
        (assist <= 64 and assist % 16 == 0) or
        (assist > 64 and (assist & (assist - 1)) == 0);
    if (report) reportGpuStallState(self, snapshot);
    if (command_processor != 0) {
        outcome = "ring_state_unavailable";
        if (snapshot) |state| {
            outcome = "ring_drained_no_wake";
            if (state.needsWorkerWake()) {
                outcome = "event_unreadable";
                if (spinRead(self, u64, command_processor +% 0x260)) |event_object| {
                    if (event_object != 0) {
                        if (spinRead(self, u64, event_object +% 8)) |handle| {
                            outcome = "handle_unregistered";
                            if (process_impl_windows_sync.windowsWaitObjectIndex(self, handle) != null) {
                                woken = process_impl_windows_sync.signalWindowsWaitObject(self, handle, false);
                                _ = self.stall_assist_gpu_wakes.fetchAdd(1, .monotonic);
                                outcome = "gpu_worker_signalled";
                            }
                        }
                    }
                }
            }
        }
    }
    if (comptime @import("builtin").is_test) return;
    if (assist > 64 and (assist & (assist - 1)) != 0) return;
    __process_log.info("PE64 STALL ASSIST: assist={d} thread='{s}' frames={d} still_for_ms={d} pauses_since_frame={d} action=inspect_gpu_ring_then_wake_if_pending outcome={s} woken={d} command_processor=0x{x} gpu_wakes={d}; read PE64 GPU STALL STATE and GUEST SPIN FORENSICS for the actual stalled edge", .{
        assist,
        process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
        swaps,
        (now_ns -| thread.spin.seen_swaps_ns) / __process_std.time.ns_per_ms,
        thread.spin.pauses_since_swap,
        outcome,
        woken,
        command_processor,
        self.stall_assist_gpu_wakes.load(.monotonic),
    });
}

pub fn gpuStallSnapshot(self: *ElfState, command_processor: u64) ?__process_gpu_stall.Snapshot {
    const membase = process_impl_guest_diagnostics.xeniaVirtualMembase(self) orelse return null;
    if (!self.gpu_ring_initialized or self.gpu_ring_size_log2 >= 29 or command_processor == 0) return null;
    const ring_dwords: u64 = (@as(u64, 1) << @intCast(self.gpu_ring_size_log2 + 3)) / 4;
    const guest_write = @as(u64, self.gpu_ring_last_write_index) % ring_dwords;
    const writeback_va = membase +% 0xE000_0000 +% @as(u64, self.gpu_ring_rptr_writeback);
    const rptr_raw = spinRead(self, u32, writeback_va) orelse return null;
    const read_index = @as(u64, @byteSwap(rptr_raw)) % ring_dwords;
    const worker_write = spinRead(self, u32, command_processor +% 0x268) orelse return null;
    const fence_raw = spinRead(self, u32, writeback_va & ~@as(u64, 0x3F)) orelse return null;
    return .{
        .frame = @atomicLoad(u64, &self.frame_cost.swaps, .monotonic),
        .guest_write = guest_write,
        .read = read_index,
        .worker_write = worker_write,
        .ring_dwords = ring_dwords,
        .fence = @byteSwap(fence_raw),
        .kicks = self.gpu_ring_updates,
        .interrupt_dpcs = process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe6kernel11KernelState21EmulateCPInterruptDPCEjjjj"),
    };
}

pub fn reportGpuStallState(self: *ElfState, snapshot: ?__process_gpu_stall.Snapshot) void {
    const current = snapshot orelse {
        __process_log.info("PE64 GPU STALL STATE: snapshot unavailable (ring, worker pointer, or writeback unreadable)", .{});
        return;
    };
    const verdict = __process_gpu_stall.classify(current, self.gpu_stall_last_snapshot);
    const previous = self.gpu_stall_last_snapshot;
    const same_frame = if (previous) |before| before.frame == current.frame else false;
    const fence_delta: u32 = if (same_frame) current.fence -% previous.?.fence else 0;
    const kick_delta: u64 = if (same_frame) current.kicks -% previous.?.kicks else 0;
    const dpc_delta: u64 = if (same_frame) current.interrupt_dpcs -% previous.?.interrupt_dpcs else 0;
    self.gpu_stall_last_snapshot = current;
    const membase = process_impl_guest_diagnostics.xeniaVirtualMembase(self) orelse return;
    const writeback_va = membase +% 0xE000_0000 +% @as(u64, self.gpu_ring_rptr_writeback);
    var page: [16]u32 = @splat(0);
    const page_va = writeback_va & ~@as(u64, 0x3F);
    for (&page, 0..) |*word, index| word.* = @byteSwap(spinRead(self, u32, page_va +% index * 4) orelse 0);
    __process_log.info("PE64 GPU STALL STATE: verdict={s} frame={d} fence={d} fence_delta={d} kicks={d} kick_delta={d} interrupt_dpcs={d} dpc_delta={d} wake_eligible={}; a drained ring with no new kick localizes the stall before GPU submission", .{ @tagName(verdict), current.frame, current.fence, fence_delta, current.kicks, kick_delta, current.interrupt_dpcs, dpc_delta, current.needsWorkerWake() });
    __process_log.info("PE64 GPU STALL STATE: guest_write_index=0x{x} writeback_read_index=0x{x} worker_write_index=0x{x} pending_dwords={d} ring_dwords={d} ring_base=0x{x} writeback=0x{x} writeback_page_be=[{x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8}]; native Xenia writes to the fence are observed by value even when Rosette's watched-store count is zero", .{
        current.guest_write,
        current.read,
        current.worker_write,
        current.pending(),
        current.ring_dwords,
        self.gpu_ring_base,
        self.gpu_ring_rptr_writeback,
        page[0],
        page[1],
        page[2],
        page[3],
        page[4],
        page[5],
        page[6],
        page[7],
        page[8],
        page[9],
        page[10],
        page[11],
        page[12],
        page[13],
        page[14],
        page[15],
    });
}

pub fn reportGuestSpinTrigger(self: *ElfState, slot: usize, swaps: u64, cause: []const u8) void {
    if (comptime @import("builtin").is_test) return;
    const thread = &self.windows_guest_threads[slot];
    const regs = guestContextField(self, "regs").*;
    var where: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 GUEST SPIN FORENSICS: thread='{s}' slot={d} cause={s} rip=0x{x} ({s}) pauses_since_frame={d} frames={d} frame_count_still_for_ms={d} capture_steps={d}; this thread ran while no frame was presented. Its PowerPC state and every guest thread's JIT frames follow, then the guest memory it reads (captured over the next steps, interpreted) and every later write to it (PE64 GUEST SPIN WATCH WRITE)", .{
        process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
        slot,
        cause,
        regs.rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, regs.rip, &where),
        thread.spin.pauses_since_swap,
        swaps,
        (thread.spin.trigger_ns -| thread.spin.seen_swaps_ns) / __process_std.time.ns_per_ms,
        __process_guest_spin.capture_steps,
    });
    __process_log.info("PE64 GUEST SPIN FORENSICS:   x86 rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rbp=0x{x} rsp=0x{x} r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rflags=0x{x}", .{
        regs.rax, regs.rbx, regs.rcx, regs.rdx, regs.rsi, regs.rdi, regs.rbp, regs.rsp, regs.r8, regs.r9, regs.r10, regs.r11, regs.r12, regs.r13, regs.r14, regs.r15, regs.rflags,
    });
    var code: [64]u8 = undefined;
    if (process_impl_execution.copyFromGuest(self, &code, regs.rip)) {
        __process_log.info("PE64 GUEST SPIN FORENSICS:   x86_code rip=0x{x} bytes={x}; disassemble this window to identify the load and branch the captured read depends on", .{ regs.rip, code });
    }
    if (spinInGeneratedCode(self, regs.rip)) {
        reportSpinPowerPcContext(self, regs.rsi);
        reportHalo3WorkQueueAtRenderWait(self, regs.rsi, swaps);
    }
    for (self.windows_guest_threads, 0..) |*other, index| {
        if (other.status == .vacant) continue;
        const live = if (index == slot) regs else other.context.regs;
        reportSpinThreadFrames(self, index, live.rip, live.rsp, live.rsi);
    }
}

pub fn reportHalo3WorkQueueAtRenderWait(self: *const ElfState, context: u64, swaps: u64) void {
    const function_marker = spinRead(self, u64, context +% 0xA0) orelse return; // PPC r12
    const global_base = spinRead(self, u64, context +% 0x138) orelse return; // PPC r31
    if (@as(u32, @truncate(function_marker)) != 0x821A856C or
        @as(u32, @truncate(global_base)) != 0x8294A504) return;
    const membase = process_impl_guest_diagnostics.xeniaVirtualMembase(self) orelse return;
    const queue = membase +% 0x8294_CA9C;
    const capacity = @byteSwap(spinRead(self, u32, queue +% 0x6C) orelse return);
    if (capacity != 2) return;
    const completed = @byteSwap(spinRead(self, u32, queue +% 0x48) orelse return);
    const index_before = @byteSwap(spinRead(self, u32, queue +% 0x4C) orelse return);
    const slot0 = @byteSwap(spinRead(self, u32, queue +% 0x0C) orelse return);
    const slot1 = @byteSwap(spinRead(self, u32, queue +% 0x1C) orelse return);
    const payload0 = @byteSwap(spinRead(self, u32, queue +% 0x14) orelse return);
    const payload1 = @byteSwap(spinRead(self, u32, queue +% 0x24) orelse return);
    const index_after = @byteSwap(spinRead(self, u32, queue +% 0x4C) orelse return);
    const selected = index_before % capacity;
    const selected_flag = if (selected == 0) slot0 else slot1;
    __process_log.info("PE64 TITLE WORK QUEUE: signature=halo3_render_wait frame={d} queue_guest=0x8294ca9c capacity={d} index_4c={d}->{d} counter_48={d} selected_slot={d} slot_flags={d}/{d} payloads=0x{x}/0x{x} stable={} verdict={s}; the PPC consumer waits up to 66 ms for a nonzero selected slot before retrying, so a persistent empty slot calls for producer-side tracing", .{
        swaps,
        capacity,
        index_before,
        index_after,
        completed,
        selected,
        slot0,
        slot1,
        payload0,
        payload1,
        index_before == index_after,
        if (selected_flag == 0) @as([]const u8, "selected_slot_empty") else "selected_slot_ready",
    });
}

pub fn reportSpinPowerPcContext(self: *const ElfState, ctx: u64) void {
    var gpr: [32]u64 = undefined;
    for (&gpr, 0..) |*value, n| value.* = spinRead(self, u64, ctx +% 40 +% 8 * n) orelse 0;
    var row: usize = 0;
    while (row < 4) : (row += 1) {
        const g = gpr[row * 8 ..][0..8];
        __process_log.info("PE64 GUEST SPIN FORENSICS:   ppc r{d}-r{d}: {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8}", .{ row * 8, row * 8 + 7, g[0], g[1], g[2], g[3], g[4], g[5], g[6], g[7] });
    }
    var cr: [32]u8 = @splat(0);
    _ = process_impl_execution.copyFromGuest(self, &cr, ctx);
    __process_log.info("PE64 GUEST SPIN FORENSICS:   ppc lr=0x{x:0>8} cr_bytes={x}", .{ spinRead(self, u32, ctx +% 0x130) orelse 0, cr });
    const membase = process_impl_guest_diagnostics.xeniaVirtualMembase(self) orelse return;
    const base = spinRead(self, u64, ctx -% 40) orelse return;
    const depth = spinRead(self, u32, ctx -% 20) orelse return;
    __process_log.info("PE64 GUEST SPIN FORENSICS:   ppc stack_points depth={d} base=0x{x}; newest first: lr is the PowerPC return address at each function's entry, code= the five big-endian words ending at it (the bl is the fourth)", .{ depth, base });
    if (depth == 0 or depth > 65536) return;
    var shown: u32 = 0;
    var index: u32 = depth;
    while (index > 0 and shown < 24) : (shown += 1) {
        index -= 1;
        var entry: [16]u8 = undefined;
        if (!process_impl_execution.copyFromGuest(self, &entry, base +% @as(u64, index) * 16)) break;
        const point = __process_guest_spin.decodeStackPoint(&entry);
        var code: [20]u8 = @splat(0);
        _ = process_impl_execution.copyFromGuest(self, &code, membase +% (@as(u64, point.lr) -% 16));
        __process_log.info("PE64 GUEST SPIN FORENSICS:     frame={d} lr=0x{x:0>8} r1=0x{x:0>8} host_rsp=0x{x} code={x}", .{ index, point.lr, point.r1, point.host_rsp, code });
    }
}

pub fn reportSpinThreadFrames(self: *const ElfState, index: usize, rip: u64, rsp: u64, rsi: u64) void {
    const thread = &self.windows_guest_threads[index];
    const source = __state_ExitContextSource{ .state = self };
    var words: [1024]u64 = undefined;
    var count: usize = 0;
    while (count < words.len) : (count += 1) {
        words[count] = source.stackWord(rsp +| @as(u64, @intCast(count * 8))) orelse break;
    }
    var frames: [12]__process_guest_backtrace.Frame = undefined;
    const found = __process_guest_backtrace.scan(source, rsp, words[0..count], &frames);
    var text: [1536]u8 = undefined;
    var used: usize = 0;
    for (frames[0..found]) |frame| {
        var lr: ?u32 = null;
        if (spinInGeneratedCode(self, frame.call_site)) {
            var before: [96]u8 = undefined;
            if (process_impl_execution.copyFromGuest(self, &before, frame.call_site -% before.len)) lr = __process_guest_spin.xeniaGuestLinkBefore(&before);
        }
        var name: [__process_guest_symbol_text_bytes]u8 = undefined;
        const piece = if (lr) |link|
            __process_std.fmt.bufPrint(text[used..], " <- 0x{x}[ppc lr 0x{x:0>8}]", .{ frame.return_address, link })
        else
            __process_std.fmt.bufPrint(text[used..], " <- 0x{x} ({s})", .{ frame.return_address, process_impl_kernel_services.describeGuestAddressOrUnnamed(self, frame.return_address, &name) });
        used += (piece catch break).len;
    }
    var where: [__process_guest_symbol_text_bytes]u8 = undefined;
    const lr_now: u32 = if (spinInGeneratedCode(self, rip)) spinRead(self, u32, rsi +% 0x130) orelse 0 else 0;
    __process_log.info("PE64 GUEST SPIN FORENSICS:   thread slot={d} '{s}' status={s} last_import='{s}' pauses={d} rip=0x{x} ({s}) ppc_lr_now=0x{x:0>8} frames:{s}", .{
        index,
        process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(index + 1, 255))),
        @tagName(thread.status),
        thread.lastImportText(),
        __process_parallel_metrics.load(u64, &thread.pause_hints),
        rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, rip, &where),
        lr_now,
        if (found == 0) " <none on the stack>" else text[0..used],
    });
}

pub fn spinCaptureStep(self: *ElfState) bool {
    const slot = guestContextField(self, "windows_active_guest_thread_slot").* orelse return false;
    if (slot >= self.windows_guest_threads.len) return false;
    const spin = &self.windows_guest_threads[slot].spin;
    if (spin.capture_remaining == 0) return false;
    spin.capture_remaining -= 1;
    if (spin.capture_remaining != 0 and spin.capture_len < __process_guest_spin.capture_capacity) return true;
    spin.capture_remaining = 0;
    _ = self.spin_capture_threads.fetchSub(1, .monotonic);
    finishSpinCapture(self, slot);
    return false;
}

pub fn noteSpinCaptureRead(self: *ElfState, addr: u64, size: __process_Size, value: u64) void {
    const slot = guestContextField(self, "windows_active_guest_thread_slot").* orelse return;
    if (slot >= self.windows_guest_threads.len) return;
    const spin = &self.windows_guest_threads[slot].spin;
    if (spin.capture_remaining == 0) return;
    spin.noteRead(guestContextField(self, "regs").*.rip, addr, @intCast(process_impl_execution.bitWidth(size) / 8), value);
}

pub fn finishSpinCapture(self: *ElfState, slot: usize) void {
    const spin = &self.windows_guest_threads[slot].spin;
    // A short loading stall can recover while its bounded capture is in
    // flight. Its reads must not arm watches in the newly moving frame.
    const capture_frame_is_current = spin.reported_at_swaps == @atomicLoad(u64, &self.frame_cost.swaps, .monotonic);
    const watch_epoch = spin.capture_watch_epoch;
    const regs = guestContextField(self, "regs").*;
    const membase = process_impl_guest_diagnostics.xeniaVirtualMembase(self) orelse regs.rdi;
    const in_jit = spinInGeneratedCode(self, regs.rip);
    const ctx: u64 = if (in_jit) regs.rsi else 0;
    const r1: u64 = if (in_jit) (spinRead(self, u64, ctx +% 48) orelse 0) & 0xFFFF_FFFF else 0;
    if (comptime !@import("builtin").is_test) {
        __process_log.info("PE64 GUEST SPIN FORENSICS: thread='{s}' captured {d} distinct reads in {d} interpreted steps (overflow={d}) ending at rip=0x{x}; guest= is the address less Xenia's membase 0x{x}, be= the last value as the big-endian PowerPC word, watch= the index a later write is logged under", .{
            process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
            spin.capture_len,
            __process_guest_spin.capture_steps,
            spin.capture_overflow,
            regs.rip,
            membase,
        });
    }
    var neighborhoods = __process_guest_spin.Neighborhoods{};
    defer if (comptime !@import("builtin").is_test) reportSpinNeighborhoods(self, &neighborhoods, membase);
    for (spin.capture[0..spin.capture_len]) |record| {
        var watch_index: ?usize = null;
        if (__process_guest_spin.watchCandidate(record.address, membase, ctx, r1)) neighborhoods.add(record.address);
        if (capture_frame_is_current and __process_guest_spin.watchCandidate(record.address, membase, ctx, r1)) {
            watch_index = self.spin_watch.armForEpoch(watch_epoch, record.address, record.size, record.last);
            if (watch_index != null) {
                const page = record.address & ~@as(u64, __process_block_jit.Tlb.page_bytes - 1);
                process_impl_block_jit.invalidateAllBlockJitTlbTables(self, page, __process_block_jit.Tlb.page_bytes, false, true);
            }
        }
        if (comptime @import("builtin").is_test) continue;
        const be: u64 = switch (record.size) {
            2 => @byteSwap(@as(u16, @truncate(record.last))),
            4 => @byteSwap(@as(u32, @truncate(record.last))),
            8 => @byteSwap(record.last),
            else => record.last,
        };
        var where: [__process_guest_symbol_text_bytes]u8 = undefined;
        const guest: u64 = if (record.address >= membase) record.address - membase else 0;
        __process_log.info("PE64 GUEST SPIN FORENSICS:   read rip=0x{x} ({s}) address=0x{x} guest=0x{x:0>8} size={d} first=0x{x} last=0x{x} be=0x{x} count={d} watch={?d}", .{
            record.rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.rip, &where),
            record.address,
            guest,
            record.size,
            record.first,
            record.last,
            be,
            record.count,
            watch_index,
        });
    }
}

pub fn reportSpinNeighborhoods(self: *const ElfState, windows: *const __process_guest_spin.Neighborhoods, membase: u64) void {
    const words = __process_guest_spin.neighborhood_bytes / 4;
    for (windows.starts[0..windows.len]) |start| {
        var text: [words * 9]u8 = undefined;
        var used: usize = 0;
        for (0..words) |index| {
            const piece = if (spinRead(self, u32, start + index * 4)) |word|
                __process_std.fmt.bufPrint(text[used..], "{x:0>8} ", .{@byteSwap(word)})
            else
                __process_std.fmt.bufPrint(text[used..], "???????? ", .{});
            used += (piece catch break).len;
        }
        __process_log.info("PE64 GUEST SPIN NEIGHBORHOOD: guest=0x{x:0>8} bytes={d} be_words=[{s}]; the memory around an address the spinner polls, as the PowerPC code reads it: a flag's producer and consumer indexes, owners and sibling slots sit beside it, and they say whether both sides still agree", .{
            if (start >= membase) start - membase else 0,
            __process_guest_spin.neighborhood_bytes,
            __process_std.mem.trimEnd(u8, text[0..used], " "),
        });
    }
}

pub fn noteSpinWatchWrite(self: *const ElfState, vaddr: u64, width: u64, value: u64, kind: []const u8) void {
    const watch_set: *__process_guest_spin.WatchSet = @constCast(&self.spin_watch);
    const match = watch_set.overlappingMatch(vaddr, width) orelse return;
    if (!watch_set.noteHit(match)) return;
    if (watch_set.epoch.load(.acquire) != match.epoch) return;
    if (comptime @import("builtin").is_test) return;
    const regs = guestContextField(self, "regs").*;
    const slot = guestContextField(self, "windows_active_guest_thread_slot").*;
    const membase = process_impl_guest_diagnostics.xeniaVirtualMembase(self) orelse 0;
    const lr: u32 = if (spinInGeneratedCode(self, regs.rip)) spinRead(self, u32, regs.rsi +% 0x130) orelse 0 else 0;
    var where: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 GUEST SPIN WATCH WRITE: watch={d} address=0x{x} guest=0x{x:0>8} width={d} value=0x{x} kind={s} thread='{s}' rip=0x{x} ({s}) ppc_lr=0x{x:0>8} op={s} hits={d}", .{
        match.index,
        vaddr,
        vaddr -% membase,
        width,
        value,
        kind,
        process_impl_guest_diagnostics.guestThreadLabel(self, if (slot) |s_index| @intCast(@min(s_index + 1, 255)) else 0),
        regs.rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, regs.rip, &where),
        lr,
        @tagName(guestContextField(self, "last_decoded_op").*),
        watch_set.hits[match.index].load(.monotonic),
    });
}

pub fn noteSpinWatchBulkWrite(self: *const ElfState, addr: u64, count: u64, kind: []const u8) void {
    const index = self.spin_watch.overlapping(addr, count) orelse return;
    const start = self.spin_watch.addresses[index].load(.monotonic);
    noteSpinWatchWrite(self, start, 1, spinRead(self, u8, start) orelse 0, kind);
}

pub fn reportSpinWatchSummary(self: *const ElfState) void {
    if (comptime @import("builtin").is_test) return;
    const membase = process_impl_guest_diagnostics.xeniaVirtualMembase(self) orelse 0;
    const epoch = self.spin_watch.epoch.load(.acquire);
    const n = @min(self.spin_watch.count.load(.acquire), __process_guest_spin.WatchSet.capacity);
    __process_log.info("PE64 GUEST SPIN WATCH: episode={d} armed={d}/{d} capacity_drops={d}; writer counts cover bounded 500ms leases per address; expired evidence is retained and later captures cannot renew the same address until a present retires this episode", .{
        epoch,
        n,
        __process_guest_spin.WatchSet.capacity,
        self.spin_watch.capacity_drops.load(.monotonic),
    });
    for (0..n) |index| {
        if (self.spin_watch.epoch.load(.acquire) != epoch) return;
        if (self.spin_watch.slot_epochs[index].load(.acquire) != epoch) continue;
        const address = self.spin_watch.addresses[index].load(.acquire);
        const width = self.spin_watch.widths[index].load(.monotonic);
        const now: u64 = switch (width) {
            1 => spinRead(self, u8, address) orelse 0,
            2 => spinRead(self, u16, address) orelse 0,
            4 => spinRead(self, u32, address) orelse 0,
            else => spinRead(self, u64, address) orelse 0,
        };
        __process_log.info("PE64 GUEST SPIN WATCH: watch={d} address=0x{x} guest=0x{x:0>8} width={d} armed_value=0x{x} value_now=0x{x} value_changed={} writes={d}; writes counts Rosette's instrumented stores only, while Xenia's native GPU writebacks can change the value without a watch hit", .{
            index,
            address,
            address -% membase,
            width,
            self.spin_watch.armed_values[index].load(.monotonic),
            now,
            now != self.spin_watch.armed_values[index].load(.monotonic),
            self.spin_watch.hits[index].load(.monotonic),
        });
    }
}
