//! Differential translation and throughput of production atomic templates.
const std = @import("std");
const core = @import("core.zig");
const f = @import("tests.zig");
const t = std.testing;
const Op = core.Op;
const Size = core.Size;
const Reg = core.RegId;
fn memory(op: Op, size: Size) core.DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = .cl_cx_ecx_rcx, .src_reg = .cl_cx_ecx_rcx, .lock = true, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx };
}
const Cases = struct { size: Size, ops: [7]Op };
const cases = [_]Cases{
    .{ .size = .bits8, .ops = .{ .add_mem8_reg8, .sub_mem8_reg8, .and_mem8_reg8, .or_mem8_reg8, .xor_mem8_reg8, .inc_mem8, .dec_mem8 } },
    .{ .size = .bits16, .ops = .{ .add_mem16_reg16, .sub_mem16_reg16, .and_mem16_reg16, .or_mem16_reg16, .xor_mem16_reg16, .inc_mem16, .dec_mem16 } },
    .{ .size = .bits32, .ops = .{ .add_mem32_reg32, .sub_mem32_reg32, .and_mem32_reg32, .or_mem32_reg32, .xor_mem32_reg32, .inc_mem32, .dec_mem32 } },
    .{ .size = .bits64, .ops = .{ .add_mem64_reg64, .sub_mem64_reg64, .and_mem64_reg64, .or_mem64_reg64, .xor_mem64_reg64, .inc_mem64, .dec_mem64 } },
};

test "atomic update single LSE matches CAS results flags and guard bytes for all widths" {
    var random = std.Random.DefaultPrng.init(0xA701);
    for (cases) |c| for (c.ops) |op| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 4, memory(op, c.size));
        for (0..32) |n| {
            var before = try t.allocator.create(f.TestState);
            defer t.allocator.destroy(before);
            before.* = .{};
            before.regs = .{ .rbx = 0x100, .rcx = random.random().int(u64), .rflags = random.random().int(u32) | 2 };
            random.random().bytes(&before.memory);
            // Include exact zero, sign edge and unsigned wraparound values.
            if (n < 8) @memset(before.memory[0x100..][0..8], @as(u8, @intCast(n)) *% 0x40);
            var after = try t.allocator.create(f.TestState);
            defer t.allocator.destroy(after);
            after.* = before.*;
            before.admitMemory(true, true);
            after.admitMemory(true, true);
            const old = try h.runWith(before, .{ .atomic_direct_updates = false });
            const new = try h.runWith(after, .{ .atomic_direct_updates = true });
            try t.expectEqual(old, new);
            try t.expectEqual(before.regs, after.regs);
            try t.expectEqualSlices(u8, &before.memory, &after.memory);
            try t.expectEqual(@as(u32, 0), after.interprets);
        }
    };
}

test "atomic compare fusion matches taken fallthrough and later conditional readers" {
    var random = std.Random.DefaultPrng.init(0xCA517);
    for ([_]Size{ .bits32, .bits64 }) |size| for ([_]core.Cond{ .e, .ne, .b, .be, .l, .ge, .p, .o }) |cond| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 4, memory(if (size == .bits32) .cmpxchg_mem32_reg32 else .cmpxchg_mem64_reg64, size));
        try h.add(0x1004, 2, .{ .op = .setcc_reg8, .size = .bits8, .dst_reg = .dl_dx_edx_rdx, .is_reg_form = true, .cond = cond });
        // Both reader edges exit with every flag live, then test ZF again.
        try h.add(0x1006, 2, .{ .op = .jcc_rel8, .cond = cond, .addr = 32 });
        try h.add(0x1008, 2, .{ .op = .setcc_reg8, .size = .bits8, .dst_reg = .ah_sp_esp_rsp, .is_reg_form = true, .cond = .e });
        for (0..32) |n| {
            var before = try t.allocator.create(f.TestState);
            defer t.allocator.destroy(before);
            before.* = .{};
            before.regs = .{ .rbx = 0x100, .rcx = random.random().int(u64), .rax = random.random().int(u64), .rflags = 0xA57 };
            const value = if (n % 2 == 0) before.regs.rax else random.random().int(u64);
            std.mem.writeInt(u64, before.memory[0x100..][0..8], value, .little);
            var after = try t.allocator.create(f.TestState);
            defer t.allocator.destroy(after);
            after.* = before.*;
            before.admitMemory(true, true);
            after.admitMemory(true, true);
            const old = try h.runWith(before, .{ .atomic_compare_fusion = false });
            const new = try h.runWith(after, .{ .atomic_compare_fusion = true });
            try t.expectEqual(old, new);
            try t.expectEqual(before.regs, after.regs);
            try t.expectEqualSlices(u8, &before.memory, &after.memory);
        }
    };
}

test "atomic compare slow guard exits before fused readers with interpreter flags intact" {
    var h = try f.TestHarness.init();
    defer h.deinit();
    try h.add(0x1000, 4, memory(.cmpxchg_mem32_reg32, .bits32));
    try h.add(0x1004, 2, .{ .op = .jcc_rel8, .cond = .ne, .addr = 32 });
    for ([_]bool{ false, true }) |misaligned| {
        var state = try t.allocator.create(f.TestState);
        defer t.allocator.destroy(state);
        state.* = .{};
        state.regs = .{ .rbx = if (misaligned) 0x101 else 0x100, .rax = 0x77, .rflags = 0xA57 };
        if (misaligned) state.admitMemory(true, true);
        const steps = try h.runWith(state, .{ .atomic_compare_fusion = true });
        try t.expectEqual(@as(u32, 1), steps);
        try t.expectEqual(@as(u32, 1), state.interprets);
        try t.expectEqual(@as(u64, 0x1004), state.regs.rip);
        try t.expectEqual(@as(u32, 0xA57), state.regs.rflags);
        try t.expectEqual(@as(u64, 0x77), state.regs.rax);
    }
}

fn wallTime() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.MONOTONIC, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
fn cpuTime() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
const Actor = struct {
    state: *f.TestState,
    block: *const core.Block,
    go: *std.atomic.Value(bool),
    ready: std.atomic.Value(bool) = .init(false),
    count: u64,
    retired: u64 = 0,
    cpu_ns: u64 = 0,
    fn run(self: *@This()) void {
        self.ready.store(true, .release);
        while (!self.go.load(.acquire)) std.atomic.spinLoopHint();
        const start = cpuTime();
        for (0..self.count) |_| {
            self.state.regs.rcx = 1;
            self.retired += self.block.entry()(self.state, &self.block.helpers, &self.state.scratch);
        }
        self.cpu_ns = cpuTime() - start;
    }
};
fn measured(enabled: bool, threads: usize, count: u64, op: Op) !void {
    var h = try f.TestHarness.init();
    defer h.deinit();
    for (0..4) |n| try h.add(0x1000 + n * 4, 4, memory(op, .bits64));
    try h.add(0x1010, 3, .{ .op = .inc_reg64, .size = .bits64, .dst_reg = .r12b_r12w_r12d_r12, .is_reg_form = true });
    var warm = try t.allocator.create(f.TestState);
    defer t.allocator.destroy(warm);
    warm.* = .{};
    warm.regs.rbx = 0x100;
    warm.admitMemory(true, true);
    _ = try h.runWith(warm, .{ .atomic_direct_updates = enabled });
    var shared: [4096]u8 align(4096) = @splat(0);
    var go: std.atomic.Value(bool) = .init(false);
    var actors: [4]Actor = undefined;
    var handles: [4]std.Thread = undefined;
    for (0..threads) |n| {
        const state = try t.allocator.create(f.TestState);
        state.* = .{};
        state.regs.rbx = 0x100;
        state.tlb.fill(true, 0, &shared);
        state.tlb.fill(false, 0, &shared);
        state.scratch.block = &h.block;
        actors[n] = .{ .state = state, .block = &h.block, .go = &go, .count = count };
        handles[n] = try std.Thread.spawn(.{}, Actor.run, .{&actors[n]});
    }
    for (actors[0..threads]) |*actor| while (!actor.ready.load(.acquire)) std.Thread.yield() catch {};
    const start = wallTime();
    go.store(true, .release);
    for (handles[0..threads]) |handle| handle.join();
    const elapsed: u64 = @intCast(wallTime() - start);
    var cpu: u64 = 0;
    var retired: u64 = 0;
    for (actors[0..threads]) |*actor| {
        cpu += actor.cpu_ns;
        retired += actor.retired;
        try t.expectEqual(count, actor.state.regs.r12);
        try t.expectEqual(@as(u32, 0), actor.state.interprets);
        t.allocator.destroy(actor.state);
    }
    const actual = std.mem.readInt(u64, shared[0x100..][0..8], .little);
    const operations = count * threads * 4;
    try t.expectEqual(if (op == .inc_mem64 or op == .add_mem64_reg64) operations else @as(u64, 0) -% operations, actual);
    std.debug.print("atomic_workers op={s} enabled={} threads={d} operations={d} retired={d} elapsed_ns={d} cpu_ns={d} words={d}\n", .{ @tagName(op), enabled, threads, operations, retired, elapsed, cpu, h.block.code.len });
}

test "atomic update throughput of actual translated shared counter work" {
    if (std.c.getenv("ROSETTE_ATOMIC_BENCH") == null) return error.SkipZigTest;
    for ([_]Op{ .inc_mem64, .add_mem64_reg64, .sub_mem64_reg64 }) |op| for ([_]usize{ 1, 4 }) |threads| for (0..7) |pair| {
        const order = if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false };
        for (order) |enabled| {
            std.debug.print("pair={d} ", .{pair});
            try measured(enabled, threads, 25_000, op);
        }
    };
}

test "atomic compare throughput on translated CAS retry and success paths" {
    if (std.c.getenv("ROSETTE_ATOMIC_BENCH") == null) return error.SkipZigTest;
    for ([_]bool{ false, true }) |success| for (0..7) |pair| {
        const order = if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false };
        for (order) |enabled| {
            var h = try f.TestHarness.init();
            defer h.deinit();
            // XOR EAX,EAX at the retry target kills incoming flags, as in
            // the captured 0x14035ce00 lock path. No guest work is removed.
            try h.add(0x1000, 2, .{ .op = .xor_reg32_reg32, .size = .bits32, .dst_reg = .al_ax_eax_rax, .src_reg = .al_ax_eax_rax, .is_reg_form = true });
            try h.add(0x1002, 4, memory(.cmpxchg_mem32_reg32, .bits32));
            try h.add(0x1006, 2, .{ .op = .jcc_rel8, .cond = .ne, .addr = @bitCast(@as(i64, -8)) });
            try h.add(0x1008, 2, .{ .op = .xor_reg32_reg32, .size = .bits32, .dst_reg = .dl_dx_edx_rdx, .src_reg = .dl_dx_edx_rdx, .is_reg_form = true });
            var state = try t.allocator.create(f.TestState);
            defer t.allocator.destroy(state);
            state.* = .{};
            state.regs = .{ .rbx = 0x100, .rcx = 0 };
            std.mem.writeInt(u32, state.memory[0x100..][0..4], if (success) 0 else 1, .little);
            state.admitMemory(true, true);
            _ = try h.runWith(state, .{ .atomic_compare_fusion = enabled });
            const start = cpuTime();
            var retired: u64 = 0;
            for (0..100_000) |_| retired += h.block.entry()(state, &h.block.helpers, &state.scratch);
            const elapsed = cpuTime() - start;
            try t.expectEqual(@as(u64, 100_000) * @as(u64, if (success) 4 else 3), retired);
            try t.expectEqual(@as(u32, 0), state.interprets);
            std.debug.print("pair={d} atomic_compare enabled={} success={} operations=100000 retired={d} cpu_ns={d} words={d}\n", .{ pair, enabled, success, retired, elapsed, h.block.code.len });
        }
    };
}
