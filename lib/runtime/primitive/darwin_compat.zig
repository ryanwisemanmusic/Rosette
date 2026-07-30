const std = @import("std");
const types = @import("types.zig");

const PrimitiveContext = types.PrimitiveContext;
const Result = types.Result;
const SlotIndex = types.SlotIndex;

const CTL_KERN: i32 = 1;
const CTL_HW: i32 = 6;
const KERN_PROC: i32 = 14;
const KERN_PROC_PID: i32 = 1;
const HW_NCPU: i32 = 3;
const HW_BYTEORDER: i32 = 4;
const HW_PAGESIZE: i32 = 7;
const HW_MEMSIZE: i32 = 24;
const HW_AVAILCPU: i32 = 25;

const virtual_cpu_count: u32 = 8;
const virtual_page_size: u32 = 4096;
const virtual_memory_size: u64 = 8 * 1024 * 1024 * 1024;
const kinfo_proc_size: usize = 0x288;

/// A deterministic Darwin sysctl model for queries made by Xenia and FFmpeg.
/// It intentionally exposes the same eight-logical-CPU geometry as Rosette's
/// Xenia CPUID profile, rather than leaking a potentially different host CPU.
pub fn sysctl(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const mib_address = ctx.readArg(0);
    const mib_count_u64 = ctx.readArg(1);
    const old_value = ctx.readArg(2);
    const old_length_address = ctx.readArg(3);
    const new_value = ctx.readArg(4);
    const new_length = ctx.readArg(5);

    if (mib_address == 0 or old_length_address == 0 or new_value != 0 or new_length != 0) {
        setSignedResult(ctx, -1);
        return .handled;
    }
    const mib_count = std.math.cast(usize, mib_count_u64) orelse {
        setSignedResult(ctx, -1);
        return .handled;
    };
    if (mib_count == 0 or mib_count > 4) {
        setSignedResult(ctx, -1);
        return .handled;
    }

    const mib_bytes = ctx.readGuest(mib_address, mib_count * @sizeOf(i32)) orelse return .unsupported;
    var mib: [4]i32 = .{0} ** 4;
    for (0..mib_count) |index| {
        mib[index] = @bitCast(std.mem.readInt(
            u32,
            mib_bytes[index * 4 ..][0..4],
            .little,
        ));
    }

    var scalar: [8]u8 = .{0} ** 8;
    var required_size: usize = 0;
    var zero_kinfo = false;

    if (mib_count == 2 and mib[0] == CTL_HW) {
        switch (mib[1]) {
            HW_NCPU, HW_AVAILCPU => {
                std.mem.writeInt(u32, scalar[0..4], virtual_cpu_count, .little);
                required_size = 4;
            },
            HW_BYTEORDER => {
                std.mem.writeInt(u32, scalar[0..4], 1234, .little);
                required_size = 4;
            },
            HW_PAGESIZE => {
                std.mem.writeInt(u32, scalar[0..4], virtual_page_size, .little);
                required_size = 4;
            },
            HW_MEMSIZE => {
                std.mem.writeInt(u64, &scalar, virtual_memory_size, .little);
                required_size = 8;
            },
            else => {
                setSignedResult(ctx, -1);
                return .handled;
            },
        }
    } else if (mib_count == 4 and
        mib[0] == CTL_KERN and mib[1] == KERN_PROC and mib[2] == KERN_PROC_PID)
    {
        // IsDebuggerAttached reads P_TRACED from kinfo_proc. A zero-filled
        // structure models a live process that is not being debugged.
        required_size = kinfo_proc_size;
        zero_kinfo = true;
    } else {
        setSignedResult(ctx, -1);
        return .handled;
    }

    const old_length_bytes = ctx.readGuest(old_length_address, 8) orelse return .unsupported;
    const supplied_size = std.mem.readInt(u64, old_length_bytes[0..8], .little);
    writeU64(ctx, old_length_address, required_size) orelse return .unsupported;

    // A null output pointer is the standard size-query form.
    if (old_value == 0) {
        ctx.setResult(0);
        return .handled;
    }
    if (supplied_size < required_size) {
        setSignedResult(ctx, -1);
        return .handled;
    }

    if (zero_kinfo) {
        var zeros: [64]u8 = .{0} ** 64;
        var offset: usize = 0;
        while (offset < required_size) {
            const chunk_size = @min(zeros.len, required_size - offset);
            ctx.writeGuest(old_value + offset, zeros[0..chunk_size]) orelse return .unsupported;
            offset += chunk_size;
        }
    } else {
        ctx.writeGuest(old_value, scalar[0..required_size]) orelse return .unsupported;
    }

    ctx.setResult(0);
    return .handled;
}

fn writeU64(ctx: *const PrimitiveContext, address: u64, value: u64) ?void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    return ctx.writeGuest(address, &bytes);
}

fn setSignedResult(ctx: *const PrimitiveContext, value: i32) void {
    ctx.setResult(@bitCast(@as(i64, value)));
}

test "sysctl returns the virtual CPU count" {
    const TestState = struct {
        args: [6]u64 = .{ 16, 2, 32, 48, 0, 0 },
        result: u64 = std.math.maxInt(u64),
        memory: [64]u8 = [_]u8{0} ** 64,

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
            if (start + size > self.memory.len) return null;
            return self.memory[start .. start + size];
        }
        fn writeGuest(ptr: *anyopaque, address: u64, data: []const u8) ?void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            const start = std.math.cast(usize, address) orelse return null;
            if (start + data.len > self.memory.len) return null;
            @memcpy(self.memory[start .. start + data.len], data);
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

    var state = TestState{};
    std.mem.writeInt(u32, state.memory[16..20], CTL_HW, .little);
    std.mem.writeInt(u32, state.memory[20..24], HW_AVAILCPU, .little);
    std.mem.writeInt(u64, state.memory[48..56], 4, .little);
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

    try std.testing.expectEqual(Result.handled, sysctl(0, &ctx));
    try std.testing.expectEqual(@as(u64, 0), state.result);
    try std.testing.expectEqual(virtual_cpu_count, std.mem.readInt(u32, state.memory[32..36], .little));
    try std.testing.expectEqual(@as(u64, 4), std.mem.readInt(u64, state.memory[48..56], .little));
}
