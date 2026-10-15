//! Real process execution: failed CAS retries retain JIT and memory guards.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const t = std.testing;
const admission = @import("../impl/atomic_admission.zig");
const impl = @import("../impl/block_jit.zig");
const base = I._MEM_BASE;
const code = base + 0x1000;
const data = base + 0x10000;
const program = [_]u8{ 0x31, 0xC0, 0xF0, 0x0F, 0xB1, 0x0B, 0x49, 0xFF, 0xCC, 0x75, 0xF5, 0xEB, 0xFE };
fn create() !*process.ElfState {
    const s = try t.allocator.create(process.ElfState);
    s.* = process.ElfState.initWithMemory(t.allocator, 0x80000);
    s.image_low = base;
    s.image_high = base + s.mem.len;
    @memcpy(s.guestMemory(code, program.len).?, &program);
    s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = program.len }});
    s.write32(data, 1);
    seed(s, 64);
    _ = try run(s, 64);
    try t.expect(s.currentBlockJit() != null);
    return s;
}
fn destroy(s: *process.ElfState) void {
    s.deinit();
    t.allocator.destroy(s);
}
fn seed(s: *process.ElfState, n: u64) void {
    s.regs = .{ .rip = code, .rbx = data, .rcx = 77, .r12 = n, .rsp = base + 0x40000, .rflags = 0x246 };
}
const Result = struct { cpu_ns: u64, elapsed_ns: u64, retired: u64, fallback: u64, steps: u64 };
fn run(s: *process.ElfState, n: u64) !Result {
    const cpu = @import("../impl/worker_cpu.zig").current().?;
    const start = I._monotonicNanoseconds();
    const falls = if (s.currentBlockJit()) |active| active.fallback_calls else 0;
    var steps: u64 = 0;
    var retired: u64 = 0;
    while (s.regs.r12 != 0 and steps < n * 6 + 100) : (steps += 1) {
        try t.expect(s.step());
        retired += s.step_retired;
    }
    const elapsed = I._monotonicNanoseconds() - start;
    const elapsed_cpu = @import("../impl/worker_cpu.zig").current().? - cpu;
    try t.expectEqual(@as(u64, 0), s.regs.r12);
    try t.expectEqual(@as(u32, 1), s.read32(data));
    try t.expectEqual(@as(u64, 1), s.regs.rax);
    try t.expectEqual(@as(u64, 77), s.regs.rcx);
    try t.expectEqual(@as(u64, 0x247), s.regs.rflags);
    return .{ .cpu_ns = elapsed_cpu, .elapsed_ns = elapsed, .retired = retired, .steps = steps, .fallback = s.currentBlockJit().?.fallback_calls - falls };
}

test "atomic failed compare admits writable page once and avoids repeated interpreter exits" {
    const bench = std.c.getenv("ROSETTE_ATOMIC_BENCH") != null;
    const count: u64 = if (bench) 100000 else 100;
    for (0..if (bench) @as(usize, 7) else 1) |pair| {
        const order = if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false };
        for (order) |enabled| {
            const s = try create();
            defer destroy(s);
            const active = s.currentBlockJit().?;
            active.admit_failed_compare = enabled;
            s.activeBlockJitTlb().flush(true, true);
            seed(s, count);
            const r = try run(s, count);
            try t.expectEqual(count * 4 + 1, r.retired);
            try t.expectEqual(if (enabled) @as(u64, 1) else count, r.fallback);
            if (bench) std.debug.print("atomic_admission pair={d} enabled={} operations={d} retired={d} fallbacks={d} cpu_ns={d} elapsed_ns={d} steps={d}\n", .{ pair, enabled, count, r.retired, r.fallback, r.cpu_ns, r.elapsed_ns, r.steps });
        }
    }
}

test "atomic failed compare writable proof retains protection tracing and executable-code guards" {
    const s = try create();
    defer destroy(s);
    const op: I._Op = .cmpxchg_mem32_reg32;
    s.activeBlockJitTlb().flush(true, true);
    _ = s.guest_page_protection.set(s.allocator, data, 4096, .read_only);
    admission.consider(s, op, data, 4, false);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) == null);
    _ = s.guest_page_protection.set(s.allocator, data, 4096, .accessible);
    s.trace_write_address = data;
    admission.consider(s, op, data, 4, false);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) == null);
    s.trace_write_address = null;
    admission.consider(s, op, code, 4, false);
    try t.expect(s.activeBlockJitTlb().lookup(true, code) == null);
    admission.consider(s, op, data, 4, false);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) != null);
    impl.invalidateAllBlockJitTlbTables(s, data, 4096, false, true);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) == null);
    admission.consider(s, .add_mem32_reg32, data, 4, false);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) == null);
}

test "atomic failed compare proof applies only to the bound worker and ordered TLB" {
    const s = try create();
    defer destroy(s);
    s.setParallelGuestExecution(true);
    defer s.setParallelGuestExecution(false);
    s.parallel_direct_tlb = true;
    var ctx: I._WindowsGuestThreadContext = .{};
    ctx.windows_active_guest_thread_slot = 3;
    s.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
    const old = I._windows_guest_execution_binding().*;
    I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(s), .context = &ctx };
    defer I._windows_guest_execution_binding().* = old;
    _ = s.parallelWorkerBlockJit(3).?;
    const owner = s.block_jit.?.failed_compare_admitted;
    admission.consider(s, .cmpxchg_mem32_reg32, data, 4, false);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) != null);
    try t.expectEqual(owner, s.block_jit.?.failed_compare_admitted);
    try t.expectEqual(@as(u64, 1), s.windows_guest_threads[3].parallel_block_jit.?.failed_compare_admitted);
    impl.invalidateAllBlockJitTlbTables(s, data, 4096, false, true);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) == null);
}

test "atomic failed compare no-access operand never receives a native write translation" {
    const s = try create();
    defer destroy(s);
    s.activeBlockJitTlb().flush(true, true);
    _ = s.guest_page_protection.set(s.allocator, data, 4096, .no_access);
    admission.consider(s, .cmpxchg_mem32_reg32, data, 4, false);
    try t.expect(s.activeBlockJitTlb().lookup(true, data) == null);
    try t.expect(s.currentBlockJit().?.failed_compare_refused > 0);
}
