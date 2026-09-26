//! Scalar guest-memory loads and stores shared by the interpreter and runtime.
//!
//! The cooperative executor owns guest memory exclusively between explicit
//! runtime handoffs, so its ordinary loads can use plain host accesses while
//! its per-context store buffer preserves x86 store ordering. When executors
//! overlap, the caller selects the coordinated path: aligned operations use
//! acquire/release atomics under a shared/exclusive address stripe, and legal
//! unaligned x86 accesses use atomic bytes under the same stripe.

const std = @import("std");
const stripes = @import("access_stripes.zig");
const StoreBuffer = @import("store_buffer.zig").StoreBuffer;

fn isInteger(comptime T: type) bool {
    return @typeInfo(T) == .int and @sizeOf(T) <= 8;
}

fn littleEndian(comptime T: type, value: T) T {
    return stripes.littleEndian(value);
}

fn readUncoordinated(comptime T: type, bytes: []const u8) T {
    const address = @intFromPtr(bytes.ptr);
    if (address & (@alignOf(T) - 1) == 0) {
        const pointer: *const T = @ptrFromInt(address);
        return littleEndian(T, pointer.*);
    }
    return std.mem.readInt(T, bytes[0..@sizeOf(T)], .little);
}

fn writeUncoordinated(comptime T: type, bytes: []u8, value: T) void {
    const address = @intFromPtr(bytes.ptr);
    if (address & (@alignOf(T) - 1) == 0) {
        const pointer: *T = @ptrFromInt(address);
        pointer.* = littleEndian(T, value);
        return;
    }
    std.mem.writeInt(T, bytes[0..@sizeOf(T)], value, .little);
}

fn readCoordinated(comptime T: type, bytes: []const u8) T {
    const operand = bytes[0..@sizeOf(T)];
    const guard = stripes.AccessGuard.lockMode(operand, true, true);
    defer guard.unlock();
    const address = @intFromPtr(operand.ptr);
    if (address & (@alignOf(T) - 1) == 0) {
        const pointer: *const T = @ptrFromInt(address);
        return littleEndian(T, @atomicLoad(T, pointer, .acquire));
    }

    var value: T = 0;
    for (0..@sizeOf(T)) |index| {
        const pointer: *const u8 = @ptrFromInt(address + index);
        const byte = @atomicLoad(u8, pointer, .monotonic);
        const shift: std.math.Log2Int(T) = @intCast(index * 8);
        value |= @as(T, byte) << shift;
    }
    stripes.fullBarrier();
    return value;
}

/// Read one little-endian scalar, then forward the newest overlapping bytes
/// from this executor's store queue. `coordinated=false` is valid only while
/// this executor has exclusive access to the guest address space.
pub fn load(comptime T: type, bytes: []const u8, coordinated: bool, buffer: ?*StoreBuffer) T {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));

    var value = if (coordinated)
        readCoordinated(T, bytes)
    else
        readUncoordinated(T, bytes);

    if (buffer) |store_buffer| {
        if (!store_buffer.isEmpty()) {
            const address = @intFromPtr(bytes.ptr);
            var encoded: [@sizeOf(T)]u8 = undefined;
            std.mem.writeInt(T, &encoded, value, .little);
            if (store_buffer.forwardInto(&encoded, address)) value = std.mem.readInt(T, &encoded, .little);
        }
    }
    return value;
}

fn writeCoordinated(comptime T: type, bytes: []u8, value: T) void {
    const operand = bytes[0..@sizeOf(T)];
    const guard = stripes.AccessGuard.lockMode(operand, true, false);
    defer guard.unlock();
    const address = @intFromPtr(operand.ptr);
    if (address & (@alignOf(T) - 1) == 0) {
        const pointer: *T = @ptrFromInt(address);
        @atomicStore(T, pointer, littleEndian(T, value), .release);
        return;
    }

    stripes.fullBarrier();
    inline for (0..@sizeOf(T)) |index| {
        const pointer: *u8 = @ptrFromInt(address + index);
        const shift: std.math.Log2Int(T) = @intCast(index * 8);
        const byte: u8 = @truncate(value >> shift);
        @atomicStore(u8, pointer, byte, .monotonic);
    }
    stripes.fullBarrier();
}

/// Queue a guest store when a buffer is bound. Runtime-owned writes with no
/// queue use the selected serial or coordinated access path directly.
pub fn store(comptime T: type, bytes: []u8, value: T, coordinated: bool, buffer: ?*StoreBuffer) void {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));

    if (buffer) |store_buffer| {
        var encoded: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &encoded, value, .little);
        store_buffer.enqueue(@intFromPtr(bytes.ptr), &encoded);
        return;
    }

    if (coordinated) {
        writeCoordinated(T, bytes, value);
    } else {
        writeUncoordinated(T, bytes, value);
    }
}

test "serial scalar access preserves buffered forwarding and unaligned width" {
    var bytes: [24]u8 align(8) = @splat(0);
    var buffer = StoreBuffer{};

    store(u64, bytes[1..9], 0x1122_3344_AABB_CCDD, false, &buffer);
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, bytes[1..9], .little));
    try std.testing.expectEqual(@as(u64, 0x1122_3344_AABB_CCDD), load(u64, bytes[1..9], false, &buffer));
    _ = buffer.drain();
    try std.testing.expectEqual(@as(u64, 0x1122_3344_AABB_CCDD), load(u64, bytes[1..9], false, null));
    store(u32, bytes[10..14], 0xA1B2_C3D4, false, null);
    try std.testing.expectEqual(@as(u32, 0xA1B2_C3D4), load(u32, bytes[10..14], false, null));
}

test "coordinated guest threads publish buffered data before a flag" {
    const Shared = struct {
        const payload_value: u64 = 0xD4C3_B2A1_8877_6655;
        bytes: [16]u8 align(8) = @splat(0),
        ready: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        result: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

        fn producer(shared: *@This()) void {
            const prior = stripes.setCoordinated(true);
            defer _ = stripes.setCoordinated(prior);
            _ = shared.ready.fetchAdd(1, .release);
            while (shared.ready.load(.acquire) != 2) std.atomic.spinLoopHint();

            var buffer = StoreBuffer{};
            store(u64, shared.bytes[0..8], payload_value, true, &buffer);
            store(u64, shared.bytes[8..16], 1, true, &buffer);
            _ = buffer.drain();
        }

        fn consumer(shared: *@This()) void {
            const prior = stripes.setCoordinated(true);
            defer _ = stripes.setCoordinated(prior);
            _ = shared.ready.fetchAdd(1, .release);
            while (shared.ready.load(.acquire) != 2) std.atomic.spinLoopHint();

            const deadline = 10_000_000;
            for (0..deadline) |_| {
                if (load(u64, shared.bytes[8..16], true, null) == 0) {
                    std.atomic.spinLoopHint();
                    continue;
                }
                const payload = load(u64, shared.bytes[0..8], true, null);
                shared.result.store(if (payload == payload_value) 1 else 2, .release);
                return;
            }
            shared.result.store(3, .release);
        }
    };

    var shared = Shared{};
    const consumer_thread = try std.Thread.spawn(.{}, Shared.consumer, .{&shared});
    const producer_thread = try std.Thread.spawn(.{}, Shared.producer, .{&shared});
    producer_thread.join();
    consumer_thread.join();
    try std.testing.expectEqual(@as(u8, 1), shared.result.load(.acquire));
}
