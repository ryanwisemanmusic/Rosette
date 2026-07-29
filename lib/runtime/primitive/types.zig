const std = @import("std");

pub const SlotIndex = u32;

pub const Result = enum(u8) {
    handled,
    handled_void,
    unsupported,
    fallback,
};

pub const Handler = *const fn (slot: SlotIndex, ctx: *const PrimitiveContext) Result;

pub const PrimitiveContext = struct {
    ptr: *anyopaque,
    readArgFn: *const fn (ptr: *anyopaque, index: u8) u64,
    setResultFn: *const fn (ptr: *anyopaque, value: u64) void,
    readGuestFn: *const fn (ptr: *const anyopaque, address: u64, size: usize) ?[]const u8,
    writeGuestFn: *const fn (ptr: *anyopaque, address: u64, data: []const u8) ?void,
    readCStringFn: *const fn (ptr: *const anyopaque, address: u64) ?[]const u8,
    /// Call a guest function synchronously and return its rax value.
    /// The guest function is called with up to 6 integer arguments (rdi–r9)
    /// and must follow the System V AMD64 ABI (caller must not be noreturn).
    /// Returns 0 if the call cannot be completed.
    callGuestFn: *const fn (ptr: *anyopaque, fn_address: u64, args: [6]u64) u64,

    pub fn readArg(self: *const PrimitiveContext, index: u8) u64 {
        return self.readArgFn(self.ptr, index);
    }

    pub fn setResult(self: *const PrimitiveContext, value: u64) void {
        self.setResultFn(self.ptr, value);
    }

    pub fn readGuest(self: *const PrimitiveContext, address: u64, size: usize) ?[]const u8 {
        return self.readGuestFn(self.ptr, address, size);
    }

    pub fn writeGuest(self: *const PrimitiveContext, address: u64, data: []const u8) ?void {
        return self.writeGuestFn(self.ptr, address, data);
    }

    pub fn readCString(self: *const PrimitiveContext, address: u64) ?[]const u8 {
        return self.readCStringFn(self.ptr, address);
    }

    pub fn callGuest(self: *const PrimitiveContext, fn_address: u64, args: [6]u64) u64 {
        return self.callGuestFn(self.ptr, fn_address, args);
    }
};

test "PrimitiveContext function dispatch works through vtable" {
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
        fn readCString(ptr: *const anyopaque, address: u64) ?[]const u8 {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            if (address >= self.memory.len) return null;
            return std.mem.sliceTo(self.memory[address..], 0);
        }
    };

    var state = TestState{ .args = .{ 42, 99, 0, 0, 0, 0 } };
    var ctx = PrimitiveContext{
        .ptr = &state,
        .readArgFn = TestState.readArg,
        .setResultFn = TestState.setResult,
        .readGuestFn = TestState.readGuest,
        .writeGuestFn = TestState.writeGuest,
        .readCStringFn = TestState.readCString,
        .callGuestFn = struct {
            fn call(_: *anyopaque, _: u64, _: [6]u64) u64 {
                return 0;
            }
        }.call,
    };
    try std.testing.expectEqual(@as(u64, 42), ctx.readArg(0));
    try std.testing.expectEqual(@as(u64, 99), ctx.readArg(1));
    ctx.setResult(77);
    try std.testing.expectEqual(@as(u64, 77), state.result);
}
