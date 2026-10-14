//! CPU-only proof of runtime availability during a long native shader call.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const clock = I._concurrency;
const ElfState = process.ElfState;
const atomic = std.atomic.Value;
const Probe = struct {
    state: *ElfState,
    ready: atomic(bool) = .init(false),
    peer_ns: u64 = 0,
    peer_inside: atomic(bool) = .init(false),
    elapsed_ns: u64 = 0,
    fn native(self: *@This()) i32 {
        const start = clock.monotonicNanoseconds();
        self.ready.store(true, .release);
        var time: std.c.timespec = .{ .sec = 0, .nsec = 150 * std.time.ns_per_ms };
        _ = std.c.nanosleep(&time, null);
        self.elapsed_ns = clock.monotonicNanoseconds() - start;
        return -123;
    }
    fn peer(self: *@This()) void {
        while (!self.ready.load(.acquire)) std.Thread.yield() catch {};
        const start = clock.monotonicNanoseconds();
        var guard = self.state.lockWindowsRuntimeForDispatch();
        self.peer_ns = clock.monotonicNanoseconds() - start;
        // A waiting native compile is a safepoint, so a guest memory
        // mutation can finish instead of deadlocking on its execution lease.
        var mutation = self.state.guest_execution_gate.enterMutation();
        self.peer_inside.store(true, .release);
        mutation.unlock();
        guard.unlock();
    }
};
fn create() !*ElfState {
    const state = try std.testing.allocator.create(ElfState);
    state.* = ElfState.init(std.testing.allocator);
    state.setParallelGuestExecution(true);
    return state;
}
fn destroy(state: *ElfState) void {
    state.setParallelGuestExecution(false);
    state.deinit();
    std.testing.allocator.destroy(state);
}
test "native shader compile releases dispatch locks retains pins and restores nested depth" {
    const state = try create();
    defer destroy(state);
    const Callback = struct {
        fn probe(s: *ElfState) bool {
            if (!s.windows_runtime_mutex.tryLock()) return false;
            s.windows_runtime_mutex.unlock();
            return true;
        }
    };
    var outer = state.lockWindowsRuntimeForDispatch();
    var inner = state.lockWindowsRuntimeForDispatch();
    try std.testing.expect(state.withWindowsRuntimeLockReleasedFor(.native_shader_module, state, Callback.probe));
    try std.testing.expect(!state.windows_runtime_mutex.tryLock());
    inner.unlock();
    outer.unlock();
    try std.testing.expectEqual(@as(u64, 1), state.runtime_lock_native_shader_yields);
    var pinned = state.lockWindowsRuntime();
    try std.testing.expect(!state.withWindowsRuntimeLockReleasedFor(.native_shader_module, state, Callback.probe));
    pinned.unlock();
    try std.testing.expectEqual(@as(u64, 1), state.runtime_lock_native_shader_refusals);
    try std.testing.expect(state.withWindowsRuntimeLockReleasedFor(.native_shader_module, state, Callback.probe));
    try std.testing.expectEqual(@as(u64, 1), state.runtime_lock_native_shader_yields);
}
test "native shader compile production lock availability benchmark (ROSETTE_SHADER_LOCK_BENCH=1)" {
    if (std.c.getenv("ROSETTE_SHADER_LOCK_BENCH") == null) return error.SkipZigTest;
    const state = try create();
    defer destroy(state);
    for (0..7) |pair| for (0..2) |arm| {
        const enabled = (pair + arm) % 2 != 0;
        var probe: Probe = .{ .state = state };
        const peer = try std.Thread.spawn(.{}, Probe.peer, .{&probe});
        var lease = state.guest_execution_gate.enterStep();
        var guard = state.lockWindowsRuntimeForDispatch();
        const result = if (enabled) state.withWindowsRuntimeLockReleasedFor(.native_shader_module, &probe, Probe.native) else probe.native();
        try std.testing.expectEqual(@as(i32, -123), result);
        try std.testing.expect(!state.windows_runtime_mutex.tryLock());
        if (enabled) try std.testing.expect(probe.peer_inside.load(.acquire));
        guard.unlock();
        lease.unlock();
        peer.join();
        try std.testing.expect(probe.peer_inside.load(.acquire));
        std.debug.print("SHADER_LOCK pair={d} enabled={} peer_ns={d} native_ns={d} result={d}\n", .{ pair, enabled, probe.peer_ns, probe.elapsed_ns, result });
    };
}
