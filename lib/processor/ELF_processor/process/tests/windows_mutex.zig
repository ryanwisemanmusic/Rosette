//! Win32 mutex semantics in Rosette's wait model.
//!
//! Xenia backs every Xbox 360 mutant with a native Win32 mutex
//! (`XMutant` -> `xe::threading::Mutant` -> CreateMutex / WaitForSingleObjectEx
//! / ReleaseMutex) and passes recursion straight through: the 360's mutants
//! are recursive and owned, exactly like a Win32 mutex. Until 2026-10-12
//! Rosette's mutex was an auto-reset flag with no owner. A thread waiting on
//! a mutex it already owned parked forever, any thread could release it,
//! and a release that woke a waiter left the mutex signalled, so the next
//! thread to ask owned it as well.
//!
//! The Halo 3 custom-game run 20261012T000703Z-d1148bf7a07f stopped on
//! exactly that: MAIN_THREAD parked on mutex 0xfffff000000002bd with an
//! infinite timeout (site_waits=1, site_signals=0), XThread0028 polled the
//! same mutex with 1 ms WaitForMultipleObjectsEx timeouts 58,476 times, no
//! release ever came, the title translated no new code for the last 93% of
//! the run, and RENDER spun waiting for a frame that never came.
const std = @import("std");
const testing = std.testing;
const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const ElfState = process.ElfState;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const WindowsMultiWaitResult = __ProcessInternals._WindowsMultiWaitResult;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const sync = __ProcessInternals._process_impl_windows_sync;
const INFINITE: u64 = std.math.maxInt(u32);

fn ownerOf(state: *const ElfState, handle: u64) u64 {
    return sync.windowsMutexOwner(state, handle).?.owner_thread_id;
}

fn recursionOf(state: *const ElfState, handle: u64) u32 {
    return sync.windowsMutexOwner(state, handle).?.recursion;
}

fn mutexObject(state: *const ElfState, handle: u64) *const __ProcessInternals._WindowsWaitObject {
    return &state.windows_wait_objects[sync.windowsWaitObjectIndex(state, handle).?];
}

/// Make slot `slot` the running guest thread with Win32 thread id `id`.
fn runAs(state: *ElfState, slot: usize, id: u64) void {
    if (state.windows_guest_threads[slot].status == .vacant) {
        state.windows_guest_threads[slot] = .{ .status = .running, .handle = 0xE000 + slot, .thread_id = id };
    }
    state.windows_guest_threads[slot].status = .running;
    state.windows_active_guest_thread_slot = slot;
}

test "a mutex's owner acquires it again at once, and must release it once per acquisition" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const mutex: u64 = 0xFFFF_F000_0000_0B01;
    state.registerWindowsMutex(mutex, false);

    runAs(&state, 1, 101);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    // The recursive wait: Win32 satisfies it at once. The old model parked
    // the owner on its own mutex for ever.
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    try testing.expectEqual(@as(u32, 2), recursionOf(&state, mutex));
    try testing.expectEqual(@as(u64, 101), ownerOf(&state, mutex));

    runAs(&state, 2, 102);
    try testing.expectEqual(ElfState.WindowsWaitResult.blocked, state.waitWindowsGuestObject(mutex, INFINITE));

    // The first release only undoes the recursion: the waiter stays parked.
    runAs(&state, 1, 101);
    try testing.expect(state.releaseWindowsMutex(mutex));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[2].status);
    // The second frees it, and it goes to the waiter.
    try testing.expect(state.releaseWindowsMutex(mutex));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[2].status);
    try testing.expectEqual(@as(u64, 102), ownerOf(&state, mutex));
    // A third release is not the owner's to make: ERROR_NOT_OWNER.
    try testing.expect(!state.releaseWindowsMutex(mutex));
    try testing.expectEqual(@as(u32, 1), mutexObject(&state, mutex).release_refusals);
    try testing.expectEqual(@as(u32, 1), mutexObject(&state, mutex).recursive_acquisitions);
}

test "a released mutex belongs to the waiter it wakes, not to the next thread that asks" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const mutex: u64 = 0xFFFF_F000_0000_0B02;
    state.registerWindowsMutex(mutex, false);

    runAs(&state, 1, 201);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    runAs(&state, 2, 202);
    try testing.expectEqual(ElfState.WindowsWaitResult.blocked, state.waitWindowsGuestObject(mutex, INFINITE));
    runAs(&state, 1, 201);
    try testing.expect(state.releaseWindowsMutex(mutex));
    try testing.expectEqual(@as(u32, 1), mutexObject(&state, mutex).handoffs);

    // Before the woken waiter has even run, a third thread asks. The mutex
    // is the waiter's: the old model left it signalled and handed it out
    // twice.
    runAs(&state, 3, 203);
    try testing.expectEqual(ElfState.WindowsWaitResult.timeout, state.waitWindowsGuestObject(mutex, 0));

    // The waiter resumes owning it.
    runAs(&state, 2, 202);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    try testing.expect(state.releaseWindowsMutex(mutex));
    runAs(&state, 3, 203);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, 0));
}

test "an initially owned mutex belongs to the thread that created it" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const mutex: u64 = 0xFFFF_F000_0000_0B03;
    runAs(&state, 1, 301);
    state.registerWindowsMutex(mutex, true);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, 0));
    runAs(&state, 2, 302);
    try testing.expectEqual(ElfState.WindowsWaitResult.timeout, state.waitWindowsGuestObject(mutex, 0));
    runAs(&state, 1, 301);
    try testing.expect(state.releaseWindowsMutex(mutex));
    try testing.expect(state.releaseWindowsMutex(mutex));
    runAs(&state, 2, 302);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, 0));
}

test "a multi-object wait takes a mutex as its owner and counts the owner's recursion" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const event: u64 = 0xFFFF_F000_0000_0B11;
    const mutex: u64 = 0xFFFF_F000_0000_0B12;
    state.registerWindowsEvent(event, false, false);
    state.registerWindowsMutex(mutex, false);
    const handles = [_]u64{ event, mutex };

    runAs(&state, 4, 401);
    try testing.expectEqual(@as(u32, 1), state.waitWindowsGuestObjects(&handles, false, 1).signaled);
    try testing.expectEqual(@as(u32, 1), state.waitWindowsGuestObjects(&handles, false, 1).signaled);
    try testing.expectEqual(@as(u32, 2), recursionOf(&state, mutex));
    runAs(&state, 5, 402);
    try testing.expectEqual(WindowsMultiWaitResult.timeout, state.waitWindowsGuestObjects(&handles, false, 0));
}

test "a thread that exits owning a mutex hands it to the next waiter" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const mutex: u64 = 0xFFFF_F000_0000_0B21;
    state.registerWindowsMutex(mutex, false);
    runAs(&state, 6, 601);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    runAs(&state, 7, 602);
    try testing.expectEqual(ElfState.WindowsWaitResult.blocked, state.waitWindowsGuestObject(mutex, INFINITE));

    runAs(&state, 6, 601);
    __ProcessInternals._process_impl_windows_sync.finishWindowsGuestThread(&state);
    try testing.expectEqual(@as(u32, 1), mutexObject(&state, mutex).abandoned);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[7].status);
    try testing.expectEqual(@as(u64, 602), ownerOf(&state, mutex));
}

test "ReleaseMutex answers FALSE with ERROR_NOT_OWNER to a thread that does not own the mutex" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x500;
    const mutex: u64 = 0xFFFF_F000_0000_0B31;
    state.registerWindowsMutex(mutex, false);
    runAs(&state, 1, 701);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));

    runAs(&state, 2, 702);
    state.regs = .{};
    state.regs.rcx = mutex;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "ReleaseMutex", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u64, 288), state.windows_last_error);

    runAs(&state, 1, 701);
    state.regs = .{};
    state.regs.rcx = mutex;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "ReleaseMutex", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(?bool, true), state.windowsWaitObjectReady(mutex));
}

test "Halo 3's custom-game stall: the owner's second wait on its mutex while a worker polls it" {
    // The interleaving of run 20261012T000703Z-d1148bf7a07f, with the run's
    // own handle and thread names. MAIN_THREAD (slot 23) takes the mutex
    // without contention, XThread0028 (slot 38) polls it with 1 ms
    // WaitForMultipleObjectsEx timeouts beside its event, and MAIN_THREAD
    // waits on the mutex again before releasing it.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.source = .retired_instructions;
    const event: u64 = 0xFFFF_F000_0000_02BC;
    const mutex: u64 = 0xFFFF_F000_0000_02BD;
    state.registerWindowsEvent(event, false, false);
    state.registerWindowsMutex(mutex, false);
    const main_slot: usize = 23;
    const worker_slot: usize = 38;
    const polled = [_]u64{ event, mutex };

    runAs(&state, main_slot, 0x14);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));

    // The worker parks for a millisecond and times out, as it did 58,476
    // times in the run.
    runAs(&state, worker_slot, 0x114);
    state.guest_clock.ticks = 10_000;
    try testing.expectEqual(WindowsMultiWaitResult.blocked, state.waitWindowsGuestObjects(&polled, false, 1));
    state.windows_active_guest_thread_slot = null;
    state.guest_clock.ticks = 10_000 + process.WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    try testing.expectEqual(@as(u64, 1), state.wakeExpiredWindowsGuestWaits());
    runAs(&state, worker_slot, 0x114);
    try testing.expectEqual(WindowsMultiWaitResult.timeout, state.waitWindowsGuestObjects(&polled, false, 1));

    // The wait that parked MAIN_THREAD for the rest of the run: it owns the
    // mutex, so Win32 satisfies it at once.
    runAs(&state, main_slot, 0x14);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    try testing.expect(state.releaseWindowsMutex(mutex));
    try testing.expect(state.releaseWindowsMutex(mutex));

    // And the worker's next poll gets the mutex.
    runAs(&state, worker_slot, 0x114);
    try testing.expectEqual(@as(u32, 1), state.waitWindowsGuestObjects(&polled, false, 1).signaled);
    try testing.expectEqual(@as(u64, 0x114), ownerOf(&state, mutex));
}
