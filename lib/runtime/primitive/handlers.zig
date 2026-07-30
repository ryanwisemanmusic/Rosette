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
pub fn pthreadMachThreadNp(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const handle = ctx.readArg(0);
    const result = ctx.pthreadMachThreadId(handle);
    ctx.setResult(result);
    return .handled;
}

/// Implements `dladdr` — resolves an address to a symbol name and location.
/// Writes a Dl_info struct (28 bytes on x86_64 macOS) at the pointer in rsi.
/// Dl_info layout (4 fields, each 8 bytes):
///   +0: dli_fname (const char*)
///   +8: dli_fbase  (void*)
///   +16: dli_sname (const char*)
///   +24: dli_saddr (void*)
/// ABI: rdi = address, rsi = Dl_info* output. Returns 1 on success, 0 on failure.
pub fn dladdr(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const address = ctx.readArg(0);
    const info_ptr = ctx.readArg(1);
    if (info_ptr == 0) {
        ctx.setResult(0);
        return .handled;
    }
    const info = ctx.dladdrResolve(address);
    if (!info.found) {
        ctx.setResult(0);
        return .handled;
    }
    var buf: [32]u8 = undefined;
    std.mem.writeInt(u64, buf[0..8], info.dli_fname, .little);
    std.mem.writeInt(u64, buf[8..16], info.dli_fbase, .little);
    std.mem.writeInt(u64, buf[16..24], info.dli_sname, .little);
    std.mem.writeInt(u64, buf[24..32], info.dli_saddr, .little);
    ctx.writeGuest(info_ptr, &buf) orelse {
        ctx.setResult(0);
        return .handled;
    };
    ctx.setResult(1);
    return .handled;
}

/// Implements `strncpy` — copies up to n characters from src to dst,
/// null-padding the remainder of dst. Returns dst.
/// ABI: rdi = dst, rsi = src, rdx = n.
pub fn strncpy(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const dst = ctx.readArg(0);
    const src = ctx.readArg(1);
    const n = ctx.readArg(2);
    if (n == 0) {
        ctx.setResult(dst);
        return .handled;
    }
    const max_copy: usize = @intCast(n);
    // Copy at most n bytes from src to dst; stop at a null byte.
    var i: usize = 0;
    while (i < max_copy) : (i += 1) {
        const byte = ctx.readGuest(src + i, 1) orelse {
            ctx.setResult(dst);
            return .handled;
        };
        ctx.writeGuest(dst + i, byte) orelse {
            ctx.setResult(dst);
            return .handled;
        };
        if (byte[0] == 0) {
            // Null-pad the remainder of dst.
            const pad_byte: [1]u8 = .{0};
            var j: usize = i + 1;
            while (j < max_copy) : (j += 1) {
                ctx.writeGuest(dst + j, &pad_byte) orelse break;
            }
            ctx.setResult(dst);
            return .handled;
        }
    }
    ctx.setResult(dst);
    return .handled;
}

/// Implements `thread_get_state` — Mach kernel API to get thread register state.
/// We cannot provide real Mach thread state for emulated threads, so return
/// KERN_FAILURE (1). The caller (PosixStackWalker) handles this gracefully.
/// ABI: rdi = thread_act (ignored), rsi = flavor, rdx = state buffer,
///      rcx = state count pointer. Returns KERN_SUCCESS (0) or KERN_FAILURE (1).
pub fn threadGetState(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    // We can't provide real Mach thread state for emulated threads.
    // Return KERN_FAILURE so the caller falls back gracefully.
    ctx.setResult(1);
    return .handled;
}

/// Implements `strtol` — parses a long integer from a C string.
/// Handles leading whitespace, optional sign, and base detection (0 or 2-36).
/// ABI: rdi = str, rsi = endptr (char**), rdx = base (0 or 2-36).
/// Returns the parsed long value, or 0 on error (without setting errno).
pub fn strtol(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const str = ctx.readArg(0);
    const endptr = ctx.readArg(1);
    const base = ctx.readArg(2);

    if (base > 36) {
        ctx.setResult(0);
        return .handled;
    }

    const cstr = ctx.readCString(str) orelse return .unsupported;
    if (cstr.len == 0) {
        if (endptr != 0) {
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, str, .little);
            ctx.writeGuest(endptr, &buf) orelse return .unsupported;
        }
        ctx.setResult(0);
        return .handled;
    }

    // Skip whitespace
    var idx: usize = 0;
    while (idx < cstr.len and (cstr[idx] == ' ' or cstr[idx] == '\t' or cstr[idx] == '\n' or cstr[idx] == '\r' or cstr[idx] == '\x0c' or cstr[idx] == '\x0b')) : (idx += 1) {}

    if (idx >= cstr.len) {
        if (endptr != 0) {
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, str, .little);
            ctx.writeGuest(endptr, &buf) orelse return .unsupported;
        }
        ctx.setResult(0);
        return .handled;
    }

    // Check sign
    var negative = false;
    if (cstr[idx] == '-') {
        negative = true;
        idx += 1;
    } else if (cstr[idx] == '+') {
        idx += 1;
    }

    // Detect base if 0 or 16
    var effective_base = base;
    if (effective_base == 0) {
        if (idx < cstr.len and cstr[idx] == '0') {
            if (idx + 1 < cstr.len and (cstr[idx + 1] == 'x' or cstr[idx + 1] == 'X')) {
                effective_base = 16;
                idx += 2;
            } else {
                effective_base = 8;
                idx += 1;
            }
        } else {
            effective_base = 10;
        }
    } else if (effective_base == 16) {
        if (idx + 1 < cstr.len and cstr[idx] == '0' and (cstr[idx + 1] == 'x' or cstr[idx + 1] == 'X')) {
            idx += 2;
        }
    }

    if (idx >= cstr.len) {
        if (endptr != 0) {
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, str, .little);
            ctx.writeGuest(endptr, &buf) orelse return .unsupported;
        }
        ctx.setResult(0);
        return .handled;
    }

    // Parse digits
    var result: i64 = 0;
    const start_idx = idx;
    while (idx < cstr.len) : (idx += 1) {
        const ch = cstr[idx];
        var digit: u8 = 0;
        if (ch >= '0' and ch <= '9') {
            digit = ch - '0';
        } else if (ch >= 'a' and ch <= 'z') {
            digit = ch - 'a' + 10;
        } else if (ch >= 'A' and ch <= 'Z') {
            digit = ch - 'A' + 10;
        } else {
            break;
        }
        if (digit >= effective_base) break;

        const r: i64 = result;
        result = r *% @as(i64, @intCast(effective_base));
        result +%= @as(i64, @intCast(digit));
    }

    if (idx == start_idx) {
        if (endptr != 0) {
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, str, .little);
            ctx.writeGuest(endptr, &buf) orelse return .unsupported;
        }
        ctx.setResult(0);
        return .handled;
    }

    // Write endptr if requested
    if (endptr != 0) {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, str + idx, .little);
        ctx.writeGuest(endptr, &buf) orelse return .unsupported;
    }

    if (negative) {
        ctx.setResult(@as(u64, @bitCast(-result)));
    } else {
        ctx.setResult(@as(u64, @bitCast(result)));
    }
    return .handled;
}

/// Implements `abs` — returns the absolute value of an int.
/// ABI: rdi = signed 32-bit int value (sign-extended to 64 in rdi).
/// Returns the absolute value (non-negative int).
pub fn absInt(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const raw = ctx.readArg(0);
    const value: i32 = @bitCast(@as(u32, @truncate(raw)));
    ctx.setResult(@as(u64, @bitCast(@as(i64, @abs(value)))));
    return .handled;
}

/// Implements `std::string::compare(size_t pos, size_t n, const char* s)` —
/// compares a substring of this string with a C string.
/// ABI: rdi = this (string*), rsi = pos, rdx = n, rcx = s.
/// Returns 0 if equal, <0 if this substring < s, >0 if this substring > s.
pub fn stringCompare(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const this_ptr = ctx.readArg(0);
    const pos = ctx.readArg(1);
    const n = ctx.readArg(2);
    const s_ptr = ctx.readArg(3);

    if (this_ptr == 0) return .unsupported;
    const s_cstr = ctx.readCString(s_ptr) orelse return .unsupported;

    // Read the libc++ string object header (24 bytes)
    const header = ctx.readGuest(this_ptr, 24) orelse return .unsupported;

    // libc++ basic_string<char> on x86_64:
    // 24-byte object. __long/short union.
    // __long: [0..7=ptr, 8..15=size, 16..23=cap]
    // __short: [0..23=inline data], size tracked via __short.__size_
    //
    // __is_long() checks capacity's LSB at bytes 16-23.
    // For long mode: (bytes[23..24].0 & 1) == 1 → capacity has bit 0 set
    // For short mode: byte 0 = (size << 1), data starts at byte 1
    //                 OR size stored in __data_[22] (last inline byte)
    //                 and data starts at byte 0
    //
    // We check both possible layouts.

    const data_ptr: u64 = blk: {
        const size_field: u64 = blk2: {
            // Try long mode: check if byte 22 or 23 has LSB = 1 (capacity marker)
            if ((header[22] & 1) == 1 or (header[23] & 1) == 1) {
                // Long mode: data pointer at bytes 0-7
                break :blk std.mem.readInt(u64, header[0..8], .little);
            }
            break :blk2 header[0];
        };
        _ = size_field;
        // Short mode: inline data starts at offset 0 or 1
        // If byte 0 is even and <= 46 (max SSO = 22 chars, byte 0 = 44), it's the size marker
        // and data starts at byte 1
        if ((header[0] & 1) == 0 and header[0] <= 44) {
            break :blk this_ptr + 1;
        }
        // Otherwise data starts at byte 0
        break :blk this_ptr;
    };

    const string_len: u64 = blk: {
        if ((header[22] & 1) == 1 or (header[23] & 1) == 1) {
            // Long mode: size at bytes 8-15
            break :blk std.mem.readInt(u64, header[8..16], .little);
        }
        // Short mode: size from byte 22 >> 1 (two layout possibilities)
        const sz22 = header[22] >> 1;
        const sz0 = header[0] >> 1;
        if (header[0] <= 44 and (header[0] & 1) == 0) {
            break :blk sz0;
        }
        if (sz22 > 0 and sz22 <= 22) {
            break :blk sz22;
        }
        // Fallback: size from byte 0 >> 1
        break :blk sz0;
    };

    if (pos >= string_len) {
        // Compare empty substring with s
        if (s_cstr.len == 0) {
            ctx.setResult(0);
        } else {
            ctx.setResult(@as(u64, @bitCast(@as(i64, @as(i32, -1)))));
        }
        return .handled;
    }

    // Read the actual string data starting at pos, up to n chars
    const available = string_len - pos;
    const compare_len = @min(n, available);
    if (compare_len == 0 and s_cstr.len == 0) {
        ctx.setResult(0);
        return .handled;
    }

    const compare_data = ctx.readGuest(data_ptr + pos, @intCast(compare_len)) orelse return .unsupported;

    // Compare byte by byte
    const limit = @min(compare_len, s_cstr.len);
    var i: usize = 0;
    while (i < limit) : (i += 1) {
        if (compare_data[i] != s_cstr[i]) {
            const diff = @as(i32, @intCast(compare_data[i])) - @as(i32, @intCast(s_cstr[i]));
            ctx.setResult(@as(u64, @bitCast(@as(i64, diff))));
            return .handled;
        }
    }

    // All characters matched up to the shorter length
    if (compare_len < s_cstr.len) {
        ctx.setResult(@as(u64, @bitCast(@as(i64, @as(i32, -1)))));
    } else if (compare_len > s_cstr.len) {
        ctx.setResult(@as(u64, @bitCast(@as(i64, @as(i32, 1)))));
    } else {
        ctx.setResult(0);
    }
    return .handled;
}

/// Implements `std::basic_ostream::sentry::sentry(basic_ostream&)` —
/// constructs a sentry object that checks the stream state and flushes
/// tied streams. For emulation, we just mark the sentry as OK.
/// ABI: rdi = this (sentry*), rsi = os (ostream&).
/// The sentry is typically a small object with a bool at offset 0.
pub fn sentryC1(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const sentry_ptr = ctx.readArg(0);
    if (sentry_ptr == 0) return .unsupported;
    // Write ok_ = true at the sentry's first byte.
    // The sentry typically has a bool `ok_` at offset 0.
    var ok_byte: [1]u8 = .{1};
    ctx.writeGuest(sentry_ptr, &ok_byte) orelse return .unsupported;
    return .handled_void;
}

/// Implements `std::random_device::random_device(const std::string&)` —
/// constructs a random_device with a token string (e.g. "/dev/urandom").
/// For emulation, we write a marker at the object to show it's initialized.
/// ABI: rdi = this (random_device*), rsi = token (const string&).
pub fn randomDeviceC1(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const this_ptr = ctx.readArg(0);
    if (this_ptr == 0) return .unsupported;
    // Write a marker showing the random_device is initialized.
    // The object is typically a small wrapper; we just need it to be
    // non-zero so operator() and destructor recognize it as active.
    var marker: [8]u8 = undefined;
    std.mem.writeInt(u64, &marker, 1, .little);
    ctx.writeGuest(this_ptr, &marker) orelse return .unsupported;
    return .handled_void;
}

extern fn arc4random() u32;

/// Implements `std::random_device::operator()()` — returns a random
/// unsigned int. Uses host arc4random() for cryptographically secure
/// random numbers.
/// ABI: rdi = this (random_device*). Returns unsigned int (32-bit).
pub fn randomDeviceCl(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    const result = arc4random();
    ctx.setResult(@as(u64, result));
    return .handled;
}

/// Implements `std::random_device::~random_device()` — destructor.
/// For our stubbed implementation, this is a no-op.
/// ABI: rdi = this (random_device*). No return value.
pub fn randomDeviceD1(_: SlotIndex, ctx: *const PrimitiveContext) Result {
    _ = ctx;
    return .handled_void;
}

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
