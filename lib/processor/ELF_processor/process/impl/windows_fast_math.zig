//! Atomic census for the pure CRT math import lane.
const std = @import("std");

pub const Ledger = struct {
    enabled: bool = true,
    calls: [2]std.atomic.Value(u64) = @splat(std.atomic.Value(u64).init(0)),

    pub fn total(self: *const Ledger) u64 {
        return self.calls[0].load(.acquire) +% self.calls[1].load(.acquire);
    }

    pub fn report(self: *const Ledger) void {
        if (self.total() == 0) return;
        std.log.info("PE64 WINDOWS FAST MATH: exp2={d} exp2f={d} shared_runtime_lock_bypassed=true arithmetic=ordinary_crt_handler guest_context=calling_thread tso_boundary=retained", .{
            self.calls[0].load(.acquire), self.calls[1].load(.acquire),
        });
    }
};
