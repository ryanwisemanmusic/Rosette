//! Host lifecycle signal capture for the Mach-O runtime.
//!
//! A supervisor, terminal, or user may stop a long-running translated process
//! with SIGHUP/SIGINT/SIGQUIT/SIGTERM. Leaving those signals at their default
//! disposition makes the process vanish before the interpreter can publish its
//! final state, which looks indistinguishable from an uninstrumented crash.
//!
//! The signal handler is deliberately async-signal-safe: it writes one
//! `sig_atomic_t` and returns. The interpreter consumes the request at an
//! existing periodic boundary and performs all logging from normal code.

const std = @import("std");

const c = @cImport({
    @cInclude("signal.h");
});

const SignalHandler = ?*const fn (c_int) callconv(.c) void;

extern "c" fn signal(c_int, SignalHandler) SignalHandler;

var pending_signal: c.sig_atomic_t = 0;

pub const Request = struct {
    number: u8,

    pub fn name(self: Request) []const u8 {
        return signalName(self.number);
    }

    pub fn exitCode(self: Request) u8 {
        return 128 + self.number;
    }
};

pub const SupervisorContext = struct {
    name: []const u8 = "",
    timeout_seconds: u64 = 0,
};

pub const Scope = struct {
    previous_hup: SignalHandler = null,
    previous_int: SignalHandler = null,
    previous_quit: SignalHandler = null,
    previous_term: SignalHandler = null,
    installed: bool = false,

    pub fn install() Scope {
        const pending: *volatile c.sig_atomic_t = &pending_signal;
        pending.* = 0;
        return .{
            .previous_hup = signal(c.SIGHUP, capture),
            .previous_int = signal(c.SIGINT, capture),
            .previous_quit = signal(c.SIGQUIT, capture),
            .previous_term = signal(c.SIGTERM, capture),
            .installed = true,
        };
    }

    pub fn deinit(self: *Scope) void {
        if (!self.installed) return;
        _ = signal(c.SIGHUP, self.previous_hup);
        _ = signal(c.SIGINT, self.previous_int);
        _ = signal(c.SIGQUIT, self.previous_quit);
        _ = signal(c.SIGTERM, self.previous_term);
        const pending: *volatile c.sig_atomic_t = &pending_signal;
        pending.* = 0;
        self.installed = false;
    }
};

fn capture(sig: c_int) callconv(.c) void {
    if (!isLifecycleSignal(sig)) return;
    const pending: *volatile c.sig_atomic_t = &pending_signal;
    // Preserve the first request. It identifies the event that began shutdown;
    // a second signal during diagnostics must not rewrite the evidence.
    if (pending.* == 0) pending.* = @intCast(sig);
}

pub fn take() ?Request {
    const pending: *volatile c.sig_atomic_t = &pending_signal;
    const raw = pending.*;
    if (!isLifecycleSignal(raw)) return null;
    pending.* = 0;
    return .{ .number = @intCast(raw) };
}

pub fn isLifecycleSignal(sig: c_int) bool {
    return sig == c.SIGHUP or sig == c.SIGINT or sig == c.SIGQUIT or sig == c.SIGTERM;
}

pub fn signalName(sig: u8) []const u8 {
    return switch (sig) {
        c.SIGHUP => "SIGHUP",
        c.SIGINT => "SIGINT",
        c.SIGQUIT => "SIGQUIT",
        c.SIGTERM => "SIGTERM",
        else => "unknown",
    };
}

pub fn supervisorContext() SupervisorContext {
    var result: SupervisorContext = .{};
    if (std.c.getenv("ROSETTE_SUPERVISOR_NAME")) |raw| {
        result.name = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    }
    if (std.c.getenv("ROSETTE_SUPERVISOR_TIMEOUT_SECONDS")) |raw| {
        const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
        result.timeout_seconds = std.fmt.parseUnsigned(u64, value, 10) catch 0;
    }
    return result;
}

test "lifecycle signals retain shell-compatible status and names" {
    const term = Request{ .number = c.SIGTERM };
    try std.testing.expectEqual(@as(u8, 143), term.exitCode());
    try std.testing.expectEqualStrings("SIGTERM", term.name());
    try std.testing.expect(isLifecycleSignal(c.SIGHUP));
    try std.testing.expect(isLifecycleSignal(c.SIGINT));
    try std.testing.expect(isLifecycleSignal(c.SIGQUIT));
    try std.testing.expect(isLifecycleSignal(c.SIGTERM));
    try std.testing.expect(!isLifecycleSignal(c.SIGSEGV));
}

test "capture retains the first lifecycle request until normal code consumes it" {
    const pending: *volatile c.sig_atomic_t = &pending_signal;
    pending.* = 0;
    capture(c.SIGTERM);
    capture(c.SIGINT);
    const request = take().?;
    try std.testing.expectEqual(@as(u8, c.SIGTERM), request.number);
    try std.testing.expect(take() == null);
}
