//! Distinguishes Vulkan surface proc discovery from a guest surface call.

pub const SurfacePathLedger = struct {
    proc_queries: u64 = 0,
    proc_available: u64 = 0,
    proc_missing: u64 = 0,
    dispatch_attempts: u64 = 0,
    dispatch_successes: u64 = 0,
    dispatch_failures: u64 = 0,
    last_guest_instance: u64 = 0,
    last_layer_token: u64 = 0,
    last_result: i32 = 0,
    last_surface_handle: u64 = 0,

    pub fn noteProcLookup(self: *SurfacePathLedger, available: bool) void {
        self.proc_queries +|= 1;
        if (available) {
            self.proc_available +|= 1;
        } else {
            self.proc_missing +|= 1;
        }
    }

    pub fn noteDispatchAttempt(self: *SurfacePathLedger, instance: u64, layer_token: u64) void {
        self.dispatch_attempts +|= 1;
        self.last_guest_instance = instance;
        self.last_layer_token = layer_token;
    }

    pub fn noteDispatchResult(self: *SurfacePathLedger, result: i32, surface: u64) void {
        self.last_result = result;
        self.last_surface_handle = surface;
        if (result == 0 and surface != 0) {
            self.dispatch_successes +|= 1;
        } else {
            self.dispatch_failures +|= 1;
        }
    }
};

test "surface path ledger separates proc availability from surface creation" {
    var ledger = SurfacePathLedger{};
    ledger.noteProcLookup(true);
    ledger.noteProcLookup(false);
    ledger.noteDispatchAttempt(0x11, 0x22);
    ledger.noteDispatchResult(0, 0x33);

    try @import("std").testing.expectEqual(@as(u64, 1), ledger.proc_available);
    try @import("std").testing.expectEqual(@as(u64, 1), ledger.proc_missing);
    try @import("std").testing.expectEqual(@as(u64, 1), ledger.dispatch_successes);
    try @import("std").testing.expectEqual(@as(u64, 0), ledger.dispatch_failures);
}
