const std = @import("std");
const core = @import("core.zig");
const harness = @import("tests.zig");
const pairs = @import("register_cache.zig");
const a64 = @import("arm64_encode");
const testing = std.testing;

test "cached register pairs preserve arbitrary cache order and skip clean writebacks" {
    var assembler = core.Assembler.init(testing.allocator);
    defer assembler.deinit();
    const ids = [_]core.RegId{ @enumFromInt(8), @enumFromInt(1), @enumFromInt(0), @enumFromInt(9), @enumFromInt(4) };
    const hosts = [_]a64.Reg{ 25, 26, 27, 28, 4 };
    try pairs.transfer(&assembler, &ids, &hosts, 20, 0xFFFF, false);
    try testing.expectEqualSlices(u32, &.{
        a64.ldp(.signed_offset, 25, 28, 20, 64).?,
        a64.ldp(.signed_offset, 27, 26, 20, 0).?,
        a64.ldrImm(.doubleword, 4, 20, 32).?,
    }, assembler.words.items);
    assembler.words.clearRetainingCapacity();
    try pairs.transfer(&assembler, &ids, &hosts, 20, (1 << 8) | (1 << 0), true);
    try testing.expectEqualSlices(u32, &.{
        a64.strImm(.doubleword, 25, 20, 64).?,
        a64.strImm(.doubleword, 27, 20, 0).?,
    }, assembler.words.items);
}

test "cached register pairs execute with all sixteen guest registers busy" {
    var h = try harness.TestHarness.init();
    defer h.deinit();
    var state = harness.TestState{};
    const gprs: *[16]u64 = @ptrCast(&state.regs);
    var expected: [16]u64 = undefined;
    for (gprs, 0..) |*value, index| {
        value.* = 0xF020_3040_5060_7080 + index;
        expected[index] = value.*;
    }
    for (0..4) |pass| for (0..16) |index| {
        const immediate = 3 + index;
        expected[index] +%= immediate;
        try h.add(0x1000 + (pass * 16 + index) * 4, 4, .{
            .op = .add_reg64_imm32,
            .size = .bits64,
            .dst_reg = @enumFromInt(index),
            .imm = immediate,
        });
    };
    _ = try h.run(&state);
    try testing.expectEqualSlices(u64, &expected, gprs);
}

fn addVector(h: *harness.TestHarness, rip: u64, dst: u8, src: u8, rhs: u8) !void {
    try h.add(rip, 4, .{ .op = .vpaddd, .size = .bits32, .xmm_dst = dst, .xmm_src = src, .xmm_src2 = rhs, .is_reg_form = true });
}

fn seedVectors(state: *harness.TestState) void {
    for (0..4) |lane| {
        std.mem.writeInt(u32, state.xmm[0][lane * 4 ..][0..4], @intCast(lane + 2), .little);
        std.mem.writeInt(u32, state.xmm[1][lane * 4 ..][0..4], @intCast(lane + 1), .little);
    }
    @memset(std.mem.asBytes(&state.ymm_hi), 0xA5);
    @memset(std.mem.asBytes(&state.zmm_hi), 0x5A);
}

test "vector moves coalesce intermediate writes but publish at block exits" {
    var h = try harness.TestHarness.init();
    defer h.deinit();
    for (0..16) |index| try addVector(&h, 0x1000 + index * 4, 0, 0, 1);
    const compiled = try core.compile(testing.allocator, &h.memory, harness.TestState.layout, h.insns.items, 0x1040);
    try testing.expectEqual(@as(u32, 15), compiled.xmm_stores_elided);
    var state = harness.TestState{};
    seedVectors(&state);
    _ = try h.run(&state);
    for (0..4) |lane| try testing.expectEqual(@as(u32, @intCast(lane + 2 + 16 * (lane + 1))), std.mem.readInt(u32, state.xmm[0][lane * 4 ..][0..4], .little));
    try testing.expectEqualSlices(u8, &(@as([16]u8, @splat(0))), &state.ymm_hi[0]);
}

test "vector moves publish before internal entries helper calls and wide consumers" {
    for (0..3) |boundary| {
        var h = try harness.TestHarness.init();
        defer h.deinit();
        var state = harness.TestState{};
        seedVectors(&state);
        if (boundary == 0) {
            try h.add(0x0FFA, 4, .{ .op = .cmp_reg64_imm32, .size = .bits64, .dst_reg = .al_ax_eax_rax, .imm = 0 });
            try h.add(0x0FFE, 2, .{ .op = .jcc_rel8, .cond = .e, .addr = 4 });
        }
        try addVector(&h, 0x1000, 0, 0, 1);
        if (boundary == 1) {
            try h.add(0x1004, 4, .{ .op = .nop });
            h.insns.items[h.insns.items.len - 1].force_fallback = true;
        }
        if (boundary == 2) {
            try h.add(0x1004, 4, .{ .op = .vaddps, .size = .bits32, .xmm_dst = 0, .xmm_src = 0, .xmm_src2 = 1, .is_reg_form = true, .vector_256 = true });
        } else try addVector(&h, if (boundary == 1) 0x1008 else 0x1004, 0, 0, 1);
        if (boundary == 0) try h.add(0x1008, 4, .{ .op = .add_reg64_imm32, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .imm = 1 });
        const insns = h.insns.items;
        const last = insns[insns.len - 1];
        const compiled = try core.compile(testing.allocator, &h.memory, harness.TestState.layout, insns, last.rip + last.len);
        try testing.expectEqual(@as(u32, 0), compiled.xmm_stores_elided);
        if (boundary != 2) {
            _ = try h.run(&state);
            for (0..4) |lane| try testing.expectEqual(@as(u32, @intCast(lane + 2 + (if (boundary == 0) @as(u32, 1) else 2) * (lane + 1))), std.mem.readInt(u32, state.xmm[0][lane * 4 ..][0..4], .little));
        }
    }
}

fn addCountedLoop(h: *harness.TestHarness) !void {
    try h.add(0x1000, 4, .{ .op = .add_reg64_imm32, .size = .bits64, .dst_reg = .al_ax_eax_rax, .imm = 1 });
    try h.add(0x1004, 3, .{ .op = .dec_reg64, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx });
    try h.add(0x1007, 2, .{ .op = .jcc_rel8, .cond = .ne, .addr = @bitCast(@as(i64, -9)) });
}

test "native hops retain self-loop registers and publish on budget break and generation refusal" {
    for ([_]bool{ false, true }) |resident| {
        for (0..4) |route| {
            var h = try harness.TestHarness.init();
            defer h.deinit();
            try addCountedLoop(&h);
            const options: core.Options = .{ .resident_self_loops = resident };
            const metadata = try core.compileWith(testing.allocator, &h.memory, harness.TestState.layout, h.insns.items, 0x1009, options);
            var state = harness.TestState{};
            state.regs.rcx = 1;
            _ = try h.runWith(&state, options); // initializes helpers and the executing block
            h.block.chain_entry = metadata.chain_entry;
            var generation: u64 = 17;
            h.block.armChain(&generation, generation);
            var slot: ?*core.Block = &h.block;
            h.block.links[0] = .{ .rip = 0x1000, .slot = @intFromPtr(&slot) };
            state.regs.rax = 0;
            state.regs.rcx = 100;
            state.scratch.chain_count = 0;
            state.scratch.chain_retired_image = 0;
            state.scratch.chain_budget = 30 << core.chain_count_shift;
            state.scratch.chain_break = 0;
            if (route == 1) generation += 1;
            if (route == 2) state.scratch.chain_break = 1;
            if (route == 3) h.block.disarmChain();
            _ = h.block.entry()(&state, &h.block.helpers, &state.scratch);
            const iterations: u64 = if (route == 0) 10 else 1;
            try testing.expectEqual(iterations, state.regs.rax);
            try testing.expectEqual(100 - iterations, state.regs.rcx);
            try testing.expectEqual(iterations, state.scratch.chain_count & core.chain_count_blocks_mask);
            try testing.expectEqual(iterations * 3, state.scratch.chain_count >> core.chain_count_shift);
            try testing.expectEqual(iterations * 3, state.scratch.chain_retired_image);
            try testing.expectEqual(@as(u64, 0x1000), state.regs.rip);
            if (route == 0) try testing.expectEqual(&h.block, state.scratch.chain_previous.?);
        }
    }
}

test "native hops self-loop helpers expose generation changes before another iteration" {
    const Invalidate = struct {
        fn read(raw: *anyopaque, _: u64, _: u8) callconv(.c) u64 {
            const state: *harness.TestState = @ptrCast(@alignCast(raw));
            state.image_low += 1;
            return 42;
        }
    };
    var h = try harness.TestHarness.init();
    defer h.deinit();
    try h.add(0x1000, 4, .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
    try h.add(0x1004, 4, .{ .op = .add_reg64_imm32, .size = .bits64, .dst_reg = .al_ax_eax_rax, .imm = 1 });
    try h.add(0x1008, 3, .{ .op = .dec_reg64, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx });
    try h.add(0x100B, 2, .{ .op = .jcc_rel8, .cond = .ne, .addr = @bitCast(@as(i64, -13)) });
    var state = harness.TestState{};
    state.regs.rcx = 1;
    _ = try h.run(&state);
    state.regs.rax = 7;
    state.regs.rcx = 100;
    state.image_low = 17;
    h.block.armChain(&state.image_low, 17);
    h.block.helpers.read = Invalidate.read;
    state.scratch.chain_count = 0;
    state.scratch.chain_budget = 400 << core.chain_count_shift;
    _ = h.block.entry()(&state, &h.block.helpers, &state.scratch);
    try testing.expectEqual(@as(u64, 18), state.image_low);
    try testing.expectEqual(@as(u64, 8), state.regs.rax);
    try testing.expectEqual(@as(u64, 42), state.regs.rdx);
    try testing.expectEqual(@as(u64, 99), state.regs.rcx);
    try testing.expectEqual(@as(u64, 1), state.scratch.chain_count & core.chain_count_blocks_mask);
}

test "vector moves resident segments agree with published state for all sixteen registers and aliases" {
    var prng = std.Random.DefaultPrng.init(0x71AC_CE42);
    const random = prng.random();
    const ops = [_]core.Op{ .vpaddd, .vpsubd, .vpxor, .vpand, .vpor, .vpunpckldq, .vminps, .vmaxps };
    for (0..64) |_| {
        var h = try harness.TestHarness.init();
        defer h.deinit();
        var baseline = harness.TestState{};
        random.bytes(std.mem.asBytes(&baseline.xmm));
        random.bytes(std.mem.asBytes(&baseline.ymm_hi));
        random.bytes(std.mem.asBytes(&baseline.zmm_hi));
        var resident = baseline;
        for (0..96) |index| {
            try h.add(0x1000 + index * 4, 4, .{
                .op = ops[random.uintLessThan(usize, ops.len)],
                .size = .bits32,
                .xmm_dst = random.uintLessThan(u8, 16),
                .xmm_src = random.uintLessThan(u8, 16),
                .xmm_src2 = random.uintLessThan(u8, 16),
                .is_reg_form = true,
            });
        }
        const a = try h.runWith(&baseline, .{ .resident_vectors = false });
        const b = try h.runWith(&resident, .{ .resident_vectors = true });
        try testing.expectEqual(a, b);
        try testing.expectEqualDeep(baseline.regs, resident.regs);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&baseline.xmm), std.mem.asBytes(&resident.xmm));
        try testing.expectEqualSlices(u8, std.mem.asBytes(&baseline.ymm_hi), std.mem.asBytes(&resident.ymm_hi));
        try testing.expectEqualSlices(u8, std.mem.asBytes(&baseline.zmm_hi), std.mem.asBytes(&resident.zmm_hi));
    }
}

test "vector moves publish to an interpreter observer and reload its changed registers" {
    const Observer = struct {
        fn interpret(raw: *anyopaque, _: *const core.Block, _: u32) callconv(.c) u32 {
            const state: *harness.TestState = @ptrCast(@alignCast(raw));
            state.flags_at_interpret = std.mem.readInt(u32, state.xmm[0][0..4], .little);
            for (0..4) |lane| std.mem.writeInt(u32, state.xmm[1][lane * 4 ..][0..4], 10, .little);
            return 0;
        }
    };
    var h = try harness.TestHarness.init();
    defer h.deinit();
    for (0..4) |i| try addVector(&h, 0x1000 + i * 4, 0, 0, 1);
    try h.add(0x1010, 1, .{ .op = .nop });
    h.insns.items[4].force_fallback = true;
    try addVector(&h, 0x1011, 0, 0, 1);
    var setup = harness.TestState{};
    _ = try h.run(&setup);
    h.block.helpers.interpret = Observer.interpret;
    var state = harness.TestState{};
    seedVectors(&state);
    _ = h.block.entry()(&state, &h.block.helpers, &state.scratch);
    try testing.expectEqual(@as(u32, 6), state.flags_at_interpret);
    for (0..4) |lane| try testing.expectEqual(@as(u32, @intCast(lane + 2 + 4 * (lane + 1) + 10)), std.mem.readInt(u32, state.xmm[0][lane * 4 ..][0..4], .little));
}
