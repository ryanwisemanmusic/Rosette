//! Actual translated tail thunks, with the underlying fast adapters ON in
//! both variants. Compare only the fused transfer, never disabling the JIT.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const t = std.testing;
const base = I._MEM_BASE;
const code = base + 0x1000;
fn create(enabled: bool, name: []const u8) !*process.ElfState {
    const s = try t.allocator.create(process.ElfState);
    s.* = process.ElfState.init(t.allocator);
    s.windows_runtime_enabled = true;
    s.guest_clock.source = .host_monotonic;
    s.setParallelGuestExecution(true);
    s.windows_active_guest_thread_slot = 3;
    s.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
    s.windows_register_imports.enabled = enabled;
    s.trace_windows_memory = true;
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    s.image_low = base;
    s.image_high = code + 0x106; // proc-address stubs are outside the PE image, as in Xenia
    const dll: []const u8 = if (std.mem.eql(u8, name, "exp2")) "api-ms-win-crt-math-l1-1-0.dll" else "ntdll.dll";
    const target = s.registerWindowsImportStub(dll, name).?;
    // vmovq xmm0,r13; call thunk; dec rbx; jne loop; jmp self.
    var program = [_]u8{ 0xC4, 0xC1, 0xF9, 0x6E, 0xC5, 0xE8, 0, 0, 0, 0, 0x48, 0xFF, 0xCB, 0x75, 0xF1, 0xEB, 0xFE };
    std.mem.writeInt(i32, program[6..10], 0x100 - 10, .little);
    @memcpy(s.guestMemory(code, program.len).?, &program);
    @memcpy(s.guestMemory(code + 0x100, 3).?, &[_]u8{ 0x41, 0xFF, 0xE4 });
    s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = 0x106 }});
    s.regs.r12 = target;
    return s;
}
fn destroy(s: *process.ElfState) void {
    s.setParallelGuestExecution(false);
    s.deinit();
    t.allocator.destroy(s);
}
fn seed(s: *process.ElfState, calls: u64) void {
    const target = s.regs.r12;
    s.regs = .{ .rip = code, .rsp = base + 0x40000, .r12 = target, .rbx = calls, .rcx = 0, .rdx = base + 0x800, .rflags = 0x246, .r15 = 0x1234, .r13 = @bitCast(@as(f64, 3)) };
    s.write64(base + 0x800, 0);
    s.windows_guest_slice_yield_requested = false;
    s.windows_slice_nt_zero_yield = false;
    s.windows_last_error = 0xBEEF;
    // exp2(exp2(1)) would quickly overflow; its input is reseeded per call.
    std.mem.writeInt(u64, s.xmm[0][0..8], @bitCast(@as(f64, 3)), .little);
}
const Result = struct { ns: u64, steps: u64, yields: u64 };
fn run(s: *process.ElfState, calls: u64, math: bool) !Result {
    var steps: u64 = 0;
    var yields: u64 = 0;
    const began = I._monotonicNanoseconds();
    while (s.regs.rip != code + 15 and steps < calls * 12 + 20) : (steps += 1) {
        try t.expect(s.step());
        if (s.windows_guest_slice_yield_requested) yields += 1;
        s.windows_guest_slice_yield_requested = false;
        s.windows_slice_nt_zero_yield = false;
    }
    const ns = I._monotonicNanoseconds() - began;
    try t.expectEqual(code + 15, s.regs.rip);
    try t.expectEqual(@as(u64, 0), s.regs.rbx);
    try t.expectEqual(base + 0x40000, s.regs.rsp);
    try t.expectEqual(@as(u64, 0x1234), s.regs.r15);
    try t.expectEqual(@as(u64, 0x246), s.regs.rflags);
    try t.expectEqual(code + 10, s.read64(base + 0x40000 - 8));
    try t.expectEqual(if (math) @as(u32, 0) else @as(u32, 0xBEEF), s.windows_last_error);
    if (math) try t.expectEqual(@as(f64, 8), @as(f64, @bitCast(std.mem.readInt(u64, s.xmm[0][0..8], .little)))) else try t.expectEqual(calls, yields);
    return .{ .ns = ns, .steps = steps, .yields = yields };
}
test "registered import tail translated NT and math thunks preserve results and measure dispatch" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const bench = std.c.getenv("ROSETTE_REGISTER_IMPORT_BENCH") != null;
    const calls: u64 = if (bench) 100000 else 32;
    for (0..if (bench) @as(usize, 7) else 1) |pair| for ([_][]const u8{ "NtDelayExecution", "exp2" }) |name| for (0..2) |order| {
        const enabled = (pair + order) % 2 != 0;
        const s = try create(enabled, name);
        defer destroy(s);
        seed(s, 64);
        const math = std.mem.eql(u8, name, "exp2");
        _ = try run(s, 64, math);
        try t.expectEqual(@as(u64, 64), if (math) s.windows_fast_math.total() else s.windows_fast_nt_yield.total());
        seed(s, calls);
        const before = @import("../impl/register_import.zig").total(s);
        const locks = s.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic);
        const count = if (math) s.windows_fast_math.total() else s.windows_fast_nt_yield.total();
        const r = try run(s, calls, math);
        try t.expectEqual(calls, (if (math) s.windows_fast_math.total() else s.windows_fast_nt_yield.total()) - count);
        const fused = @import("../impl/register_import.zig").total(s) - before;
        try t.expectEqual(if (enabled) calls else 0, fused);
        try t.expectEqual(locks, s.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));
        try t.expect(s.windows_guest_threads[3].parallel_block_jit.?.instructions_retired > 0);
        if (bench) std.debug.print("register_tail pair={d} name={s} enabled={} calls={d} elapsed_ns={d} steps={d} yields={d} fused={d}\n", .{ pair, name, enabled, calls, r.ns, r.steps, r.yields, fused });
    };
}
test "registered import tail declines interior targets diagnostics hooks and rebound static imports" {
    const s = try create(true, "NtDelayExecution");
    defer destroy(s);
    seed(s, 1);
    s.regs.rip = code + 0x100;
    s.regs.rsp -= 8;
    s.write64(s.regs.rsp, code + 5);
    const insn: I._block_jit.Insn = .{ .rip = code + 0x100, .len = 3, .segment = .ds, .registered_import_tail = true, .decoded = I._decodeInsn(&.{ 0x41, 0xFF, 0xE4 }) };
    const adapter = @import("../impl/register_import.zig");
    const target = s.regs.r12;
    s.regs.r12 += 1;
    const regs = s.regs;
    try t.expect(!adapter.tryExecute(s, &insn));
    try t.expectEqualDeep(regs, s.regs);
    s.regs.r12 = target;
    s.trace_windows_threads = true;
    @import("../impl/block_jit.zig").refreshBlockJitTransferTraced(s);
    @import("../impl/guest_diagnostics.zig").refreshBlockJitGuards(s, &s.block_jit_scratch);
    try t.expect(!adapter.tryExecute(s, &insn));
    s.trace_windows_threads = false;
    @import("../impl/block_jit.zig").refreshBlockJitTransferTraced(s);
    @import("../impl/guest_diagnostics.zig").refreshBlockJitGuards(s, &s.block_jit_scratch);
    s.windows_memory_trace_step_closed.store(false, .monotonic);
    try t.expect(!adapter.tryExecute(s, &insn));
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    s.diagnose_abi = true;
    try t.expect(!adapter.tryExecute(s, &insn));
    s.diagnose_abi = false;
    s.block_jit_verify_memory = true;
    try t.expect(!adapter.tryExecute(s, &insn));
    s.block_jit_verify_memory = false;
    s.guest_clock.source = .retired_instructions;
    try t.expect(!adapter.tryExecute(s, &insn));
    s.guest_clock.source = .host_monotonic;
    try t.expect(s.call_probes.add(target, "retained probe"));
    try t.expect(!adapter.tryExecute(s, &insn));
    s.call_probes = .{};
    var ordinary_call = insn;
    ordinary_call.decoded = I._decodeInsn(&.{ 0x41, 0xFF, 0xD4 });
    try t.expect(!adapter.tryExecute(s, &ordinary_call));
    // A dynamic stub registered as a static IAT import must retain its live binding.
    s.windows_stub_storage[s.windows_stub_count - 1].iat_address = base + 0x900;
    s.windows_dynamic_stub_start = s.windows_stub_count;
    s.windows_direct_stub_count = s.windows_stub_count;
    s.windows_direct_stub_base = target;
    s.write64(base + 0x900, target + 16);
    try t.expect(!adapter.tryExecute(s, &insn));
    s.write64(base + 0x900, target);
    try t.expect(adapter.tryExecute(s, &insn));
    try t.expectEqual(code + 5, s.regs.rip);
    try t.expectEqual(base + 0x40000, s.regs.rsp);
    try t.expect(s.windows_slice_nt_zero_yield);
}

test "registered import tail retains bound worker state and exact queued-store boundary" {
    const s = try create(true, "NtDelayExecution");
    defer destroy(s);
    seed(s, 1);
    var context: I._WindowsGuestThreadContext = .{};
    context.windows_active_guest_thread_slot = 3;
    context.regs = s.regs;
    context.regs.rip = code + 0x100;
    context.regs.rsp = base + 0x35000;
    context.regs.rax = 0xCAFE;
    context.windows_last_error = 0xF00D;
    s.write64(context.regs.rsp, code + 10);
    const owner_regs = s.regs;
    const old = I._windows_guest_execution_binding().*;
    I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(s), .context = &context };
    defer I._windows_guest_execution_binding().* = old;
    var stores: I._tso_memory.StoreBuffer = .{};
    const old_buffer = I._tso_memory.setActiveStoreBuffer(&stores);
    defer _ = I._tso_memory.setActiveStoreBuffer(old_buffer);
    var bytes = [_]u8{0} ** 8;
    I._tso_memory.store(u64, &bytes, 0x12345678);
    try t.expectEqual(@as(usize, 1), stores.pendingCount());
    const insn: I._block_jit.Insn = .{ .rip = code + 0x100, .len = 3, .segment = .ds, .registered_import_tail = true, .decoded = I._decodeInsn(&.{ 0x41, 0xFF, 0xE4 }) };
    try t.expect(@import("../impl/register_import.zig").tryExecute(s, &insn));
    try t.expectEqualDeep(owner_regs, s.regs);
    try t.expectEqual(code + 10, context.regs.rip);
    try t.expectEqual(base + 0x35008, context.regs.rsp);
    try t.expectEqual(@as(u64, 0), context.regs.rax);
    try t.expectEqual(@as(u64, 0x246), context.regs.rflags);
    try t.expectEqual(@as(u32, 0xF00D), context.windows_last_error);
    try t.expect(context.windows_slice_nt_zero_yield);
    try t.expect(!s.windows_slice_nt_zero_yield);
    try t.expectEqual(@as(usize, 0), stores.pendingCount());
    try t.expectEqual(@as(u64, 0x12345678), std.mem.readInt(u64, &bytes, .little));
}

test "registered import tail memory-verification profile keeps the ordinary transfer and one callback" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const s = try create(true, "NtDelayExecution");
    defer destroy(s);
    s.block_jit_verify_memory = true;
    seed(s, 64);
    _ = try run(s, 64, false);
    try t.expectEqual(@as(u64, 64), s.windows_fast_nt_yield.total());
    try t.expectEqual(@as(u64, 0), @import("../impl/register_import.zig").total(s));
    try t.expectEqual(@as(u64, 0), s.windows_guest_threads[3].parallel_block_jit.?.mismatches);
}

test "registered import tail four bound production workers preserve shared registry and private counters" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const bench = std.c.getenv("ROSETTE_REGISTER_IMPORT_BENCH") != null;
    const calls: u64 = if (bench) 25000 else 32;
    const Runner = struct {
        state: *process.ElfState,
        context: I._WindowsGuestThreadContext = .{},
        ready: *std.atomic.Value(u32),
        go: *std.atomic.Value(bool),
        calls: u64,
        cpu_ns: u64 = 0,
        warm_fused: u64 = 0,
        failed: bool = false,
        fn cpu() u64 {
            var time: std.c.timespec = undefined;
            std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
            return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
        }
        fn execute(self: *@This(), n: u64) bool {
            self.context.regs.rip = code;
            self.context.regs.rbx = n;
            self.context.regs.rflags = 0x246;
            var steps: u64 = 0;
            var yields: u64 = 0;
            while (self.context.regs.rip != code + 15 and steps < n * 12 + 20) : (steps += 1) {
                if (!self.state.step()) return false;
                if (self.context.windows_guest_slice_yield_requested) {
                    yields += 1;
                    std.Thread.yield() catch {};
                }
                self.context.windows_guest_slice_yield_requested = false;
                self.context.windows_slice_nt_zero_yield = false;
            }
            const regs = self.context.regs;
            const slot = self.context.windows_active_guest_thread_slot.?;
            return regs.rip == code + 15 and regs.rbx == 0 and regs.rax == 0 and
                regs.rsp == base + 0x40000 + slot * 0x1000 and regs.rflags == 0x246 and
                regs.r15 == slot and yields == n and self.context.windows_last_error == 0xF00D;
        }
        fn run(self: *@This()) void {
            const old = I._windows_guest_execution_binding().*;
            I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(self.state), .context = &self.context };
            defer I._windows_guest_execution_binding().* = old;
            if (!self.execute(64)) self.failed = true;
            const active = self.state.windows_guest_threads[self.context.windows_active_guest_thread_slot.?].parallel_block_jit.?;
            self.warm_fused = @atomicLoad(u64, &active.register_import_tail_calls, .monotonic);
            _ = self.ready.fetchAdd(1, .release);
            while (!self.go.load(.acquire)) std.Thread.yield() catch {};
            const stamp = cpu();
            if (!self.execute(self.calls)) self.failed = true;
            self.cpu_ns = cpu() - stamp;
        }
    };
    for (0..if (bench) @as(usize, 7) else 1) |pair| for (0..2) |order| {
        const enabled = (pair + order) % 2 != 0;
        const s = try create(enabled, "NtDelayExecution");
        defer destroy(s);
        seed(s, 1);
        const owner = s.regs;
        var ready: std.atomic.Value(u32) = .init(0);
        var go: std.atomic.Value(bool) = .init(false);
        var runners: [4]Runner = undefined;
        var threads: [4]std.Thread = undefined;
        var started: usize = 0;
        errdefer {
            go.store(true, .release);
            for (threads[0..started]) |thread| thread.join();
        }
        for (&runners, 0..) |*r, i| {
            const slot = i + 4;
            s.windows_guest_threads[slot] = .{ .status = .running, .thread_id = @intCast(slot + 43) };
            r.* = .{ .state = s, .ready = &ready, .go = &go, .calls = calls };
            r.context.windows_active_guest_thread_slot = slot;
            r.context.regs = s.regs;
            r.context.regs.rsp = base + 0x40000 + slot * 0x1000;
            r.context.regs.r15 = slot;
            r.context.windows_last_error = 0xF00D;
            threads[i] = try std.Thread.spawn(.{}, Runner.run, .{r});
            started += 1;
        }
        const deadline = I._monotonicNanoseconds() + 10_000_000_000;
        while (ready.load(.acquire) != 4) {
            if (I._monotonicNanoseconds() > deadline) return error.WarmupStalled;
            std.Thread.yield() catch {};
        }
        const stamp = I._monotonicNanoseconds();
        go.store(true, .release);
        for (threads) |thread| thread.join();
        started = 0;
        const elapsed = I._monotonicNanoseconds() - stamp;
        var cpu_ns: u64 = 0;
        for (runners) |r| {
            try t.expect(!r.failed);
            cpu_ns += r.cpu_ns;
            const active = s.windows_guest_threads[r.context.windows_active_guest_thread_slot.?].parallel_block_jit.?;
            try t.expectEqual(if (enabled) calls else 0, @atomicLoad(u64, &active.register_import_tail_calls, .monotonic) - r.warm_fused);
        }
        try t.expectEqualDeep(owner, s.regs);
        try t.expectEqual(4 * (calls + 64), s.windows_fast_nt_yield.total());
        try t.expect(cpu_ns <= elapsed * 4 + 5_000_000);
        if (bench) std.debug.print("register_threads pair={d} enabled={} calls={d} cpu_ns={d} elapsed_ns={d} actual_host_yields={d}\n", .{ pair, enabled, calls * 4, cpu_ns, elapsed, calls * 4 });
    };
}

test "registered import tail narrow dispatch matches the full adapter for all four handlers" {
    const s = try create(true, "NtDelayExecution");
    defer destroy(s);
    var random = std.Random.DefaultPrng.init(0x651239);
    for ([_][]const u8{ "NtDelayExecution", "NtYieldExecution", "exp2", "exp2f" }) |name| {
        const dll: []const u8 = if (std.mem.startsWith(u8, name, "exp2")) "UCRTBASE.DLL" else "NTDLL.DLL";
        for (0..256) |_| {
            const input = random.random().int(u64);
            seed(s, 1);
            std.mem.writeInt(u64, s.xmm[0][0..8], input, .little);
            try t.expect(I._x64_linux_runtime.tryWindowsFastFunction(s, dll, name, code + 10));
            const regs = s.regs;
            const xmm = s.xmm;
            const last_error = s.windows_last_error;
            const yielded = s.windows_guest_slice_yield_requested;
            const nt_marker = s.windows_slice_nt_zero_yield;
            seed(s, 1);
            std.mem.writeInt(u64, s.xmm[0][0..8], input, .little);
            try t.expect(I._x64_linux_runtime.tryWindowsFastRegisteredTail(s, dll, name, code + 10));
            try t.expectEqualDeep(regs, s.regs);
            try t.expectEqualDeep(xmm, s.xmm);
            try t.expectEqual(last_error, s.windows_last_error);
            try t.expectEqual(yielded, s.windows_guest_slice_yield_requested);
            try t.expectEqual(nt_marker, s.windows_slice_nt_zero_yield);
        }
        seed(s, 1);
        try t.expect(!I._x64_linux_runtime.tryWindowsFastRegisteredTail(s, "unclaimed.dll", name, code + 10));
    }
    seed(s, 1);
    try t.expect(!I._x64_linux_runtime.tryWindowsFastRegisteredTail(s, "ntdll.dll", "NtSetEvent", code + 10));
}
