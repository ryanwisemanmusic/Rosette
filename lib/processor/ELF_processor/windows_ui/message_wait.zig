//! Polling policy for the Win32 message pump's host-event bridge.
//!
//! Guest-posted messages, paint requests, quit, and shutdown wake the pump
//! directly. Native host-window events do not have a queue notification, so
//! the owner periodically runs the host event pump while an otherwise-empty
//! GetMessage remains blocked.

const std = @import("std");

pub const WakeReason = enum {
    guest_notification,
    host_event_poll,
};

pub const Policy = struct {
    /// Bound input-to-message latency to roughly one 60 Hz display interval
    /// while avoiding the 250 wakeups/second caused by a 4 ms poll.
    host_event_poll_ns: u64 = 16 * std.time.ns_per_ms,

    pub fn nextPollDeadline(self: Policy, now_ns: u64) u64 {
        return now_ns +| self.host_event_poll_ns;
    }

    pub fn classifyWake(_: Policy, notified: bool) WakeReason {
        return if (notified) .guest_notification else .host_event_poll;
    }
};

pub const default = Policy{};

test "message wait polls host events at the configured cadence" {
    const deadline = default.nextPollDeadline(100);
    try std.testing.expectEqual(@as(u64, 16 * std.time.ns_per_ms + 100), deadline);
    try std.testing.expectEqual(WakeReason.guest_notification, default.classifyWake(true));
    try std.testing.expectEqual(WakeReason.host_event_poll, default.classifyWake(false));
}

test "message wait poll deadline saturates instead of wrapping" {
    try std.testing.expectEqual(std.math.maxInt(u64), default.nextPollDeadline(std.math.maxInt(u64) - 2));
}
