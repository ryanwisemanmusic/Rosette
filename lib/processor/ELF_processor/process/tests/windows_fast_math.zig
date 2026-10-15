//! Exercise the production import adapter and translated IAT transfers;
//! no emulator, graphics device, synthetic approximation or host DLL needed.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const testing = std.testing;
const ElfState = process.ElfState;
const runtime = I._x64_linux_runtime;
const fp = @import("../../host_fp_control.zig");
const base = I._MEM_BASE;
const dll = "api-ms-win-crt-math-l1-1-0.dll";

fn stateForTest() !*ElfState {
    const state = try testing.allocator.create(ElfState);
    state.* = ElfState.init(testing.allocator);
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    return state;
}

fn destroy(state: *ElfState) void {
    state.setParallelGuestExecution(false);
    state.deinit();
    testing.allocator.destroy(state);
}

fn seed(state: *ElfState, input: u64) void {
    state.regs = .{ .rip = base + 0x700, .rsp = base + 0x30000, .rax = 0xABCD, .rbx = 0x1234, .rflags = 0x246 };
    for (&state.xmm, 0..) |*reg, n| @memset(reg, @as(u8, @intCast(n + 1)));
    for (&state.ymm_hi) |*reg| @memset(reg, 0xCD);
    for (&state.zmm_hi) |*reg| @memset(reg, 0xEF);
    std.mem.writeInt(u64, state.xmm[0][0..8], input, .little);
    state.windows_last_error = 0xBEEF;
    state.write64(state.regs.rsp, base + 0x1200);
}

test "fast math production results and ABI match general dispatch in every MXCSR mode" {
    const state = try stateForTest();
    defer destroy(state);
    const saved_fpcr = fp.read();
    defer fp.write(saved_fpcr);
    const edges = [_]u64{ 0, 0x8000000000000000, 1, 0x8000000000000001, 0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000001234, 0xFFF8000000005678, @bitCast(@as(f64, -1075)), @bitCast(@as(f64, -1074)), @bitCast(@as(f64, -1022)), @bitCast(@as(f64, 1024)), @bitCast(@as(f64, 0.5)) };
    const float_edges = [_]u32{ 0, 0x80000000, 1, 0x80000001, 0x7F800000, 0xFF800000, 0x7FC01234, 0xFFC05678, @bitCast(@as(f32, -150)), @bitCast(@as(f32, -149)), @bitCast(@as(f32, -126)), @bitCast(@as(f32, 128)), @bitCast(@as(f32, 0.5)) };
    var prng = std.Random.DefaultPrng.init(0xE2F064);
    const random = prng.random();
    for ([_]u32{ 0x1F80, 0x3F80, 0x5F80, 0x7F80, 0x9FC0, 0xBFC0, 0xDFC0, 0xFFC0 }) |mxcsr| {
        for ([_][]const u8{ "exp2", "exp2f", "log10" }) |name| {
            for (0..256) |index| {
                const input: u64 = if (index < edges.len) (if (std.mem.eql(u8, name, "exp2f")) float_edges[index] else edges[index]) else random.int(u64);
                seed(state, input);
                state.regs.mxcsr = mxcsr;
                fp.applyGuestMxcsr(mxcsr);
                state.windows_fast_math.enabled = false;
                try testing.expect(runtime.tryWindowsFunction(state, dll, name, base + 0x1200));
                const expected_regs = state.regs;
                const expected_xmm = state.xmm;
                const expected_error = state.windows_last_error;
                const expected_fpcr = fp.read();
                seed(state, input);
                state.regs.mxcsr = mxcsr;
                fp.applyGuestMxcsr(mxcsr);
                state.windows_fast_math.enabled = true;
                const locks_before = state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic);
                try testing.expect(runtime.tryWindowsFastFunction(state, dll, name, base + 0x1200));
                try testing.expectEqualDeep(expected_regs, state.regs);
                try testing.expectEqualDeep(expected_xmm, state.xmm);
                for (state.ymm_hi) |reg| for (reg) |byte| try testing.expectEqual(@as(u8, 0xCD), byte);
                for (state.zmm_hi) |reg| for (reg) |byte| try testing.expectEqual(@as(u8, 0xEF), byte);
                try testing.expectEqual(expected_error, state.windows_last_error);
                try testing.expectEqual(expected_fpcr, fp.read());
                try testing.expectEqual(mxcsr, state.regs.mxcsr);
                try testing.expectEqual(locks_before, state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));
            }
        }
    }
    try testing.expectEqual(@as(u64, 6144), state.windows_fast_math.total());
}

test "fast math refuses diagnostics lock recursion and a rebound IAT without side effects" {
    const state = try stateForTest();
    defer destroy(state);
    const stub = base + 0x700;
    const iat = base + 0x900;
    try testing.expect(state.registerWindowsImportStubAtIat(stub, dll, "exp2", iat));
    state.windows_direct_stub_base = stub;
    state.windows_direct_stub_count = 1;
    state.write64(iat, stub);
    seed(state, @bitCast(@as(f64, 3)));
    const before = state.regs;
    state.diagnose_abi = true;
    try testing.expect(!state.tryWindowsFastImportStub(stub));
    state.diagnose_abi = false;
    state.write64(iat, stub + 1);
    try testing.expect(!state.tryWindowsFastImportStub(stub));
    state.write64(iat, stub);
    var guard = state.lockWindowsRuntime();
    try testing.expect(!state.tryWindowsFastImportStub(stub));
    guard.unlock();
    try testing.expectEqualDeep(before, state.regs);
    try testing.expectEqual(@as(u64, 0), state.windows_fast_math.total());
    try testing.expect(!runtime.tryWindowsFastFunction(state, "user32.dll", "exp2", base + 0x1200));
    try testing.expect(!runtime.tryWindowsFastFunction(state, dll, "exp2", null));
    try testing.expect(state.tryWindowsFastImportStub(stub));
    try testing.expectEqual(base + 0x1200, state.regs.rip);
    try testing.expectEqual(before.rsp + 8, state.regs.rsp);
    try testing.expectEqual(@as(f64, 8), @as(f64, @bitCast(std.mem.readInt(u64, state.xmm[0][0..8], .little))));
}

test "fast math uses the bound calling context and drains its TSO stores" {
    const state = try stateForTest();
    defer destroy(state);
    seed(state, @bitCast(@as(f64, 7)));
    var context: I._WindowsGuestThreadContext = .{};
    context.regs = .{ .rip = base + 0x700, .rsp = base + 0x31000, .rax = 0xCAFE };
    std.mem.writeInt(u64, context.xmm[0][0..8], @bitCast(@as(f64, 3)), .little);
    context.windows_last_error = 0xFACE;
    const prior_binding = I._windows_guest_execution_binding().*;
    I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(state), .context = &context };
    defer I._windows_guest_execution_binding().* = prior_binding;
    var stores: I._tso_memory.StoreBuffer = .{};
    const prior = I._tso_memory.setActiveStoreBuffer(&stores);
    defer _ = I._tso_memory.setActiveStoreBuffer(prior);
    var bytes = [_]u8{0} ** 8;
    I._tso_memory.store(u64, &bytes, 0x12345678);
    try testing.expectEqual(@as(usize, 1), stores.pendingCount());
    try testing.expect(runtime.tryWindowsFastFunction(state, dll, "exp2", base + 0x1200));
    try testing.expectEqual(@as(f64, 8), @as(f64, @bitCast(std.mem.readInt(u64, context.xmm[0][0..8], .little))));
    try testing.expectEqual(base + 0x1200, context.regs.rip);
    try testing.expectEqual(@as(u64, 0xCAFE), context.regs.rax);
    try testing.expectEqual(@as(u32, 0), context.windows_last_error);
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, 7))), std.mem.readInt(u64, state.xmm[0][0..8], .little));
    try testing.expectEqual(@as(u64, 0x12345678), std.mem.readInt(u64, &bytes, .little));
    try testing.expectEqual(@as(usize, 0), stores.pendingCount());
    try testing.expect(I._tso_memory.activeStoreBuffer() == &stores);
}

test "fast math translated call and tail-jump IAT loops preserve results (ROSETTE_MATH_BENCH=1)" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const bench = std.c.getenv("ROSETTE_MATH_BENCH") != null;
    const pairs: usize = if (bench) 7 else 1;
    const iterations: u64 = if (bench) 100_000 else 8;
    for (0..pairs) |pair| {
        for ([_]bool{ false, true }) |tail| {
            for (0..2) |order| {
                const enabled = (order + pair) % 2 == 1;
                const state = try stateForTest();
                defer destroy(state);
                state.windows_fast_math.enabled = enabled;
                state.image_low = base;
                state.image_high = base + state.mem.len;
                const code = base + 0x1000;
                const iat = base + 0x900;
                const stub = base + 0x700;
                try testing.expect(state.registerWindowsImportStubAtIat(stub, dll, "exp2", iat));
                state.windows_direct_stub_base = stub;
                state.windows_direct_stub_count = 1;
                state.windows_iat_low = iat;
                state.windows_iat_high = iat + 8;
                state.write64(iat, stub);
                state.indexWindowsIatStubs();
                // vmovq xmm0,rax; call [IAT]/relative thunk; dec rbx; jne loop.
                var program = [_]u8{ 0xC4, 0xE1, 0xF9, 0x6E, 0xC0, 0xFF, 0x15, 0, 0, 0, 0, 0x48, 0xFF, 0xCB, 0x75, 0xF0, 0xEB, 0xFE };
                std.mem.writeInt(i32, program[7..11], @intCast(@as(i64, @intCast(iat)) - @as(i64, @intCast(code + 11))), .little);
                if (tail) {
                    program[5] = 0xE8;
                    std.mem.writeInt(i32, program[6..10], 0x100 - 10, .little);
                    program[10] = 0x90;
                    var thunk = [_]u8{ 0xFF, 0x25, 0, 0, 0, 0 };
                    std.mem.writeInt(i32, thunk[2..6], @intCast(@as(i64, @intCast(iat)) - @as(i64, @intCast(code + 0x106))), .little);
                    @memcpy(state.guestMemory(code + 0x100, thunk.len).?, &thunk);
                }
                @memcpy(state.guestMemory(code, program.len).?, &program);
                state.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = 0x106 }});
                state.regs = .{ .rip = code, .rsp = base + 0x40000, .rbx = iterations, .rax = @bitCast(@as(f64, 3)), .rflags = 2 };
                state.block_jit_enabled = true;
                const started = I._monotonicNanoseconds();
                var steps: u64 = 0;
                while (state.regs.rip != code + 16 and !state.terminated and steps < iterations * 20) : (steps += 1) _ = state.step();
                const elapsed = I._monotonicNanoseconds() - started;
                try testing.expectEqual(code + 16, state.regs.rip);
                try testing.expectEqual(@as(u64, 0), state.regs.rbx);
                try testing.expectEqual(base + 0x40000, state.regs.rsp);
                try testing.expectEqual(@as(f64, 8), @as(f64, @bitCast(std.mem.readInt(u64, state.xmm[0][0..8], .little))));
                try testing.expectEqual(if (enabled) iterations else 0, state.windows_fast_math.total());
                try testing.expect(state.block_jit != null);
                if (bench) std.debug.print("MATH_BENCH pair={d} tail={} enabled={} iterations={d} elapsed_ns={d} steps={d} fast_calls={d}\n", .{ pair, tail, enabled, iterations, elapsed, steps, state.windows_fast_math.total() });
            }
        }
    }
}

test "fast math parallel production imports preserve independent calling contexts (ROSETTE_MATH_BENCH=1)" {
    const bench = std.c.getenv("ROSETTE_MATH_BENCH") != null;
    const pairs: usize = if (bench) 7 else 1;
    const iterations: u64 = if (bench) 25_000 else 32;
    const Runner = struct {
        state: *ElfState,
        iterations: u64,
        context: I._WindowsGuestThreadContext = .{},
        ready: *std.atomic.Value(u32),
        go: *std.atomic.Value(bool),
        failed: bool = false,

        fn run(self: *@This()) void {
            const old_binding = I._windows_guest_execution_binding().*;
            I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(self.state), .context = &self.context };
            defer I._windows_guest_execution_binding().* = old_binding;
            const saved = fp.read();
            defer fp.write(saved);
            fp.applyGuestMxcsr(0x9FC0);
            _ = self.ready.fetchAdd(1, .release);
            while (!self.go.load(.acquire)) std.atomic.spinLoopHint();
            var index: u64 = 0;
            while (index < self.iterations) : (index += 1) {
                const input: f64 = @as(f64, @floatFromInt(index & 7)) - 3;
                std.mem.writeInt(u64, self.context.xmm[0][0..8], @bitCast(input), .little);
                if (!runtime.tryWindowsFunction(self.state, dll, "exp2", base + 0x1200) or
                    self.context.regs.rip != base + 0x1200 or
                    std.mem.readInt(u64, self.context.xmm[0][0..8], .little) != @as(u64, @bitCast(std.math.exp2(input))))
                    self.failed = true;
            }
        }
    };
    for (0..pairs) |pair| {
        for (0..2) |order| {
            const enabled = (pair + order) % 2 == 1;
            const state = try stateForTest();
            defer destroy(state);
            state.windows_fast_math.enabled = enabled;
            seed(state, @bitCast(@as(f64, 7)));
            var ready: std.atomic.Value(u32) = .init(0);
            var go: std.atomic.Value(bool) = .init(false);
            var runners: [4]Runner = undefined;
            var threads: [4]std.Thread = undefined;
            for (&runners, 0..) |*runner, n| {
                runner.* = .{ .state = state, .iterations = iterations, .ready = &ready, .go = &go };
                runner.context.regs.rbx = n + 1;
                threads[n] = try std.Thread.spawn(.{}, Runner.run, .{runner});
            }
            while (ready.load(.acquire) != 4) std.atomic.spinLoopHint();
            const started = I._monotonicNanoseconds();
            go.store(true, .release);
            for (threads) |thread| thread.join();
            const elapsed = I._monotonicNanoseconds() - started;
            for (runners, 0..) |runner, n| {
                try testing.expect(!runner.failed);
                try testing.expectEqual(@as(u64, n + 1), runner.context.regs.rbx);
            }
            try testing.expectEqual(if (enabled) iterations * 4 else 0, state.windows_fast_math.total());
            try testing.expectEqual(@as(u64, @bitCast(@as(f64, 7))), std.mem.readInt(u64, state.xmm[0][0..8], .little));
            if (bench) std.debug.print("MATH_PARALLEL pair={d} enabled={} threads=4 iterations={d} elapsed_ns={d} fast_calls={d}\n", .{ pair, enabled, iterations * 4, elapsed, state.windows_fast_math.total() });
        }
    }
}
