const std = @import("std");
const core = @import("core.zig");
const lanes = @import("ordered_lanes.zig");
const a64 = @import("arm64_encode");
const testing = std.testing;

test "TLB unaligned lanes retain atomics and break the first vector dependency" {
    var a = core.Assembler.init(testing.allocator);
    defer a.deinit();
    try lanes.vector(&a, 0, 13, false, .b16, .byte, 1);
    try testing.expectEqual(@as(usize, 48), a.words.items.len);
    try testing.expectEqual(a64.ldar(.byte, 9, 10), a.words.items[1]);
    try testing.expectEqual(a64.fmovSFromW(0, 9), a.words.items[2]);
    for (1..16) |lane| try testing.expectEqual(a64.vinsGpr(.b16, 0, @intCast(lane), 9), a.words.items[2 + lane * 3]);
    a.words.clearRetainingCapacity();
    try lanes.vector(&a, 0, 13, true, .s4, .word, 4);
    try testing.expectEqual(@as(usize, 12), a.words.items.len);
    for (0..4) |lane| try testing.expectEqual(a64.stlr(.word, 9, 10), a.words.items[2 + lane * 3]);
}

test "TLB unaligned lanes publish ordinary payload across two native threads" {
    if (!core.CodeMemory.available()) return error.SkipZigTest;
    var memory = try core.CodeMemory.init(4096);
    defer memory.deinit();
    var a = core.Assembler.init(testing.allocator);
    defer a.deinit();
    // Producer: ordinary payload store, then an unaligned 16-bit flag
    // through the exact production scalar lane generator.
    try a.emit(a64.strImm(.word, 1, 0, 0).?);
    try a.emit(a64.addImm(.x64, 13, 0, 9).?);
    try a.emit(a64.mov(.x64, 3, 1));
    try lanes.scalarStore(&a, 13, 2);
    try a.emit(a64.ret());
    const producer_words = try a.finish();
    const producer_code = try memory.reserve(producer_words.len);
    memory.beginWrite();
    @memcpy(producer_code, producer_words);
    memory.endWrite(producer_code);
    a.deinit();
    a = core.Assembler.init(testing.allocator);
    // Consumer: acquire the unaligned flag before reading ordinary data.
    try a.emit(a64.addImm(.x64, 13, 0, 9).?);
    try lanes.scalarLoad(&a, 9, 13, 2);
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
    try testing.expectEqual(@as(u8, 0), fixture.bytes[8]);
    try testing.expectEqual(@as(u8, 0), fixture.bytes[11]);
}
