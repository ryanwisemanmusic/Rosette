//! Census for the NT zero-delay lane; shared scheduling tables are untouched.
const std = @import("std");
pub const Ledger = struct {
    enabled: bool = true,
    calls: [2]std.atomic.Value(u64) = @splat(std.atomic.Value(u64).init(0)),
    pub fn total(self: *const Ledger) u64 {
        return self.calls[0].load(.acquire) +% self.calls[1].load(.acquire);
    }
    pub fn report(self: *const Ledger) void {
        if (self.total() == 0) return;
        std.log.info("PE64 WINDOWS FAST NT YIELD: zero_delay={d} explicit_yield={d} shared_runtime_lock_bypassed=true timed_alertable_and_lock_owned_calls=ordinary_dispatch host_yield_requested_per_call=true tso_boundary=retained", .{ self.calls[0].load(.acquire), self.calls[1].load(.acquire) });
    }
};
