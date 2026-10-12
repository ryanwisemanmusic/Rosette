//! The Win32 mutex contract, observed only through what a guest sees: the
//! answers of WaitForSingleObject, WaitForMultipleObjects and ReleaseMutex.
//! It uses no API younger than the defect it checks, so the same file runs
//! against the runtime before and after the 2026-10-12 ownership fix: before
//! it, every test here fails; after it, every test passes (see
//! `docs/halo3-mutex-stall-20261012.md` for the recorded runs of both).
const std = @import("std");
const testing = std.testing;
const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const ElfState = process.ElfState;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const WindowsMultiWaitResult = __ProcessInternals._WindowsMultiWaitResult;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const INFINITE: u64 = std.math.maxInt(u32);

fn runAs(state: *ElfState, slot: usize, id: u64) void {
    if (state.windows_guest_threads[slot].status == .vacant) {
        state.windows_guest_threads[slot] = .{ .status = .running, .handle = 0xE000 + slot, .thread_id = id };
    }
    state.windows_guest_threads[slot].status = .running;
    state.windows_active_guest_thread_slot = slot;
}

/// ReleaseMutex through Rosette's import dispatcher, as the guest calls it.
fn releaseMutex(state: *ElfState, handle: u64) u64 {
    state.regs = .{};
    state.regs.rcx = handle;
    std.debug.assert(x64_linux_runtime.tryWindowsFunction(state, "KERNEL32.dll", "ReleaseMutex", MEM_BASE + 0x500));
    return state.regs.rax;
}

test "contract: a mutex's owner may wait on it again and is satisfied at once" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const mutex: u64 = 0xFFFF_F000_0000_0C01;
    state.registerWindowsMutex(mutex, false);
    runAs(&state, 1, 101);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
}

test "contract: a mutex released to a waiter is not handed to a third thread as well" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const mutex: u64 = 0xFFFF_F000_0000_0C02;
    state.registerWindowsMutex(mutex, false);
    runAs(&state, 1, 201);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    runAs(&state, 2, 202);
    try testing.expectEqual(ElfState.WindowsWaitResult.blocked, state.waitWindowsGuestObject(mutex, INFINITE));
    runAs(&state, 1, 201);
    try testing.expectEqual(@as(u64, 1), releaseMutex(&state, mutex));
    runAs(&state, 3, 203);
    try testing.expectEqual(ElfState.WindowsWaitResult.timeout, state.waitWindowsGuestObject(mutex, 0));
}

test "contract: ReleaseMutex fails for a thread that does not own the mutex" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const mutex: u64 = 0xFFFF_F000_0000_0C03;
    state.registerWindowsMutex(mutex, false);
    runAs(&state, 1, 301);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    runAs(&state, 2, 302);
    try testing.expectEqual(@as(u64, 0), releaseMutex(&state, mutex));
}

test "contract: Halo 3's custom-game stall interleaving completes" {
    // Run 20261012T000703Z-d1148bf7a07f: MAIN_THREAD owns the mutex, the
    // worker polls it with 1 ms multi-object waits, and MAIN_THREAD waits on
    // the mutex again before releasing it - the wait that never returned.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.guest_clock.source = .retired_instructions;
    const event: u64 = 0xFFFF_F000_0000_02BC;
    const mutex: u64 = 0xFFFF_F000_0000_02BD;
    state.registerWindowsEvent(event, false, false);
    state.registerWindowsMutex(mutex, false);
    const polled = [_]u64{ event, mutex };

    runAs(&state, 23, 0x14);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    runAs(&state, 38, 0x114);
    state.guest_clock.ticks = 10_000;
    try testing.expectEqual(WindowsMultiWaitResult.blocked, state.waitWindowsGuestObjects(&polled, false, 1));
    state.windows_active_guest_thread_slot = null;
    state.guest_clock.ticks = 10_000 + process.WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    _ = state.wakeExpiredWindowsGuestWaits();
    runAs(&state, 38, 0x114);
    try testing.expectEqual(WindowsMultiWaitResult.timeout, state.waitWindowsGuestObjects(&polled, false, 1));

    runAs(&state, 23, 0x14);
    try testing.expectEqual(ElfState.WindowsWaitResult.signaled, state.waitWindowsGuestObject(mutex, INFINITE));
    try testing.expectEqual(@as(u64, 1), releaseMutex(&state, mutex));
    try testing.expectEqual(@as(u64, 1), releaseMutex(&state, mutex));
    runAs(&state, 38, 0x114);
    try testing.expectEqual(@as(u32, 1), state.waitWindowsGuestObjects(&polled, false, 1).signaled);
}
