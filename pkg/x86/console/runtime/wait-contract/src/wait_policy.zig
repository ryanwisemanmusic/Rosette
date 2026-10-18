//! Pure event semantics reusable by host runtimes and test harnesses.

pub const EventMode = enum {
    consume_one,
    manual_reset,
};

pub const WaitResult = enum {
    blocked,
    signaled,
};

pub const WaitContract = struct {
    mode: EventMode,

    pub fn result(self: WaitContract, pending_signals: u64) WaitResult {
        _ = self;
        return if (pending_signals == 0) .blocked else .signaled;
    }

    pub fn signal(self: WaitContract, pending_signals: u64) u64 {
        return switch (self.mode) {
            .consume_one => pending_signals +| 1,
            .manual_reset => 1,
        };
    }

    pub fn broadcast(self: WaitContract, pending_signals: u64, waiter_count: u64) u64 {
        return switch (self.mode) {
            .consume_one => pending_signals +| waiter_count,
            .manual_reset => 1,
        };
    }

    pub fn reset(self: WaitContract, pending_signals: u64) u64 {
        _ = self;
        _ = pending_signals;
        return 0;
    }

    pub fn consumes(self: WaitContract) bool {
        return self.mode == .consume_one;
    }

    pub fn invariantHolds(
        self: WaitContract,
        successful_wait_count: u64,
        consumed_signal_count: u64,
        invalid_success_count: u64,
    ) bool {
        if (invalid_success_count != 0) return false;
        return self.mode == .manual_reset or successful_wait_count == consumed_signal_count;
    }
};
