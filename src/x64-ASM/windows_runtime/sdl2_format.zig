//! Bounded formatting for SDL's Win64 variadic imports.
//!
//! A PE guest's `va_list` is a guest pointer to eight-byte argument slots. It
//! must be read from guest memory rather than passed to a host `printf` call.
//! This formatter implements the string and integer conversions used by SDL
//! diagnostics and treats invalid guest pointers as a formatting failure.

const std = @import("std");

const Writer = struct {
    output: []u8,
    count: usize = 0,

    fn byte(self: *Writer, value: u8) void {
        if (self.count < self.output.len) self.output[self.count] = value;
        self.count +|= 1;
    }

    fn bytes(self: *Writer, value: []const u8) void {
        for (value) |character| self.byte(character);
    }

    fn repeat(self: *Writer, value: u8, amount: usize) void {
        for (0..amount) |_| self.byte(value);
    }
};

const Length = enum { int, long };

/// Formats a Win64 guest varargs list into `output`. The returned length is
/// the full, untruncated output size, matching `vsnprintf`'s return contract.
pub fn formatWindowsV(state: anytype, format: []const u8, varargs: u64, output: []u8) ?usize {
    var writer: Writer = .{ .output = output };
    var arguments = varargs;
    var index: usize = 0;

    while (index < format.len) {
        if (format[index] != '%') {
            writer.byte(format[index]);
            index += 1;
            continue;
        }
        index += 1;
        if (index == format.len) {
            writer.byte('%');
            break;
        }
        if (format[index] == '%') {
            writer.byte('%');
            index += 1;
            continue;
        }

        var left = false;
        var plus = false;
        var space = false;
        var alternate = false;
        var zero = false;
        while (index < format.len) : (index += 1) {
            switch (format[index]) {
                '-' => left = true,
                '+' => plus = true,
                ' ' => space = true,
                '#' => alternate = true,
                '0' => zero = true,
                else => break,
            }
        }

        var width: usize = 0;
        if (index < format.len and format[index] == '*') {
            const raw = nextArgument(state, &arguments) orelse return null;
            const signed_width: i32 = @bitCast(@as(u32, @truncate(raw)));
            if (signed_width < 0) {
                left = true;
                width = @as(usize, @intCast(-@as(i64, signed_width)));
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
                const raw = nextArgument(state, &arguments) orelse return null;
                const signed_precision: i32 = @bitCast(@as(u32, @truncate(raw)));
                precision = if (signed_precision < 0) null else @intCast(signed_precision);
                index += 1;
            } else {
                var value: usize = 0;
                while (index < format.len and std.ascii.isDigit(format[index])) : (index += 1) {
                    value = value *| 10 +| (format[index] - '0');
                }
                precision = value;
            }
        }

        var length: Length = .int;
        if (index < format.len) {
            if (format[index] == 'h') {
                index += 1;
                if (index < format.len and format[index] == 'h') index += 1;
            } else if (format[index] == 'l' or format[index] == 'z' or format[index] == 't' or format[index] == 'j' or format[index] == 'L') {
                length = .long;
                const first = format[index];
                index += 1;
                if (index < format.len and format[index] == first) index += 1;
            } else if (format[index] == 'I' and index + 2 < format.len and std.mem.eql(u8, format[index .. index + 3], "I64")) {
                length = .long;
                index += 3;
            }
        }
        if (index == format.len) {
            writer.bytes(format[if (index > 0) index - 1 else 0 ..]);
            break;
        }

        const conversion = format[index];
        index += 1;
        switch (conversion) {
            's' => {
                const address = nextArgument(state, &arguments) orelse return null;
                const string = guestString(state, address) orelse return null;
                const shown = string[0..@min(string.len, precision orelse string.len)];
                writePadded(&writer, shown, width, left, ' ');
            },
            'c' => {
                const value = nextArgument(state, &arguments) orelse return null;
                const character = [_]u8{@truncate(value)};
                writePadded(&writer, &character, width, left, ' ');
            },
            'd', 'i', 'u', 'o', 'x', 'X', 'p' => {
                const raw = nextArgument(state, &arguments) orelse return null;
                const signed = conversion == 'd' or conversion == 'i';
                const signed_value: i64 = if (length == .long)
                    @bitCast(raw)
                else
                    @as(i32, @bitCast(@as(u32, @truncate(raw))));
                const negative = signed and signed_value < 0;
                const magnitude = if (negative) 0 -% @as(u64, @bitCast(signed_value)) else if (signed) @as(u64, @bitCast(signed_value)) else raw;
                const base: u8 = switch (conversion) {
                    'o' => 8,
                    'x', 'X', 'p' => 16,
                    else => 10,
                };
                writeInteger(&writer, magnitude, base, conversion == 'X', negative, plus, space, alternate or conversion == 'p', zero, left, width, precision);
            },
            // These conversions are not required to retrieve SDL fatal
            // messages. Consume their single Win64 slot so a later supported
            // conversion still reads the correct argument and leave a clear
            // token in diagnostic output instead of inventing a value.
            'a', 'A', 'e', 'E', 'f', 'F', 'g', 'G', 'n' => {
                _ = nextArgument(state, &arguments) orelse return null;
                writer.bytes("<unsupported-format>");
            },
            else => {
                writer.byte('%');
                writer.byte(conversion);
            },
        }
    }

    if (writer.count > std.math.maxInt(i32)) return null;
    return writer.count;
}

fn nextArgument(state: anytype, address: *u64) ?u64 {
    if (address.* == 0 or state.guestMemoryConst(address.*, 8) == null) return null;
    const value = state.read64(address.*);
    address.* +|= 8;
    return value;
}

fn guestString(state: anytype, address: u64) ?[]const u8 {
    if (address == 0) return "(null)";
    var length: u64 = 0;
    while (length < 1 << 20) : (length += 1) {
        const byte = state.guestMemoryConst(address + length, 1) orelse return null;
        if (byte[0] == 0) return state.guestMemoryConst(address, length) orelse return null;
    }
    return null;
}

fn writePadded(writer: *Writer, value: []const u8, width: usize, left: bool, pad: u8) void {
    const padding = width -| value.len;
    if (!left) writer.repeat(pad, padding);
    writer.bytes(value);
    if (left) writer.repeat(pad, padding);
}

fn writeInteger(
    writer: *Writer,
    value: u64,
    base: u8,
    uppercase: bool,
    negative: bool,
    plus: bool,
    space: bool,
    alternate: bool,
    zero: bool,
    left: bool,
    width: usize,
    precision: ?usize,
) void {
    var reversed: [64]u8 = undefined;
    var digits: usize = 0;
    var remaining = value;
    const alphabet = if (uppercase) "0123456789ABCDEF" else "0123456789abcdef";
    if (remaining != 0 or precision != 0) {
        while (remaining != 0) : (remaining /= base) {
            reversed[digits] = alphabet[@intCast(remaining % base)];
            digits += 1;
        }
    }
    const sign: ?u8 = if (negative) '-' else if (plus) '+' else if (space) ' ' else null;
    const prefix: []const u8 = if (alternate and base == 16) (if (uppercase) "0X" else "0x") else if (alternate and base == 8 and (digits == 0 or reversed[digits -| 1] != '0')) "0" else "";
    const precision_zeroes = if (precision) |minimum| minimum -| digits else 0;
    const base_width = digits + precision_zeroes + prefix.len + @intFromBool(sign != null);
    const width_padding = width -| base_width;
    const width_zeroes = if (zero and !left and precision == null) width_padding else 0;
    const spaces = width_padding -| width_zeroes;

    if (!left) writer.repeat(' ', spaces);
    if (sign) |character| writer.byte(character);
    writer.bytes(prefix);
    writer.repeat('0', precision_zeroes + width_zeroes);
    var cursor = digits;
    while (cursor > 0) {
        cursor -= 1;
        writer.byte(reversed[cursor]);
    }
    if (left) writer.repeat(' ', spaces);
}

test "Win64 SDL formatting reads guest string and integer slots" {
    const MockState = struct {
        bytes: [4096]u8 = @splat(0),

        fn guestMemoryConst(self: *const @This(), address: u64, count: u64) ?[]const u8 {
            const base: u64 = 0x1000;
            if (address < base) return null;
            const offset = address - base;
            if (offset > self.bytes.len or count > self.bytes.len - offset) return null;
            return self.bytes[@intCast(offset)..][0..@intCast(count)];
        }

        fn read64(self: *const @This(), address: u64) u64 {
            const bytes = self.guestMemoryConst(address, 8) orelse return 0;
            return std.mem.readInt(u64, bytes[0..8], .little);
        }
    };

    var state: MockState = .{};
    @memcpy(state.bytes[0x100..0x104], "file");
    @memcpy(state.bytes[0x110..0x118], "missing!");
    state.bytes[0x104] = 0;
    state.bytes[0x118] = 0;
    std.mem.writeInt(u64, state.bytes[0x200..0x208], 0x1100, .little);
    std.mem.writeInt(u64, state.bytes[0x208..0x210], 0x1110, .little);
    std.mem.writeInt(u64, state.bytes[0x210..0x218], 17, .little);

    var output: [128]u8 = undefined;
    const length = formatWindowsV(&state, "Failed '%s': %s (%u)", 0x1200, &output) orelse return error.FormatFailed;
    try std.testing.expectEqual(@as(usize, 28), length);
    try std.testing.expectEqualStrings("Failed 'file': missing! (17)", output[0..length]);
}
