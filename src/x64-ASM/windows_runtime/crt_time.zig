//! Calendar and CRT time imports for the Windows guest ABI.
const std = @import("std");

/// Select CPU and thread-local import state from a bound Windows guest
/// execution context when one is active, while preserving the standalone
/// state shape used by the generic runtime helpers and tests.
fn guestStateField(state: anytype, comptime field: []const u8) *@FieldType(@TypeOf(state.*), field) {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "windowsGuestContextField")) {
        return state.windowsGuestContextField(field);
    }
    return &@field(state.*, field);
}

// ---------------------------------------------------------------------------
// The C runtime's calendar surface.
//
// Eleven of these fourteen names were reaching the ABI fallback, which
// returns zero. Zero is a valid `time_t`, a valid `clock_t` and a valid
// character count, so every one of them was returning an answer the guest
// could not tell from a real one - and three of them return *pointers the
// caller dereferences without checking*, where the fallback's zero is a guest
// crash rather than a wrong date.
//
// All of it is arithmetic. Rosette's clock already publishes real time, so
// there is no modelling decision left: the only reason these were missing is
// that a name list does not say whether anything answers a name.

const seconds_per_day: i64 = 86_400;

/// Days since 1970-01-01 for a civil date, by Howard Hinnant's algorithm.
///
/// Written out rather than looped, because the loop version - stepping year
/// by year from 1970 - is where date code goes wrong: it is quadratic for
/// distant dates and it gets leap centuries wrong at exactly the boundaries
/// nobody tests.
fn daysFromCivil(year_in: i64, month_in: i64, day: i64) i64 {
    const year = year_in - @as(i64, if (month_in <= 2) 1 else 0);
    const era = @divFloor(if (year >= 0) year else year - 399, 400);
    const year_of_era = year - era * 400;
    const day_of_year = @divTrunc(153 * (month_in + (if (month_in > 2) @as(i64, -3) else 9)) + 2, 5) + day - 1;
    const day_of_era = year_of_era * 365 + @divTrunc(year_of_era, 4) - @divTrunc(year_of_era, 100) + day_of_year;
    return era * 146_097 + day_of_era - 719_468;
}

const CivilDate = struct { year: i64, month: i64, day: i64 };

fn civilFromDays(days: i64) CivilDate {
    const shifted = days + 719_468;
    const era = @divFloor(if (shifted >= 0) shifted else shifted - 146_096, 146_097);
    const day_of_era = shifted - era * 146_097;
    const year_of_era = @divTrunc(day_of_era - @divTrunc(day_of_era, 1460) + @divTrunc(day_of_era, 36_524) - @divTrunc(day_of_era, 146_096), 365);
    const year = year_of_era + era * 400;
    const day_of_year = day_of_era - (365 * year_of_era + @divTrunc(year_of_era, 4) - @divTrunc(year_of_era, 100));
    const mp = @divTrunc(5 * day_of_year + 2, 153);
    const day = day_of_year - @divTrunc(153 * mp + 2, 5) + 1;
    const month = mp + (if (mp < 10) @as(i64, 3) else -9);
    return .{ .year = year + @as(i64, if (month <= 2) 1 else 0), .month = month, .day = day };
}

/// Windows' `struct tm`: nine 32-bit ints, in this order.
const GuestTm = struct {
    sec: i32 = 0,
    min: i32 = 0,
    hour: i32 = 0,
    mday: i32 = 1,
    mon: i32 = 0,
    year: i32 = 70,
    wday: i32 = 0,
    yday: i32 = 0,
    isdst: i32 = 0,

    const bytes: u64 = 36;

    fn fromEpoch(epoch: i64) GuestTm {
        const days = @divFloor(epoch, seconds_per_day);
        var remainder = epoch - days * seconds_per_day;
        if (remainder < 0) remainder += seconds_per_day;
        const date = civilFromDays(days);
        // 1970-01-01 was a Thursday, which is weekday 4.
        const weekday = @mod(days + 4, 7);
        const january_first = daysFromCivil(date.year, 1, 1);
        return .{
            .sec = @intCast(@mod(remainder, 60)),
            .min = @intCast(@mod(@divTrunc(remainder, 60), 60)),
            .hour = @intCast(@divTrunc(remainder, 3600)),
            .mday = @intCast(date.day),
            .mon = @intCast(date.month - 1),
            .year = @intCast(date.year - 1900),
            .wday = @intCast(weekday),
            .yday = @intCast(days - january_first),
            .isdst = 0,
        };
    }

    fn toEpoch(self: GuestTm) i64 {
        const days = daysFromCivil(@as(i64, self.year) + 1900, @as(i64, self.mon) + 1, self.mday);
        return days * seconds_per_day + @as(i64, self.hour) * 3600 + @as(i64, self.min) * 60 + self.sec;
    }
};

fn readGuestTm(state: anytype, address: u64) ?GuestTm {
    if (address == 0 or state.guestMemoryConst(address, GuestTm.bytes) == null) return null;
    return GuestTm{
        .sec = @bitCast(state.read32(address + 0)),
        .min = @bitCast(state.read32(address + 4)),
        .hour = @bitCast(state.read32(address + 8)),
        .mday = @bitCast(state.read32(address + 12)),
        .mon = @bitCast(state.read32(address + 16)),
        .year = @bitCast(state.read32(address + 20)),
        .wday = @bitCast(state.read32(address + 24)),
        .yday = @bitCast(state.read32(address + 28)),
        .isdst = @bitCast(state.read32(address + 32)),
    };
}

fn writeGuestTm(state: anytype, address: u64, value: GuestTm) void {
    if (address == 0 or state.guestMemory(address, GuestTm.bytes) == null) return;
    state.write32(address + 0, @bitCast(value.sec));
    state.write32(address + 4, @bitCast(value.min));
    state.write32(address + 8, @bitCast(value.hour));
    state.write32(address + 12, @bitCast(value.mday));
    state.write32(address + 16, @bitCast(value.mon));
    state.write32(address + 20, @bitCast(value.year));
    state.write32(address + 24, @bitCast(value.wday));
    state.write32(address + 28, @bitCast(value.yday));
    state.write32(address + 32, @bitCast(value.isdst));
}

const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
const day_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

/// Render one `strftime` conversion. Returns what was written, in `scratch`.
///
/// The subset every caller in this image uses, plus the ones whose absence
/// would silently shorten a timestamp rather than fail it. An unrecognised
/// specifier is emitted verbatim, which is what the C standard leaves
/// implementation-defined and what every real CRT does.
fn formatTimeField(specifier: u8, value: GuestTm, scratch: []u8) []const u8 {
    return switch (specifier) {
        'Y' => std.fmt.bufPrint(scratch, "{d}", .{@as(i64, value.year) + 1900}) catch "",
        'y' => std.fmt.bufPrint(scratch, "{d:0>2}", .{@mod(@as(i64, value.year), 100)}) catch "",
        'm' => std.fmt.bufPrint(scratch, "{d:0>2}", .{value.mon + 1}) catch "",
        'd' => std.fmt.bufPrint(scratch, "{d:0>2}", .{value.mday}) catch "",
        'H' => std.fmt.bufPrint(scratch, "{d:0>2}", .{value.hour}) catch "",
        'M' => std.fmt.bufPrint(scratch, "{d:0>2}", .{value.min}) catch "",
        'S' => std.fmt.bufPrint(scratch, "{d:0>2}", .{value.sec}) catch "",
        'j' => std.fmt.bufPrint(scratch, "{d:0>3}", .{value.yday + 1}) catch "",
        'b', 'h' => if (value.mon >= 0 and value.mon < 12) month_names[@intCast(value.mon)] else "",
        'a' => if (value.wday >= 0 and value.wday < 7) day_names[@intCast(value.wday)] else "",
        'p' => if (value.hour < 12) "AM" else "PM",
        'I' => blk: {
            const hour12 = if (@mod(value.hour, 12) == 0) @as(i32, 12) else @mod(value.hour, 12);
            break :blk std.fmt.bufPrint(scratch, "{d:0>2}", .{hour12}) catch "";
        },
        'Z' => "UTC",
        'z' => "+0000",
        'n' => "\n",
        't' => "\t",
        '%' => "%",
        else => "",
    };
}

/// The C runtime's calendar functions.
pub fn tryFunction(comptime host: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (std.mem.eql(u8, name, "clock")) {
        // CLOCKS_PER_SEC is 1000 on Windows, so this is milliseconds of
        // process time. Zero would mean "no time has passed", which is a
        // plausible first reading and a wrong one for every reading after.
        const State = @TypeOf(state.*);
        const milliseconds = if (comptime @hasDecl(State, "windowsGuestClockTicks"))
            @divTrunc(state.windowsGuestClockTicks(), 1000)
        else
            0;
        guestStateField(state, "regs").*.rax = milliseconds;
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_tzset")) {
        // Rosette reports UTC, so there is nothing to recompute. Accepting
        // the call is correct; the globals it would set are already right.
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__daylight") or std.mem.eql(u8, name, "__timezone") or
        std.mem.eql(u8, name, "__tzname"))
    {
        // These return *pointers to CRT globals* that the caller dereferences
        // immediately. The ABI fallback's zero is not a wrong value here, it
        // is a null dereference in the guest - which makes them the three
        // most dangerous names in this library.
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "windowsTimezoneGlobal")) {
            guestStateField(state, "regs").*.rax = state.windowsTimezoneGlobal(name);
        } else {
            guestStateField(state, "regs").*.rax = 0;
        }
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_mktime64") or std.mem.eql(u8, name, "_mkgmtime64")) {
        // Rosette's clock is UTC, so local and GMT are the same conversion.
        const value = readGuestTm(state, host.argument(state, 0, direct_return_rip)) orelse {
            guestStateField(state, "regs").*.rax = @bitCast(@as(i64, -1));
            host.completeCall(state, direct_return_rip);
            return true;
        };
        const epoch = value.toEpoch();
        // Normalise the caller's struct in place, which is the half of
        // mktime callers rely on and a stub cannot fake.
        writeGuestTm(state, host.argument(state, 0, direct_return_rip), GuestTm.fromEpoch(epoch));
        guestStateField(state, "regs").*.rax = @bitCast(epoch);
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_gmtime64")) {
        const pointer = host.argument(state, 0, direct_return_rip);
        if (pointer == 0 or state.guestMemoryConst(pointer, 8) == null) {
            host.returnZeroCall(state, direct_return_rip);
            return true;
        }
        const State = @TypeOf(state.*);
        if (comptime !@hasDecl(State, "windowsStaticTmBuffer")) {
            host.returnZeroCall(state, direct_return_rip);
            return true;
        }
        const buffer = state.windowsStaticTmBuffer();
        if (buffer == 0) {
            host.returnZeroCall(state, direct_return_rip);
            return true;
        }
        writeGuestTm(state, buffer, GuestTm.fromEpoch(@bitCast(state.read64(pointer))));
        guestStateField(state, "regs").*.rax = buffer;
        host.completeCall(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strftime") or std.mem.eql(u8, name, "wcsftime")) {
        const wide = std.mem.eql(u8, name, "wcsftime");
        const destination = host.argument(state, 0, direct_return_rip);
        const capacity = host.argument(state, 1, direct_return_rip);
        const format_address = host.argument(state, 2, direct_return_rip);
        const value = readGuestTm(state, host.argument(state, 3, direct_return_rip)) orelse GuestTm{};

        var rendered: [512]u8 = undefined;
        var written: usize = 0;
        var index: usize = 0;
        var scratch: [32]u8 = undefined;
        while (written < rendered.len) : (index += 1) {
            const unit: u16 = if (wide)
                (host.readWideUnit(state, format_address, index) orelse 0)
            else blk: {
                const address = format_address +| @as(u64, index);
                if (state.guestMemoryConst(address, 1) == null) break :blk 0;
                break :blk state.read8(address);
            };
            if (unit == 0) break;
            if (unit != '%') {
                rendered[written] = if (unit < 0x80) @intCast(unit) else '?';
                written += 1;
                continue;
            }
            index += 1;
            const specifier: u16 = if (wide)
                (host.readWideUnit(state, format_address, index) orelse 0)
            else blk: {
                const address = format_address +| @as(u64, index);
                if (state.guestMemoryConst(address, 1) == null) break :blk 0;
                break :blk state.read8(address);
            };
            if (specifier == 0) break;
            const text = formatTimeField(@truncate(specifier), value, &scratch);
            const room = @min(text.len, rendered.len - written);
            @memcpy(rendered[written..][0..room], text[0..room]);
            written += room;
        }

        // strftime returns zero when the result does not fit, and writes
        // nothing. Callers size their buffers by probing for that zero, so
        // reporting a truncated length would make them believe a short
        // timestamp was complete.
        const needed: u64 = @as(u64, written) + 1;
        if (destination == 0 or capacity < needed) {
            guestStateField(state, "regs").*.rax = 0;
            host.completeCall(state, direct_return_rip);
            return true;
        }
        if (wide) {
            for (rendered[0..written], 0..) |byte, position| {
                const slot = destination +| @as(u64, position * 2);
                if (state.guestMemory(slot, 2) == null) break;
                state.write16(slot, byte);
            }
            const terminator = destination +| @as(u64, written * 2);
            if (state.guestMemory(terminator, 2) != null) state.write16(terminator, 0);
        } else {
            if (state.guestMemory(destination, @intCast(needed)) != null) {
                _ = host.copyBytes(state, destination, rendered[0..written]);
                state.write8(destination +| written, 0);
            }
        }
        guestStateField(state, "regs").*.rax = written;
        host.completeCall(state, direct_return_rip);
        return true;
    }
    return false;
}

test "civil date conversion round trips Unix epoch boundaries" {
    try std.testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
    try std.testing.expectEqual(@as(i64, -1), GuestTm.fromEpoch(-1).toEpoch());
    const before_epoch = GuestTm.fromEpoch(-1);
    try std.testing.expectEqual(@as(i32, 1969 - 1900), before_epoch.year);
    try std.testing.expectEqual(@as(i32, 11), before_epoch.mon);
    try std.testing.expectEqual(@as(i32, 31), before_epoch.mday);
    try std.testing.expectEqual(@as(i32, 23), before_epoch.hour);
    try std.testing.expectEqual(@as(i32, 59), before_epoch.sec);
}

test "civil date conversion follows Gregorian leap-century rules" {
    try std.testing.expectEqual(@as(i64, 2), daysFromCivil(2000, 3, 1) - daysFromCivil(2000, 2, 28));
    try std.testing.expectEqual(@as(i64, 1), daysFromCivil(1900, 3, 1) - daysFromCivil(1900, 2, 28));
}
