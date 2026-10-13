//! FIFO-head fence custody, protected by Monitor.mutex. The queue thread may
//! observe a fence only inside its host-only, runtime-lock-released room wait.
//! A full two-info group gives that thread one short scheduling opportunity;
//! the watcher takes over if no room waiter arrives. No polling spin is added.
pub const grace_ns: u64 = 1_000_000;

pub const Route = struct {
    active_serial: u64 = 0,
    preferred_serial: u64 = 0,
    inline_waits: u64 = 0,
    inline_completions: u64 = 0,
    inline_timeouts: u64 = 0,
    watcher_waits: u64 = 0,

    pub fn prefer(self: *Route, serial: u64) void {
        self.preferred_serial = serial;
    }

    pub fn claim(self: *Route, serial: u64, inline_wait: bool) bool {
        if (serial == 0 or self.active_serial != 0) return false;
        self.active_serial = serial;
        self.preferred_serial = 0;
        if (inline_wait) self.inline_waits +|= 1 else self.watcher_waits +|= 1;
        return true;
    }

    pub fn finish(self: *Route, serial: u64, inline_wait: bool, result: anytype) void {
        @import("std").debug.assert(self.active_serial == serial);
        if (inline_wait) switch (result) {
            .signaled => self.inline_completions +|= 1,
            .timeout => self.inline_timeouts +|= 1,
            .failed => {},
        };
        self.active_serial = 0;
    }

    pub fn takePreference(self: *Route, serial: u64) bool {
        if (self.preferred_serial != serial or serial == 0) return false;
        self.preferred_serial = 0;
        return true;
    }
};

test "FSI observer custody has one owner and each grace is consumed once" {
    const testing = @import("std").testing;
    const Result = enum { signaled, timeout, failed };
    var route = Route{};
    route.prefer(7);
    try testing.expect(route.takePreference(7));
    try testing.expect(!route.takePreference(7));
    try testing.expect(route.claim(7, true));
    try testing.expect(!route.claim(7, false));
    try testing.expect(!route.claim(8, true));
    route.finish(7, true, Result.timeout);
    try testing.expect(route.claim(7, false));
    route.finish(7, false, Result.signaled);
    route.prefer(8);
    try testing.expect(route.claim(8, true));
    try testing.expect(!route.takePreference(8));
    route.finish(8, true, Result.signaled);
    try testing.expectEqual(@as(u64, 2), route.inline_waits);
    try testing.expectEqual(@as(u64, 1), route.inline_completions);
    try testing.expectEqual(@as(u64, 1), route.inline_timeouts);
    try testing.expectEqual(@as(u64, 1), route.watcher_waits);
}
