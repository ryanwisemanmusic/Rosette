const std = @import("std");
const types = @import("types.zig");

const PrimitiveContext = types.PrimitiveContext;
const Result = types.Result;
const SlotIndex = types.SlotIndex;

/// Darwin's fortified memmove entry point.
///
/// ABI:
///   rdi = destination
///   rsi = source
///   rdx = byte count
///   rcx = compiler-known destination size, or SIZE_MAX when unknown
///
/// A failed fortify check deliberately falls back to the legacy dispatcher,
/// which owns fatal guest termination and its diagnostic. Valid moves stay in
/// the primitive layer and retain true overlap-safe memmove behavior.
pub fn memmoveChk(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const destination = ctx.readArg(0);
    const source = ctx.readArg(1);
    const count_u64 = ctx.readArg(2);
    const destination_size = ctx.readArg(3);

    if (destination_size != std.math.maxInt(u64) and count_u64 > destination_size) {
        return .fallback;
    }
    if (count_u64 == 0) {
        ctx.setResult(destination);
        return .handled;
    }
    if (destination == 0 or source == 0) return .unsupported;

    const count = std.math.cast(usize, count_u64) orelse return .unsupported;
    _ = std.math.add(u64, source, count_u64) catch return .unsupported;
    _ = std.math.add(u64, destination, count_u64) catch return .unsupported;
    if (!ctx.moveGuest(destination, source, count)) return .unsupported;

    ctx.setResult(destination);
    return .handled;
}

test "memmove_chk preserves overlapping bytes and returns destination" {
    const TestState = struct {
        args: [6]u64,
        result: u64 = 0,
        memory: [32]u8 = [_]u8{0} ** 32,

        fn readArg(ptr: *anyopaque, index: u8) u64 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self.args[index];
        }
        fn setResult(ptr: *anyopaque, value: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.result = value;
        }
        fn readGuest(ptr: *const anyopaque, address: u64, size: usize) ?[]const u8 {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            const start = std.math.cast(usize, address) orelse return null;
            const end = std.math.add(usize, start, size) catch return null;
            if (end > self.memory.len) return null;
            return self.memory[start..end];
        }
        fn writeGuest(ptr: *anyopaque, address: u64, data: []const u8) ?void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            const start = std.math.cast(usize, address) orelse return null;
            const end = std.math.add(usize, start, data.len) catch return null;
            if (end > self.memory.len) return null;
            @memcpy(self.memory[start..end], data);
            return {};
        }
        fn readCString(_: *const anyopaque, _: u64) ?[]const u8 {
            return null;
        }
        fn callGuest(_: *anyopaque, _: u64, _: [6]u64) u64 {
            return 0;
        }
        fn pthreadId(_: *anyopaque, _: u64) u64 {
            return 0;
        }
        fn dladdrResolve(_: *anyopaque, _: u64) types.DladdrInfo {
            return .{};
        }
    };

    var state = TestState{ .args = .{ 6, 4, 8, std.math.maxInt(u64), 0, 0 } };
    @memcpy(state.memory[4..12], "abcdefgh");
    const ctx = PrimitiveContext{
        .ptr = &state,
        .readArgFn = TestState.readArg,
        .setResultFn = TestState.setResult,
        .readGuestFn = TestState.readGuest,
        .writeGuestFn = TestState.writeGuest,
        .readCStringFn = TestState.readCString,
        .callGuestFn = TestState.callGuest,
        .pthreadMachThreadIdFn = TestState.pthreadId,
        .dladdrResolveFn = TestState.dladdrResolve,
    };

    try std.testing.expectEqual(Result.handled, memmoveChk(0, &ctx));
    try std.testing.expectEqual(@as(u64, 6), state.result);
    try std.testing.expectEqualStrings("abcdefgh", state.memory[6..14]);
}

test "memmove_chk rejects an exceeded fortified size" {
    const TestContext = struct {
        fn readArg(_: *anyopaque, index: u8) u64 {
            return switch (index) {
                0 => 0x1000,
                1 => 0x2000,
                2 => 9,
                3 => 8,
                else => 0,
            };
        }
        fn setResult(_: *anyopaque, _: u64) void {}
        fn readGuest(_: *const anyopaque, _: u64, _: usize) ?[]const u8 {
            return null;
        }
        fn writeGuest(_: *anyopaque, _: u64, _: []const u8) ?void {
            return null;
        }
        fn readCString(_: *const anyopaque, _: u64) ?[]const u8 {
            return null;
        }
        fn callGuest(_: *anyopaque, _: u64, _: [6]u64) u64 {
            return 0;
        }
        fn pthreadId(_: *anyopaque, _: u64) u64 {
            return 0;
        }
        fn dladdrResolve(_: *anyopaque, _: u64) types.DladdrInfo {
            return .{};
        }
    };
    var state: u8 = 0;
    const ctx = PrimitiveContext{
        .ptr = &state,
        .readArgFn = TestContext.readArg,
        .setResultFn = TestContext.setResult,
        .readGuestFn = TestContext.readGuest,
        .writeGuestFn = TestContext.writeGuest,
        .readCStringFn = TestContext.readCString,
        .callGuestFn = TestContext.callGuest,
        .pthreadMachThreadIdFn = TestContext.pthreadId,
        .dladdrResolveFn = TestContext.dladdrResolve,
    };
    try std.testing.expectEqual(Result.fallback, memmoveChk(0, &ctx));
}
