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

pub fn llabs(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const val = ctx.readArg(0);
    // Branchless abs for two's complement: mask = -(val >> 63)
    // If val >= 0: mask = 0, result = (val ^ 0) - 0 = val
    // If val < 0:  mask = all_ones, result = (~val) - (-1) = ~val + 1 = -val
    const mask = 0 -% (val >> 63);
    const result = (val ^ mask) -% mask;
    ctx.setResult(result);
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

/// Implements `std::to_string(int)` — formats an int as a decimal string
/// and writes a libc++ SSO std::string at the hidden pointer in rdi.
/// ABI: rdi = output string ptr, rsi = int value.
pub fn to_string(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const output_ptr = ctx.readArg(0); // hidden pointer for return string
    const raw_value = ctx.readArg(1); // int value as u64
    const value: i32 = @bitCast(@as(u32, @truncate(raw_value)));

    // Format the integer as a decimal string (i32 max = 11 chars including '-').
    // Always fits in SSO (max 22 chars).
    var buf: [12]u8 = undefined;
    const len = formatIntDecimal(value, &buf);

    // Write SSO libc++ string at output_ptr.
    // Layout: byte 0 = (length << 1), bytes 1..len = data, byte 1+len = 0, rest = 0.
    var string_buf: [24]u8 = .{0} ** 24;
    string_buf[0] = @as(u8, @intCast(len << 1));
    @memcpy(string_buf[1 .. 1 + len], buf[0..len]);
    string_buf[1 + len] = 0;

    ctx.writeGuest(output_ptr, &string_buf) orelse return .unsupported;
    return .handled_void;
}

/// Formats an i32 as a decimal string. Returns the string length.
fn formatIntDecimal(value: i32, buf: []u8) usize {
    if (value == std.math.minInt(i32)) {
        @memcpy(buf[0..11], "-2147483648");
        return 11;
    }

    var v = value;
    var i: usize = 0;

    if (v < 0) {
        buf[i] = '-';
        i += 1;
        v = -v;
    }

    if (v == 0) {
        buf[i] = '0';
        return i + 1;
    }

    const digit_start = i;
    while (v > 0) : (v = @divTrunc(v, 10)) {
        buf[i] = @as(u8, @intCast(@rem(v, 10))) + '0';
        i += 1;
    }

    std.mem.reverse(u8, buf[digit_start..i]);
    return i;
}

/// Implements `std::basic_ostream::put(char_type)` — writes a single
/// character to the output stream.
/// ABI: rdi = this (ostream), rsi = char value (sign-extended). Returns *ostream.
pub fn ostreamPut(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const character = @as(u8, @truncate(ctx.readArg(1))); // rsi = char
    var buf: [1]u8 = .{character};
    _ = std.c.write(1, &buf, 1);

    ctx.setResult(ctx.readArg(0)); // return ostream pointer (this)
    return .handled;
}

/// Implements `std::basic_ostream::write(const char_type*, streamsize)` —
/// writes data to the output stream. For now, routes content to host stdout
/// so the guest sees its output.
/// ABI: rdi = this (ostream), rsi = data ptr, rdx = length. Returns *ostream.
pub fn ostreamWrite(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const data_ptr = ctx.readArg(1);
    const length = ctx.readArg(2);

    if (length == 0) {
        ctx.setResult(ctx.readArg(0));
        return .handled;
    }

    const data = ctx.readGuest(data_ptr, @as(usize, @intCast(length))) orelse return .unsupported;
    _ = std.c.write(1, data.ptr, @as(usize, @intCast(length)));

    ctx.setResult(ctx.readArg(0));
    return .handled;
}

/// Implements `qsort` — sorts an array in guest memory using insertion sort.
/// Calls the guest comparison function via `callGuestFn` for each pair.
/// ABI: rdi = base, rsi = nmemb, rdx = size, rcx = compar.
pub fn qsort(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const base = ctx.readArg(0);
    const nmemb = ctx.readArg(1);
    const size = ctx.readArg(2);
    const compar = ctx.readArg(3);

    if (nmemb <= 1 or size == 0) return .handled_void;
    if (base == 0 or compar == 0) return .unsupported;

    // For large sizes (unlikely for qsort), fall back to the legacy import path.
    if (size > 4096) return .unsupported;
    const element_size: usize = @intCast(size);

    // Validate the complete range once. Besides rejecting integer overflow, this
    // prevents a partially completed sort if a later element is not guest-backed.
    const byte_count = std.math.mul(u64, nmemb, size) catch return .unsupported;
    _ = std.math.add(u64, base, byte_count) catch return .unsupported;
    _ = ctx.readGuest(base, @intCast(byte_count)) orelse return .unsupported;

    // Guest slices alias the emulated address space. Keep the right-hand element
    // in independent storage before either destination is changed.
    var swap_storage: [4096]u8 = undefined;

    var i: u64 = 1;
    while (i < nmemb) : (i += 1) {
        var j = i;
        while (j > 0) : (j -= 1) {
            const a_ptr = base + j * size;
            const b_ptr = base + (j - 1) * size;

            // Move the current element left when compar(current, previous) < 0.
            // A C comparator returns int, so only the signed low 32 bits are
            // authoritative even when writing EAX has cleared RAX's upper half.
            const result = ctx.callGuest(compar, .{ a_ptr, b_ptr, 0, 0, 0, 0 });
            const cmp: i32 = @bitCast(@as(u32, @truncate(result)));

            if (cmp < 0) {
                // Swap elements at j and j-1.
                const a_data = ctx.readGuest(a_ptr, element_size) orelse return .unsupported;
                const b_data = ctx.readGuest(b_ptr, element_size) orelse return .unsupported;
                @memcpy(swap_storage[0..element_size], b_data);
                ctx.writeGuest(b_ptr, a_data) orelse return .unsupported;
                ctx.writeGuest(a_ptr, swap_storage[0..element_size]) orelse return .unsupported;
            } else {
                break; // Already in order, inner loop done
            }
        }
    }

    return .handled_void;
}

/// Implements `std::terminate()` — called by `__clang_call_terminate` when a
/// `noexcept` violation occurs during C++ exception stack unwinding.
/// ABI: no arguments. This function never returns — it calls host `abort()`.
pub fn stdTerminate(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    _ = ctx;
    const msg = "std::terminate() called from guest code; aborting\n";
    _ = std.c.write(2, msg.ptr, msg.len);
    std.c.abort();
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
        .callGuestFn = struct {
            fn call(_: *anyopaque, _: u64, _: [6]u64) u64 {
                return 0;
            }
        }.call,
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
        .callGuestFn = struct {
            fn call(_: *anyopaque, _: u64, _: [6]u64) u64 {
                return 0;
            }
        }.call,
    };

    try std.testing.expectEqual(Result.handled_void, cxaGuardRelease(0, &ctx));
    const val = std.mem.readInt(u64, state.memory[0..8], .little);
    try std.testing.expectEqual(@as(u64, 1), val);
}

test "handlers: qsort honors signed 32-bit comparator and preserves elements" {
    const TestState = struct {
        args: [6]u64 = .{0} ** 6,
        memory: [64]u8 = [_]u8{0} ** 64,

        fn readArg(ptr: *anyopaque, index: u8) u64 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return if (index < 6) self.args[index] else 0;
        }
        fn setResult(_: *anyopaque, _: u64) void {}
        fn readGuest(ptr: *const anyopaque, address: u64, size_bytes: usize) ?[]const u8 {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            const start: usize = @intCast(address);
            const end = std.math.add(usize, start, size_bytes) catch return null;
            if (end > self.memory.len) return null;
            return self.memory[start..end];
        }
        fn writeGuest(ptr: *anyopaque, address: u64, data: []const u8) ?void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            const start: usize = @intCast(address);
            const end = std.math.add(usize, start, data.len) catch return null;
            if (end > self.memory.len) return null;
            @memcpy(self.memory[start..end], data);
            return {};
        }
        fn readCString(_: *const anyopaque, _: u64) ?[]const u8 {
            return null;
        }
        fn callGuest(ptr: *anyopaque, _: u64, call_args: [6]u64) u64 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            const lhs_start: usize = @intCast(call_args[0]);
            const rhs_start: usize = @intCast(call_args[1]);
            const lhs = std.mem.readInt(u32, self.memory[lhs_start..][0..4], .little);
            const rhs = std.mem.readInt(u32, self.memory[rhs_start..][0..4], .little);
            const comparison: i32 = if (lhs < rhs) -1 else if (lhs > rhs) 1 else 0;

            // Model the zero-extension caused by a guest comparator returning
            // through EAX. The bridge must still interpret 0x00000000FFFFFFFF
            // as the signed int value -1.
            return @as(u32, @bitCast(comparison));
        }
    };

    var state = TestState{};
    const input = [_]u32{ 5, 1, 4, 2, 3 };
    for (input, 0..) |value, index| {
        std.mem.writeInt(u32, state.memory[8 + index * 4 ..][0..4], value, .little);
    }
    state.args = .{ 8, input.len, @sizeOf(u32), 0x1234, 0, 0 };

    const ctx = PrimitiveContext{
        .ptr = &state,
        .readArgFn = TestState.readArg,
        .setResultFn = TestState.setResult,
        .readGuestFn = TestState.readGuest,
        .writeGuestFn = TestState.writeGuest,
        .readCStringFn = TestState.readCString,
        .callGuestFn = TestState.callGuest,
    };

    try std.testing.expectEqual(Result.handled_void, qsort(0, &ctx));
    const expected = [_]u32{ 1, 2, 3, 4, 5 };
    for (expected, 0..) |value, index| {
        const actual = std.mem.readInt(u32, state.memory[8 + index * 4 ..][0..4], .little);
        try std.testing.expectEqual(value, actual);
    }
}
