const std = @import("std");
const core = @import("core.zig");
const f = @import("tests.zig");
const ids = [_]core.RegId{
    .bl_bx_ebx_rbx,      .dh_si_esi_rsi,      .bh_di_edi_rdi,      .al_ax_eax_rax,
    .r10b_r10w_r10d_r10, .r11b_r11w_r11d_r11, .r12b_r12w_r12d_r12, .r13b_r13w_r13d_r13,
    .r14b_r14w_r14d_r14,
};
const t = std.testing;

const Graph = struct {
    h: [4]f.TestHarness = undefined,
    slots: [4]?*core.Block = @splat(null),
    generation: [4]u64 = @splat(17),
    count: usize = 0,
    block_insns: [4]usize = @splat(0),
    fn create(enabled: bool, profile: usize, boundary: usize, pointers: bool) !*@This() {
        const g = try t.allocator.create(@This());
        g.* = .{};
        errdefer g.destroy();
        const warm = try allocate();
        defer t.allocator.destroy(warm);
        for (&g.h, 0..) |*h, index| {
            h.* = try f.TestHarness.init();
            g.count += 1;
            var rip: u64 = 0x1000 + index * 0x1000;
            if (profile == 1) {
                // Context load/modify/store, using the ordinary admitted TLB.
                for (0..4) |_| {
                    try h.add(rip, 4, .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .sib_has_base = true, .sib_base_reg = .dh_si_esi_rsi, .addr = 48 });
                    rip += 4;
                    try h.add(rip, 4, .{ .op = .add_reg64_reg64, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .src_reg = .r10b_r10w_r10d_r10 });
                    rip += 4;
                    try h.add(rip, 4, .{ .op = .mov_mem64_reg64, .size = .bits64, .src_reg = .bl_bx_ebx_rbx, .sib_has_base = true, .sib_base_reg = .dh_si_esi_rsi, .addr = 48 });
                    rip += 4;
                }
            } else {
                const registers: usize = if (profile == 2 or profile == 5) 1 else if (profile == 4) 3 else 8;
                for (0..16) |n| {
                    const id: core.RegId = if (profile == 3) @enumFromInt(n % 16) else if (profile == 5) .r15b_r15w_r15d_r15 else ids[(n % registers + (if (profile == 4) index * 2 else 0)) % ids.len];
                    const mixed: core.Op = if (profile == 6 and n % 4 != 3) switch (n % 3) {
                        0 => .shl_reg_imm,
                        1 => .ror_reg_imm,
                        else => .not_reg64,
                    } else .add_reg64_imm32;
                    try h.add(rip, 4, .{ .op = mixed, .size = .bits64, .dst_reg = id, .imm = 1 + index });
                    rip += 4;
                }
            }
            if (boundary == 1 and index == 1) {
                try h.add(rip, 1, .{ .op = .nop });
                h.insns.items[h.insns.items.len - 1].force_fallback = true;
                rip += 1;
            }
            const target: u64 = 0x1000 + ((index + 1) % 4) * 0x1000;
            if (boundary == 3 and index == 0) {
                try h.add(rip, 10, .{ .op = .mov_reg_imm, .size = .bits64, .dst_reg = .r15b_r15w_r15d_r15, .imm = target });
                rip += 10;
                try h.add(rip, 3, .{ .op = .jmp_reg64, .size = .bits64, .src_reg = .r15b_r15w_r15d_r15 });
                rip += 3;
            } else {
                try h.add(rip, 5, .{ .op = .jmp_rel8, .imm = target -% (rip + 5) });
                rip += 5;
            }
            const ledger: core.Ledger = if (boundary == 2 and index == 2) .image else .code_cache;
            // Bind unchanged test helpers, then install this graph's metadata.
            warm.* = .{};
            _ = try h.run(warm);
            var layout = f.TestState.layout;
            if (pointers) layout.register_files = .pointers_in_scratch;
            const c = try core.compileWith(t.allocator, &h.memory, layout, h.insns.items, rip, .{ .ledger = ledger, .first_way_fallthrough = enabled, .direct_scalar_paths = if (profile == 6) enabled else true });
            h.block.code = c.code;
            h.block.chain_entry = c.chain_entry;
            h.block.helpers.block = &h.block;
            h.block.armChain(&g.generation[index], g.generation[index]);
            g.slots[index] = &h.block;
            g.block_insns[index] = h.insns.items.len;
        }
        for (&g.h, 0..) |*h, index| h.block.links[0] = .{ .rip = g.h[(index + 1) % 4].block.start_rip, .slot = @intFromPtr(&g.slots[(index + 1) % 4]) };
        return g;
    }
    fn destroy(g: *@This()) void {
        for (g.h[0..g.count]) |*h| h.deinit();
        t.allocator.destroy(g);
    }
    fn run(g: *@This(), s: *f.TestState, instructions: u64) u64 {
        s.scratch.block = &g.h[0].block;
        s.scratch.regs_file = @intFromPtr(&s.regs);
        s.scratch.xmm_file = @intFromPtr(&s.xmm);
        s.scratch.ymm_hi_file = @intFromPtr(&s.ymm_hi);
        s.scratch.zmm_hi_file = @intFromPtr(&s.zmm_hi);
        s.scratch.tlb_file = @intFromPtr(&s.tlb);
        s.scratch.chain_count = 0;
        s.scratch.chain_retired_image = 0;
        s.scratch.chain_retired_other_mapped = 0;
        s.scratch.chain_budget = instructions << core.chain_count_shift;
        _ = g.h[0].block.entry()(s, &g.h[0].block.helpers, &s.scratch);
        return s.scratch.chain_count >> core.chain_count_shift;
    }
};
fn allocate() !*f.TestState {
    const s = try t.allocator.create(f.TestState);
    s.* = .{};
    return s;
}
fn seed(s: *f.TestState, memory: bool) void {
    s.* = .{};
    const regs: *[16]u64 = @ptrCast(&s.regs);
    for (regs, 0..) |*value, i| value.* = 0x1020304050607000 + i;
    if (memory) s.regs.rsi = 128;
    s.regs.rflags = 0xA57;
    s.code_cache_low = 0x1000;
    s.code_cache_high = 0x5000;
    s.admitMemory(true, true);
}
fn equal(a: *const f.TestState, b: *const f.TestState) !void {
    try t.expectEqualDeep(a.regs, b.regs);
    try t.expectEqualDeep(a.memory, b.memory);
    try t.expectEqualDeep(a.xmm, b.xmm);
    try t.expectEqualDeep(a.ymm_hi, b.ymm_hi);
    try t.expectEqualDeep(a.zmm_hi, b.zmm_hi);
    try t.expectEqual(a.interprets, b.interprets);
    try t.expectEqual(a.reads, b.reads);
    try t.expectEqual(a.writes, b.writes);
    try t.expectEqual(a.scratch.chain_count, b.scratch.chain_count);
    try t.expectEqual(a.scratch.chain_retired_image, b.scratch.chain_retired_image);
}
test "native first successor keeps guards budgets mixed entries and context state exact" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    for (0..7) |profile| for (0..4) |boundary| for ([_]bool{ false, true }) |pointers| {
        const old = try Graph.create(false, profile, boundary, pointers);
        defer old.destroy();
        const new = try Graph.create(true, profile, boundary, pointers);
        defer new.destroy();
        for (0..7) |route| {
            seed(a, profile == 1);
            seed(b, profile == 1);
            if (route == 1) {
                old.generation[1] += 1;
                new.generation[1] += 1;
            }
            if (route == 2) {
                old.h[1].block.disarmChain();
                new.h[1].block.disarmChain();
            }
            if (route == 3) {
                old.slots[1] = null;
                new.slots[1] = null;
            }
            if (route == 4) {
                a.scratch.chain_break = 1;
                b.scratch.chain_break = 1;
            }
            if (route == 5) {
                old.h[0].block.links[0].rip += 1;
                new.h[0].block.links[0].rip += 1;
            }
            try t.expectEqual(old.run(a, if (route == 6) 1 else 2048), new.run(b, if (route == 6) 1 else 2048));
            try equal(a, b);
            // Restore all proof state before the next route.
            for (&old.h, &new.h, 0..) |*x, *y, index| {
                x.block.armChain(&old.generation[index], old.generation[index]);
                y.block.armChain(&new.generation[index], new.generation[index]);
                old.slots[index] = &x.block;
                new.slots[index] = &y.block;
                x.block.links[0].rip = old.h[(index + 1) % 4].block.start_rip;
                y.block.links[0].rip = new.h[(index + 1) % 4].block.start_rip;
            }
        }
    };
}
fn cpu() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
test "native first successor alternating complete native chain CPU comparisons" {
    const bench = std.c.getenv("ROSETTE_CHAIN_BENCH") != null;
    for (0..10) |variant| {
        const profile: usize = if (variant < 6) variant else if (variant == 9) 6 else 4;
        const boundary: usize = if (variant == 6) 1 else if (variant == 7) 2 else 0;
        const budget: u64 = if (variant == 8) 1 else 4096;
        const old = try Graph.create(false, profile, boundary, true);
        defer old.destroy();
        const new = try Graph.create(true, profile, boundary, true);
        defer new.destroy();
        const a = try allocate();
        defer t.allocator.destroy(a);
        const b = try allocate();
        defer t.allocator.destroy(b);
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) b else a;
                const g = if (enabled) new else old;
                seed(s, profile == 1);
                const n: usize = if (bench) (if (variant == 8) @as(usize, 1000000) else 10000) else 8;
                var retired: u64 = 0;
                const start = cpu();
                for (0..n) |_| retired += g.run(s, budget);
                const ns = cpu() - start;
                const width = g.block_insns[0];
                if (boundary == 0) try t.expectEqual(@as(u64, n * ((budget + width - 1) / width) * width), retired);
                var bytes: usize = 0;
                for (g.h) |h| bytes += h.block.code.len * @sizeOf(u32);
                if (bench) std.debug.print("chains profile={d} pair={d} enabled={} entries={d} retired={d} cpu_ns={d} qualified={} code_bytes={d}\n", .{ variant, pair, enabled, n, retired, ns, enabled, bytes });
            }
            try equal(a, b);
        }
    }
}

const Witness = struct {
    base: f.TestState = .{},
    checksum: u64 = 0,
    change_generation: ?*u64 = null,
    fn observe(raw: *anyopaque, block: *const core.Block, index: u32) callconv(.c) u32 {
        const s: *f.TestState = @ptrCast(@alignCast(raw));
        const w: *Witness = @fieldParentPtr("base", s);
        block.helpers.flags(raw);
        const regs: *[16]u64 = @ptrCast(&s.regs);
        for (regs) |value| w.checksum = std.math.rotl(u64, w.checksum, 7) +% value;
        w.checksum +%= s.regs.rflags;
        for (regs, 0..) |*value, i| value.* ^= 0x1234 + i;
        s.ymm_hi[0][3] +%= 1;
        s.interprets += 1;
        s.regs.rip = block.insns[index].rip + block.insns[index].len;
        if (w.change_generation) |word| word.* += 1;
        return 0;
    }
};
test "native first successor publishes incoming dirty state to mutating helpers and invalidated successors" {
    const a = try t.allocator.create(Witness);
    defer t.allocator.destroy(a);
    const b = try t.allocator.create(Witness);
    defer t.allocator.destroy(b);
    for ([_]bool{ false, true }) |pointers| for ([_]bool{ false, true }) |invalidate| {
        const old = try Graph.create(false, 4, 1, pointers);
        defer old.destroy();
        const new = try Graph.create(true, 4, 1, pointers);
        defer new.destroy();
        a.* = .{};
        b.* = .{};
        seed(&a.base, false);
        seed(&b.base, false);
        old.h[1].block.helpers.interpret = Witness.observe;
        new.h[1].block.helpers.interpret = Witness.observe;
        if (invalidate) {
            a.change_generation = &old.generation[2];
            b.change_generation = &new.generation[2];
        }
        try t.expectEqual(old.run(&a.base, 4096), new.run(&b.base, 4096));
        try t.expect(a.base.interprets != 0);
        try t.expectEqual(a.checksum, b.checksum);
        try equal(&a.base, &b.base);
    };
}
test "native first successor cold memory abort and private concurrent contexts remain exact" {
    const old = try Graph.create(false, 1, 0, true);
    defer old.destroy();
    const new = try Graph.create(true, 1, 0, true);
    defer new.destroy();
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    for ([_]bool{ false, true }) |abort| {
        seed(a, true);
        seed(b, true);
        a.tlb = core.Tlb.empty;
        b.tlb = core.Tlb.empty;
        a.abort_on_access = abort;
        b.abort_on_access = abort;
        try t.expectEqual(old.run(a, 4096), new.run(b, 4096));
        try t.expect(a.reads != 0);
        try equal(a, b);
        try t.expectEqual(a.scratch.abort, b.scratch.abort);
    }
    const Job = struct {
        g: *Graph,
        state: *f.TestState,
        retired: u64 = 0,
        fn run(j: *@This()) void {
            for (0..32) |_| j.retired += j.g.run(j.state, 4096);
        }
    };
    var jobs: [4]Job = undefined;
    var threads: [4]std.Thread = undefined;
    for (&jobs, 0..) |*job, i| {
        const s = try allocate();
        seed(s, true);
        s.regs.r10 += i;
        job.* = .{ .g = new, .state = s };
    }
    defer for (jobs) |job| t.allocator.destroy(job.state);
    for (&threads, &jobs) |*thread, *job| thread.* = try std.Thread.spawn(.{}, Job.run, .{job});
    for (threads) |thread| thread.join();
    for (jobs, 0..) |job, i| {
        seed(a, true);
        a.regs.r10 += i;
        var reference = Job{ .g = old, .state = a };
        reference.run();
        try t.expectEqual(reference.retired, job.retired);
        try equal(a, job.state);
    }
}

test "native first successor retains every later way and jump-cache proof" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    const ac = try t.allocator.alloc(core.Link, core.jump_cache_entries);
    defer t.allocator.free(ac);
    const bc = try t.allocator.alloc(core.Link, core.jump_cache_entries);
    defer t.allocator.free(bc);
    for (0..7) |route| {
        const old = try Graph.create(false, 4, 0, true);
        defer old.destroy();
        const new = try Graph.create(true, 4, 0, true);
        defer new.destroy();
        seed(a, false);
        seed(b, false);
        @memset(ac, .{});
        @memset(bc, .{});
        const target = old.h[1].block.start_rip;
        const al = old.h[0].block.links[0];
        const bl = new.h[0].block.links[0];
        old.h[0].block.links[0] = .{};
        new.h[0].block.links[0] = .{};
        if (route < 3) {
            old.h[0].block.links[1 + route] = al;
            new.h[0].block.links[1 + route] = bl;
        } else {
            const slot = core.jumpCacheIndex(target);
            ac[slot] = al;
            bc[slot] = bl;
            a.scratch.jump_cache = ac.ptr;
            b.scratch.jump_cache = bc.ptr;
            if (route == 4) {
                old.slots[1] = &old.h[2].block;
                new.slots[1] = &new.h[2].block;
            }
            if (route == 5) {
                old.generation[1] += 1;
                new.generation[1] += 1;
            }
            if (route == 6) {
                ac[slot].rip += 1;
                bc[slot].rip += 1;
            }
        }
        const retired = new.run(b, 2048);
        try t.expectEqual(old.run(a, 2048), retired);
        try equal(a, b);
        if (route < 4) try t.expect(retired >= 2048) else try t.expectEqual(@as(u64, 17), retired);
    }
}
