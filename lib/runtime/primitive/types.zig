const std = @import("std");

pub const SlotIndex = u32;

/// Result of a dladdr lookup, with guest-accessible addresses for strings
/// and pointers. The four fields mirror Dl_info from <dlfcn.h>.
pub const DladdrInfo = struct {
    /// True if the address was resolved to a symbol
    found: bool = false,
    /// Guest vaddr of the image path string, or 0
    dli_fname: u64 = 0,
    /// Guest vaddr of the image base (the Mach-O header)
    dli_fbase: u64 = 0,
    /// Guest vaddr of the nearest symbol name string, or 0
    dli_sname: u64 = 0,
    /// Guest vaddr of the nearest symbol
    dli_saddr: u64 = 0,
};

pub const Result = enum(u8) {
    handled,
    handled_void,
    unsupported,
    fallback,
};

fn unavailablePthreadMachThreadId(_: *anyopaque, _: u64) u64 {
    return 0;
}

fn unavailableDladdrResolve(_: *anyopaque, _: u64) DladdrInfo {
    return .{};
}

pub const Handler = *const fn (slot: SlotIndex, ctx: *const PrimitiveContext) Result;

pub const PrimitiveContext = struct {
    ptr: *anyopaque,
    readArgFn: *const fn (ptr: *anyopaque, index: u8) u64,
    setResultFn: *const fn (ptr: *anyopaque, value: u64) void,
    readGuestFn: *const fn (ptr: *const anyopaque, address: u64, size: usize) ?[]const u8,
    writeGuestFn: *const fn (ptr: *anyopaque, address: u64, data: []const u8) ?void,
    readCStringFn: *const fn (ptr: *const anyopaque, address: u64) ?[]const u8,
    /// Perform an overlap-safe move entirely within guest memory. Runtime
    /// integrations should provide this so bulk moves also pass through their
    /// memory-mutation tracking. Tests and small embedders may omit it; the
    /// bytewise fallback in `moveGuest` preserves memmove ordering.
    moveGuestFn: ?*const fn (ptr: *anyopaque, destination: u64, source: u64, count: usize) bool = null,
    /// Call a guest function synchronously and return its rax value.
    /// The guest function is called with up to 6 integer arguments (rdi–r9)
    /// and must follow the System V AMD64 ABI (caller must not be noreturn).
    /// Returns 0 if the call cannot be completed.
    callGuestFn: *const fn (ptr: *anyopaque, fn_address: u64, args: [6]u64) u64,

    /// Resolve a pthread handle to its Mach thread ID.
    /// Returns the mach_port_t for the given pthread handle, or 0 if unknown.
    pthreadMachThreadIdFn: *const fn (ptr: *anyopaque, handle: u64) u64 = unavailablePthreadMachThreadId,

    /// Resolve an address to a Dl_info (dladdr) result.
    /// Returns the DladdrInfo with the resolved symbol information.
    /// The caller is responsible for writing the Dl_info struct to guest memory.
    dladdrResolveFn: *const fn (ptr: *anyopaque, address: u64) DladdrInfo = unavailableDladdrResolve,

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

    pub fn moveGuest(self: *const PrimitiveContext, destination: u64, source: u64, count: usize) bool {
        if (self.moveGuestFn) |move_fn| {
            return move_fn(self.ptr, destination, source, count);
        }
        if (count == 0 or destination == source) return true;

        // Use single-byte transfers so readGuest and writeGuest slices never
        // overlap. The direction is the defining semantic difference between
        // memmove and memcpy.
        if (destination > source and destination - source < count) {
            var remaining = count;
            while (remaining != 0) {
                remaining -= 1;
                const byte = self.readGuest(source + remaining, 1) orelse return false;
                const value = [1]u8{byte[0]};
                self.writeGuest(destination + remaining, &value) orelse return false;
            }
        } else {
            var index: usize = 0;
            while (index < count) : (index += 1) {
                const byte = self.readGuest(source + index, 1) orelse return false;
                const value = [1]u8{byte[0]};
                self.writeGuest(destination + index, &value) orelse return false;
            }
        }
        return true;
    }

    pub fn callGuest(self: *const PrimitiveContext, fn_address: u64, args: [6]u64) u64 {
        return self.callGuestFn(self.ptr, fn_address, args);
    }

    pub fn pthreadMachThreadId(self: *const PrimitiveContext, handle: u64) u64 {
        return self.pthreadMachThreadIdFn(self.ptr, handle);
    }

    pub fn dladdrResolve(self: *const PrimitiveContext, address: u64) DladdrInfo {
        return self.dladdrResolveFn(self.ptr, address);
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
        .pthreadMachThreadIdFn = struct {
            fn lookup(_: *anyopaque, _: u64) u64 {
                return 0;
            }
        }.lookup,
        .dladdrResolveFn = struct {
            fn resolve(_: *anyopaque, _: u64) DladdrInfo {
                return .{};
            }
        }.resolve,
    };
    try std.testing.expectEqual(@as(u64, 42), ctx.readArg(0));
    try std.testing.expectEqual(@as(u64, 99), ctx.readArg(1));
    ctx.setResult(77);
    try std.testing.expectEqual(@as(u64, 77), state.result);
}
