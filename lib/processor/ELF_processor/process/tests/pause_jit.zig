//! CPU-only production PAUSE traces; exact scheduling boundaries and real
//! instruction bytes, with the block translator enabled in both variants.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const t = std.testing;
const base = I._MEM_BASE;
const code = base + 0x1000;
const ElfState = process.ElfState;

fn create(enabled: bool, bundle: usize) !*ElfState {
    const s = try t.allocator.create(ElfState);
    s.* = ElfState.init(t.allocator);
    s.parallel_guest_execution = true;
    // The normal launcher keeps this flag ON after its bounded trace closes.
    s.trace_windows_memory = true;
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    s.guest_clock.source = .host_monotonic;
    s.windows_idle_yield.pause_translated_enabled = enabled;
    s.windows_active_guest_thread_slot = 3;
    s.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
    s.image_low = base;
    s.image_high = base + s.mem.len;
    for (0..bundle) |i| {
        s.write8(code + i * 2, 0xF3);
        s.write8(code + i * 2 + 1, 0x90);
    }
    // dec rcx; jne loop; jmp self (end sentinel).
    const tail = [_]u8{ 0x48, 0xFF, 0xC9, 0x75, @bitCast(-@as(i8, @intCast(bundle * 2 + 5))), 0xEB, 0xFE };
    @memcpy(s.guestMemory(code + bundle * 2, tail.len).?, &tail);
    s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = bundle * 2 + tail.len }});
    return s;
}
fn destroy(s: *ElfState) void {
    s.setParallelGuestExecution(false);
    s.deinit();
    t.allocator.destroy(s);
}
fn seed(s: *ElfState, loops: u64, hints: u64) void {
    s.regs = .{ .rip = code, .rsp = base + 0x40000, .rcx = loops, .rbx = 0xDEADBEEF, .r12 = 0x12345678, .rflags = 0x246 };
    s.windows_guest_threads[3].pause_hints = hints;
    s.windows_guest_slice_yield_requested = false;
    s.windows_slice_pause_yield = false;
}
const Result = struct { steps: u64 = 0, retired: u64 = 0, yields: u64 = 0, elapsed_ns: u64 = 0 };
fn run(s: *ElfState, bundle: usize, loops: u64, host_yield: bool) !Result {
    var r: Result = .{};
    const started = I._monotonicNanoseconds();
    while (s.regs.rcx != 0 and r.steps < loops * (bundle + 5) + 100) {
        try t.expect(s.step());
        r.retired += s.step_retired;
        r.steps += 1;
        if (s.windows_guest_slice_yield_requested) {
            r.yields += 1;
            if (host_yield) std.Thread.yield() catch {};
        }
        s.windows_guest_slice_yield_requested = false;
        s.windows_slice_pause_yield = false;
    }
    r.elapsed_ns = I._monotonicNanoseconds() - started;
    try t.expectEqual(@as(u64, 0), s.regs.rcx);
    try t.expectEqual(@as(u64, 0xDEADBEEF), s.regs.rbx);
    try t.expectEqual(@as(u64, 0x12345678), s.regs.r12);
    try t.expectEqual(base + 0x40000, s.regs.rsp);
    return r;
}

test "translated PAUSE keeps exact first and 256-hint yield boundaries and flags" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    for ([_]u64{ 0, 1, 254, 256, std.math.maxInt(u64) - 2 }) |start| {
        const s = try create(true, 8);
        defer destroy(s);
        seed(s, 32, 1);
        _ = try run(s, 8, 32, false); // populate real caches
        seed(s, 1, start);
        try t.expect(s.step());
        const boundary: u64 = if (start >= std.math.maxInt(u64) - 2) std.math.maxInt(u64) else if (start == 0) 1 else ((start + 255) / 256) * 256 + 1;
        if (boundary - start <= 8) {
            try t.expectEqual(boundary, s.windows_guest_threads[3].pause_hints);
            try t.expectEqual(code + (boundary - start) * 2, s.regs.rip);
            try t.expect(s.windows_guest_slice_yield_requested);
            try t.expectEqual(@as(u64, 0x246), s.regs.rflags);
            try t.expectEqual(s.regs.rip - 2, s.last_instruction_rip);
        } else {
            try t.expectEqual(start + 8, s.windows_guest_threads[3].pause_hints);
            try t.expect(!s.windows_guest_slice_yield_requested);
        }
        try t.expect(s.windows_guest_threads[3].parallel_block_jit.?.pause_helper_calls > 0);
    }
}

test "translated PAUSE and ordinary scheduling produce identical registers counts and yields" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    for ([_]usize{ 1, 8 }) |bundle| {
        var before: ?I._ElfRegs = null;
        var expected: ?Result = null;
        for ([_]bool{ false, true }) |enabled| {
            const s = try create(enabled, bundle);
            defer destroy(s);
            seed(s, 1024, 0);
            const r = try run(s, bundle, 1024, false);
            try t.expectEqual(@as(u64, 1024 * bundle), s.windows_guest_threads[3].pause_hints);
            if (before) |regs| {
                try t.expectEqualDeep(regs, s.regs);
                try t.expectEqual(expected.?.yields, r.yields);
                try t.expectEqual(expected.?.retired, r.retired);
            } else {
                before = s.regs;
                expected = r;
            }
        }
    }
}

test "translated PAUSE admission retains cooperative traced and instruction-clock steps" {
    const s = try create(true, 8);
    defer destroy(s);
    const admission = @import("../impl/pause_jit.zig");
    const d = I._decodeInsn(&.{ 0xF3, 0x90 });
    try t.expect(admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    try t.expect(!admission.canCompile(s, d, &.{ 0x66, 0x90 }));
    s.parallel_guest_execution = false;
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    s.parallel_guest_execution = true;
    s.windows_active_guest_thread_slot = null;
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    s.windows_active_guest_thread_slot = 3;
    s.guest_clock.source = .retired_instructions;
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    s.guest_clock.source = .host_monotonic;
    s.block_jit_verify_memory = true;
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    s.block_jit_verify_memory = false;
    s.trace_rip_start = code;
    s.trace_rip_end = code + 100;
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
}

test "translated PAUSE source revalidation sees a replaced hint and preserves spin captures" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const s = try create(true, 1);
    defer destroy(s);
    seed(s, 128, 1);
    _ = try run(s, 1, 128, false);
    // Production image write increments generation. The former hint is
    // now INC EAX; stale translated PAUSE must never count it as a hint.
    s.write8(code, 0xFF);
    s.write8(code + 1, 0xC0);
    seed(s, 1, 1);
    try t.expect(s.step());
    try t.expectEqual(@as(u64, 1), s.windows_guest_threads[3].pause_hints);
    try t.expectEqual(@as(u64, 1), s.regs.rax);

    const fresh = try create(true, 1);
    defer destroy(fresh);
    const program = [_]u8{ 0xF3, 0x90, 0x8A, 0x07, 0xEB, 0xFA }; // PAUSE; mov al,[rdi]; loop
    for (program, 0..) |b, n| fresh.write8(code + n, b);
    fresh.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = program.len }});
    fresh.regs = .{ .rip = code, .rsp = base + 0x40000, .rdi = base + 0x20000, .rflags = 0x246 };
    fresh.write8(base + 0x20000, 0x5A);
    for (0..40) |_| {
        fresh.windows_guest_slice_yield_requested = false;
        fresh.windows_slice_pause_yield = false;
        try t.expect(fresh.step());
    }
    fresh.windows_runtime_enabled = true;
    fresh.frame_cost.swaps = 1;
    fresh.windows_guest_threads[3].pause_hints = 256;
    const spin = &fresh.windows_guest_threads[3].spin;
    spin.seen_swaps = 1;
    spin.seen_swaps_ns = I._monotonicNanoseconds() - 7_000_000_000;
    spin.pauses_since_swap = 65536 - 256;
    spin.last_assist_ns = I._monotonicNanoseconds(); // this check dispatches no assist
    fresh.regs.rip = code;
    fresh.windows_guest_slice_yield_requested = false;
    try t.expect(fresh.step());
    try t.expectEqual(@as(u32, 512), spin.capture_remaining);
    try t.expectEqual(code, spin.trigger_rip);
    try t.expectEqual(@as(u64, 0x246), fresh.regs.rflags);
    try t.expectEqual(code + 2, fresh.regs.rip);
    try t.expectEqual(@as(u32, 1), fresh.spin_capture_threads.load(.acquire));
    const helpers = fresh.windows_guest_threads[3].parallel_block_jit.?.pause_helper_calls;
    fresh.windows_guest_slice_yield_requested = false;
    try t.expect(fresh.step());
    try t.expectEqual(helpers, fresh.windows_guest_threads[3].parallel_block_jit.?.pause_helper_calls);
    try t.expect(spin.capture_len > 0);
    try t.expectEqual(base + 0x20000, spin.capture[0].address);
    try t.expectEqual(@as(u64, 0x5A), spin.capture[0].last);
}

test "translated PAUSE alternating production benchmark (ROSETTE_PAUSE_BENCH=1)" {
    if (std.c.getenv("ROSETTE_PAUSE_BENCH") == null) return error.SkipZigTest;
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    for (0..7) |pair| for ([_]usize{ 1, 8 }) |bundle| for ([_]bool{ false, true }) |host_yield| for (0..2) |order| {
        const enabled = (pair + order) % 2 != 0;
        const s = try create(enabled, bundle);
        defer destroy(s);
        seed(s, 2048, 0);
        _ = try run(s, bundle, 2048, false);
        seed(s, 100000, 0);
        const r = try run(s, bundle, 100000, host_yield);
        try t.expectEqual(@as(u64, 100000 * bundle), s.windows_guest_threads[3].pause_hints);
        try t.expectEqual(@as(u64, (100000 * bundle + 255) / 256), r.yields);
        std.debug.print("pause_trace pair={d} bundle={d} host_yield={} enabled={} hints={d} retired={d} steps={d} yields={d} elapsed_ns={d}\n", .{ pair, bundle, host_yield, enabled, s.windows_guest_threads[3].pause_hints, r.retired, r.steps, r.yields, r.elapsed_ns });
    };
}

test "translated PAUSE publishes the bound worker context and backoff excludes pending TSO stores" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const s = try create(true, 8);
    defer destroy(s);
    seed(s, 64, 0);
    _ = try run(s, 8, 64, false);
    var context: I._WindowsGuestThreadContext = .{};
    context.windows_active_guest_thread_slot = 3;
    context.regs = .{ .rip = code, .rsp = base + 0x30000, .rax = 0x1234, .rcx = 1, .rflags = 0x246 };
    const owner = s.regs;
    const old = I._windows_guest_execution_binding().*;
    I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(s), .context = &context };
    defer I._windows_guest_execution_binding().* = old;
    s.windows_guest_threads[3].pause_hints = 256;
    try t.expect(s.step());
    try t.expect(context.windows_guest_slice_yield_requested);
    try t.expectEqual(code + 2, context.regs.rip);
    try t.expectEqual(@as(u64, 0x1234), context.regs.rax);
    try t.expectEqual(@as(u64, 0x246), context.regs.rflags);
    try t.expectEqualDeep(owner, s.regs);
    const policy = @import("../impl/pause_jit.zig");
    s.windows_runtime_enabled = true;
    s.parallel_direct_tlb = false;
    try t.expect(policy.canBackoff(s, false));
    try t.expect(!policy.canBackoff(s, true));
    const stores = s.activeGuestTsoStoreBuffer().?;
    var bytes: [8]u8 = @splat(0);
    stores.enqueue(@intFromPtr(&bytes), &.{ 0x34, 0x12 });
    try t.expect(!policy.canBackoff(s, false));
    try t.expectEqual(@as(u8, 0), bytes[0]);
    _ = stores.drain();
    try t.expect(policy.canBackoff(s, false));
    try t.expectEqual(@as(u8, 0x34), bytes[0]);
    s.diagnose_abi = true;
    try t.expect(!policy.canBackoff(s, false));
}

test "translated PAUSE admission follows bounded trace liveness without disabling diagnostics" {
    const s = try create(true, 1);
    defer destroy(s);
    const admission = @import("../impl/pause_jit.zig");
    const d = I._decodeInsn(&.{ 0xF3, 0x90 });
    s.windows_memory_trace_step_closed.store(false, .monotonic);
    s.windows_memory_trace_events.store(0, .monotonic);
    try t.expect(s.windowsMemoryTraceLive());
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    try t.expect(!admission.canBackoff(s, false));
    s.windows_memory_trace_events.store(ElfState.__StateInternals._windows_memory_trace_budget, .monotonic);
    try t.expect(!s.windowsMemoryTraceLive());
    try t.expect(admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    try t.expect(admission.canBackoff(s, false));
    try t.expect(!admission.canBackoff(s, true));
    s.block_jit_verify_memory = true;
    try t.expect(!admission.canBackoff(s, false));
    s.block_jit_verify_memory = false;
    s.windows_memory_trace_events.store(0, .monotonic);
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    try t.expect(admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    try t.expect(admission.canBackoff(s, false));
    s.diagnose_abi = true;
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    try t.expect(!admission.canBackoff(s, false));
    s.diagnose_abi = false;
    s.trace_ring_enabled = true;
    try t.expect(!admission.canCompile(s, d, &.{ 0xF3, 0x90 }));
    try t.expect(!admission.canBackoff(s, false));
    try t.expect(s.trace_windows_memory);
}
