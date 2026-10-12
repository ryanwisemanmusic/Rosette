const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const guest_observation = @import("guest_observation.zig");
const BLOCK_JIT_WAYS = __ProcessInternals._BLOCK_JIT_WAYS;
const BlockJitState = __ProcessInternals._BlockJitState;
const GUEST_MILESTONE_TRANSLATOR_SATURATION = __ProcessInternals._GUEST_MILESTONE_TRANSLATOR_SATURATION;
const GuestExecutionGate = __ProcessInternals._GuestExecutionGate;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const Op = process.Op;
const RFL_CF = __ProcessInternals._RFL_CF;
const RFL_ZF = __ProcessInternals._RFL_ZF;
const SYNTHETIC_RIP_FLOOR = __ProcessInternals._SYNTHETIC_RIP_FLOOR;
const WindowsExecutableRange = process.WindowsExecutableRange;
const WindowsGuestThreadContext = __ProcessInternals._WindowsGuestThreadContext;
const WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const WindowsMappedCodeSlice = __ProcessInternals._WindowsMappedCodeSlice;
const block_jit = __ProcessInternals._block_jit;
const concurrency = __ProcessInternals._concurrency;
const elf_loader = __ProcessInternals._elf_loader;
const freeTranslatedBlock = __ProcessInternals._freeTranslatedBlock;
const guestMilestoneSaturable = __ProcessInternals._guestMilestoneSaturable;
const guest_clock = __ProcessInternals._guest_clock;
const heap_guard = __ProcessInternals._heap_guard;
const host_profile = __ProcessInternals._host_profile;
const mainThreadRequestHook = process.mainThreadRequestHook;
const monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const parallel_workers = __ProcessInternals._parallel_workers;
const std = __ProcessInternals._std;
const testing = std.testing;
const trimAddressOffset = __ProcessInternals._trimAddressOffset;
const tso_memory = __ProcessInternals._tso_memory;
const tso_memory_policy = __ProcessInternals._tso_memory_policy;
const windows_srw_owner_stack_depth = __ProcessInternals._windows_srw_owner_stack_depth;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const xenia_event_audit = __ProcessInternals._xenia_event_audit;
const xenia_guest_milestone_map = __ProcessInternals._xenia_guest_milestone_map;
const ElfState = process.ElfState;
const decodeInsn = __ProcessInternals._decodeInsn;
const envU64 = __ProcessInternals._envU64;
const windows_guest_execution_binding = __ProcessInternals._windows_guest_execution_binding;
const main = process.main;

fn sleepForTest(milliseconds: u64) void {
    var request = std.c.timespec{ .sec = 0, .nsec = @intCast(milliseconds * std.time.ns_per_ms) };
    _ = std.c.nanosleep(&request, null);
}

test "in parallel mode a runtime call leaves other executors running, and an address-space change stops them" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const Stepper = struct {
        state: *ElfState,
        inside: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        release: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        fn run(self: *@This()) void {
            var step = self.state.guest_execution_gate.enterStep();
            self.inside.store(true, .release);
            while (!self.release.load(.acquire)) std.atomic.spinLoopHint();
            step.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    var stepper = Stepper{ .state = &state };
    const stepper_thread = try std.Thread.spawn(.{}, Stepper.run, .{&stepper});
    while (!stepper.inside.load(.acquire)) std.atomic.spinLoopHint();

    // Another executor is mid-instruction; an import's lock does not wait
    // for it. The old runtime lock stopped the world here.
    var runtime_guard = state.lockWindowsRuntime();
    try testing.expect(!state.guest_execution_gate.mutationPending());
    runtime_guard.unlock();

    // Changing what guest memory is must wait for that instruction.
    const Remapper = struct {
        state: *ElfState,
        done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        fn run(self: *@This()) void {
            var guard = self.state.lockGuestAddressSpaceIfParallel();
            self.done.store(true, .release);
            if (guard) |*held| held.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    var remapper = Remapper{ .state = &state };
    const remapper_thread = try std.Thread.spawn(.{}, Remapper.run, .{&remapper});
    while (!state.guest_execution_gate.mutationPending()) std.atomic.spinLoopHint();
    sleepForTest(2);
    try testing.expect(!remapper.done.load(.acquire));
    stepper.release.store(true, .release);
    stepper_thread.join();
    remapper_thread.join();
    try testing.expect(remapper.done.load(.acquire));
    try testing.expect(!state.guest_execution_gate.mutationPending());
}

test "native pipeline calls release only dispatch-level runtime locks" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.setParallelGuestExecution(true);

    const Probe = struct {
        state: *ElfState,

        fn canAcquireRuntimeMutex(probe: @This()) bool {
            if (!probe.state.windows_runtime_mutex.tryLock()) return false;
            probe.state.windows_runtime_mutex.unlock();
            return true;
        }
    };

    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const mutex_was_released = state.withWindowsRuntimeLockReleased(
        Probe{ .state = &state },
        Probe.canAcquireRuntimeMutex,
    );
    try testing.expect(mutex_was_released);
    // The helper reacquires before returning to pipeline bookkeeping.
    try testing.expect(!state.windows_runtime_mutex.tryLock());
    dispatch_guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.runtime_lock_native_pipeline_yields);

    var pinned_guard = state.lockWindowsRuntime();
    const mutex_was_still_held = state.withWindowsRuntimeLockReleased(
        Probe{ .state = &state },
        Probe.canAcquireRuntimeMutex,
    );
    try testing.expect(!mutex_was_still_held);
    try testing.expect(!state.windows_runtime_mutex.tryLock());
    pinned_guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.runtime_lock_native_pipeline_yield_refusals);
}

test "GPU fence waits release dispatch-only runtime locks and retain pinned locks" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.setParallelGuestExecution(true);

    const Probe = struct {
        state: *ElfState,

        fn canAcquireRuntimeMutex(probe: @This()) bool {
            if (!probe.state.windows_runtime_mutex.tryLock()) return false;
            probe.state.windows_runtime_mutex.unlock();
            return true;
        }
    };

    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const mutex_was_released = state.withWindowsRuntimeLockReleasedForGpuFenceWait(
        Probe{ .state = &state },
        Probe.canAcquireRuntimeMutex,
    );
    try testing.expect(mutex_was_released);
    try testing.expect(!state.windows_runtime_mutex.tryLock());
    dispatch_guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.runtime_lock_gpu_fence_wait_yields);

    var pinned_guard = state.lockWindowsRuntime();
    const mutex_was_still_held = state.withWindowsRuntimeLockReleasedForGpuFenceWait(
        Probe{ .state = &state },
        Probe.canAcquireRuntimeMutex,
    );
    try testing.expect(!mutex_was_still_held);
    try testing.expect(!state.windows_runtime_mutex.tryLock());
    pinned_guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.runtime_lock_gpu_fence_wait_yield_refusals);
}

test "Vulkan queue waits release dispatch-only locks and refuse pinned waits" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.setParallelGuestExecution(true);

    const Probe = struct {
        state: *ElfState,
        called: bool = false,
        mutex_was_free: bool = false,

        fn observe(probe: *@This()) void {
            probe.called = true;
            probe.mutex_was_free = probe.state.windows_runtime_mutex.tryLock();
            if (probe.mutex_was_free) probe.state.windows_runtime_mutex.unlock();
        }
    };

    var dispatch_probe = Probe{ .state = &state };
    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const dispatched = state.tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(&dispatch_probe, Probe.observe);
    try testing.expect(dispatched);
    try testing.expect(dispatch_probe.called);
    try testing.expect(dispatch_probe.mutex_was_free);
    try testing.expect(!state.windows_runtime_mutex.tryLock());
    dispatch_guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.runtime_lock_gpu_queue_wait_yields);

    var pinned_probe = Probe{ .state = &state };
    var pinned_guard = state.lockWindowsRuntime();
    const pinned = state.tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(&pinned_probe, Probe.observe);
    try testing.expect(!pinned);
    try testing.expect(!pinned_probe.called);
    try testing.expect(!state.windows_runtime_mutex.tryLock());
    pinned_guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.runtime_lock_gpu_queue_wait_yield_refusals);
}

test "in parallel mode an empty GetMessage blocks until another thread posts" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const Poster = struct {
        state: *ElfState,
        fn run(self: *@This()) void {
            sleepForTest(5);
            var guard = self.state.lockWindowsRuntime();
            _ = self.state.enqueueWindowsMessage(.{ .hwnd = 0x1234, .message = 0x400 });
            guard.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    var poster = Poster{ .state = &state };
    // As inside the GetMessage import: the runtime lock is held by the
    // dispatch that routed the call here, and by nothing pinned.
    var guard = state.lockWindowsRuntimeForDispatch();
    const poster_thread = try std.Thread.spawn(.{}, Poster.run, .{&poster});
    const blocked = state.waitForWindowsMessage(0, 0, 0);
    guard.unlock();
    poster_thread.join();
    try testing.expect(blocked > 0);
    // Woken by the post, not by the 50 ms limit.
    try testing.expect(blocked < 45 * std.time.ns_per_ms);
    try testing.expectEqual(@as(usize, 1), state.windowsMessageCount());
    try testing.expectEqual(@as(u64, 1), state.windows_get_message_blocks);
}

test "in parallel mode GetMessageW reached through the import dispatcher blocks until another thread posts" {
    // The path the guest takes: the step loop's dispatch lock, then the
    // Windows runtime's own entry lock, then the handler. On 2026-09-26 the
    // second level made the wait refuse every call, and Xenia's UI thread
    // spun through its message loop instead of sleeping.
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const Poster = struct {
        state: *ElfState,
        fn run(self: *@This()) void {
            sleepForTest(5);
            var guard = self.state.lockWindowsRuntime();
            _ = self.state.enqueueWindowsMessage(.{ .hwnd = 0x1234, .message = 0x400, .wparam = 7 });
            guard.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    const message = state.mem_base + 0x4000;
    state.regs.rcx = message;
    state.regs.rdx = 0;
    state.regs.r8 = 0;
    state.regs.r9 = 0;
    var poster = Poster{ .state = &state };
    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const poster_thread = try std.Thread.spawn(.{}, Poster.run, .{&poster});
    const started = concurrency.monotonicNanoseconds();
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "USER32.dll", "GetMessageW", state.mem_base + 0x1000));
    const elapsed = concurrency.monotonicNanoseconds() - started;
    dispatch_guard.unlock();
    poster_thread.join();
    try testing.expectEqual(@as(u64, 1), state.windows_get_message_blocks);
    try testing.expectEqual(@as(u64, 0), state.windows_get_message_unreleasable);
    // It slept until the post and then delivered it, not WM_NULL.
    try testing.expect(elapsed < 45 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x1234), state.read64(message));
    try testing.expectEqual(@as(u32, 0x400), state.read32(message + 8));
    try testing.expectEqual(@as(u64, 7), state.read64(message + 16));
    try testing.expectEqual(@as(usize, 0), state.windowsMessageCount());
}

test "parallel GetMessage stays blocked past the former 50 ms synthetic WM_NULL timeout" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const Poster = struct {
        state: *ElfState,
        fn run(self: *@This()) void {
            sleepForTest(70);
            var guard = self.state.lockWindowsRuntime();
            _ = self.state.enqueueWindowsMessage(.{ .hwnd = 0x1234, .message = 0x400, .wparam = 9 });
            guard.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    const message = state.mem_base + 0x4000;
    state.regs.rcx = message;
    state.regs.rdx = 0;
    state.regs.r8 = 0;
    state.regs.r9 = 0;
    var poster = Poster{ .state = &state };
    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const poster_thread = try std.Thread.spawn(.{}, Poster.run, .{&poster});
    const started = concurrency.monotonicNanoseconds();
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "USER32.dll", "GetMessageW", state.mem_base + 0x1000));
    const elapsed = concurrency.monotonicNanoseconds() - started;
    dispatch_guard.unlock();
    poster_thread.join();

    try testing.expect(elapsed >= 60 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u64, 1), state.windows_get_message_blocks);
    try testing.expect(state.windows_get_message_host_polls >= 1);
    try testing.expect(state.windows_get_message_event_wakes >= 1);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u32, 0x400), state.read32(message + 8));
    try testing.expectEqual(@as(u64, 9), state.read64(message + 16));
}

test "in parallel mode the owner sleeps in a guest wait until another thread signals, instead of spinning" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const handle: u64 = 0xfffff00000000301;
    state.registerWindowsEvent(handle, false, false);

    const Signaler = struct {
        state: *ElfState,
        handle: u64,
        fn run(self: *@This()) void {
            sleepForTest(12);
            var guard = self.state.lockWindowsRuntime();
            _ = self.state.signalWindowsWaitObject(self.handle, false);
            guard.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    var signaler = Signaler{ .state = &state, .handle = handle };
    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const signaler_thread = try std.Thread.spawn(.{}, Signaler.run, .{&signaler});
    const started = concurrency.monotonicNanoseconds();
    var retries: u32 = 0;
    while (true) {
        switch (state.waitWindowsGuestObject(handle, 0xFFFF_FFFF)) {
            .retry => retries += 1,
            .signaled => break,
            else => return error.TestUnexpectedResult,
        }
        if (retries > 1000) return error.TestUnexpectedResult;
    }
    const elapsed = concurrency.monotonicNanoseconds() - started;
    dispatch_guard.unlock();
    signaler_thread.join();
    // It waited for the signal, in a handful of slices - the cooperative
    // path retried as fast as the interpreter could go.
    try testing.expect(elapsed >= 8 * std.time.ns_per_ms);
    try testing.expect(retries < 40);
    try testing.expectEqual(@as(u64, 1), state.windows_owner_waits);
    // An auto-reset event is consumed by the wait it satisfied.
    try testing.expect(!state.windowsWaitObjectSignaled(handle));
}

test "in parallel mode an owner wait with a timeout lasts its timeout, and Sleep sleeps" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const handle: u64 = 0xfffff00000000302;
    state.registerWindowsEvent(handle, true, false);

    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const started = concurrency.monotonicNanoseconds();
    var outcome = state.waitWindowsGuestObject(handle, 15);
    while (outcome == .retry) outcome = state.waitWindowsGuestObject(handle, 15);
    const waited = concurrency.monotonicNanoseconds() - started;
    try testing.expectEqual(ElfState.WindowsWaitResult.timeout, outcome);
    // The cooperative owner answered WAIT_TIMEOUT at once.
    try testing.expect(waited >= 14 * std.time.ns_per_ms);

    state.regs = .{ .rcx = 20 };
    const sleep_started = concurrency.monotonicNanoseconds();
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "Sleep", state.mem_base + 0x1000));
    const slept = concurrency.monotonicNanoseconds() - sleep_started;
    dispatch_guard.unlock();
    try testing.expect(slept >= 18 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u64, 1), state.windows_owner_sleeps);
}

test "in parallel mode a window's messages go to the thread that created it" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    // The owner (the UI thread) creates the window and a worker posts to it.
    try testing.expect(state.createWindowsWindow(0xfffff00000000013, 0, 0, true, 0, 0, true));
    state.windows_active_guest_thread_slot = 0;
    try testing.expect(state.postWindowsMessage(0xfffff00000000013, 0x400, 0, 0, 0));
    // The worker's own message loop does not see it...
    try testing.expect(state.dequeueWindowsMessage(0, 0, 0, true) == null);
    try testing.expectEqual(@as(u64, 1), state.windowsMessageAffinitySkipCount());
    // ...the creator's does.
    state.windows_active_guest_thread_slot = null;
    const message = state.dequeueWindowsMessage(0, 0, 0, true).?;
    try testing.expectEqual(@as(u32, 0x400), message.message);
}

test "in parallel mode the owner's pthread condition wait sleeps until a signal reaches it" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const condition = state.mem_base + 0x2700;

    const Signaler = struct {
        state: *ElfState,
        condition: u64,
        fn run(self: *@This()) void {
            sleepForTest(10);
            var guard = self.state.lockWindowsRuntime();
            _ = self.state.signalWindowsGuestCondition(self.condition, false);
            guard.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    var signaler = Signaler{ .state = &state, .condition = condition };
    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    const signaler_thread = try std.Thread.spawn(.{}, Signaler.run, .{&signaler});
    const started = concurrency.monotonicNanoseconds();
    var slices: u32 = 0;
    var result = state.waitWindowsGuestCondition(condition, 0);
    while (result == .blocked and slices < 1000) : (slices += 1) result = state.waitWindowsGuestCondition(condition, 0);
    const elapsed = concurrency.monotonicNanoseconds() - started;
    dispatch_guard.unlock();
    signaler_thread.join();
    // The cooperative owner could not wait at all; the image's own wait
    // would never have been released by the shimmed signal.
    try testing.expectEqual(ElfState.WindowsConditionWaitResult.resumed, result);
    try testing.expect(elapsed >= 8 * std.time.ns_per_ms);
    try testing.expect(slices < 40);
    try testing.expectEqual(@as(u64, 1), state.windows_owner_condition_waits);
    try testing.expectEqual(@as(u64, 0), state.owner_pthread_condition);
}

test "a pinned runtime lock keeps an empty GetMessage from releasing it, and says so" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    var dispatch_guard = state.lockWindowsRuntimeForDispatch();
    var critical_guard = state.lockWindowsRuntime();
    try testing.expectEqual(@as(u64, 0), state.waitForWindowsMessage(0, 0, 0));
    critical_guard.unlock();
    dispatch_guard.unlock();
    try testing.expectEqual(@as(u64, 0), state.windows_get_message_blocks);
    try testing.expectEqual(@as(u64, 1), state.windows_get_message_unreleasable);
    try testing.expectEqual(@as(usize, 2), state.windows_get_message_unreleasable_depth);
    try testing.expectEqual(@as(usize, 1), state.windows_get_message_unreleasable_pinned);
}

test "a main thread parked on the runtime lock still runs the request the lock's holder waits on" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    // The test thread plays the host main thread: its park service drains a
    // stand-in for the main dispatch queue.
    const MainQueue = struct {
        pending: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        served: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        fn service(context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.pending.swap(0, .acq_rel) != 0) _ = self.served.fetchAdd(1, .acq_rel);
        }
    };
    var queue: MainQueue = .{};
    const previous_service = concurrency.park.installService(.{ .context = &queue, .run = MainQueue.service });
    defer _ = concurrency.park.installService(previous_service);

    // A guest worker, inside an import, asks the main thread for AppKit work
    // and waits for it - the 2026-09-25 GPU thread.
    const Worker = struct {
        state: *ElfState,
        queue: *MainQueue,
        holding: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        fn run(self: *@This()) void {
            var guard = self.state.lockWindowsRuntime();
            self.holding.store(true, .release);
            self.queue.pending.store(1, .release);
            mainThreadRequestHook(0);
            while (self.queue.served.load(.acquire) == 0) std.atomic.spinLoopHint();
            mainThreadRequestHook(1);
            guard.unlock();
            self.state.guest_execution_gate.unregisterCurrentThread();
        }
    };
    var worker = Worker{ .state = &state, .queue = &queue };
    const worker_thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (!worker.holding.load(.acquire)) std.atomic.spinLoopHint();

    // The main thread's next import needs that lock, from inside its step.
    // It parks - and its park serves the request, so the worker finishes and
    // lets the lock go. Before the park service this never returned.
    var step = state.guest_execution_gate.enterStep();
    var guard = state.lockWindowsRuntime();
    guard.unlock();
    step.unlock();
    worker_thread.join();
    try testing.expectEqual(@as(u32, 1), queue.served.load(.acquire));
}

test "a parked worker whose wait has a timeout wakes itself at the deadline" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    // Start the host clock, then park slot 0 as a Sleep(5).
    state.refreshWindowsGuestClock();
    state.refreshWindowsGuestClock();
    const thread = &state.windows_guest_threads[0];
    thread.status = .blocked;
    thread.blocked_wait_handle = 0;
    thread.blocked_wait_deadline = state.windowsGuestClockTicks() + 5 * guest_clock.ticks_per_millisecond;
    var worker: parallel_workers.Worker = .{ .wake_hub = &state.parallel_guest_wake_hub, .slot = 0 };
    const started = concurrency.monotonicNanoseconds();
    state.parkParallelWorker(0, &worker);
    const elapsed = concurrency.monotonicNanoseconds() - started;
    // Its own deadline, not the 100 ms safety net, and not a busy return.
    try testing.expect(elapsed >= 3 * std.time.ns_per_ms);
    try testing.expect(elapsed < 80 * std.time.ns_per_ms);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, thread.status);
}

test "the translator stays off under per-instruction tracing and when refused by name" {
    var traced = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer traced.deinit();
    traced.trace_rip_start = MEM_BASE;
    try std.testing.expect(traced.blockJitActive() == null);
    try std.testing.expect(traced.block_jit_unavailable);
    var refused = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer refused.deinit();
    refused.block_jit_enabled = false;
    try std.testing.expect(refused.blockJitActive() == null);
    try std.testing.expect(refused.block_jit == null);
}

test {
    _ = block_jit;
}

/// Interpreter and translator side by side over the same program: the
/// translating state takes one step (one instruction or one block), the
/// interpreting state takes as many instructions as that retired, and every
/// register is compared. The first disagreement names the block and the
/// register, which is how a template defect is found in minutes rather than
/// from a digest that came out wrong.
const LockstepDivergence = struct {
    step: usize,
    register: []const u8,
    interpreted: u64,
    translated: u64,
    block_start: u64,
    block_ops: [8]Op,
    block_len: usize,
};

fn lockstepDivergence(interpreting: *ElfState, translating: *ElfState, max_steps: usize, stop_rip: ?u64) ?LockstepDivergence {
    interpreting.block_jit_enabled = false;
    translating.block_jit_hot_threshold = 2;
    var step_index: usize = 0;
    while (step_index < max_steps and !translating.terminated) : (step_index += 1) {
        if (stop_rip) |stop| if (translating.regs.rip == stop) break;
        const rip_before = translating.regs.rip;
        _ = translating.step();
        var retired = translating.step_retired;
        while (retired > 0 and !interpreting.terminated) : (retired -= 1) _ = interpreting.step();
        var divergence: ?LockstepDivergence = null;
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
            if (divergence == null and @field(interpreting.regs, name) != @field(translating.regs, name)) {
                divergence = .{ .step = step_index, .register = name, .interpreted = @field(interpreting.regs, name), .translated = @field(translating.regs, name), .block_start = rip_before, .block_ops = undefined, .block_len = 0 };
            }
        }
        // A translated block that ended at a call or a return under the
        // Windows calling convention owes the next one at most the flags a
        // helper returns (`block_jit.returnFlagsLive`), and leaves the rest
        // as they were: the interpreter's are the ones to go on with.
        if (translating.windows_runtime_enabled and block_jit.isCallOrReturn(translating.last_decoded_op)) {
            translating.regs.rflags = interpreting.regs.rflags;
        }
        if (divergence == null and interpreting.regs.rflags != translating.regs.rflags) {
            divergence = .{ .step = step_index, .register = "rflags", .interpreted = interpreting.regs.rflags, .translated = translating.regs.rflags, .block_start = rip_before, .block_ops = undefined, .block_len = 0 };
        }
        if (divergence) |*found| {
            if (translating.blockJitFind(rip_before)) |block| {
                found.block_len = @min(block.insns.len, found.block_ops.len);
                for (block.insns[0..found.block_len], 0..) |insn, i| found.block_ops[i] = insn.decoded.op;
            }
            return found.*;
        }
    }
    return null;
}

fn expectNoLockstepDivergence(interpreting: *ElfState, translating: *ElfState, max_steps: usize, stop_rip: ?u64) !void {
    if (lockstepDivergence(interpreting, translating, max_steps, stop_rip)) |found| {
        std.debug.print("lockstep divergence at step {d}: {s} interpreter=0x{x} translated=0x{x} block=0x{x} ops:", .{ found.step, found.register, found.interpreted, found.translated, found.block_start });
        for (found.block_ops[0..found.block_len]) |op| std.debug.print(" {s}", .{@tagName(op)});
        std.debug.print("\n", .{});
        return error.TestUnexpectedResult;
    }
}

/// Run the hybrid-TSO tier-boundary fixture: a hot loop whose block stores
/// through an interpreted `movaps` and reads the stored qword back with a
/// translated `mov`. Returns rbx, the sum of every value read back.
fn runTsoTierBoundaryFixture(translate: bool, fallbacks: *u64) !u64 {
    // The trailing jump parks the thread; a translated chain would otherwise
    // run straight past a terminating nop within the same step.
    const program = [_]u8{
        0x66, 0x48, 0x0F, 0x6E, 0xC1, // loop: movq xmm0, rcx
        0x0F, 0x29, 0x44, 0x24, 0xC0, // movaps [rsp-0x40], xmm0
        0x48, 0x8B, 0x44, 0x24, 0xC0, // mov rax, [rsp-0x40]
        0x48, 0x01, 0xC3, // add rbx, rax
        0x48, 0xFF, 0xC9, // dec rcx
        0x75, 0xE9, // jnz loop
        0xEB, 0xFE, // jmp $
    };
    const state = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(state);
    state.* = ElfState.init(testing.allocator);
    defer state.deinit();
    // Windows mode binds the per-context store buffers.
    state.windows_runtime_enabled = true;
    const code = state.mem_base + 0x1000;
    @memcpy(state.guestMemory(code, program.len).?, &program);
    state.regs.rip = code;
    state.regs.rsp = state.mem_base + 0x40000;
    state.regs.rcx = 64;
    state.regs.rbx = 0;
    state.regs.rflags = 0x2;
    state.block_jit_enabled = translate;
    state.block_jit_hot_threshold = 2;
    const exit_rip = code + program.len - 2;
    var steps: usize = 0;
    while (state.regs.rip != exit_rip and steps < 20_000 and !state.terminated) : (steps += 1) _ = state.step();
    try testing.expectEqual(exit_rip, state.regs.rip);
    fallbacks.* = if (state.block_jit) |jit| jit.fallback_ops[@intFromEnum(Op.movaps_mem_xmm)] else 0;
    return state.regs.rbx;
}

test "an interpreted store inside a translated block is visible to the rest of the block" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    tso_memory.boundary_ledger.resetForTest();
    defer tso_memory.boundary_ledger.resetForTest();
    var interpreted_fallbacks: u64 = 0;
    var translated_fallbacks: u64 = 0;
    // 64 + 63 + ... + 1
    try testing.expectEqual(@as(u64, 2080), try runTsoTierBoundaryFixture(false, &interpreted_fallbacks));
    // On 2026-09-24 the interpreted `movaps` left its store in the buffer
    // and the translated load read the previous iteration's bytes.
    try testing.expectEqual(@as(u64, 2080), try runTsoTierBoundaryFixture(true, &translated_fallbacks));
    // The fixture only proves the boundary when the store really was an
    // interpreted fallback inside a translated block.
    try testing.expect(translated_fallbacks > 0);
    try testing.expectEqual(@as(u64, 0), tso_memory.boundary_ledger.snapshot().translated_entry_violations);
}

test "lockstep: the SHA1 feed loop translates identically to its interpretation" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const interpreting = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(interpreting);
    interpreting.* = ElfState.init(testing.allocator);
    defer interpreting.deinit();
    const translating = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(translating);
    translating.* = ElfState.init(testing.allocator);
    defer translating.deinit();
    guest_observation.seedKernelSha1FeedFixture(interpreting, 0x4001);
    guest_observation.seedKernelSha1FeedFixture(translating, 0x4001);
    interpreting.xenia_sha1_feed_enabled = false;
    translating.xenia_sha1_feed_enabled = false;
    const stop = translating.mem_base + 0x2000 + 78;
    try expectNoLockstepDivergence(interpreting, translating, 200_000, stop);
    try testing.expectEqual(stop, translating.regs.rip);
    try testing.expectEqualSlices(u8, interpreting.guestMemoryConst(interpreting.regs.rdi, 0x70).?, translating.guestMemoryConst(translating.regs.rdi, 0x70).?);
    try testing.expect(translating.block_jit.?.instructions_retired > 100_000);
    // The loop body is a chain: blocks reach their successors inside
    // translated code rather than by returning here for a hash probe. The
    // lockstep comparison above is what makes this safe to assert - every
    // one of those hops retired exactly what the interpreter retired.
    try testing.expect(translating.block_jit.?.native_chain_hops > 0);
    try testing.expect(translating.block_jit.?.links_armed > 0);
}

test "the hooked-target filter names every call-arm hook and opens image targets only when nothing else hooks them" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    try testing.expectEqual(@as(u8, 1), state.block_jit_image_targets_hooked);
    state.windows_pthread_cond_signal_entry = 0x1451_3914;
    state.guest_milestone_addresses[0] = 0x1406_2bff0;
    state.rebuildBlockJitHookFilter();
    try testing.expectEqual(@as(u8, 0), state.block_jit_image_targets_hooked);
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, 0x1451_3914));
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, 0x1406_2bff0));
    // The accelerators resolve their targets while the filter is built, so
    // an enabled one no longer holds every image target on the interpreter
    // for the rest of the run, which is what the first build used to leave.
    state.windows_runtime_enabled = true;
    state.xenia_sha1_accelerator_enabled = true;
    state.xenia_rijndael_accelerator_enabled = true;
    state.xenia_tabulate_accelerator_enabled = true;
    state.rebuildBlockJitHookFilter();
    try testing.expect(state.xenia_sha1_target_checked);
    try testing.expect(state.xenia_rijndael_target_checked);
    try testing.expect(state.xenia_tabulate_target_checked);
    try testing.expectEqual(@as(u8, 0), state.block_jit_image_targets_hooked);
    // A target an accelerator does find is named like any other hook.
    state.xenia_rijndael_target = 0x1401_a03a0;
    state.rebuildBlockJitHookFilter();
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, 0x1401_a03a0));
    try testing.expectEqual(@as(u8, 0), state.block_jit_image_targets_hooked);
    // Anything the filter cannot see still closes every image target.
    state.trace_windows_threads = true;
    state.rebuildBlockJitHookFilter();
    try testing.expectEqual(@as(u8, 1), state.block_jit_image_targets_hooked);
}

test "every pthread condition entry is hooked, so no translated jump reaches winpthreads' own body" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.image_low = 0x1400_0000;
    state.image_high = 0x1700_0000;
    state.windows_pthread_cond_wait_entry = 0x1451_3b07;
    state.windows_pthread_cond_signal_entry = 0x1451_3914;
    state.windows_pthread_cond_broadcast_entry = 0x1451_3a10;
    state.windows_pthread_cond_timedwait_entry = 0x1451_3c00;
    // A tail jump into any of them is forced to the interpreter's jump arm,
    // where the condition shim runs; a call is refused the native template.
    for ([_]u64{ 0x1451_3b07, 0x1451_3914, 0x1451_3a10, 0x1451_3c00 }) |entry| {
        try testing.expect(state.blockJitTargetHooked(entry));
        try testing.expect(!state.blockJitCallTargetPlain(entry));
    }
    try testing.expect(!state.blockJitTargetHooked(0x1451_3b08));
}

test "a direct call is translated unless a hook or a trace could claim its target" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.image_low = 0x1400_0000;
    state.image_high = 0x1700_0000;

    // Xenia's own code. The milestones, the kernel-call census, the
    // accelerators and the pthread shims are exact addresses the predicate
    // checks; the one hook it cannot see by address is the local-function
    // shim, whose table is empty on the PE route. So an image target is
    // translated here, and refused once either of the others is present.
    try testing.expect(state.blockJitCallTargetPlain(state.image_low));
    try testing.expect(state.blockJitCallTargetPlain(0x1500_0000));
    state.trace_calls = true;
    try testing.expect(!state.blockJitCallTargetPlain(0x1500_0000));
    state.trace_calls = false;
    state.block_jit_transfer_traced = true;
    try testing.expect(!state.blockJitCallTargetPlain(0x1500_0000));
    state.block_jit_transfer_traced = false;
    const symbols = [_]elf_loader.Symbol{.{ .name = "local", .value = 0x1500_0000, .size = 0, .section_index = 0 }};
    state.local_symbols = &symbols;
    try testing.expect(!state.blockJitCallTargetPlain(0x1500_0000));
    state.local_symbols = &.{};

    // Xenia's generated PowerPC code, which is where the hot calls are.
    try testing.expect(state.blockJitCallTargetPlain(state.image_high));
    try testing.expect(state.blockJitCallTargetPlain(0xA000_0000));

    // The predicate must answer from range tests, array indices and hash
    // probes only. A linear scan of the roughly ninety-six thousand symbols
    // Xenia carries, once per call site per block compile, would cost far
    // more than the fallbacks this removes; that is what an earlier version
    // did. Nothing below may reintroduce one.
    try testing.expect(state.local_symbols.len == 0);

    // An unresolved image is refused outright rather than treated as an
    // empty range that admits everything.
    state.image_low = 0;
    state.image_high = 0;
    try testing.expect(!state.blockJitCallTargetPlain(0xA000_0000));

    // A synthetic address is already the hook box's, and stays refused.
    state.image_low = 0x1400_0000;
    state.image_high = 0x1700_0000;
    try testing.expect(!state.blockJitCallTargetPlain(SYNTHETIC_RIP_FLOOR));
}

test "a host profile trims function offsets and reports a run it sampled" {
    try testing.expectEqualStrings("xe::gpu::CommandProcessor::ExecutePacket", trimAddressOffset("xe::gpu::CommandProcessor::ExecutePacket+0x80"));
    try testing.expectEqualStrings("unnamed", trimAddressOffset("unnamed"));
    try testing.expectEqualStrings("+0x10", trimAddressOffset("+0x10"));
    try testing.expectEqualStrings("a+0xzz", trimAddressOffset("a+0xzz"));
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // Exercise the sampler itself independently of the production opt-in.
    state.beginHostProfileSampling();
    if (!host_profile.supported) return;
    try testing.expect(state.host_profile_started);
    var sink: u64 = 0;
    const began = monotonicNanoseconds();
    while (monotonicNanoseconds() -| began < 20 * std.time.ns_per_ms) {
        for (0..4096) |index| sink +%= index *% 31;
    }
    std.mem.doNotOptimizeAway(sink);
    state.reportHostProfile();
    try testing.expect(!state.host_profile_started);
    try testing.expect(!host_profile.active());
}

test "an observation-only milestone saturates into counting, and one with a hook never does" {
    const map = xenia_guest_milestone_map;
    const execute_packet = comptime map.indexOf("_ZN2xe3gpu6vulkan22VulkanCommandProcessor13ExecutePacketEv").?;
    const update_write_pointer = comptime map.indexOf("_ZN2xe3gpu16CommandProcessor18UpdateWritePointerEj").?;
    try testing.expect(guestMilestoneSaturable(execute_packet));
    try testing.expect(!guestMilestoneSaturable(update_write_pointer));
    try testing.expect(!guestMilestoneSaturable(comptime map.indexOf("_ZN2xe6kernel7XThread7ExecuteEv").?));
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_milestone_hits[execute_packet] = GUEST_MILESTONE_TRANSLATOR_SATURATION - 1;
    state.recordGuestMilestone(execute_packet, 0x1_40a3_fc70);
    try testing.expectEqual(@as(u8, 1), state.guest_milestone_saturated[execute_packet]);
    state.guest_milestone_hits[update_write_pointer] = GUEST_MILESTONE_TRANSLATOR_SATURATION - 1;
    state.recordGuestMilestone(update_write_pointer, 0x1_4000_1000);
    try testing.expectEqual(@as(u8, 0), state.guest_milestone_saturated[update_write_pointer]);
}

test "guest execution mutation waits for other instruction leases" {
    const Worker = struct {
        gate: *GuestExecutionGate,
        started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn mutate(self: *@This()) void {
            self.started.store(true, .release);
            var guard = self.gate.enterMutation();
            defer guard.unlock();
            self.completed.store(true, .release);
        }
    };

    var gate = GuestExecutionGate{};
    var step_guard = gate.enterStep();
    var worker = Worker{ .gate = &gate };
    const thread = try std.Thread.spawn(.{}, Worker.mutate, .{&worker});
    while (!worker.started.load(.acquire)) std.atomic.spinLoopHint();

    // Wait until the writer has closed admission, then prove it is waiting
    // for the current instruction to retire instead of mutating live state.
    while (true) {
        const pending = gate.mutationPending();
        const active_steps = gate.activeSteps();
        if (!pending) {
            std.atomic.spinLoopHint();
            continue;
        }
        try testing.expectEqual(@as(usize, 1), active_steps);
        break;
    }
    try testing.expect(!worker.completed.load(.acquire));
    step_guard.unlock();
    thread.join();
    try testing.expect(worker.completed.load(.acquire));
}

test "guest execution mutations from concurrent steps do not deadlock" {
    const Worker = struct {
        gate: *GuestExecutionGate,
        ready: *std.atomic.Value(u32),
        completed: *std.atomic.Value(u32),

        fn mutate(self: *@This()) void {
            var step_guard = self.gate.enterStep();
            defer step_guard.unlock();
            _ = self.ready.fetchAdd(1, .seq_cst);
            while (self.ready.load(.seq_cst) != 2) std.atomic.spinLoopHint();

            var mutation_guard = self.gate.enterMutation();
            defer mutation_guard.unlock();
            _ = self.completed.fetchAdd(1, .seq_cst);
        }
    };

    var gate = GuestExecutionGate{};
    var ready = std.atomic.Value(u32).init(0);
    var completed = std.atomic.Value(u32).init(0);
    var first = Worker{ .gate = &gate, .ready = &ready, .completed = &completed };
    var second = Worker{ .gate = &gate, .ready = &ready, .completed = &completed };
    const first_thread = try std.Thread.spawn(.{}, Worker.mutate, .{&first});
    const second_thread = try std.Thread.spawn(.{}, Worker.mutate, .{&second});
    first_thread.join();
    second_thread.join();

    try testing.expectEqual(@as(u32, 2), completed.load(.seq_cst));
    try testing.expect(!gate.mutationPending());
    try testing.expectEqual(@as(usize, 0), gate.activeSteps());
}

test "guest execution mutation is reentrant and permits nested cooperative steps" {
    var gate = GuestExecutionGate{};
    var outer = gate.enterMutation();
    var nested = gate.enterMutation();
    var step = gate.enterStep();
    step.unlock();
    nested.unlock();
    outer.unlock();
    try testing.expect(!gate.mutationPending());
    try testing.expectEqual(@as(usize, 0), gate.activeSteps());
}

test "guest execution gates retain nested leases across process instances" {
    var outer_gate = GuestExecutionGate{};
    var nested_gate = GuestExecutionGate{};

    var outer_step = outer_gate.enterStep();
    var nested_step = nested_gate.enterStep();
    // Mutating the outer process from a nested callback must account for the
    // outer step already held by this host thread, or it waits for itself.
    var outer_mutation = outer_gate.enterMutation();
    var nested_mutation = nested_gate.enterMutation();
    // Re-entering the outer gate while a different gate is on the stack is
    // still a re-entrant mutation of the already-owned outer process.
    var outer_mutation_again = outer_gate.enterMutation();

    outer_mutation_again.unlock();
    nested_mutation.unlock();
    outer_mutation.unlock();
    nested_step.unlock();
    outer_step.unlock();

    try testing.expect(!outer_gate.mutationPending());
    try testing.expect(!nested_gate.mutationPending());
    try testing.expectEqual(@as(usize, 0), outer_gate.activeSteps());
    try testing.expectEqual(@as(usize, 0), nested_gate.activeSteps());
}

test "Windows runtime locks are reentrant across nested process callbacks" {
    var first = ElfState.init(testing.allocator);
    defer first.deinit();
    var second = ElfState.init(testing.allocator);
    defer second.deinit();

    var first_outer = first.lockWindowsRuntime();
    var second_lock = second.lockWindowsRuntime();
    // A callback can be dispatched through a helper associated with another
    // process and then call back into the first. The per-process recursion
    // record must not mistake that for a new host thread and deadlock.
    var first_nested = first.lockWindowsRuntime();

    first_nested.unlock();
    second_lock.unlock();
    first_outer.unlock();

    try testing.expect(!first.guest_execution_gate.mutationPending());
    try testing.expect(!second.guest_execution_gate.mutationPending());
}

test "Xenia event audit keeps the guest header's type, state, and native handle distinct" {
    const bytes = [_]u8{
        0,    0,    0,    0,
        0,    0,    0,    1,
        0,    0x4e, 0x45, 0x58,
        0xf8, 0,    0,    0x20,
    };
    const header = xenia_event_audit.parseHeader(&bytes).?;
    try testing.expectEqual(@as(u8, 0), header.object_type);
    try testing.expectEqual(@as(u32, 1), header.signal_state);
    try testing.expect(header.hasXeniaObjectSignature());
    try testing.expect(header.isEventType());
    try testing.expectEqual(@as(u32, 0xF800_0020), header.blink);
    try testing.expectEqual(xenia_event_audit.Operation.reset, xenia_event_audit.Operation.forExport("KeResetEvent").?);
    try testing.expect(xenia_event_audit.Operation.forExport("KeWaitForSingleObject") == null);
}

test "a code write moves its own page's word and the one before, not the code cache's other blocks" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    // The rewrite at the end refills a decode-cache entry from changed
    // bytes, which a production run stops at.
    state.windows_fatal_point_terminate = false;
    // Xenia's code cache: written through one view, run through another.
    const mapping: u64 = 0xFFFF_F000_0000_0F30;
    const run: u64 = 0x6000_0000;
    const write: u64 = 0x7000_0000;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, run, 0x10000, 0).?;
    _ = state.mapWindowsMemoryView(mapping, write, 0x10000, 0).?;
    // Page 2: loop: inc rbx; dec rcx; jnz loop; jmp $
    const loop = [_]u8{ 0x48, 0xFF, 0xC3, 0x48, 0xFF, 0xC9, 0x75, 0xF8, 0xEB, 0xFE };
    for (loop, 0..) |byte, offset| state.write8(write + 0x2000 + offset, byte);
    state.block_jit_enabled = true;
    state.block_jit_hot_threshold = 2;
    const runLoop = struct {
        fn go(s: *ElfState, at: u64, count: u64) !void {
            s.regs.rip = at;
            s.regs.rcx = count;
            s.regs.rflags = 0x2;
            var steps: usize = 0;
            while (s.regs.rip != at + 8 and steps < 10_000 and !s.terminated) : (steps += 1) _ = s.step();
            try testing.expectEqual(at + 8, s.regs.rip);
        }
    }.go;
    state.regs.rbx = 0;
    try runLoop(&state, run + 0x2000, 10);
    try testing.expectEqual(@as(u64, 10), state.regs.rbx);
    const block = state.blockJitFind(run + 0x2000) orelse return error.NotTranslated;
    try testing.expect(state.code_page_generations.len != 0);
    const word = block.generation_ptr orelse return error.NoGenerationWord;
    try testing.expect(word == @as(*const u64, state.codePageGenerationWord(.memory_view, block.source_index, 0x2000).?));
    const proven = block.source_generation.?;
    try testing.expectEqual(proven, state.blockJitSourceGeneration(block).?);

    // Code placed elsewhere in the cache: pages 5 and 1 (whose page-before
    // is 0). The block on page 2 keeps its proof, though the mapping-wide
    // generation the decode cache reads moves on every store.
    const slot = state.windowsMappingIndex(mapping).?;
    const mapping_generation = state.windows_file_mappings[slot].code_generation;
    state.write8(write + 0x5000, 0x90);
    state.write8(write + 0x1FFF, 0x90);
    try testing.expectEqual(proven, state.blockJitSourceGeneration(block).?);
    try testing.expect(state.windows_file_mappings[slot].code_generation != mapping_generation);

    // A store to page 3 may be the tail of a block that starts on page 2.
    state.write8(write + 0x3000, 0x90);
    try testing.expect(state.blockJitSourceGeneration(block).? != proven);

    // The bytes still match, so the block is revalidated, not dropped; then
    // a real rewrite (inc rbx -> dec rbx) through the write view retires it.
    const revalidations = state.block_jit.?.revalidations;
    state.regs.rbx = 0;
    try runLoop(&state, run + 0x2000, 4);
    try testing.expectEqual(@as(u64, 4), state.regs.rbx);
    try testing.expect(state.block_jit.?.revalidations > revalidations);
    state.write8(write + 0x2002, 0xCB);
    state.regs.rbx = 100;
    try runLoop(&state, run + 0x2000, 4);
    try testing.expectEqual(@as(u64, 96), state.regs.rbx);
}

test "every instruction boundary of RENDER's hot 2026-10-02 code-cache function compiles in parallel mode" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const state = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(state);
    state.* = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.image_low = state.mem_base;
    state.image_high = state.mem_base + state.mem.len;
    const hex = "488b5ed88b46ec4c8b4630446bc8104c01cb48892344894308448b86300100004489430c83c0018946ec3d000001000f8d160400004883ec6831c048894c24584889442460488b9e3001000048899e88000000b8d07e5a824889442460c78630010000d07e5a8289be34010000488b4c2460e8d9f59bfff7c40f0000000f85d8030000488b5e304989da4981ea8000000089db4489d04139f20f83c70300000f38f11c074c895630488b5e4048899e2001000048c786800000000400000089d839f30f83a6030000";
    var bytes: [hex.len / 2]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes, hex);
    const mapping: u64 = 0xFFFF_F000_0000_0C10;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x1000_0000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, 0xA000_0000, 0x1000_0000, 0).?;
    const base: u64 = 0xa064ba00;
    for (bytes, 0..) |byte, offset| state.write8(base + offset, byte);
    state.regs.rip = base;
    const jit = state.blockJitActive() orelse return error.NoJit;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    // Xenia's stack-point push, the frame and a call: the address RENDER
    // interpreted 358 million times because its compile had been refused.
    var offset: u64 = 0;
    while (offset < 0xC0) {
        const rip = base + offset;
        const d = decodeInsn(bytes[@intCast(offset)..]);
        try testing.expect(d.len != 0);
        const compiled = state.compileBlockJit(jit, rip) orelse return error.Refused;
        freeTranslatedBlock(testing.allocator, compiled);
        offset += d.len;
    }
    try testing.expectEqual(@as(u64, 0), jit.compile_failures);
}

/// A block-translator benchmark program: bytes placed at `mem_base + 0x1000`
/// and run until RIP reaches the `jmp $` at `exit_offset`.
const BlockJitBenchProgram = struct {
    name: []const u8,
    bytes: [0x180]u8,
    exit_offset: u64,
    iterations: u64,
    instructions_per_iteration: u64,
    tlb_enabled: bool = true,
    parallel: bool = false,
    streaming_stores: bool = true,
    verify_vector_copy: ?u8 = null,
    verify_vector_adds: bool = false,
    verify_vector_accumulators: bool = false,
};

fn blockJitBenchRel32(from_end: u64, to: u64) [4]u8 {
    return @bitCast(@as(i32, @intCast(@as(i64, @intCast(to)) - @as(i64, @intCast(from_end)))));
}

/// Eight call sites of one function: its `ret` has eight return targets,
/// the shape of a Xenia helper every translated guest function calls.
fn blockJitBenchCallFanIn() BlockJitBenchProgram {
    var p: BlockJitBenchProgram = .{ .name = "call fan-in (8 sites, one ret)", .bytes = @splat(0xCC), .exit_offset = 73, .iterations = 2_000_000, .instructions_per_iteration = 58 };
    for (0..8) |k| {
        const at = k * 8;
        p.bytes[at] = 0xE8;
        @memcpy(p.bytes[at + 1 .. at + 5], &blockJitBenchRel32(at + 5, 0x100));
        @memcpy(p.bytes[at + 5 .. at + 8], &[_]u8{ 0x48, 0x01, 0xC3 }); // add rbx, rax
    }
    @memcpy(p.bytes[64..67], &[_]u8{ 0x48, 0xFF, 0xC9 }); // dec rcx
    p.bytes[67] = 0x0F;
    p.bytes[68] = 0x85;
    @memcpy(p.bytes[69..73], &blockJitBenchRel32(73, 0)); // jnz loop
    @memcpy(p.bytes[73..75], &[_]u8{ 0xEB, 0xFE });
    @memcpy(p.bytes[0x100..0x10F], &[_]u8{
        0x48, 0x8B, 0x46, 0x08, // mov rax, [rsi+8]
        0x48, 0x01, 0xD0, // add rax, rdx
        0x48, 0x89, 0x46, 0x10, // mov [rsi+16], rax
        0x48, 0xFF, 0xC2, // inc rdx
        0xC3, // ret
    });
    return p;
}

/// `mov rax, [rdi + rax*8]; call rax` through an eight-entry table, the way
/// Xenia calls through its indirection table: one call site, eight targets.
fn blockJitBenchIndirectCall() BlockJitBenchProgram {
    var p: BlockJitBenchProgram = .{ .name = "indirect call (8 targets)", .bytes = @splat(0xCC), .exit_offset = 23, .iterations = 8_000_000, .instructions_per_iteration = 9 };
    @memcpy(p.bytes[0..17], &[_]u8{
        0x89, 0xC8, // mov eax, ecx
        0x83, 0xE0, 0x07, // and eax, 7
        0x48, 0x8B, 0x04, 0xC7, // mov rax, [rdi + rax*8]
        0xFF, 0xD0, // call rax
        0x48, 0x01, 0xC3, // add rbx, rax
        0x48, 0xFF, 0xC9, // dec rcx
    });
    p.bytes[17] = 0x0F;
    p.bytes[18] = 0x85;
    @memcpy(p.bytes[19..23], &blockJitBenchRel32(23, 0));
    @memcpy(p.bytes[23..25], &[_]u8{ 0xEB, 0xFE });
    for (0..8) |k| {
        const at = 0x100 + k * 16;
        @memcpy(p.bytes[at .. at + 5], &[_]u8{ 0x48, 0x8D, 0x42, @intCast(k), 0xC3 }); // lea rax, [rdx+k]; ret
    }
    return p;
}

/// A loop whose forward branch alternates, so its block leaves by both
/// edges in turn.
fn blockJitBenchBranchy() BlockJitBenchProgram {
    var p: BlockJitBenchProgram = .{ .name = "alternating branch loop", .bytes = @splat(0xCC), .exit_offset = 20, .iterations = 12_000_000, .instructions_per_iteration = 6 };
    @memcpy(p.bytes[0..22], &[_]u8{
        0x48, 0xFF, 0xC2, // loop: inc rdx
        0xF6, 0xC2, 0x01, // test dl, 1
        0x74, 0x04, // jz skip
        0x48, 0x83, 0xC3, 0x03, // add rbx, 3
        0x48, 0x01, 0xD3, // skip: add rbx, rdx
        0x48, 0xFF, 0xC9, // dec rcx
        0x75, 0xEC, // jnz loop
        0xEB, 0xFE,
    });
    return p;
}

/// Straight-line context and guest-memory traffic: what a translated
/// PowerPC instruction becomes in Xenia's code cache.
fn blockJitBenchMemory() BlockJitBenchProgram {
    var p: BlockJitBenchProgram = .{ .name = "context + guest memory traffic", .bytes = @splat(0xCC), .exit_offset = 32, .iterations = 8_000_000, .instructions_per_iteration = 10 };
    @memcpy(p.bytes[0..34], &[_]u8{
        0x8B, 0x46, 0x10, // loop: mov eax, [rsi+0x10]
        0x03, 0x46, 0x14, // add eax, [rsi+0x14]
        0x89, 0x46, 0x18, // mov [rsi+0x18], eax
        0x48, 0x8B, 0x04, 0xD7, // mov rax, [rdi+rdx*8]
        0x48, 0x0F, 0xC8, // bswap rax
        0x48, 0x01, 0x46, 0x20, // add [rsi+0x20], rax
        0x48, 0xFF, 0xC2, // inc rdx
        0x48, 0x83, 0xE2, 0x3F, // and rdx, 63
        0x48, 0xFF, 0xC9, // dec rcx
        0x75, 0xE0, // jnz loop
        0xEB, 0xFE,
    });
    return p;
}

/// A function shaped like Xenia's x64 output for `lwz; addi; stw; cmpwi`:
/// context loads through rsi, a guest load and store through rdi with byte
/// swaps, a compare whose result is three `setcc` into the condition
/// register's bytes, and a frame. Called from a loop counted in r8.
fn blockJitBenchXeniaFunction() BlockJitBenchProgram {
    var p: BlockJitBenchProgram = .{ .name = "xenia-shaped function", .bytes = @splat(0xCC), .exit_offset = 14, .iterations = 4_000_000, .instructions_per_iteration = 19 };
    p.bytes[0] = 0xE8;
    @memcpy(p.bytes[1..5], &blockJitBenchRel32(5, 0x100)); // loop: call F
    @memcpy(p.bytes[5..8], &[_]u8{ 0x49, 0xFF, 0xC8 }); // dec r8
    p.bytes[8] = 0x0F;
    p.bytes[9] = 0x85;
    @memcpy(p.bytes[10..14], &blockJitBenchRel32(14, 0)); // jnz loop
    @memcpy(p.bytes[14..16], &[_]u8{ 0xEB, 0xFE });
    const body = [_]u8{
        0x48, 0x83, 0xEC, 0x28, // sub rsp, 0x28
        0x8B, 0x46, 0x40, // mov eax, [rsi+0x40]
        0x8B, 0x04, 0x07, // mov eax, [rdi+rax]
        0x0F, 0xC8, // bswap eax
        0x83, 0xC0, 0x01, // add eax, 1
        0x48, 0x89, 0x46, 0x38, // mov [rsi+0x38], rax
        0x8B, 0x4E, 0x40, // mov ecx, [rsi+0x40]
        0x89, 0xC2, // mov edx, eax
        0x0F, 0xCA, // bswap edx
        0x89, 0x14, 0x0F, // mov [rdi+rcx], edx
        0x83, 0xF8, 0x64, // cmp eax, 100
        0x0F, 0x9C, 0x86, 0xA0, 0x00, 0x00, 0x00, // setl [rsi+0xA0]
        0x0F, 0x9F, 0x86, 0xA1, 0x00, 0x00, 0x00, // setg [rsi+0xA1]
        0x0F, 0x94, 0x86, 0xA2, 0x00, 0x00, 0x00, // sete [rsi+0xA2]
        0x48, 0x83, 0xC4, 0x28, // add rsp, 0x28
        0xC3, // ret
    };
    @memcpy(p.bytes[0x100 .. 0x100 + body.len], &body);
    return p;
}

/// Repeated dependent VMX-style vector additions. Checks all four lanes,
/// and exposes private XMM load and upper-lane clear costs without a game.
fn blockJitBenchVectorChain() BlockJitBenchProgram {
    var p: BlockJitBenchProgram = .{ .name = "dependent vector arithmetic", .bytes = @splat(0xCC), .exit_offset = 69, .iterations = 2_000_000, .instructions_per_iteration = 18, .verify_vector_adds = true };
    for (0..16) |i| @memcpy(p.bytes[i * 4 ..][0..4], &[_]u8{ 0xC5, 0xF9, 0xFE, 0xC1 }); // vpaddd xmm0,xmm0,xmm1
    @memcpy(p.bytes[64..71], &[_]u8{ 0x48, 0xFF, 0xC9, 0x75, 0xBB, 0xEB, 0xFE });
    return p;
}

/// Four interleaved accumulators retain independent VMX register state.
fn blockJitBenchVectorAccumulators() BlockJitBenchProgram {
    var p: BlockJitBenchProgram = .{ .name = "independent VMX accumulators", .bytes = @splat(0xCC), .exit_offset = 265, .iterations = 2_000_000, .instructions_per_iteration = 66, .verify_vector_adds = true, .verify_vector_accumulators = true };
    for (0..16) |round| for ([_]u8{ 0, 2, 3, 4 }, 0..) |dst, slot| {
        const offset = (round * 4 + slot) * 4;
        @memcpy(p.bytes[offset..][0..4], &[_]u8{ 0xC5, 0xF9 ^ (dst << 3), 0xFE, 0xC1 | (dst << 3) });
    };
    @memcpy(p.bytes[256..261], &[_]u8{ 0x48, 0xFF, 0xC9, 0x0F, 0x85 });
    @memcpy(p.bytes[261..265], &blockJitBenchRel32(265, 0));
    @memcpy(p.bytes[265..267], &[_]u8{ 0xEB, 0xFE });
    return p;
}

fn runBlockJitBench(program: BlockJitBenchProgram, mapped: bool) !void {
    const state = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(state);
    state.* = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    // A PE launch always has image bounds; without them every `call` is
    // refused to the interpreter.
    state.image_low = state.mem_base;
    state.image_high = state.mem_base + state.mem.len;
    // Image code is proven by the image generation, as PE sections are; a
    // mapped run places the program in a file-mapping view the way Xenia
    // places its code cache.
    const code: u64 = if (mapped) 0x6000_0000 else state.mem_base + 0x1000;
    if (mapped) {
        const mapping: u64 = 0xFFFF_F000_0000_0B10;
        try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
        _ = state.mapWindowsMemoryView(mapping, code, 0x10000, 0).?;
        for (program.bytes, 0..) |byte, offset| state.write8(code + offset, byte);
        // Published as the code cache, as Xenia's view at 0xA0000000 is:
        // transfers into it are proven by its interval.
        state.windows_code_cache_view = state.windows_mapped_ranges.find(code, 1).?.slot;
        state.block_jit_code_cache_guest_low = code;
        state.block_jit_code_cache_guest_high = code + 0x10000;
    } else {
        state.configureWindowsExecutableRanges(&[_]WindowsExecutableRange{.{ .guest_base = code, .length = program.bytes.len }});
        @memcpy(state.guestMemory(code, program.bytes.len).?, &program.bytes);
    }
    const table = state.mem_base + 0x30000;
    for (0..64) |k| state.write64(table + k * 8, if (k < 8) code + 0x100 + k * 16 else k *% 0x0102_0304_0506_0708);
    // A PE launch knows its import table; without it every memory operand
    // in the image is treated as a possible import slot.
    state.windows_iat_low = state.mem_base + 0x3F000;
    state.windows_iat_high = state.mem_base + 0x3F008;
    state.regs.rip = code;
    state.regs.rsp = state.mem_base + 0x40000;
    state.regs.rsi = state.mem_base + 0x20000;
    state.regs.rdi = table;
    state.regs.rcx = program.iterations;
    state.regs.r8 = program.iterations;
    // The guest address the xenia-shaped function loads and stores.
    state.write32(state.regs.rsi + 0x40, 0x100);
    state.regs.rflags = 0x2;
    state.block_jit_enabled = true;
    state.block_jit_tlb_enabled = program.tlb_enabled;
    state.block_jit_streaming_stores_enabled = program.streaming_stores;
    if (program.parallel) state.setParallelGuestExecution(true);
    if (program.verify_vector_copy) |offset| {
        for (0..64) |byte| state.write8(state.regs.rsi + offset + byte, @intCast(byte ^ 0xA5));
    }
    if (program.verify_vector_adds) {
        for (0..4) |lane| std.mem.writeInt(u32, state.xmm[1][lane * 4 ..][0..4], 1, .little);
    }
    const exit_rip = code + program.exit_offset;
    const started = monotonicNanoseconds();
    var steps: u64 = 0;
    while (state.regs.rip != exit_rip and !state.terminated) : (steps += 1) _ = state.step();
    const elapsed = @max(monotonicNanoseconds() -| started, 1);
    try testing.expectEqual(exit_rip, state.regs.rip);
    if (program.verify_vector_copy) |offset| {
        try testing.expectEqualSlices(u8, state.guestMemory(state.regs.rsi + offset, 64).?, state.guestMemory(state.regs.rdi + offset, 64).?);
    }
    if (program.verify_vector_adds) {
        for (0..4) |lane| try testing.expectEqual(@as(u32, @truncate(program.iterations * 16)), std.mem.readInt(u32, state.xmm[0][lane * 4 ..][0..4], .little));
    }
    if (program.verify_vector_accumulators) {
        for ([_]u8{ 0, 2, 3, 4 }) |reg| for (0..4) |lane| try testing.expectEqual(@as(u32, @truncate(program.iterations * 16)), std.mem.readInt(u32, state.xmm[reg][lane * 4 ..][0..4], .little));
    }
    const instructions = program.iterations * program.instructions_per_iteration;
    const jit = state.block_jit.?;
    std.debug.print("BLOCK JIT BENCH: {s} ({s}): {d} instructions in {d} ms = {d} M instr/s ({d}.{d:0>2} ns/instr) steps={d} entries={d} relinks={d} native_hops={d} links_armed={d} revalidations={d} tlb_fills={d} compiled={d}\n", .{
        program.name,
        if (mapped) "mapped" else "image",
        instructions,
        elapsed / std.time.ns_per_ms,
        instructions * 1000 / elapsed,
        elapsed / instructions,
        (elapsed * 100 / instructions) % 100,
        steps,
        jit.dispatch_entries,
        jit.dispatch_relinks,
        jit.native_chain_hops,
        jit.links_armed,
        jit.revalidations,
        jit.tlb_fills,
        jit.compiled,
    });
    // `ROSETTE_BLOCK_JIT_BENCH_DUMP=1`: every block's ARM64 words, for
    // `llvm-mc --disassemble -triple=aarch64`.
    if (std.c.getenv("ROSETTE_BLOCK_JIT_BENCH_DUMP") != null) {
        for (jit.blocks) |maybe| {
            const block = maybe orelse continue;
            std.debug.print("BLOCK JIT BENCH CODE: rip=0x{x} code=0x{x} chain_entry={d} words=", .{ block.start_rip, @intFromPtr(block.code.ptr), block.chain_entry });
            for (block.code) |word| std.debug.print("{x:0>8} ", .{word});
            std.debug.print("\n", .{});
        }
    }
}

test "block jit benchmark: ordered vector TLB production benchmark (ROSETTE_VECTOR_BENCH=1)" {
    if (std.c.getenv("ROSETTE_VECTOR_BENCH") == null) return error.SkipZigTest;
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    for ([_]u8{ 0, 4, 1 }) |alignment| {
        for ([_]bool{ false, true }) |admitted| {
            var name: [96]u8 = undefined;
            var program: BlockJitBenchProgram = .{
                .name = try std.fmt.bufPrint(&name, "vector copy offset={d} admitted={}", .{ alignment, admitted }),
                .bytes = @splat(0xCC),
                .exit_offset = 45,
                .iterations = 500_000,
                .instructions_per_iteration = 10,
                .tlb_enabled = admitted,
                .verify_vector_copy = alignment,
            };
            for (0..4) |lane| {
                const displacement: u8 = @intCast(lane * 16 + alignment);
                // vmovdqu xmm0,[rsi+disp]; vmovdqu [rdi+disp],xmm0.
                @memcpy(program.bytes[lane * 10 ..][0..10], &[_]u8{ 0xC5, 0xFA, 0x6F, 0x46, displacement, 0xC5, 0xFA, 0x7F, 0x47, displacement });
            }
            @memcpy(program.bytes[40..47], &[_]u8{ 0x48, 0xFF, 0xC9, 0x75, 0xD3, 0xEB, 0xFE });
            try runBlockJitBench(program, false);
        }
    }
}

test "non-temporal vector stores production benchmark (ROSETTE_VECTOR_BENCH=1)" {
    if (std.c.getenv("ROSETTE_VECTOR_BENCH") == null) return error.SkipZigTest;
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    for ([_]bool{ false, true }) |direct| {
        var name: [96]u8 = undefined;
        var program: BlockJitBenchProgram = .{
            .name = try std.fmt.bufPrint(&name, "streaming copy direct={}", .{direct}),
            .bytes = @splat(0xCC),
            .exit_offset = 45,
            .iterations = 500_000,
            .instructions_per_iteration = 10,
            .parallel = true,
            .streaming_stores = direct,
            .verify_vector_copy = 0,
        };
        for (0..4) |lane| {
            const displacement: u8 = @intCast(lane * 16);
            // vmovdqu xmm0,[rsi+disp]; vmovntps [rdi+disp],xmm0.
            @memcpy(program.bytes[lane * 10 ..][0..10], &[_]u8{ 0xC5, 0xFA, 0x6F, 0x46, displacement, 0xC5, 0xF8, 0x2B, 0x47, displacement });
        }
        @memcpy(program.bytes[40..47], &[_]u8{ 0x48, 0xFF, 0xC9, 0x75, 0xD3, 0xEB, 0xFE });
        try runBlockJitBench(program, false);
    }
}

test "block jit benchmark: code expansion of RENDER's hot 2026-10-02 function (ROSETTE_BLOCK_JIT_BENCH=1)" {
    if (std.c.getenv("ROSETTE_BLOCK_JIT_BENCH") == null) return error.SkipZigTest;
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const state = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(state);
    state.* = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.image_low = state.mem_base;
    state.image_high = state.mem_base + state.mem.len;
    const hex = "488b5ed88b46ec4c8b4630446bc8104c01cb48892344894308448b86300100004489430c83c0018946ec3d000001000f8d160400004883ec6831c048894c24584889442460488b9e3001000048899e88000000b8d07e5a824889442460c78630010000d07e5a8289be34010000488b4c2460e8d9f59bfff7c40f0000000f85d8030000488b5e304989da4981ea8000000089db4489d04139f20f83c70300000f38f11c074c895630488b5e4048899e2001000048c786800000000400000089d839f30f83a6030000";
    var bytes: [hex.len / 2]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes, hex);
    const mapping: u64 = 0xFFFF_F000_0000_0C10;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x1000_0000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, 0xA000_0000, 0x1000_0000, 0).?;
    const base: u64 = 0xa064ba00;
    for (bytes, 0..) |byte, offset| state.write8(base + offset, byte);
    // The sample ends mid-function: int3 past it ends the last block there.
    for (bytes.len..bytes.len + 16) |offset| state.write8(base + offset, 0xCC);
    state.regs.rip = base;
    const jit = state.blockJitActive() orelse return error.NoJit;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    var offset: u64 = 0;
    var total_insns: usize = 0;
    var total_words: usize = 0;
    while (offset < bytes.len) {
        const compiled = state.compileBlockJit(jit, base + offset) orelse return error.Refused;
        defer freeTranslatedBlock(testing.allocator, compiled);
        total_insns += compiled.insns.len;
        total_words += compiled.code.len;
        std.debug.print("BLOCK JIT EXPANSION: rip=0x{x} x86={d} arm64_words={d} per_insn={d}\n", .{ base + offset, compiled.insns.len, compiled.code.len, compiled.code.len / @max(compiled.insns.len, 1) });
        if (std.c.getenv("ROSETTE_BLOCK_JIT_BENCH_DUMP") != null) {
            std.debug.print("BLOCK JIT BENCH CODE: rip=0x{x} words=", .{base + offset});
            for (compiled.code) |word| std.debug.print("{x:0>8} ", .{word});
            std.debug.print("\n", .{});
        }
        offset = compiled.end_rip - base;
    }
    std.debug.print("BLOCK JIT EXPANSION: total x86={d} arm64_words={d} bytes_per_x86={d}\n", .{ total_insns, total_words, total_words * 4 / @max(total_insns, 1) });
}

test "block jit benchmark: hops, relinks and memory traffic (ROSETTE_BLOCK_JIT_BENCH=1)" {
    if (std.c.getenv("ROSETTE_BLOCK_JIT_BENCH") == null) return error.SkipZigTest;
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // `ROSETTE_BLOCK_JIT_BENCH_ONLY=<name substring>` and
    // `ROSETTE_BLOCK_JIT_BENCH_SCALE=<n>` single out one program and run it
    // n times longer, for a sampling profiler.
    const only: ?[]const u8 = if (std.c.getenv("ROSETTE_BLOCK_JIT_BENCH_ONLY")) |raw| std.mem.sliceTo(raw, 0) else null;
    const scale = envU64("ROSETTE_BLOCK_JIT_BENCH_SCALE") orelse 1;
    for ([_]bool{ false, true }) |mapped| {
        for ([_]BlockJitBenchProgram{ blockJitBenchCallFanIn(), blockJitBenchIndirectCall(), blockJitBenchBranchy(), blockJitBenchMemory(), blockJitBenchXeniaFunction(), blockJitBenchVectorChain(), blockJitBenchVectorAccumulators() }) |program| {
            if (only) |name| if (std.mem.indexOf(u8, program.name, name) == null) continue;
            var scaled = program;
            scaled.iterations *|= @max(scale, 1);
            try runBlockJitBench(scaled, mapped);
        }
    }
}

test "SRW import lane IAT calls and tail jumps preserve the calling convention and decline changed bindings" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const acquire_stub = MEM_BASE + 0x700;
    const release_stub = MEM_BASE + 0x710;
    const iat = MEM_BASE + 0x900;
    const stack = MEM_BASE + 0x1000;
    const lock_address = MEM_BASE + 0x2000;
    const returned = MEM_BASE + 0x1200;
    try testing.expect(state.registerWindowsImportStubAtIat(acquire_stub, "kernel32.dll", "AcquireSRWLockExclusive", iat));
    try testing.expect(state.registerWindowsImportStubAtIat(release_stub, "kernel32.dll", "ReleaseSRWLockExclusive", iat + 8));
    state.windows_direct_stub_base = acquire_stub;
    state.windows_direct_stub_count = 2;
    state.windows_iat_low = iat;
    state.windows_iat_high = iat + 16;
    state.write64(iat, acquire_stub);
    state.write64(iat + 8, release_stub);
    state.write64(stack, returned);
    state.regs = .{ .rip = MEM_BASE + 0x300, .rsp = stack, .rcx = lock_address, .rax = 0xA1, .rbx = 0xB2, .rflags = 0x247 };
    state.xmm[7][3] = 0xA5;
    try testing.expect(state.tryImportSlotFastTransfer(iat, returned));
    try testing.expectEqual(returned, state.regs.rip);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(@as(u64, 0xA1), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xB2), state.regs.rbx);
    try testing.expectEqual(@as(u64, 0x247), state.regs.rflags);
    try testing.expectEqual(@as(u8, 0xA5), state.xmm[7][3]);
    try testing.expectEqual(@as(u64, 1), state.read64(lock_address));
    try testing.expect(state.tryImportSlotFastTransfer(iat + 8, 0));
    try testing.expectEqual(stack + 8, state.regs.rsp);
    try testing.expectEqual(returned, state.regs.rip);
    try testing.expectEqual(@as(u64, 0), state.read64(lock_address));
    try testing.expectEqual(@as(u64, 1), state.windows_srw_fast_acquires.load(.monotonic));
    try testing.expectEqual(@as(u64, 1), state.windows_srw_fast_releases.load(.monotonic));
    // This path serializes lock metadata; it does not claim a mutex bypass.
    try testing.expect(state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic) >= 2);
    state.write64(iat, acquire_stub + 0x200);
    const before = state.regs;
    try testing.expect(!state.tryImportSlotFastTransfer(iat, returned));
    try testing.expectEqualDeep(before, state.regs);
}

test "SRW import lane contended acquisition declines unchanged and release grants the oldest waiter" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const address = MEM_BASE + 0x2000;
    const returned = MEM_BASE + 0x1200;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };
    state.windows_guest_threads[2] = .{ .status = .running, .handle = 0x12, .thread_id = 7 };
    state.windows_active_guest_thread_slot = 0;
    state.regs = .{ .rip = MEM_BASE + 0x300, .rsp = MEM_BASE + 0x1000, .rcx = address };
    try testing.expect(state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    // Ordinary dispatch owns parking; the narrow lane only tests eligibility.
    for ([_]usize{ 2, 1 }) |slot| {
        state.windows_active_guest_thread_slot = slot;
        const before = state.regs;
        try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
        try testing.expectEqualDeep(before, state.regs);
        try testing.expectEqual(@as(u64, 1), state.read64(address));
        try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(address));
        try testing.expect(state.blockWindowsGuestThreadOnSrwLock(address));
    }
    state.windows_active_guest_thread_slot = 0;
    try testing.expect(state.tryWindowsSrwImport("ReleaseSRWLockExclusive", returned));
    const index = state.windowsSrwLockIndex(address).?;
    try testing.expectEqual(@as(u64, 7), state.windows_srw_locks[index].owner_thread_id);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[2].status);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[1].status);
    try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    state.windows_active_guest_thread_slot = 2;
    state.windows_guest_threads[2].status = .running;
    try testing.expect(state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    try testing.expect(state.tryWindowsSrwImport("ReleaseSRWLockExclusive", returned));
    try testing.expectEqual(@as(u64, 6), state.windows_srw_locks[index].owner_thread_id);
}

test "SRW import lane declines tracing invalid memory disabled mode and nested dispatch" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const address = MEM_BASE + 0x2000;
    const returned = MEM_BASE + 0x1200;
    state.regs = .{ .rip = MEM_BASE + 0x300, .rsp = MEM_BASE + 0x1000, .rcx = address };
    state.trace_calls = true;
    try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    state.trace_calls = false;
    state.trace_windows_threads = true;
    try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    state.trace_windows_threads = false;
    state.trace_vector = true;
    try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    state.trace_vector = false;
    state.windows_srw_import_lane = false;
    try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    state.windows_srw_import_lane = true;
    var guard = state.lockWindowsRuntimeForDispatch();
    try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    guard.unlock();
    state.regs.rcx = 0;
    try testing.expect(!state.tryWindowsSrwImport("ReleaseSRWLockExclusive", returned));
    state.regs.rcx = 0xDEAD_BEEF;
    try testing.expect(!state.tryWindowsSrwImport("AcquireSRWLockExclusive", returned));
    try testing.expectEqual(@as(u64, 0), state.read64(address));
    try testing.expectEqual(@as(u64, 0), state.windows_srw_fast_acquires.load(.monotonic));
}

test "SRW owner stack sampling clears stale frames and full capture remains available" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const address = MEM_BASE + 0x2000;
    const stack = MEM_BASE + 0x1000;
    state.regs.rsp = stack;
    for (0..1025) |_| {
        try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(address));
        state.releaseWindowsSrwLock(address);
    }
    try testing.expectEqual(@as(u64, 2), state.windows_srw_stack_captures);
    try testing.expectEqual(@as(u64, 1023), state.windows_srw_stack_skipped);
    const record = &state.windows_srw_locks[state.windowsSrwLockIndex(address).?];
    record.owner_stack = @splat(0xBAD);
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(address));
    try testing.expect(!record.owner_stack_sampled);
    try testing.expectEqualDeep([_]u64{0} ** windows_srw_owner_stack_depth, record.owner_stack);
    state.releaseWindowsSrwLock(address);
    state.windows_srw_stack_capture_all = true;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(address));
    try testing.expect(record.owner_stack_sampled);
    try testing.expectEqual(@as(u64, 3), state.windows_srw_stack_captures);
    state.releaseWindowsSrwLock(address);
}

test "SRW import lane production benchmark (ROSETTE_VECTOR_BENCH=1)" {
    if (std.c.getenv("ROSETTE_VECTOR_BENCH") == null) return error.SkipZigTest;
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const address = MEM_BASE + 0x2000;
    const returned = MEM_BASE + 0x1200;
    const acquire_stub = MEM_BASE + 0x700;
    const release_stub = MEM_BASE + 0x710;
    const iat = MEM_BASE + 0x900;
    try testing.expect(state.registerWindowsImportStubAtIat(acquire_stub, "kernel32.dll", "AcquireSRWLockExclusive", iat));
    try testing.expect(state.registerWindowsImportStubAtIat(release_stub, "kernel32.dll", "ReleaseSRWLockExclusive", iat + 8));
    state.windows_direct_stub_count = 2;
    state.windows_iat_low = iat;
    state.windows_iat_high = iat + 16;
    state.write64(iat, acquire_stub);
    state.write64(iat + 8, release_stub);
    state.regs = .{ .rsp = MEM_BASE + 0x1000, .rcx = address, .rbx = 0xB2 };
    const pairs = 200_000;
    var elapsed: [3]u64 = undefined;
    for (0..3) |mode| {
        state.windows_srw_stack_capture_all = mode == 0;
        state.windows_srw_import_lane = mode == 2;
        const started = monotonicNanoseconds();
        for (0..pairs) |_| {
            if (mode == 2) {
                try testing.expect(state.tryImportSlotFastTransfer(iat, returned));
                try testing.expect(state.tryImportSlotFastTransfer(iat + 8, returned));
            } else {
                var guard = state.lockWindowsRuntimeForDispatch();
                try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "AcquireSRWLockExclusive", returned));
                guard.unlock();
                guard = state.lockWindowsRuntimeForDispatch();
                try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "ReleaseSRWLockExclusive", returned));
                guard.unlock();
            }
        }
        elapsed[mode] = monotonicNanoseconds() - started;
        try testing.expectEqual(@as(u64, 0), state.read64(address));
        try testing.expectEqual(@as(u64, 0xB2), state.regs.rbx);
    }
    std.debug.print("SRW production benchmark: pairs={d} general_full_stack_ns={d} general_sampled_stack_ns={d} sampled_IAT_lane_ns={d}; runtime mutex, fences and handoff remain enabled\n", .{ pairs, elapsed[0], elapsed[1], elapsed[2] });
}

test "SRW import lane translated IAT loop preserves ownership and removes interpreter dispatch" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const bench = std.c.getenv("ROSETTE_VECTOR_BENCH") != null;
    const pairs: u64 = if (bench) 100_000 else 8;
    for ([_]bool{ false, true }) |enabled| {
        const state = try testing.allocator.create(ElfState);
        defer testing.allocator.destroy(state);
        state.* = ElfState.init(testing.allocator);
        defer state.deinit();
        state.windows_runtime_enabled = true;
        state.setParallelGuestExecution(true);
        defer state.setParallelGuestExecution(false);
        state.windows_srw_import_lane = enabled;
        state.windows_srw_stack_capture_all = !enabled;
        state.image_low = state.mem_base;
        state.image_high = state.mem_base + state.mem.len;
        const code = MEM_BASE + 0x1000;
        const iat = MEM_BASE + 0x900;
        const lock_address = MEM_BASE + 0x2000;
        try testing.expect(state.registerWindowsImportStubAtIat(MEM_BASE + 0x700, "kernel32.dll", "AcquireSRWLockExclusive", iat));
        try testing.expect(state.registerWindowsImportStubAtIat(MEM_BASE + 0x710, "kernel32.dll", "ReleaseSRWLockExclusive", iat + 8));
        state.windows_direct_stub_base = MEM_BASE + 0x700;
        state.windows_direct_stub_count = 2;
        state.windows_iat_low = iat;
        state.windows_iat_high = iat + 16;
        state.write64(iat, MEM_BASE + 0x700);
        state.write64(iat + 8, MEM_BASE + 0x710);
        state.indexWindowsIatStubs();
        // call [acquire IAT]; call [release IAT]; dec rbx; jne loop.
        var program = [_]u8{ 0xFF, 0x15, 0, 0, 0, 0, 0xFF, 0x15, 0, 0, 0, 0, 0x48, 0xFF, 0xCB, 0x75, 0xEF, 0xEB, 0xFE };
        std.mem.writeInt(i32, program[2..6], @intCast(@as(i64, @intCast(iat)) - @as(i64, @intCast(code + 6))), .little);
        std.mem.writeInt(i32, program[8..12], @intCast(@as(i64, @intCast(iat + 8)) - @as(i64, @intCast(code + 12))), .little);
        @memcpy(state.guestMemory(code, program.len).?, &program);
        state.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = program.len }});
        state.regs = .{ .rip = code, .rsp = MEM_BASE + 0x40000, .rcx = lock_address, .rbx = pairs, .rflags = 2 };
        state.block_jit_enabled = true;
        const started = monotonicNanoseconds();
        var steps: u64 = 0;
        while (state.regs.rip != code + 17 and !state.terminated and steps < pairs * 20) : (steps += 1) _ = state.step();
        const elapsed = monotonicNanoseconds() - started;
        try testing.expectEqual(code + 17, state.regs.rip);
        try testing.expectEqual(@as(u64, 0), state.regs.rbx);
        try testing.expectEqual(MEM_BASE + 0x40000, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0), state.read64(lock_address));
        try testing.expect(state.block_jit != null);
        try testing.expectEqual(if (enabled) pairs else 0, state.windows_srw_fast_acquires.load(.monotonic));
        try testing.expectEqual(if (enabled) pairs else 0, state.windows_srw_fast_releases.load(.monotonic));
        if (bench) std.debug.print("SRW translated IAT benchmark: enabled={} pairs={d} elapsed_ns={d} dispatch_steps={d} import_slot_fast_transfers={d}\n", .{ enabled, pairs, elapsed, steps, state.windows_import_slot_fast_transfers.load(.monotonic) });
    }
}

test "parallel workers translate their hot loops into their own caches and run them at once" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 4 * 1024 * 1024);
    defer state.deinit();
    const image_base: u64 = 0x140000000;
    state.mem_base = image_base;
    state.mem_size = state.mem.len;
    state.image_low = image_base;
    state.image_high = image_base + 0x10000;
    state.heap_next = image_base + 0x20000;
    state.guest_heap_limit = image_base + state.mem_size - 0x10000;
    state.windows_process_peb = image_base + 0x8000;
    state.windows_runtime_enabled = true;
    state.block_jit_hot_threshold = 2;
    state.regs.rax = 0xCAFE;
    const start = image_base + 0x1000;
    const code_offset: usize = @intCast(start - image_base);
    const program = [_]u8{
        0x48, 0x89, 0xCA, // mov rdx, rcx (the thread argument)
        0x31, 0xC0, // xor eax, eax
        0x48, 0x83, 0xC0, 0x03, // loop: add rax, 3
        0x48, 0xFF, 0xCA, // dec rdx
        0x75, 0xF7, // jnz loop
        0xC3, // ret
    };
    @memcpy(state.mem[code_offset .. code_offset + program.len], &program);
    state.configureWindowsExecutableRanges(&.{.{ .guest_base = start, .length = 0x1000 }});
    state.setParallelGuestExecution(true);

    try testing.expect(state.enqueueWindowsGuestThread(0xF000000000000001, start, 1000, 64 * 1024, true));
    try testing.expect(state.enqueueWindowsGuestThread(0xF000000000000002, start, 2500, 64 * 1024, true));
    _ = state.serviceWindowsGuestThreads(64);
    _ = state.serviceWindowsGuestThreads(64);
    try testing.expect(state.windows_guest_threads[0].parallel_worker.isStarted());
    try testing.expect(state.windows_guest_threads[1].parallel_worker.isStarted());
    state.windows_guest_threads[0].parallel_worker.join();
    state.windows_guest_threads[1].parallel_worker.join();

    const expected = [_]u64{ 3000, 7500 };
    for (expected, 0..) |rax, slot| {
        const thread = &state.windows_guest_threads[slot];
        try testing.expectEqual(WindowsGuestThreadStatus.completed, thread.status);
        try testing.expectEqual(rax, thread.context.regs.rax);
        // Its own cache, with its own translated loop in it.
        const jit = thread.parallel_block_jit orelse return error.TestUnexpectedResult;
        try testing.expect(jit.compiled > 0);
        try testing.expect(jit.instructions_retired > 0);
        try testing.expectEqual(@as(u64, 0), jit.mismatches);
    }
    var accounted_worker_steps: u64 = 0;
    for (state.windows_guest_threads[0..expected.len]) |*thread| {
        // The second worker retires more than the 4096-step publication
        // interval, exercising both an in-run batch and the exit flush.
        const steps = @atomicLoad(u64, &thread.executed_steps, .monotonic);
        try testing.expect(steps != 0);
        accounted_worker_steps +|= steps;
    }
    try testing.expectEqual(accounted_worker_steps, state.windowsWorkerSteps());
    try testing.expect(state.windows_guest_threads[0].parallel_block_jit != state.windows_guest_threads[1].parallel_block_jit);
    try testing.expectEqual(@as(u64, 0xCAFE), state.regs.rax);
}
