const std = @import("std");

/// A libc++ sleep request is guest scheduler input, not permission to block
/// the single host thread that drives the Mach-O interpreter.
pub const Repair = enum {
    none,
    non_positive,
    max_duration_sentinel,
};

/// Scheduler meaning of a guest sleep request.  Keeping this separate from a
/// duration prevents "infinite" from being accidentally converted into a
/// short deadline and then treated as runnable work.
pub const Kind = enum {
    yield,
    timed,
    indefinite,
    invalid,
};

pub const Decision = struct {
    requested_nanoseconds: i64,
    effective_nanoseconds: u64,
    kind: Kind,
    repair: Repair,

    pub fn repaired(self: Decision) bool {
        return self.repair != .none;
    }

    pub fn parksThread(self: Decision) bool {
        return self.kind == .timed or self.kind == .indefinite;
    }
};

/// disruptorplus::spin_wait requests one millisecond. A failed/overflowed
/// libc++ duration conversion can surface as duration::max() instead. Advancing
/// the virtual clock by INT64_MAX permanently saturates scheduler deadlines, so
/// preserve the call site's intended bounded backoff when that exact sentinel
/// reaches the bridge.
pub const zero_duration_yield_nanoseconds: u64 = 1;

/// libc++ implements `std::this_thread::sleep_for` out of line on macOS. In a
/// native process the call blocks only the calling pthread. Rosette multiplexes
/// guest pthreads on one interpreter thread, so a completed virtual sleep must
/// also be treated as a cooperative scheduling boundary.
pub fn isVirtualSleepImport(name: []const u8) bool {
    if (std.mem.endsWith(
        u8,
        name,
        "ZNSt3__111this_thread9sleep_forERKNS_6chrono8durationIxNS_5ratioILl1ELl1000000000EEEEE",
    )) return true;
    // POSIX sleep/poll variants that should deschedule the guest thread
    if (std.mem.endsWith(u8, name, "nanosleep")) return true;
    if (std.mem.endsWith(u8, name, "usleep")) return true;
    if (std.mem.endsWith(u8, name, "sleep")) return true;
    if (std.mem.endsWith(u8, name, "poll")) return true;
    return false;
}

pub fn classify(nanoseconds: i64) Decision {
    if (nanoseconds == 0) {
        return .{
            .requested_nanoseconds = nanoseconds,
            .effective_nanoseconds = zero_duration_yield_nanoseconds,
            .kind = .yield,
            .repair = .non_positive,
        };
    }
    if (nanoseconds < 0) return .{
        .requested_nanoseconds = nanoseconds,
        .effective_nanoseconds = 0,
        .kind = .invalid,
        .repair = .non_positive,
    };
    if (nanoseconds == std.math.maxInt(i64)) {
        return .{
            .requested_nanoseconds = nanoseconds,
            .effective_nanoseconds = 0,
            .kind = .indefinite,
            .repair = .max_duration_sentinel,
        };
    }
    return .{
        .requested_nanoseconds = nanoseconds,
        .effective_nanoseconds = @intCast(nanoseconds),
        .kind = .timed,
        .repair = .none,
    };
}

test "normal guest sleep advances by its requested duration" {
    const decision = classify(500 * std.time.ns_per_ms);
    try std.testing.expectEqual(Kind.timed, decision.kind);
    try std.testing.expectEqual(@as(u64, 500 * std.time.ns_per_ms), decision.effective_nanoseconds);
    try std.testing.expectEqual(Repair.none, decision.repair);
}

test "maximum duration sentinel becomes an indefinite park" {
    const decision = classify(std.math.maxInt(i64));
    try std.testing.expectEqual(Kind.indefinite, decision.kind);
    try std.testing.expectEqual(@as(u64, 0), decision.effective_nanoseconds);
    try std.testing.expectEqual(Repair.max_duration_sentinel, decision.repair);
    try std.testing.expect(decision.repaired());
}

test "zero sleep advances one virtual tick as a cooperative yield" {
    try std.testing.expectEqual(Kind.yield, classify(0).kind);
    try std.testing.expectEqual(zero_duration_yield_nanoseconds, classify(0).effective_nanoseconds);
    try std.testing.expectEqual(Repair.non_positive, classify(-1).repair);
    try std.testing.expectEqual(@as(u64, 0), classify(-1).effective_nanoseconds);
    try std.testing.expectEqual(Kind.invalid, classify(-1).kind);
}

test "libc++ sleep import recognition accepts Mach-O underscore variants" {
    const symbol = "_ZNSt3__111this_thread9sleep_forERKNS_6chrono8durationIxNS_5ratioILl1ELl1000000000EEEEE";
    try std.testing.expect(isVirtualSleepImport(symbol));
    try std.testing.expect(isVirtualSleepImport("_" ++ symbol));
    try std.testing.expect(isVirtualSleepImport("_nanosleep"));
}
