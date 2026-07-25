const std = @import("std");
const types = @import("types.zig");
const PrimitiveContext = types.PrimitiveContext;
const SlotIndex = types.SlotIndex;
const Result = types.Result;

pub fn strlen(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const string_ptr = ctx.readArg(0);
    const slice = ctx.readCString(string_ptr) orelse return .unsupported;
    ctx.setResult(slice.len);
    return .handled;
}

pub fn cxaGuardAcquire(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const guard_ptr = ctx.readArg(0);
    const guard_bytes = ctx.readGuest(guard_ptr, 8) orelse return .unsupported;
    const guard_val = std.mem.readInt(u64, guard_bytes[0..8], .little);
    if ((guard_val & 1) != 0) {
        ctx.setResult(0);
        return .handled;
    }
    return .fallback;
}

pub fn cxaGuardRelease(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const guard_ptr = ctx.readArg(0);
    const guard_bytes = ctx.readGuest(guard_ptr, 8) orelse return .unsupported;
    var guard_val = std.mem.readInt(u64, guard_bytes[0..8], .little);
    guard_val |= 1;
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, guard_val, .little);
    ctx.writeGuest(guard_ptr, &buf) orelse return .unsupported;
    return .handled_void;
}

pub fn cxaGuardAbort(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    _ = ctx;
    return .handled_void;
}

pub fn memcmp(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const s1 = ctx.readArg(0);
    const s2 = ctx.readArg(1);
    const n = ctx.readArg(2);
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const b1 = ctx.readGuest(s1 + i, 1) orelse return .unsupported;
        const b2 = ctx.readGuest(s2 + i, 1) orelse return .unsupported;
        if (b1[0] != b2[0]) {
            ctx.setResult(@as(u64, @bitCast(@as(i64, @as(i32, @intCast(b1[0] - b2[0]))))));
            return .handled;
        }
    }
    ctx.setResult(0);
    return .handled;
}

pub fn strcmp(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const s1 = ctx.readArg(0);
    const s2 = ctx.readArg(1);
    const a = ctx.readCString(s1) orelse return .unsupported;
    const b = ctx.readCString(s2) orelse return .unsupported;
    const cmp = std.mem.order(u8, a, b);
    const result: i32 = switch (cmp) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
    ctx.setResult(@as(u64, @bitCast(@as(i64, result))));
    return .handled;
}

pub fn strncmp(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const s1 = ctx.readArg(0);
    const s2 = ctx.readArg(1);
    const n = ctx.readArg(2);
    const a = ctx.readCString(s1) orelse return .unsupported;
    const b = ctx.readCString(s2) orelse return .unsupported;
    const limit = @min(n, @min(a.len, b.len));
    const cmp = std.mem.order(u8, a[0..limit], b[0..limit]);
    const result: i32 = if (cmp != .eq) switch (cmp) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    } else if (a.len < n and b.len < n) 0 else if (a.len < b.len) -1 else 1;
    ctx.setResult(@as(u64, @bitCast(@as(i64, if (n == 0) 0 else result))));
    return .handled;
}

test "handlers: strlen reads cstring and returns length" {
    const TestState = struct {
        args: [6]u64 = .{0} ** 6,
        result: u64 = 0,
        memory: [64]u8 = undefined,

        fn readArg(ptr: *anyopaque, index: u8) u64 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return if (index < 6) self.args[index] else 0;
        }
        fn setResult(ptr: *anyopaque, value: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.result = value;
        }
        fn readGuest(_: *const anyopaque, _: u64, _: usize) ?[]const u8 {
            return null;
        }
        fn writeGuest(_: *anyopaque, _: u64, _: []const u8) ?void {
            return null;
        }
        fn readCString(ptr: *const anyopaque, address: u64) ?[]const u8 {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            if (address >= self.memory.len) return null;
            return std.mem.sliceTo(self.memory[address..], 0);
        }
    };

    var state = TestState{};
    const hello = "hello world";
    @memcpy(state.memory[0..hello.len], hello);
    state.memory[hello.len] = 0;
    state.args[0] = 0;

    var ctx = PrimitiveContext{
        .ptr = &state,
        .readArgFn = TestState.readArg,
        .setResultFn = TestState.setResult,
        .readGuestFn = TestState.readGuest,
        .writeGuestFn = TestState.writeGuest,
        .readCStringFn = TestState.readCString,
    };

    try std.testing.expectEqual(Result.handled, strlen(0, &ctx));
    try std.testing.expectEqual(@as(u64, 11), state.result);
}

test "handlers: cxaGuardRelease sets bit 0" {
    const TestState = struct {
        args: [6]u64 = .{0} ** 6,
        result: u64 = 0,
        memory: [64]u8 = undefined,

        fn readArg(ptr: *anyopaque, index: u8) u64 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return if (index < 6) self.args[index] else 0;
        }
        fn setResult(_: *anyopaque, _: u64) void {}
        fn readGuest(ptr: *const anyopaque, address: u64, size: usize) ?[]const u8 {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            if (address + size > self.memory.len) return null;
            return self.memory[address..][0..size];
        }
        fn writeGuest(ptr: *anyopaque, address: u64, data: []const u8) ?void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            if (address + data.len > self.memory.len) return null;
            @memcpy(self.memory[address..][0..data.len], data);
            return {};
        }
        fn readCString(_: *const anyopaque, _: u64) ?[:0]const u8 {
            return null;
        }
    };

    var state = TestState{};
    state.memory[0..8].* = @bitCast(@as(u64, 0));
    state.args[0] = 0;

    var ctx = PrimitiveContext{
        .ptr = &state,
        .readArgFn = TestState.readArg,
        .setResultFn = TestState.setResult,
        .readGuestFn = TestState.readGuest,
        .writeGuestFn = TestState.writeGuest,
        .readCStringFn = TestState.readCString,
    };

    try std.testing.expectEqual(Result.handled_void, cxaGuardRelease(0, &ctx));
    const val = std.mem.readInt(u64, state.memory[0..8], .little);
    try std.testing.expectEqual(@as(u64, 1), val);
}
