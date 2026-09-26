//! The one place a Rosette host thread sleeps until a word changes.
//!
//! Every blocking primitive in this package parks here, so every wait in the
//! process shares one implementation and one interruption path (`park.zig`).
//! On Apple platforms this is the kernel's ulock compare-and-wait, on Linux
//! the futex system call, and anywhere else a bounded sleep.
//!
//! A wait returns early for many reasons: a wake, the timeout, a signal, a
//! spurious kernel return, or the word already differing. Callers always
//! re-check their own condition in a loop; nothing here promises that the
//! word changed.
//!
//! Before this package the PE executor's waits spun: its mutex was a spin
//! lock, its condition variable yielded in a loop, and parked guest workers
//! woke every millisecond to look. On 2026-09-25 that and the gate built on
//! it held Xenia's Emulator thread to 0.28M instructions a second.

const std = @import("std");
const builtin = @import("builtin");

pub const Word = std.atomic.Value(u32);

pub const Waiters = enum { one, all };

const is_darwin = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .driverkit, .maccatalyst => true,
    else => false,
};

/// Sleep while `word` holds `expected`, for at most `timeout_ns` when one is
/// given. A zero timeout returns at once. See the file comment for why a
/// return proves nothing.
pub fn wait(word: *const Word, expected: u32, timeout_ns: ?u64) void {
    if (timeout_ns) |ns| {
        if (ns == 0) return;
    }
    if (word.load(.monotonic) != expected) return;
    if (comptime is_darwin) {
        darwinWait(word, expected, timeout_ns);
    } else if (comptime builtin.os.tag == .linux) {
        linuxWait(word, expected, timeout_ns);
    } else {
        fallbackWait(word, expected, timeout_ns);
    }
}

/// Wake threads sleeping on `word`. Waking with no sleeper is harmless.
pub fn wake(word: *const Word, waiters: Waiters) void {
    if (comptime is_darwin) {
        darwinWake(word, waiters);
    } else if (comptime builtin.os.tag == .linux) {
        linuxWake(word, waiters);
    }
    // The fallback wait polls; it needs no wake.
}

fn darwinWait(word: *const Word, expected: u32, timeout_ns: ?u64) void {
    const op: std.c.UL = .{ .op = .COMPARE_AND_WAIT, .NO_ERRNO = true };
    // `__ulock_wait2` takes nanoseconds (macOS 11+); zero means forever,
    // which is what an absent timeout asks for.
    _ = std.c.__ulock_wait2(op, @ptrCast(word), expected, timeout_ns orelse 0, 0);
}

fn darwinWake(word: *const Word, waiters: Waiters) void {
    const op: std.c.UL = .{ .op = .COMPARE_AND_WAIT, .WAKE_ALL = waiters == .all, .NO_ERRNO = true };
    _ = std.c.__ulock_wake(op, @ptrCast(word), 0);
}

fn linuxWait(word: *const Word, expected: u32, timeout_ns: ?u64) void {
    const linux = std.os.linux;
    var timeout: linux.timespec = undefined;
    const timeout_pointer: ?*const linux.timespec = if (timeout_ns) |ns| blk: {
        timeout = .{
            .sec = @intCast(ns / std.time.ns_per_s),
            .nsec = @intCast(ns % std.time.ns_per_s),
        };
        break :blk &timeout;
    } else null;
    _ = linux.futex_4arg(@ptrCast(word), .{ .cmd = .WAIT, .private = true }, expected, timeout_pointer);
}

fn linuxWake(word: *const Word, waiters: Waiters) void {
    const count: u32 = if (waiters == .all) std.math.maxInt(i32) else 1;
    _ = std.os.linux.futex_3arg(@ptrCast(word), .{ .cmd = .WAKE, .private = true }, count);
}

/// No kernel wait: poll the word in short sleeps until it changes or the
/// timeout passes. Only reached on hosts Rosette does not ship on.
fn fallbackWait(word: *const Word, expected: u32, timeout_ns: ?u64) void {
    const step_ns: u64 = 50_000;
    var slept: u64 = 0;
    while (word.load(.acquire) == expected) {
        if (timeout_ns) |limit| {
            if (slept >= limit) return;
        }
        var request = std.c.timespec{ .sec = 0, .nsec = @intCast(step_ns) };
        _ = std.c.nanosleep(&request, null);
        slept +|= step_ns;
    }
}

/// Host monotonic time, for deadlines and the waits' own accounting.
pub fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    if (timestamp.sec < 0 or timestamp.nsec < 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(timestamp.nsec));
}

test "a wait on a word that already differs returns at once" {
    var word = Word.init(1);
    wait(&word, 0, null);
    wait(&word, 1, 0);
}

test "a timed wait returns after its timeout" {
    var word = Word.init(7);
    const started = monotonicNanoseconds();
    wait(&word, 7, 2 * std.time.ns_per_ms);
    // Early returns are allowed, but a wait that ignored its timeout
    // entirely would not come back at all.
    try std.testing.expect(monotonicNanoseconds() >= started);
}

test "a wake releases a sleeping thread" {
    const Shared = struct {
        word: Word = Word.init(0),
        woke: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn sleeper(shared: *@This()) void {
            while (shared.word.load(.acquire) == 0) wait(&shared.word, 0, null);
            shared.woke.store(true, .release);
        }
    };
    var shared: Shared = .{};
    const thread = try std.Thread.spawn(.{}, Shared.sleeper, .{&shared});
    var request = std.c.timespec{ .sec = 0, .nsec = 2 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&request, null);
    shared.word.store(1, .release);
    wake(&shared.word, .all);
    thread.join();
    try std.testing.expect(shared.woke.load(.acquire));
}
