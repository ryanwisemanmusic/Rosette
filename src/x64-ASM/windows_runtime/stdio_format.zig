//! Bounded implementation of the narrow UCRT `__stdio_common_vsprintf` ABI.
//!
//! This keeps guest variadic arguments in guest memory and writes only to a
//! validated guest buffer. It is shared by ordinary PE programs, including
//! SDL-based applications that assemble asset paths through `snprintf`.

const std = @import("std");

const max_buffer_bytes: usize = 1024 * 1024;
const max_format_bytes: usize = 64 * 1024;

pub fn handle(comptime api: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (!std.mem.eql(u8, name, "__stdio_common_vsprintf")) return false;
    const destination = api._arg(state, 1, direct_return_rip);
    const capacity = api._arg(state, 2, direct_return_rip);
    const format_address = api._arg(state, 3, direct_return_rip);
    const varargs = api._arg(state, 5, direct_return_rip);

    var format_storage: [max_format_bytes]u8 = undefined;
    const format = readFormat(state, format_address, &format_storage) orelse
        return fail(api, state, destination, capacity, direct_return_rip);

    const required_capacity = capacity -| 1;
    const output_capacity: usize = @intCast(@min(required_capacity, max_buffer_bytes));
    const scratch = std.heap.page_allocator.alloc(u8, @max(output_capacity, 1)) catch
        return fail(api, state, destination, capacity, direct_return_rip);
    defer std.heap.page_allocator.free(scratch);

    const output = api._formatWindowsV(state, format, varargs, scratch[0..output_capacity]) orelse
        return fail(api, state, destination, capacity, direct_return_rip);

    const write_count_u64 = @min(@as(u64, @intCast(output)), required_capacity);
    if (write_count_u64 > max_buffer_bytes) {
        return fail(api, state, destination, capacity, direct_return_rip);
    }
    const write_count: usize = @intCast(write_count_u64);

    if (capacity != 0) {
        if (destination == 0) return fail(api, state, destination, capacity, direct_return_rip);
        const target = state.guestMemory(destination, write_count_u64 + 1) orelse
            return fail(api, state, destination, capacity, direct_return_rip);
        if (write_count != 0) @memcpy(target[0..write_count], scratch[0..write_count]);
        target[write_count] = 0;
    }

    api._guestStateField(state, "regs").*.rax = @intCast(output);
    api._finish(state, direct_return_rip);
    return true;
}

fn readFormat(state: anytype, address: u64, storage: []u8) ?[]const u8 {
    if (address == 0) return null;
    for (storage, 0..) |*byte, index| {
        const source = state.guestMemoryConst(address +| index, 1) orelse return null;
        if (source[0] == 0) return storage[0..index];
        byte.* = source[0];
    }
    return null;
}

fn fail(api: anytype, state: anytype, destination: u64, capacity: u64, direct_return_rip: ?u64) bool {
    if (capacity != 0 and destination != 0) {
        if (state.guestMemory(destination, 1)) |first| first[0] = 0;
    }
    api._guestStateField(state, "regs").*.rax = std.math.maxInt(u32); // EOF / -1 as a 32-bit CRT int
    api._finish(state, direct_return_rip);
    return true;
}

test "UCRT vsprintf formats guest arguments and terminates guest output" {
    const MockState = struct {
        regs: Registers = .{ .rsp = 0x1200 },
        bytes: [8192]u8 = @splat(0),

        const Registers = struct { rax: u64 = 0, rcx: u64 = 0, rdx: u64 = 0, r8: u64 = 0, r9: u64 = 0, rsp: u64 = 0, rip: u64 = 0 };

        pub fn guestMemory(self: *@This(), address: u64, count: u64) ?[]u8 {
            const offset = address -| 0x1000;
            if (address < 0x1000 or offset > self.bytes.len or count > self.bytes.len - offset) return null;
            return self.bytes[@intCast(offset)..][0..@intCast(count)];
        }

        pub fn guestMemoryConst(self: *const @This(), address: u64, count: u64) ?[]const u8 {
            const offset = address -| 0x1000;
            if (address < 0x1000 or offset > self.bytes.len or count > self.bytes.len - offset) return null;
            return self.bytes[@intCast(offset)..][0..@intCast(count)];
        }

        pub fn read64(self: *const @This(), address: u64) u64 {
            const bytes = self.guestMemoryConst(address, 8) orelse return 0;
            return std.mem.readInt(u64, bytes[0..8], .little);
        }
    };

    const Api = struct {
        pub fn argument(state: anytype, index: usize, direct_return_rip: ?u64) u64 {
            return switch (index) {
                0 => state.regs.rcx,
                1 => state.regs.rdx,
                2 => state.regs.r8,
                3 => state.regs.r9,
                else => state.read64(state.regs.rsp + (if (direct_return_rip != null) @as(u64, 32) else 40) + (index - 4) * 8),
            };
        }

        pub fn finish(state: anytype, direct_return_rip: ?u64) void {
            state.regs.rip = direct_return_rip orelse state.read64(state.regs.rsp);
        }

        pub const _arg = argument;
        pub const _finish = finish;
        pub const _formatWindowsV = @import("sdl2_format.zig").formatWindowsV;
    };

    var state: MockState = .{};
    const memory = &state.bytes;
    @memcpy(memory[0x100..0x10A], "path=%s:%u");
    memory[0x10A] = 0;
    @memcpy(memory[0x120..0x129], "asset.dat");
    memory[0x129] = 0;
    std.mem.writeInt(u64, memory[0x200..0x208], 0x1120, .little);
    std.mem.writeInt(u64, memory[0x208..0x210], 17, .little);
    state.regs.rcx = 0;
    state.regs.rdx = 0x1300;
    state.regs.r8 = 64;
    state.regs.r9 = 0x1100;
    state.regs.rsp = 0x1200;
    std.mem.writeInt(u64, memory[0x220..0x228], 0, .little); // locale (arg 4)
    std.mem.writeInt(u64, memory[0x228..0x230], 0x1200, .little); // va_list (arg 5)

    try std.testing.expect(handle(Api, &state, "__stdio_common_vsprintf", 0x5000));
    try std.testing.expectEqual(@as(u64, 17), state.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x5000), state.regs.rip);
    try std.testing.expectEqualStrings("path=asset.dat:17", state.guestMemoryConst(0x1300, 17).?);
    try std.testing.expectEqual(@as(u8, 0), state.guestMemoryConst(0x1311, 1).?[0]);
}

test "UCRT vsprintf follows snprintf truncation and rejects invalid guest buffers" {
    const State = struct {
        regs: struct { rax: u64 = 0, rcx: u64 = 0, rdx: u64 = 0, r8: u64 = 0, r9: u64 = 0, rsp: u64 = 0, rip: u64 = 0 } = .{},
        bytes: [128]u8 = @splat(0),
        pub fn guestMemory(self: *@This(), address: u64, count: u64) ?[]u8 {
            const offset = address -| 0x1000;
            if (address < 0x1000 or offset > self.bytes.len or count > self.bytes.len - offset) return null;
            return self.bytes[@intCast(offset)..][0..@intCast(count)];
        }
        pub fn guestMemoryConst(self: *const @This(), address: u64, count: u64) ?[]const u8 {
            const offset = address -| 0x1000;
            if (address < 0x1000 or offset > self.bytes.len or count > self.bytes.len - offset) return null;
            return self.bytes[@intCast(offset)..][0..@intCast(count)];
        }
        pub fn read64(self: *const @This(), address: u64) u64 {
            const bytes = self.guestMemoryConst(address, 8) orelse return 0;
            return std.mem.readInt(u64, bytes[0..8], .little);
        }
    };
    const Api = struct {
        pub fn argument(state: anytype, index: usize, direct_return_rip: ?u64) u64 {
            return switch (index) {
                1 => state.regs.rdx,
                2 => state.regs.r8,
                3 => state.regs.r9,
                else => state.read64(state.regs.rsp + (if (direct_return_rip != null) @as(u64, 32) else 40) + (index - 4) * 8),
            };
        }
        pub fn finish(state: anytype, direct_return_rip: ?u64) void {
            state.regs.rip = direct_return_rip orelse 0;
        }
        pub const _arg = argument;
        pub const _finish = finish;
        pub const _formatWindowsV = @import("sdl2_format.zig").formatWindowsV;
    };

    var state: State = .{};
    @memcpy(state.bytes[0x10..0x15], "hello");
    state.bytes[0x15] = 0;
    state.regs.rdx = 0x1040;
    state.regs.r8 = 4;
    state.regs.r9 = 0x1010;
    state.regs.rsp = 0x1000;
    std.mem.writeInt(u64, state.bytes[0x20..0x28], 0, .little);
    std.mem.writeInt(u64, state.bytes[0x28..0x30], 0x1020, .little);
    try std.testing.expect(handle(Api, &state, "__stdio_common_vsprintf", 1));
    try std.testing.expectEqual(@as(u64, 5), state.regs.rax);
    try std.testing.expectEqualStrings("hel", state.guestMemoryConst(0x1040, 3).?);
    try std.testing.expectEqual(@as(u8, 0), state.guestMemoryConst(0x1043, 1).?[0]);

    state.regs.rdx = 0;
    state.regs.r8 = 4;
    state.regs.rax = 0;
    try std.testing.expect(handle(Api, &state, "__stdio_common_vsprintf", 2));
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u32)), state.regs.rax);
}
