//! Production NT zero-delay adapters and translated IAT call loops.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const testing = std.testing;
const ElfState = process.ElfState;
const runtime = I._x64_linux_runtime;
const base = I._MEM_BASE;

fn create() !*ElfState {
    const state = try testing.allocator.create(ElfState);
    state.* = ElfState.init(testing.allocator);
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    state.windows_active_guest_thread_slot = 3;
    state.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
    return state;
}
fn destroy(state: *ElfState) void {
    state.setParallelGuestExecution(false);
    state.deinit();
    testing.allocator.destroy(state);
}
fn seed(state: *ElfState) void {
    state.regs = .{ .rip = base + 0x700, .rsp = base + 0x30000, .rax = 0xBAD, .rcx = 0, .rdx = base + 0x800, .rbx = 0x1234, .rflags = 0x246 };
    state.write64(state.regs.rdx, 0);
    state.write64(state.regs.rsp, base + 0x1200);
    state.windows_last_error = 0xBEEF;
    state.windows_guest_slice_yield_requested = false;
}

test "NT zero-delay fast lane preserves the ordinary ABI and scheduler yield" {
    const state = try create();
    defer destroy(state);
    for ([_][]const u8{ "NtDelayExecution", "NtYieldExecution" }) |name| {
        seed(state);
        state.windows_fast_nt_yield.enabled = false;
        try testing.expect(runtime.tryWindowsFunction(state, "ntdll.dll", name, base + 0x1200));
        const expected = state.regs;
        const last_error = state.windows_last_error;
        const yielded = state.windows_guest_slice_yield_requested;
        seed(state);
        state.windows_fast_nt_yield.enabled = true;
        const locks = state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic);
        try testing.expect(runtime.tryWindowsFastFunction(state, "NTDLL.DLL", name, base + 0x1200));
        try testing.expectEqualDeep(expected, state.regs);
        try testing.expectEqual(last_error, state.windows_last_error);
        try testing.expectEqual(yielded, state.windows_guest_slice_yield_requested);
        try testing.expectEqual(locks, state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));
        try testing.expectEqual(I._WindowsGuestThreadStatus.running, state.windows_guest_threads[3].status);
    }
    try testing.expectEqual(@as(u64, 2), state.windows_fast_nt_yield.total());
}

test "NT zero-delay fast lane declines timed alertable invalid diagnostic and owned-lock calls" {
    const state = try create();
    defer destroy(state);
    seed(state);
    for ([_]i64{ -1, -150000, 1, std.math.minInt(i64) }) |interval| {
        state.write64(state.regs.rdx, @bitCast(interval));
        try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    }
    seed(state);
    state.regs.rcx = 1;
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    seed(state);
    state.regs.rdx = 0;
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    state.regs.rdx = 0xDEAD00000000;
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    seed(state);
    state.diagnose_abi = true;
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    state.diagnose_abi = false;
    state.trace_windows_memory = true;
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    state.trace_windows_memory = false;
    state.trace_write_address = base + 0x800;
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    state.trace_write_address = null;
    state.guest_clock.source = .retired_instructions;
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    state.guest_clock.source = .host_monotonic;
    var guard = state.lockWindowsRuntime();
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    guard.unlock();
    state.xenia_global_mutex_address = base + 0xA00;
    state.write32(base + 0xA00 + I._XENIA_GLOBAL_MUTEX_OWNER_OFFSET, 43);
    state.write32(base + 0xA00 + I._XENIA_GLOBAL_MUTEX_RECURSION_OFFSET, 1);
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    state.write32(base + 0xA00 + I._XENIA_GLOBAL_MUTEX_RECURSION_OFFSET, 0);
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    state.write32(base + 0xA00 + I._XENIA_GLOBAL_MUTEX_OWNER_OFFSET, 99);
    try testing.expect(!runtime.tryWindowsFastFunction(state, "user32.dll", "NtDelayExecution", base + 0x1200));
    try testing.expect(!runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", null));
    try testing.expectEqual(@as(u64, 0), state.windows_fast_nt_yield.total());
    try testing.expect(runtime.tryWindowsFastFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    // A real nonzero interval still parks through general dispatch.
    seed(state);
    state.write64(state.regs.rdx, @bitCast(@as(i64, -150000)));
    try testing.expect(runtime.tryWindowsFunction(state, "ntdll.dll", "NtDelayExecution", base + 0x1200));
    try testing.expectEqual(I._WindowsGuestThreadStatus.blocked, state.windows_guest_threads[3].status);
    try testing.expectEqual(@as(u64, 1), state.windows_nt_delay_parks);
}

test "NT zero-delay fast lane validates IAT rebinding and drains the calling context's TSO stores" {
    const state = try create();
    defer destroy(state);
    seed(state);
    const stub = base + 0x700;
    const iat = base + 0x900;
    try testing.expect(state.registerWindowsImportStubAtIat(stub, "ntdll.dll", "NtDelayExecution", iat));
    state.windows_direct_stub_base = stub;
    state.windows_direct_stub_count = 1;
    state.write64(iat, stub + 1);
    try testing.expect(!state.tryWindowsFastImportStub(stub));
    state.write64(iat, stub);
    var context: I._WindowsGuestThreadContext = .{};
    context.regs = state.regs;
    context.regs.rax = 0xCAFE;
    context.windows_active_guest_thread_slot = 3;
    context.windows_last_error = 0xF00D;
    const old_binding = I._windows_guest_execution_binding().*;
    I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(state), .context = &context };
    defer I._windows_guest_execution_binding().* = old_binding;
    var stores: I._tso_memory.StoreBuffer = .{};
    const old_buffer = I._tso_memory.setActiveStoreBuffer(&stores);
    defer _ = I._tso_memory.setActiveStoreBuffer(old_buffer);
    var bytes = [_]u8{0} ** 8;
    I._tso_memory.store(u64, &bytes, 0x12345678);
    try testing.expectEqual(@as(usize, 1), stores.pendingCount());
    try testing.expect(state.tryWindowsFastImportStub(stub));
    try testing.expectEqual(@as(u64, 0), context.regs.rax);
    try testing.expectEqual(base + 0x1200, context.regs.rip);
    try testing.expectEqual(base + 0x30008, context.regs.rsp);
    try testing.expect(context.windows_guest_slice_yield_requested);
    try testing.expect(!state.windows_guest_slice_yield_requested);
    try testing.expectEqual(@as(u64, 0xBAD), state.regs.rax);
    try testing.expectEqual(@as(u32, 0xF00D), context.windows_last_error);
    try testing.expectEqual(@as(u64, 0x12345678), std.mem.readInt(u64, &bytes, .little));
    try testing.expectEqual(@as(usize, 0), stores.pendingCount());
    try testing.expect(I._tso_memory.activeStoreBuffer() == &stores);
}

test "NT zero-delay translated IAT loop benchmark (ROSETTE_YIELD_BENCH=1)" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const bench = std.c.getenv("ROSETTE_YIELD_BENCH") != null;
    const iterations: u64 = if (bench) 100000 else 16;
    const pairs: usize = if (bench) 7 else 1;
    for (0..pairs) |pair| for ([_]bool{ false, true }) |tail| for (0..2) |order| {
        const enabled = (pair + order) % 2 == 1;
        const state = try create();
        defer destroy(state);
        state.windows_fast_nt_yield.enabled = enabled;
        state.image_low = base;
        state.image_high = base + state.mem.len;
        const code = base + 0x1000;
        const stub = base + 0x700;
        const iat = base + 0x900;
        try testing.expect(state.registerWindowsImportStubAtIat(stub, "ntdll.dll", "NtDelayExecution", iat));
        state.windows_direct_stub_base = stub;
        state.windows_direct_stub_count = 1;
        state.windows_iat_low = iat;
        state.windows_iat_high = iat + 8;
        state.write64(iat, stub);
        state.indexWindowsIatStubs();
        // call [IAT]; dec rbx; jne loop; jmp self. Or call->jmp[IAT].
        var program = [_]u8{ 0xFF, 0x15, 0, 0, 0, 0, 0x48, 0xFF, 0xCB, 0x75, 0xF5, 0xEB, 0xFE };
        std.mem.writeInt(i32, program[2..6], @intCast(@as(i64, @intCast(iat)) - @as(i64, @intCast(code + 6))), .little);
        if (tail) {
            program[0] = 0xE8;
            std.mem.writeInt(i32, program[1..5], 0x100 - 5, .little);
            program[5] = 0x90;
            var thunk = [_]u8{ 0xFF, 0x25, 0, 0, 0, 0 };
            std.mem.writeInt(i32, thunk[2..6], @intCast(@as(i64, @intCast(iat)) - @as(i64, @intCast(code + 0x106))), .little);
            @memcpy(state.guestMemory(code + 0x100, thunk.len).?, &thunk);
        }
        @memcpy(state.guestMemory(code, program.len).?, &program);
        state.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = 0x106 }});
        state.write64(base + 0x800, 0);
        state.regs = .{ .rip = code, .rsp = base + 0x40000, .rbx = iterations, .rcx = 0, .rdx = base + 0x800, .rflags = 2 };
        state.block_jit_enabled = true;
        const locks_before = state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic);
        const started = I._monotonicNanoseconds();
        var steps: u64 = 0;
        var yields: u64 = 0;
        while (state.regs.rip != code + 11 and steps < iterations * 8 + 20) : (steps += 1) {
            try testing.expect(state.step());
            if (state.windows_guest_slice_yield_requested) yields += 1;
            state.windows_guest_slice_yield_requested = false;
        }
        const elapsed = I._monotonicNanoseconds() - started;
        try testing.expectEqual(@as(u64, 0), state.regs.rbx);
        try testing.expectEqual(base + 0x40000, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0), state.regs.rax);
        try testing.expectEqual(iterations, yields);
        try testing.expectEqual(iterations, state.windows_nt_delay_yields + state.windows_fast_nt_yield.total());
        try testing.expect(state.windows_guest_threads[3].parallel_block_jit != null and state.windows_guest_threads[3].parallel_block_jit.?.instructions_retired > 0);
        if (enabled) try testing.expectEqual(iterations, state.windows_fast_nt_yield.total());
        if (bench) std.debug.print("nt_yield pair={d} tail={} enabled={} calls={d} elapsed_ns={d} runtime_locks={d} yields={d} steps={d}\n", .{ pair, tail, enabled, iterations, elapsed, state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic) - locks_before, yields, steps });
    };
}

test "PAUSE bundle production dispatch benchmark (ROSETTE_YIELD_BENCH=1)" {
    if (std.c.getenv("ROSETTE_YIELD_BENCH") == null) return error.SkipZigTest;
    const state = try create();
    defer destroy(state);
    const rip = base + 0x1800;
    for (0..16) |i| state.write8(rip + i, if (i % 2 == 0) 0xF3 else 0x90);
    state.block_jit_enabled = true;
    const hints: u64 = 2000000;
    for (0..7) |pair| {
        state.windows_guest_threads[3].pause_hints = 0;
        var retired: u64 = 0;
        var dispatches: u64 = 0;
        const started = I._monotonicNanoseconds();
        while (retired < hints) {
            state.regs.rip = rip;
            state.windows_guest_slice_yield_requested = false;
            state.windows_slice_pause_yield = false;
            try testing.expect(state.step());
            retired += state.step_retired;
            dispatches += 1;
        }
        const elapsed = I._monotonicNanoseconds() - started;
        try testing.expectEqual(retired, state.windows_guest_threads[3].pause_hints);
        try testing.expect(state.regs.rip <= rip + 16);
        std.debug.print("pause_bundle pair={d} hints={d} elapsed_ns={d} dispatches={d}\n", .{ pair, retired, elapsed, dispatches });
    }
}

test "NT zero-delay concurrent production callers retain host yields (ROSETTE_YIELD_BENCH=1)" {
    const bench = std.c.getenv("ROSETTE_YIELD_BENCH") != null;
    const iterations: u64 = if (bench) 25000 else 32;
    const pairs: usize = if (bench) 7 else 1;
    const Runner = struct {
        state: *ElfState,
        context: I._WindowsGuestThreadContext = .{},
        ready: *std.atomic.Value(u32),
        go: *std.atomic.Value(bool),
        iterations: u64,
        host_yield: bool,
        checked: u64 = 0,
        failed: bool = false,
        fn run(self: *@This()) void {
            const binding = I._windows_guest_execution_binding().*;
            I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(self.state), .context = &self.context };
            defer I._windows_guest_execution_binding().* = binding;
            _ = self.ready.fetchAdd(1, .release);
            while (!self.go.load(.acquire)) std.atomic.spinLoopHint();
            for (0..self.iterations) |_| {
                self.context.regs.rax = 0xBAD;
                self.context.windows_guest_slice_yield_requested = false;
                if (!runtime.tryWindowsFunction(self.state, "ntdll.dll", "NtDelayExecution", base + 0x1200) or
                    self.context.regs.rax != 0 or self.context.regs.rip != base + 0x1200 or
                    self.context.windows_last_error != 0xCAFE or !self.context.windows_guest_slice_yield_requested) self.failed = true;
                self.checked += 1;
                if (self.host_yield) std.Thread.yield() catch {};
            }
        }
    };
    for (0..pairs) |pair| for ([_]bool{ false, true }) |host_yield| for (0..2) |order| {
        const enabled = (pair + order) % 2 == 1;
        const state = try create();
        defer destroy(state);
        state.windows_fast_nt_yield.enabled = enabled;
        state.write64(base + 0x800, 0);
        var ready: std.atomic.Value(u32) = .init(0);
        var go: std.atomic.Value(bool) = .init(false);
        var runners: [4]Runner = undefined;
        var threads: [4]std.Thread = undefined;
        for (&runners, 0..) |*runner, n| {
            state.windows_guest_threads[n + 3] = .{ .status = .running, .thread_id = n + 43 };
            runner.* = .{ .state = state, .ready = &ready, .go = &go, .iterations = iterations, .host_yield = host_yield };
            runner.context.windows_active_guest_thread_slot = n + 3;
            runner.context.windows_last_error = 0xCAFE;
            runner.context.regs = .{ .rcx = 0, .rdx = base + 0x800, .rbx = n + 100 };
            threads[n] = try std.Thread.spawn(.{}, Runner.run, .{runner});
        }
        while (ready.load(.acquire) != 4) std.atomic.spinLoopHint();
        const locks = state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic);
        const started = I._monotonicNanoseconds();
        go.store(true, .release);
        for (threads) |thread| thread.join();
        const elapsed = I._monotonicNanoseconds() - started;
        for (runners, 0..) |runner, n| {
            try testing.expect(!runner.failed);
            try testing.expectEqual(iterations, runner.checked);
            try testing.expectEqual(@as(u64, n + 100), runner.context.regs.rbx);
        }
        try testing.expectEqual(iterations * 4, state.windows_nt_delay_yields + state.windows_fast_nt_yield.total());
        if (enabled) try testing.expectEqual(locks, state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));
        if (bench) std.debug.print("nt_concurrent pair={d} host_yield={} enabled={} calls={d} elapsed_ns={d} runtime_locks={d}\n", .{ pair, host_yield, enabled, iterations * 4, elapsed, state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic) - locks });
    };
}

test "NT zero-delay dynamic register and tail-jump loops preserve registered targets (ROSETTE_YIELD_BENCH=1)" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const bench = std.c.getenv("ROSETTE_YIELD_BENCH") != null;
    const iterations: u64 = if (bench) 100000 else 16;
    const pairs: usize = if (bench) 7 else 1;
    for (0..pairs) |pair| for ([_]bool{ false, true }) |tail| for (0..2) |order| {
        const enabled = (pair + order) % 2 == 1;
        const state = try create();
        defer destroy(state);
        state.windows_fast_nt_yield.enabled = enabled;
        state.image_low = base;
        state.image_high = base + state.mem.len;
        const code = base + 0x1000;
        const stub = state.registerWindowsImportStub("ntdll.dll", "NtDelayExecution").?;
        const direct = [_]u8{ 0x41, 0xFF, 0xD4, 0x48, 0xFF, 0xCB, 0x75, 0xF8, 0xEB, 0xFE };
        var thunked = [_]u8{ 0xE8, 0, 0, 0, 0, 0x48, 0xFF, 0xCB, 0x75, 0xF6, 0xEB, 0xFE };
        std.mem.writeInt(i32, thunked[1..5], 0x100 - 5, .little);
        const program: []const u8 = if (tail) &thunked else &direct;
        @memcpy(state.guestMemory(code, program.len).?, program);
        @memcpy(state.guestMemory(code + 0x100, 3).?, &[_]u8{ 0x41, 0xFF, 0xE4 }); // jmp r12
        state.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = 0x106 }});
        state.write64(base + 0x800, 0);
        state.regs = .{ .rip = code, .rsp = base + 0x40000, .rbx = iterations, .r12 = stub, .rcx = 0, .rdx = base + 0x800, .rflags = 2 };
        state.block_jit_enabled = true;
        const locks = state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic);
        const started = I._monotonicNanoseconds();
        var steps: u64 = 0;
        var yields: u64 = 0;
        while (state.regs.rip != code + program.len - 2 and steps < iterations * 8 + 20) : (steps += 1) {
            try testing.expect(state.step());
            if (state.windows_guest_slice_yield_requested) yields += 1;
            state.windows_guest_slice_yield_requested = false;
        }
        const elapsed = I._monotonicNanoseconds() - started;
        try testing.expectEqual(@as(u64, 0), state.regs.rbx);
        try testing.expectEqual(stub, state.regs.r12);
        try testing.expectEqual(base + 0x40000, state.regs.rsp);
        try testing.expectEqual(iterations, yields);
        try testing.expectEqual(iterations, state.windows_nt_delay_yields + state.windows_fast_nt_yield.total());
        try testing.expect(state.windows_guest_threads[3].parallel_block_jit != null);
        try testing.expect(state.windows_guest_threads[3].parallel_block_jit.?.instructions_retired > 0);
        if (bench) std.debug.print("nt_register pair={d} tail={} enabled={} calls={d} elapsed_ns={d} runtime_locks={d} yields={d} steps={d}\n", .{ pair, tail, enabled, iterations, elapsed, state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic) - locks, yields, steps });
    };
}
