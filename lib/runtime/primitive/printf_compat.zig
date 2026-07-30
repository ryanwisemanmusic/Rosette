const std = @import("std");
const types = @import("types.zig");

const PrimitiveContext = types.PrimitiveContext;
const Result = types.Result;
const SlotIndex = types.SlotIndex;

const VaList = struct {
    ctx: *const PrimitiveContext,
    address: u64,
    gp_offset: u32,
    fp_offset: u32,
    overflow_arg_area: u64,
    reg_save_area: u64,

    fn init(ctx: *const PrimitiveContext, address: u64) ?VaList {
        if (address == 0) return null;
        const bytes = ctx.readGuest(address, 24) orelse return null;
        return .{
            .ctx = ctx,
            .address = address,
            .gp_offset = std.mem.readInt(u32, bytes[0..4], .little),
            .fp_offset = std.mem.readInt(u32, bytes[4..8], .little),
            .overflow_arg_area = std.mem.readInt(u64, bytes[8..16], .little),
            .reg_save_area = std.mem.readInt(u64, bytes[16..24], .little),
        };
    }

    fn nextInteger(self: *VaList) ?u64 {
        const value_address: u64 = if (self.gp_offset <= 40) blk: {
            const address = std.math.add(u64, self.reg_save_area, self.gp_offset) catch return null;
            self.gp_offset += 8;
            break :blk address;
        } else blk: {
            const address = self.overflow_arg_area;
            self.overflow_arg_area = std.math.add(u64, self.overflow_arg_area, 8) catch return null;
            break :blk address;
        };
        const bytes = self.ctx.readGuest(value_address, 8) orelse return null;
        return std.mem.readInt(u64, bytes[0..8], .little);
    }

    fn nextFloat(self: *VaList) ?f64 {
        const value_address: u64 = if (self.fp_offset >= 48 and self.fp_offset <= 288) blk: {
            const address = std.math.add(u64, self.reg_save_area, self.fp_offset) catch return null;
            self.fp_offset += 16;
            break :blk address;
        } else blk: {
            const address = self.overflow_arg_area;
            self.overflow_arg_area = std.math.add(u64, self.overflow_arg_area, 8) catch return null;
            break :blk address;
        };
        const bytes = self.ctx.readGuest(value_address, 8) orelse return null;
        return @bitCast(std.mem.readInt(u64, bytes[0..8], .little));
    }

    fn commit(self: *const VaList) bool {
        var bytes: [24]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], self.gp_offset, .little);
        std.mem.writeInt(u32, bytes[4..8], self.fp_offset, .little);
        std.mem.writeInt(u64, bytes[8..16], self.overflow_arg_area, .little);
        std.mem.writeInt(u64, bytes[16..24], self.reg_save_area, .little);
        self.ctx.writeGuest(self.address, &bytes) orelse return false;
        return true;
    }
};

const Output = struct {
    ctx: *const PrimitiveContext,
    address: u64,
    capacity: usize,
    stored: usize = 0,
    total: usize = 0,
    failed: bool = false,

    fn append(self: *Output, bytes: []const u8) void {
        self.total +|= bytes.len;
        if (self.failed or self.stored >= self.capacity) return;
        const copy_size = @min(bytes.len, self.capacity - self.stored);
        if (copy_size == 0) return;
        const destination = std.math.add(u64, self.address, self.stored) catch {
            self.failed = true;
            return;
        };
        self.ctx.writeGuest(destination, bytes[0..copy_size]) orelse {
            self.failed = true;
            return;
        };
        self.stored += copy_size;
    }

    fn repeat(self: *Output, byte: u8, count: usize) void {
        var block: [32]u8 = undefined;
        @memset(&block, byte);
        var remaining = count;
        while (remaining != 0) {
            const chunk = @min(remaining, block.len);
            self.append(block[0..chunk]);
            remaining -= chunk;
        }
    }

    fn terminate(self: *Output, requested_size: u64) bool {
        if (requested_size == 0) return !self.failed;
        const terminator_address = std.math.add(u64, self.address, self.stored) catch return false;
        const terminator = [1]u8{0};
        self.ctx.writeGuest(terminator_address, &terminator) orelse return false;
        return !self.failed;
    }
};

const Flags = struct {
    left: bool = false,
    plus: bool = false,
    space: bool = false,
    alternate: bool = false,
    zero: bool = false,
};

const Length = enum {
    none,
    hh,
    h,
    l,
    ll,
    j,
    z,
    t,
    long_double,
};

/// Guest-aware implementation of the x86_64 Darwin `vsnprintf` ABI.
///
/// The fourth argument is a guest `__va_list_tag*`, so forwarding it to host
/// libc would be invalid: the contained pointers belong to Rosette's guest
/// address space. This formatter consumes the System V register-save/overflow
/// areas itself and supports the conversions used by Capstone, Xenia logging,
/// FFmpeg and MicroProfile.
pub fn vsnprintf(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const destination = ctx.readArg(0);
    const requested_size = ctx.readArg(1);
    const format_address = ctx.readArg(2);
    const va_list_address = ctx.readArg(3);

    if (requested_size != 0 and destination == 0) return .unsupported;
    const format = ctx.readCString(format_address) orelse return .unsupported;
    var arguments = VaList.init(ctx, va_list_address) orelse return .unsupported;
    const capacity_u64 = if (requested_size == 0) 0 else requested_size - 1;
    const capacity = std.math.cast(usize, capacity_u64) orelse std.math.maxInt(usize);
    var output = Output{
        .ctx = ctx,
        .address = destination,
        .capacity = capacity,
    };

    var index: usize = 0;
    while (index < format.len) {
        if (format[index] != '%') {
            const literal_start = index;
            while (index < format.len and format[index] != '%') : (index += 1) {}
            output.append(format[literal_start..index]);
            continue;
        }
        index += 1;
        if (index >= format.len) {
            output.append("%");
            break;
        }
        if (format[index] == '%') {
            output.append("%");
            index += 1;
            continue;
        }

        var flags = Flags{};
        while (index < format.len) {
            switch (format[index]) {
                '-' => flags.left = true,
                '+' => flags.plus = true,
                ' ' => flags.space = true,
                '#' => flags.alternate = true,
                '0' => flags.zero = true,
                '\'' => {},
                else => break,
            }
            index += 1;
        }

        var width: usize = 0;
        if (index < format.len and format[index] == '*') {
            const raw = arguments.nextInteger() orelse return .unsupported;
            const signed_width: i32 = @bitCast(@as(u32, @truncate(raw)));
            if (signed_width < 0) {
                flags.left = true;
                width = @intCast(-@as(i64, signed_width));
            } else {
                width = @intCast(signed_width);
            }
            index += 1;
        } else {
            while (index < format.len and std.ascii.isDigit(format[index])) : (index += 1) {
                width = width *| 10 +| (format[index] - '0');
            }
        }

        var precision: ?usize = null;
        if (index < format.len and format[index] == '.') {
            index += 1;
            if (index < format.len and format[index] == '*') {
                const raw = arguments.nextInteger() orelse return .unsupported;
                const signed_precision: i32 = @bitCast(@as(u32, @truncate(raw)));
                if (signed_precision >= 0) precision = @intCast(signed_precision);
                index += 1;
            } else {
                var parsed_precision: usize = 0;
                while (index < format.len and std.ascii.isDigit(format[index])) : (index += 1) {
                    parsed_precision = parsed_precision *| 10 +| (format[index] - '0');
                }
                precision = parsed_precision;
            }
        }

        var length: Length = .none;
        if (index < format.len) {
            switch (format[index]) {
                'h' => {
                    index += 1;
                    if (index < format.len and format[index] == 'h') {
                        length = .hh;
                        index += 1;
                    } else {
                        length = .h;
                    }
                },
                'l' => {
                    index += 1;
                    if (index < format.len and format[index] == 'l') {
                        length = .ll;
                        index += 1;
                    } else {
                        length = .l;
                    }
                },
                'j' => {
                    length = .j;
                    index += 1;
                },
                'z' => {
                    length = .z;
                    index += 1;
                },
                't' => {
                    length = .t;
                    index += 1;
                },
                'L' => {
                    length = .long_double;
                    index += 1;
                },
                else => {},
            }
        }
        if (index >= format.len) {
            output.append("%");
            break;
        }

        const conversion = format[index];
        index += 1;
        switch (conversion) {
            'd', 'i' => {
                const raw = arguments.nextInteger() orelse return .unsupported;
                const value: i64 = switch (length) {
                    .hh => @as(i8, @bitCast(@as(u8, @truncate(raw)))),
                    .h => @as(i16, @bitCast(@as(u16, @truncate(raw)))),
                    .none => @as(i32, @bitCast(@as(u32, @truncate(raw)))),
                    else => @bitCast(raw),
                };
                const negative = value < 0;
                const magnitude: u64 = if (negative)
                    (~@as(u64, @bitCast(value))) +% 1
                else
                    @bitCast(value);
                emitInteger(&output, magnitude, 10, false, negative, flags, width, precision, false);
            },
            'u', 'o', 'x', 'X' => {
                const raw = arguments.nextInteger() orelse return .unsupported;
                const value: u64 = switch (length) {
                    .hh => @as(u8, @truncate(raw)),
                    .h => @as(u16, @truncate(raw)),
                    .none => @as(u32, @truncate(raw)),
                    else => raw,
                };
                const base: u8 = if (conversion == 'o') 8 else if (conversion == 'u') 10 else 16;
                emitInteger(
                    &output,
                    value,
                    base,
                    conversion == 'X',
                    false,
                    flags,
                    width,
                    precision,
                    false,
                );
            },
            'p' => {
                const value = arguments.nextInteger() orelse return .unsupported;
                var pointer_flags = flags;
                pointer_flags.alternate = true;
                emitInteger(&output, value, 16, false, false, pointer_flags, width, precision, true);
            },
            'c' => {
                const value = arguments.nextInteger() orelse return .unsupported;
                const character = [1]u8{@truncate(value)};
                emitPadded(&output, &character, width, flags.left, ' ');
            },
            's' => {
                const string_address = arguments.nextInteger() orelse return .unsupported;
                const string = if (string_address == 0)
                    "(null)"
                else
                    ctx.readCString(string_address) orelse return .unsupported;
                const visible = if (precision) |limit| string[0..@min(limit, string.len)] else string;
                emitPadded(&output, visible, width, flags.left, ' ');
            },
            'f', 'F', 'e', 'E', 'g', 'G', 'a', 'A' => {
                // Capstone does not currently use floating conversions, but
                // Xenia/MicroProfile occasionally do. Decimal rendering keeps
                // the ABI correct and produces useful diagnostics even when a
                // requested scientific/hex presentation is approximated.
                const value = arguments.nextFloat() orelse return .unsupported;
                var float_buffer: [128]u8 = undefined;
                const rendered = std.fmt.bufPrint(&float_buffer, "{d}", .{value}) catch return .unsupported;
                emitPadded(&output, rendered, width, flags.left, if (flags.zero) '0' else ' ');
            },
            'n' => {
                const count_address = arguments.nextInteger() orelse return .unsupported;
                if (!writeCount(ctx, count_address, output.total, length)) return .unsupported;
            },
            'm' => output.append("Success"),
            else => {
                // Keep unknown extensions visible without consuming an
                // argument whose ABI class cannot be inferred.
                output.append("%");
                const unknown = [1]u8{conversion};
                output.append(&unknown);
            },
        }
    }

    if (!arguments.commit()) return .unsupported;
    if (!output.terminate(requested_size)) return .unsupported;
    const return_value: u64 = if (output.total > std.math.maxInt(i32))
        @bitCast(@as(i64, -1))
    else
        @intCast(output.total);
    ctx.setResult(return_value);
    return .handled;
}

fn emitPadded(output: *Output, value: []const u8, width: usize, left: bool, pad: u8) void {
    const padding = width -| value.len;
    if (!left) output.repeat(pad, padding);
    output.append(value);
    if (left) output.repeat(' ', padding);
}

fn emitInteger(
    output: *Output,
    value: u64,
    base: u8,
    uppercase: bool,
    negative: bool,
    flags: Flags,
    width: usize,
    precision: ?usize,
    force_pointer_prefix: bool,
) void {
    var digit_buffer: [64]u8 = undefined;
    var digit_start = digit_buffer.len;
    if (value != 0 or precision != 0) {
        var remaining = value;
        while (remaining != 0) {
            digit_start -= 1;
            const digit: u8 = @intCast(remaining % base);
            digit_buffer[digit_start] = if (digit < 10)
                '0' + digit
            else if (uppercase)
                'A' + digit - 10
            else
                'a' + digit - 10;
            remaining /= base;
        }
        if (digit_start == digit_buffer.len) {
            digit_start -= 1;
            digit_buffer[digit_start] = '0';
        }
    }
    const digits = digit_buffer[digit_start..];

    var prefix: [3]u8 = undefined;
    var prefix_len: usize = 0;
    if (negative) {
        prefix[0] = '-';
        prefix_len = 1;
    } else if (flags.plus) {
        prefix[0] = '+';
        prefix_len = 1;
    } else if (flags.space) {
        prefix[0] = ' ';
        prefix_len = 1;
    }
    if ((flags.alternate or force_pointer_prefix) and base == 16 and (value != 0 or force_pointer_prefix)) {
        prefix[prefix_len] = '0';
        prefix[prefix_len + 1] = if (uppercase) 'X' else 'x';
        prefix_len += 2;
    } else if (flags.alternate and base == 8 and (digits.len == 0 or digits[0] != '0')) {
        prefix[prefix_len] = '0';
        prefix_len += 1;
    }

    const precision_zeros = if (precision) |minimum| minimum -| digits.len else 0;
    const value_width = prefix_len + precision_zeros + digits.len;
    const width_padding = width -| value_width;
    const zero_width_padding = flags.zero and !flags.left and precision == null;

    if (!flags.left and !zero_width_padding) output.repeat(' ', width_padding);
    output.append(prefix[0..prefix_len]);
    if (zero_width_padding) output.repeat('0', width_padding);
    output.repeat('0', precision_zeros);
    output.append(digits);
    if (flags.left) output.repeat(' ', width_padding);
}

fn writeCount(ctx: *const PrimitiveContext, address: u64, count: usize, length: Length) bool {
    switch (length) {
        .hh => {
            const bytes = [1]u8{@truncate(count)};
            ctx.writeGuest(address, &bytes) orelse return false;
        },
        .h => {
            var bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &bytes, @truncate(count), .little);
            ctx.writeGuest(address, &bytes) orelse return false;
        },
        .l, .ll, .j, .z, .t => {
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, count, .little);
            ctx.writeGuest(address, &bytes) orelse return false;
        },
        else => {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, @truncate(count), .little);
            ctx.writeGuest(address, &bytes) orelse return false;
        },
    }
    return true;
}

test "vsnprintf consumes a guest SysV va_list and terminates output" {
    const TestState = struct {
        args: [6]u64 = .{ 16, 64, 128, 384, 0, 0 },
        result: u64 = 0,
        memory: [768]u8 = [_]u8{0} ** 768,

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
        fn readCString(ptr: *const anyopaque, address: u64) ?[]const u8 {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            const start = std.math.cast(usize, address) orelse return null;
            if (start >= self.memory.len) return null;
            return std.mem.sliceTo(self.memory[start..], 0);
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
    const format = "%s %d 0x%08x %%";
    @memcpy(state.memory[128 .. 128 + format.len], format);
    state.memory[128 + format.len] = 0;
    @memcpy(state.memory[256..260], "halo");
    state.memory[260] = 0;

    std.mem.writeInt(u32, state.memory[384..388], 0, .little);
    std.mem.writeInt(u32, state.memory[388..392], 48, .little);
    std.mem.writeInt(u64, state.memory[392..400], 640, .little);
    std.mem.writeInt(u64, state.memory[400..408], 512, .little);
    std.mem.writeInt(u64, state.memory[512..520], 256, .little);
    std.mem.writeInt(u64, state.memory[520..528], @bitCast(@as(i64, -7)), .little);
    std.mem.writeInt(u64, state.memory[528..536], 42, .little);

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

    try std.testing.expectEqual(Result.handled, vsnprintf(0, &ctx));
    const expected = "halo -7 0x0000002a %";
    try std.testing.expectEqualStrings(expected, std.mem.sliceTo(state.memory[16..], 0));
    try std.testing.expectEqual(@as(u64, expected.len), state.result);
    try std.testing.expectEqual(@as(u32, 24), std.mem.readInt(u32, state.memory[384..388], .little));
}

test "vsnprintf reports untruncated length" {
    const TestState = struct {
        args: [6]u64 = .{ 8, 5, 32, 64, 0, 0 },
        result: u64 = 0,
        memory: [128]u8 = [_]u8{0} ** 128,
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
            const start: usize = @intCast(address);
            if (start + size > self.memory.len) return null;
            return self.memory[start .. start + size];
        }
        fn writeGuest(ptr: *anyopaque, address: u64, data: []const u8) ?void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            const start: usize = @intCast(address);
            if (start + data.len > self.memory.len) return null;
            @memcpy(self.memory[start .. start + data.len], data);
            return {};
        }
        fn readCString(ptr: *const anyopaque, address: u64) ?[]const u8 {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            const start: usize = @intCast(address);
            return std.mem.sliceTo(self.memory[start..], 0);
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
    @memcpy(state.memory[32..38], "abcdef");
    state.memory[38] = 0;
    std.mem.writeInt(u32, state.memory[64..68], 48, .little);
    std.mem.writeInt(u32, state.memory[68..72], 48, .little);
    std.mem.writeInt(u64, state.memory[72..80], 96, .little);
    std.mem.writeInt(u64, state.memory[80..88], 96, .little);
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
    try std.testing.expectEqual(Result.handled, vsnprintf(0, &ctx));
    try std.testing.expectEqualStrings("abcd", std.mem.sliceTo(state.memory[8..], 0));
    try std.testing.expectEqual(@as(u64, 6), state.result);
}
