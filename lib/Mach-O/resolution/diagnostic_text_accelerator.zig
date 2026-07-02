const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");

const MAX_INPUT_SIZE: usize = 4 * 1024 * 1024;
const PREFIX = "----------- CONFIG DUMP -----------\n";
const SUFFIX = "----------- END OF CONFIG DUMP ----";

pub const Output = struct {
    address: u64,
    length: u64,
    input_bytes: u64,
    lines_seen: u64,
    lines_retained: u64,
};

pub const Failure = enum {
    none,
    invalid_path_object,
    invalid_guest_path,
    path_too_long,
    open_failed,
    host_allocation_failed,
    read_failed,
    input_too_large,
    guest_allocation_failed,
    invalid_guest_output,
    output_overflow,
};

pub const Engine = struct {
    accelerations: u64 = 0,
    input_bytes: u64 = 0,
    output_bytes: u64 = 0,
    lines_seen: u64 = 0,
    lines_retained: u64 = 0,
    failures: u64 = 0,
    last_failure: Failure = .none,

    pub fn buildConfigDump(self: *Engine, state: anytype, fs: anytype, path_object: u64) ?Output {
        const path_view = compat_runtime.libcppStringView(state, path_object) orelse return self.fail(.invalid_path_object);
        const guest_path = state.guestMemoryConst(path_view.address, path_view.length) orelse return self.fail(.invalid_guest_path);
        var translated_buffer: [4096]u8 = undefined;
        const path = fs.resolveHostPath(guest_path, &translated_buffer) orelse guest_path;
        if (path.len >= translated_buffer.len) return self.fail(.path_too_long);

        var path_z: [4096]u8 = undefined;
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        var flags: std.c.O = .{};
        flags.ACCMODE = .RDONLY;
        const fd = std.c.open(@ptrCast(&path_z), flags, @as(std.c.mode_t, 0));
        if (fd < 0) return self.fail(.open_failed);
        defer _ = std.c.close(fd);

        const input = state.allocator.alloc(u8, MAX_INPUT_SIZE) catch return self.fail(.host_allocation_failed);
        defer state.allocator.free(input);
        var input_length: usize = 0;
        while (input_length < input.len) {
            const amount = std.c.read(fd, input.ptr + input_length, input.len - input_length);
            if (amount < 0) return self.fail(.read_failed);
            if (amount == 0) break;
            input_length += @intCast(amount);
        }
        if (input_length == input.len) return self.fail(.input_too_large);

        const output_capacity = input_length + PREFIX.len + SUFFIX.len + countByte(input[0..input_length], '\n') + 2;
        const output_address = state.guestAlloc(output_capacity, 1) orelse return self.fail(.guest_allocation_failed);
        const output = state.guestMemory(output_address, output_capacity) orelse return self.fail(.invalid_guest_output);
        const filtered = filterConfigDump(input[0..input_length], output) orelse return self.fail(.output_overflow);

        self.accelerations +|= 1;
        self.last_failure = .none;
        self.input_bytes +|= input_length;
        self.output_bytes +|= filtered.length;
        self.lines_seen +|= filtered.lines_seen;
        self.lines_retained +|= filtered.lines_retained;
        std.debug.print(
            "macho-processor: diagnostic text acceleration: {s} input={d} output={d} lines={d}/{d}\n",
            .{ path, input_length, filtered.length, filtered.lines_retained, filtered.lines_seen },
        );
        return .{
            .address = output_address,
            .length = filtered.length,
            .input_bytes = input_length,
            .lines_seen = filtered.lines_seen,
            .lines_retained = filtered.lines_retained,
        };
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.accelerations == 0 and self.failures == 0) return;
        std.debug.print(
            "macho-processor: diagnostic text accelerator: runs={d} input={d} output={d} lines={d}/{d} failures={d} last_failure={s}\n",
            .{ self.accelerations, self.input_bytes, self.output_bytes, self.lines_retained, self.lines_seen, self.failures, @tagName(self.last_failure) },
        );
    }

    fn fail(self: *Engine, reason: Failure) ?Output {
        self.failures +|= 1;
        self.last_failure = reason;
        std.debug.print(
            "macho-processor: diagnostic text acceleration unavailable: {s}; continuing with guest implementation\n",
            .{@tagName(reason)},
        );
        return null;
    }
};

const FilterResult = struct {
    length: usize,
    lines_seen: u64,
    lines_retained: u64,
};

fn filterConfigDump(input: []const u8, output: []u8) ?FilterResult {
    var output_length: usize = 0;
    append(output, &output_length, PREFIX) orelse return null;
    var lines_seen: u64 = 0;
    var lines_retained: u64 = 0;
    var start: usize = 0;
    while (start < input.len) {
        const newline = std.mem.indexOfScalarPos(u8, input, start, '\n') orelse input.len;
        var line = input[start..newline];
        lines_seen +|= 1;
        if (line.len != 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        if (std.mem.indexOfScalar(u8, line, '#')) |comment| line = line[0..comment];

        var non_whitespace = false;
        for (line) |byte| {
            if (!std.ascii.isWhitespace(byte)) {
                non_whitespace = true;
                break;
            }
        }
        if (non_whitespace) {
            if (line[0] == '[') append(output, &output_length, "\n") orelse return null;
            append(output, &output_length, line) orelse return null;
            append(output, &output_length, "\n") orelse return null;
            lines_retained +|= 1;
        }
        if (newline == input.len) break;
        start = newline + 1;
    }
    append(output, &output_length, SUFFIX) orelse return null;
    return .{ .length = output_length, .lines_seen = lines_seen, .lines_retained = lines_retained };
}

fn append(output: []u8, length: *usize, bytes: []const u8) ?void {
    if (bytes.len > output.len - length.*) return null;
    @memcpy(output[length.* .. length.* + bytes.len], bytes);
    length.* += bytes.len;
}

fn countByte(bytes: []const u8, needle: u8) usize {
    var count: usize = 0;
    for (bytes) |byte| {
        if (byte == needle) count += 1;
    }
    return count;
}

test "config dump filtering matches Xenia startup semantics" {
    const input =
        "# heading\n" ++
        "[CPU]\n" ++
        "cpu = \"any\" # comment\n" ++
        "   # only comment\n" ++
        "\n" ++
        "mute = false\n";
    var output: [512]u8 = undefined;
    const result = filterConfigDump(input, &output).?;
    try std.testing.expectEqual(@as(u64, 6), result.lines_seen);
    try std.testing.expectEqual(@as(u64, 3), result.lines_retained);
    try std.testing.expectEqualStrings(
        PREFIX ++ "\n[CPU]\ncpu = \"any\" \nmute = false\n" ++ SUFFIX,
        output[0..result.length],
    );
}
