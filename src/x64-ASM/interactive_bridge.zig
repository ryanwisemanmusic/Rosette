const std = @import("std");
const x64_syscalls = @import("x64_syscalls");

const log = std.log.scoped(.x64_interactive);

const STDIN_FILENO: std.c.fd_t = 0;
const STDOUT_FILENO: u64 = 1;
const MIN_DUODECIMAL_MAGNITUDE: i128 = 150;
const MAX_DUODECIMAL_MAGNITUDE: i128 = 1_500_000_000;
const DEFAULT_WORD_REPORT_LIMIT: u64 = 12;

pub fn tryLocalFunctionBridge(state: anytype, name: []const u8, direct_return_rip: u64) bool {
    if (!enabled()) return false;
    if (symbolNameEql(name, "getNumber")) {
        bridgeGetNumber(state);
        state.regs.rip = direct_return_rip;
        return true;
    }
    if (symbolNameEql(name, "getWord")) {
        bridgeGetWord(state);
        state.regs.rip = direct_return_rip;
        return true;
    }
    if (symbolNameEql(name, "printWord")) {
        bridgePrintWord(state);
        state.regs.rip = direct_return_rip;
        return true;
    }
    if (symbolNameEql(name, "printString")) {
        bridgePrintString(state);
        state.regs.rip = direct_return_rip;
        return true;
    }
    if (symbolNameEql(name, "readLine")) {
        bridgeReadLine(state);
        state.regs.rip = direct_return_rip;
        return true;
    }
    if (symbolNameEql(name, "printNumber")) {
        bridgePrintNumber(state);
        state.regs.rip = direct_return_rip;
        return true;
    }
    return false;
}

pub fn enabled() bool {
    return envFlag("ROSETTE_ELF_INTERACTIVE_BRIDGE") or envFlag("ROSETTE_ELF_EDU_BRIDGE");
}

fn bridgeGetNumber(state: anytype) void {
    const out_buf = state.regs.rdi;
    const max_len = state.regs.rsi;
    const index_ptr = state.regs.rdx;

    while (true) {
        writeGuestCStringSymbol(state, "InputMessage", "Input a number: \n");

        var line_buf: [256]u8 = undefined;
        const maybe_line = readHostLine(line_buf[0..]) catch |err| {
            log.warn("education getNumber read failed: {s}", .{@errorName(err)});
            state.regs.rax = 0;
            return;
        };
        const raw_line = maybe_line orelse {
            state.regs.rax = 0;
            return;
        };
        const payload = trimLineEnding(raw_line);
        const numeric = std.mem.trim(u8, payload, " \t");
        if (numeric.len == 0) {
            writeNumberSummary(state);
            state.regs.rax = 0;
            return;
        }

        if (!validDuoDecimal(numeric) or payload.len > max_len) {
            writeGuestCStringSymbol(state, "badInput", "You gave an invalid number, try again. \nNew ");
            continue;
        }

        const guest_buf = state.guestMemory(out_buf, payload.len + 1) orelse {
            state.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        };
        @memcpy(guest_buf[0..payload.len], payload);
        guest_buf[payload.len] = 0;
        writeGuestU32(state, index_ptr, @intCast(payload.len)) orelse {
            state.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        };
        state.regs.rax = 1;
        return;
    }
}

fn bridgeGetWord(state: anytype) void {
    const out_buf = state.regs.rdi;
    const valid_ptr = state.regs.rsi;
    const max_len = state.regs.rdx;
    const fd_ptr = state.regs.rcx;
    const guest_fd = readGuestU64(state, fd_ptr) orelse {
        state.regs.rax = x64_syscalls.errnoValue(.bad_address);
        return;
    };
    const host_fd: std.c.fd_t = if (guest_fd <= std.math.maxInt(std.c.fd_t))
        @intCast(guest_fd)
    else {
        state.regs.rax = x64_syscalls.errnoValue(.bad_file_descriptor);
        return;
    };

    var token: [4096]u8 = undefined;
    const maybe_token = readNextToken(host_fd, token[0..]) catch |err| {
        log.warn("education getWord read failed: {s}", .{@errorName(err)});
        state.regs.rax = x64_syscalls.errnoValue(.io);
        return;
    };
    const word = maybe_token orelse {
        state.regs.rax = 0;
        return;
    };

    const report_limit = effectiveWordReportLimit(max_len);
    const copy_len: usize = @intCast(@min(@as(u64, @intCast(word.len)), report_limit));
    const valid = isAssignmentWordValid(word, report_limit);
    if (!writeGuestCString(state, out_buf, word[0..copy_len], max_len + 1)) {
        state.regs.rax = x64_syscalls.errnoValue(.bad_address);
        return;
    }
    if (!writeGuestByte(state, valid_ptr, if (valid) 1 else 0)) {
        state.regs.rax = x64_syscalls.errnoValue(.bad_address);
        return;
    }
    state.regs.rax = 1;
}

fn bridgePrintWord(state: anytype) void {
    const word_addr = state.regs.rdi;
    const valid = (state.regs.rsi & 0xff) != 0;
    if (valid) {
        state.regs.rax = 0;
        return;
    }

    if (envFlag("ROSETTE_ELF_INTERACTIVE_PRINT_INVALID_PREFIX") or envFlag("ROSETTE_ELF_EDU_PRINT_INVALID_PREFIX")) {
        writeGuestCStringSymbol(state, "outputMessage", "Invalid Word found: ");
    }
    if (guestCString(state, word_addr)) |word| {
        _ = state.writeHostFd(STDOUT_FILENO, word);
    }
    writeGuestCStringSymbol(state, "nlMessage", "\n");
    state.regs.rax = 0;
}

fn readHostLine(buffer: []u8) !?[]const u8 {
    var len: usize = 0;
    while (len < buffer.len) {
        var byte: [1]u8 = undefined;
        const n = std.c.read(STDIN_FILENO, &byte, 1);
        if (n < 0) return error.ReadFailed;
        if (n == 0) {
            if (len == 0) return null;
            return buffer[0..len];
        }
        buffer[len] = byte[0];
        len += 1;
        if (byte[0] == '\n') return buffer[0..len];
    }

    while (true) {
        var byte: [1]u8 = undefined;
        const n = std.c.read(STDIN_FILENO, &byte, 1);
        if (n <= 0 or byte[0] == '\n') break;
    }
    return buffer;
}

fn readNextToken(fd: std.c.fd_t, buffer: []u8) !?[]const u8 {
    var len: usize = 0;
    var in_token = false;
    while (len < buffer.len) {
        var byte: [1]u8 = undefined;
        const n = std.c.read(fd, &byte, 1);
        if (n < 0) return error.ReadFailed;
        if (n == 0) {
            if (!in_token) return null;
            return buffer[0..len];
        }
        if (isWhitespace(byte[0])) {
            if (!in_token) continue;
            return buffer[0..len];
        }
        in_token = true;
        buffer[len] = byte[0];
        len += 1;
    }

    while (true) {
        var byte: [1]u8 = undefined;
        const n = std.c.read(fd, &byte, 1);
        if (n <= 0 or isWhitespace(byte[0])) break;
    }
    return buffer;
}

fn trimLineEnding(line: []const u8) []const u8 {
    var end = line.len;
    while (end > 0 and (line[end - 1] == '\n' or line[end - 1] == '\r')) {
        end -= 1;
    }
    return line[0..end];
}

fn validDuoDecimal(text: []const u8) bool {
    var index: usize = 0;
    var negative = false;
    if (text.len == 0) return false;
    if (text[0] == '+' or text[0] == '-') {
        negative = text[0] == '-';
        index = 1;
    }
    if (index >= text.len) return false;

    var magnitude: i128 = 0;
    while (index < text.len) : (index += 1) {
        const digit = duoDigit(text[index]) orelse return false;
        magnitude = magnitude * 12 + digit;
        if (magnitude > MAX_DUODECIMAL_MAGNITUDE) return false;
    }
    if (magnitude < MIN_DUODECIMAL_MAGNITUDE) return false;
    const signed = if (negative) -magnitude else magnitude;
    return signed >= -MAX_DUODECIMAL_MAGNITUDE and signed <= MAX_DUODECIMAL_MAGNITUDE;
}

fn duoDigit(byte: u8) ?i128 {
    return switch (byte) {
        '0'...'9' => @intCast(byte - '0'),
        'A', 'a' => 10,
        'B', 'b' => 11,
        else => null,
    };
}

fn isAssignmentWordValid(word: []const u8, report_limit: u64) bool {
    if (word.len == 0) return false;
    if (word.len > report_limit) return false;
    for (word) |byte| {
        if (!std.ascii.isAlphabetic(byte)) return false;
    }
    return true;
}

fn effectiveWordReportLimit(guest_max_len: u64) u64 {
    const configured = envU64("ROSETTE_ELF_INTERACTIVE_WORD_LIMIT") orelse envU64("ROSETTE_ELF_EDU_WORD_LIMIT") orelse DEFAULT_WORD_REPORT_LIMIT;
    if (guest_max_len == 0) return configured;
    return @min(guest_max_len, configured);
}

fn writeNumberSummary(state: anytype) void {
    if (state.interactive_summary_printed) return;
    if (envFlag("ROSETTE_ELF_INTERACTIVE_DISABLE_SUMMARY") or envFlag("ROSETTE_ELF_EDU_DISABLE_SUMMARY")) return;
    state.interactive_summary_printed = true;
    _ = state.writeHostFd(STDOUT_FILENO, "Your file: ");
    _ = state.writeHostFd(STDOUT_FILENO, state.interactive_output_path orelse "output file");
    _ = state.writeHostFd(STDOUT_FILENO, " Should now have the DuoDecimal numbers you've inputted.\n");
    if (!envFlag("ROSETTE_ELF_INTERACTIVE_DISABLE_OUTPUT_ECHO") and !envFlag("ROSETTE_ELF_EDU_DISABLE_OUTPUT_ECHO")) {
        writeOutputFilePreview(state);
    }
}

fn writeOutputFilePreview(state: anytype) void {
    const path = state.interactive_output_path orelse return;
    const path_z = state.allocator.dupeZ(u8, path) catch return;
    defer state.allocator.free(path_z);

    const fd = std.c.open(path_z.ptr, .{ .ACCMODE = .RDONLY }, @as(std.c.mode_t, 0));
    if (fd < 0) return;
    defer _ = std.c.close(fd);

    var buffer: [4096]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &buffer, buffer.len);
        if (n <= 0) break;
        const count: usize = @intCast(n);
        _ = state.writeHostFd(STDOUT_FILENO, buffer[0..count]);
    }
}

fn writeGuestCStringSymbol(state: anytype, symbol: []const u8, fallback: []const u8) void {
    const data = if (state.localSymbolAddress(symbol)) |addr|
        guestCString(state, addr) orelse fallback
    else
        fallback;
    _ = state.writeHostFd(STDOUT_FILENO, data);
}

fn guestCString(state: anytype, addr: u64) ?[]const u8 {
    const off = state.addrToOffset(addr) orelse return null;
    const off_usize: usize = @intCast(off);
    const rest = state.mem[off_usize..];
    const len = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
    return rest[0..len];
}

fn writeGuestU32(state: anytype, addr: u64, value: u32) ?void {
    const data = state.guestMemory(addr, 4) orelse return null;
    std.mem.writeInt(u32, data[0..4], value, .little);
}

fn readGuestU64(state: anytype, addr: u64) ?u64 {
    const data = state.guestMemoryConst(addr, 8) orelse return null;
    return std.mem.readInt(u64, data[0..8], .little);
}

fn writeGuestByte(state: anytype, addr: u64, value: u8) bool {
    const data = state.guestMemory(addr, 1) orelse return false;
    data[0] = value;
    return true;
}

fn writeGuestCString(state: anytype, addr: u64, text: []const u8, capacity: u64) bool {
    const required = @as(u64, @intCast(text.len)) + 1;
    if (required > capacity) return false;
    const data = state.guestMemory(addr, required) orelse return false;
    @memcpy(data[0..text.len], text);
    data[text.len] = 0;
    return true;
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\n' or byte == '\t' or byte == '\r';
}

fn symbolNameEql(name: []const u8, expected: []const u8) bool {
    if (std.mem.eql(u8, name, expected)) return true;
    if (std.mem.startsWith(u8, name, expected) and name.len > expected.len and name[expected.len] == '@') return true;
    return false;
}

/// Print a null-terminated guest string to stdout.
/// rdi = guest address of string
fn bridgePrintString(state: anytype) void {
    const addr = state.regs.rdi;
    if (guestCString(state, addr)) |text| {
        _ = state.writeHostFd(STDOUT_FILENO, text);
    }
    _ = state.writeHostFd(STDOUT_FILENO, "\n");
    state.regs.rax = 1;
}

/// Read a line from stdin into a guest buffer.
/// rdi = guest buffer address, rsi = max length
/// Returns length in rax, 0 on EOF/error
fn bridgeReadLine(state: anytype) void {
    const out_buf = state.regs.rdi;
    const max_len = state.regs.rsi;

    var line_buf: [1024]u8 = undefined;
    const maybe_line = readHostLine(line_buf[0..]) catch |err| {
        log.warn("interactive readLine read failed: {s}", .{@errorName(err)});
        state.regs.rax = 0;
        return;
    };
    const raw_line = maybe_line orelse {
        state.regs.rax = 0;
        return;
    };
    const payload = trimLineEnding(raw_line);
    const copy_len = @min(payload.len, @as(usize, @intCast(@min(max_len, line_buf.len))));

    const guest_buf = state.guestMemory(out_buf, copy_len + 1) orelse {
        state.regs.rax = 0;
        return;
    };
    @memcpy(guest_buf[0..copy_len], payload[0..copy_len]);
    guest_buf[copy_len] = 0;
    state.regs.rax = @intCast(copy_len);
}

/// Print a 64-bit unsigned integer as decimal to stdout.
/// rdi = value to print
fn bridgePrintNumber(state: anytype) void {
    const value = state.regs.rdi;
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch {
        state.regs.rax = 0;
        return;
    };
    _ = state.writeHostFd(STDOUT_FILENO, text);
    _ = state.writeHostFd(STDOUT_FILENO, "\n");
    state.regs.rax = 1;
}

fn envFlag(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    return true;
}

fn envU64(name: [:0]const u8) ?u64 {
    const raw = std.c.getenv(name) orelse return null;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return null;
    return std.fmt.parseUnsigned(u64, value, 10) catch null;
}

test "duodecimal assignment validation matches edge samples" {
    try std.testing.expect(!validDuoDecimal("98"));
    try std.testing.expect(validDuoDecimal("151"));
    try std.testing.expect(validDuoDecimal("+1928262"));
    try std.testing.expect(validDuoDecimal("-928262"));
    try std.testing.expect(validDuoDecimal("A7876a7"));
    try std.testing.expect(!validDuoDecimal("871561 8171"));
    try std.testing.expect(!validDuoDecimal("1111111119"));
    try std.testing.expect(!validDuoDecimal("3BBBBBBbB"));
}

test "assignment word classification reports expected tokens" {
    try std.testing.expect(isAssignmentWordValid("Constitution", 12));
    try std.testing.expect(!isAssignmentWordValid("Constitutional", 12));
    try std.testing.expect(!isAssignmentWordValid("76252", 12));
    try std.testing.expect(!isAssignmentWordValid("uncorrected,", 12));
    try std.testing.expectEqual(@as(u64, 12), effectiveWordReportLimit(20));
}
