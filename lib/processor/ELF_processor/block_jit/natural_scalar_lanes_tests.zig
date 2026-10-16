const std = @import("std");
const core = @import("core.zig");
const f = @import("tests.zig");
const t = std.testing;
const testing = std.testing;
const a64 = @import("arm64_encode");

fn allocate() !*f.TestState {
    const s = try t.allocator.create(f.TestState);
    s.* = .{};
    return s;
}
fn instruction(bytes: usize, store: bool) core.DecodedInsn {
    return .{
        .op = if (store) switch (bytes) {
            2 => .mov_mem16_reg16,
            4 => .mov_mem32_reg32,
            else => .mov_mem64_reg64,
        } else switch (bytes) {
            2 => .mov_reg16_mem16,
            4 => .mov_reg32_mem32,
            else => .mov_reg64_mem64,
        },
        .size = switch (bytes) {
            2 => .bits16,
            4 => .bits32,
            else => .bits64,
        },
        .dst_reg = .al_ax_eax_rax,
        .src_reg = .dl_dx_edx_rdx,
        .sib_has_base = true,
        .sib_base_reg = .bl_bx_ebx_rbx,
    };
}
test "natural scalar lanes preserve widths alignments neighbouring bytes and helper refusal" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    for ([_]usize{ 2, 4, 8 }) |bytes| for ([_]bool{ false, true }) |store| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 4, instruction(bytes, store));
        for (0..5) |route| for (0..16) |offset| {
            a.* = .{};
            for (&a.memory, 0..) |*byte, i| byte.* = @truncate(i * 31 + offset);
            a.regs.rax = 0xA1B2C3D4E5F60718;
            a.regs.rdx = 0xBA9876543210FEDC;
            a.regs.rflags = 0x8D7;
            a.regs.rbx = (if (route == 2) @as(u64, 4080) else 128) + offset;
            if (route != 1) a.admitMemory(route != 3, route != 4);
            if (route == 1) a.abort_on_access = true;
            // TLB host pointers belong to each context's private array.
            b.* = a.*;
            b.tlb = .empty;
            if (route != 1) b.admitMemory(route != 3, route != 4);
            const x = try h.runWith(a, .{ .natural_scalar_lanes = false });
            const y = try h.runWith(b, .{ .natural_scalar_lanes = true });
            try t.expectEqual(x, y);
            try t.expectEqualDeep(a.regs, b.regs);
            try t.expectEqualDeep(a.memory, b.memory);
            try t.expectEqual(a.reads, b.reads);
            try t.expectEqual(a.writes, b.writes);
            try t.expectEqual(a.scratch.abort, b.scratch.abort);
            try t.expectEqual(a.interprets, b.interprets);
        };
    };
}
fn cpu() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
test "natural scalar lanes alternating complete translated memory blocks" {
    const bench = std.c.getenv("ROSETTE_ARITHMETIC_BENCH") != null;
    for ([_]usize{ 1, 2, 4, 8 }) |offset| for ([_]bool{ false, true }) |store| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        for (0..32) |n| try h.add(0x1000 + n * 4, 4, instruction(8, store));
        const a = try allocate();
        defer t.allocator.destroy(a);
        const b = try allocate();
        defer t.allocator.destroy(b);
        _ = try h.run(a);
        const old = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x1080, .{ .natural_scalar_lanes = false });
        const new = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x1080, .{ .natural_scalar_lanes = true });
        var blocks = [_]core.Block{ h.block, h.block };
        blocks[0].code = old.code;
        blocks[1].code = new.code;
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) b else a;
                s.* = .{};
                s.regs.rbx = 128 + offset;
                s.regs.rdx = 0xBA9876543210FEDC;
                s.admitMemory(true, true);
                const block = &blocks[@intFromBool(enabled)];
                s.scratch.block = block;
                const count: usize = if (bench) 100000 else 16;
                var retired: u64 = 0;
                const start = cpu();
                for (0..count) |_| retired += block.entry()(s, &block.helpers, &s.scratch);
                const ns = cpu() - start;
                try t.expectEqual(@as(u64, count * 32), retired);
                try t.expectEqual(@as(u32, 0), s.reads + s.writes);
                if (bench) std.debug.print("natural offset={d} store={} pair={d} enabled={} operations={d} retired={d} cpu_ns={d} code_bytes={d}\n", .{ offset, store, pair, enabled, count, retired, ns, block.code.len * @sizeOf(u32) });
            }
            try t.expectEqualDeep(a.regs, b.regs);
            try t.expectEqualDeep(a.memory, b.memory);
        }
    };
}

test "natural scalar lanes publish an eight-byte flag across two native threads" {
    if (!core.CodeMemory.available()) return error.SkipZigTest;
    var memory = try core.CodeMemory.init(4096);
    defer memory.deinit();
    var a = core.Assembler.init(testing.allocator);
    defer a.deinit();
    // Producer: ordinary payload store, then an unaligned 64-bit flag
    // through the exact production scalar lane generator.
    try a.emit(a64.strImm(.word, 1, 0, 0).?);
    try a.emit(a64.addImm(.x64, 13, 0, 12).?);
    try a.emit(a64.mov(.x64, 3, 1));
    try @import("natural_scalar_lanes.zig").emit(&a, 3, 13, 8, true);
    try a.emit(a64.ret());
    const producer_words = try a.finish();
    const producer_code = try memory.reserve(producer_words.len);
    memory.beginWrite();
    @memcpy(producer_code, producer_words);
    memory.endWrite(producer_code);
    a.deinit();
    a = core.Assembler.init(testing.allocator);
    // Consumer: acquire the unaligned flag before reading ordinary data.
    try a.emit(a64.addImm(.x64, 13, 0, 12).?);
    try @import("natural_scalar_lanes.zig").emit(&a, 9, 13, 8, false);
    try a.emit(a64.ldrImm(.word, 2, 0, 0).?);
    try a.emit(a64.lslImm(.x64, 9, 9, 32));
    try a.emit(a64.orrReg(.x64, 0, 2, 9));
    try a.emit(a64.ret());
    const consumer_words = try a.finish();
    const consumer_code = try memory.reserve(consumer_words.len);
    memory.beginWrite();
    @memcpy(consumer_code, consumer_words);
    memory.endWrite(consumer_code);

    const Fixture = struct {
        bytes: [32]u8 align(16) = @splat(0),
        acknowledged: std.atomic.Value(u32) = .init(0),
        failed: std.atomic.Value(bool) = .init(false),
        publish: *const fn (*anyopaque, u32) callconv(.c) void,
        observe: *const fn (*anyopaque) callconv(.c) u64,
        deadline: u64,
        const iterations = 50_000;
        fn producer(self: *@This()) void {
            for (1..iterations + 1) |i| {
                while (self.acknowledged.load(.acquire) != i - 1) {
                    if (self.failed.load(.acquire)) return;
                    std.atomic.spinLoopHint();
                }
                self.publish(&self.bytes, @intCast(i));
            }
        }
        fn consumer(self: *@This()) void {
            for (1..iterations + 1) |i| {
                var spins: usize = 0;
                while (true) : (spins += 1) {
                    const value = self.observe(&self.bytes);
                    if (value >> 32 == i) {
                        if (@as(u32, @truncate(value)) != i) {
                            self.failed.store(true, .release);
                            return;
                        }
                        self.acknowledged.store(@intCast(i), .release);
                        break;
                    }
                    if (spins & 0x3FF == 0 and std.c.mach_absolute_time() > self.deadline) {
                        self.failed.store(true, .release);
                        return;
                    }
                    std.atomic.spinLoopHint();
                }
            }
        }
    };
    var scale: std.c.mach_timebase_info_data = undefined;
    try testing.expectEqual(@as(c_int, 0), std.c.mach_timebase_info(&scale));
    try testing.expect(scale.numer != 0);
    const deadline = std.c.mach_absolute_time() + @as(u64, @intCast(@as(u128, 10 * std.time.ns_per_s) * scale.denom / scale.numer));
    var fixture: Fixture = .{ .publish = @ptrCast(producer_code.ptr), .observe = @ptrCast(consumer_code.ptr), .deadline = deadline };
    const producer = try std.Thread.spawn(.{}, Fixture.producer, .{&fixture});
    const consumer = std.Thread.spawn(.{}, Fixture.consumer, .{&fixture}) catch |err| {
        fixture.failed.store(true, .release);
        producer.join();
        return err;
    };
    producer.join();
    consumer.join();
    try testing.expect(!fixture.failed.load(.acquire));
    try testing.expectEqual(@as(u32, Fixture.iterations), fixture.acknowledged.load(.acquire));
    // Width and bounds are part of the contract: adjacent bytes survive.
    try testing.expectEqual(@as(u8, 0), fixture.bytes[11]);
    try testing.expectEqual(@as(u8, 0), fixture.bytes[20]);
}
