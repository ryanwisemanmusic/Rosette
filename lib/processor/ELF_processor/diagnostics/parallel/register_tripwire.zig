//! A write to a guest thread's register file by some other host thread,
//! caught at the owning thread's own instruction boundaries.
//!
//! Only the executor running a guest context may change its registers
//! between two of its steps. In parallel mode the process owner's registers
//! are the PE state's own fields, which is exactly what shared runtime code
//! reaches for when it forgets which thread it is running for: on
//! 2026-09-26 the Windows Vulkan adapter copied the Emulator thread's
//! registers over the UI thread's for every Vulkan call and copied a stale
//! set back afterwards, and the UI thread jumped into the Emulator thread's
//! stack. The executor records rip and rsp as it leaves a step and compares
//! them as it begins the next: any difference is a write it did not make.
//!
//! The window is only the time between two steps, so a race that lands
//! entirely inside one step is not seen here - `tools/audit_guest_context_access.py`
//! is what keeps the code that could make one from existing. What is seen
//! is certain: nothing in the executor's own loop writes these registers
//! between steps.

const std = @import("std");

pub const Registers = struct {
    rip: u64 = 0,
    rsp: u64 = 0,
};

pub const Finding = struct {
    /// What the executor left at the end of its previous step.
    expected: Registers,
    /// What it found at the start of the next.
    found: Registers,
    /// This tripwire's count, including this one.
    trip: u64,
};

pub const Tripwire = struct {
    armed: bool = false,
    last: Registers = .{},
    trips: u64 = 0,
    checks: u64 = 0,

    /// The file as this executor left it.
    pub fn arm(self: *Tripwire, rip: u64, rsp: u64) void {
        self.last = .{ .rip = rip, .rsp = rsp };
        self.armed = true;
    }

    /// Forget the baseline: something may legitimately write the file before
    /// the next step, as a waker completing this thread's wait does.
    pub fn disarm(self: *Tripwire) void {
        self.armed = false;
    }

    /// Compare before the executor's next step.
    pub fn check(self: *Tripwire, rip: u64, rsp: u64) ?Finding {
        if (!self.armed) return null;
        self.checks +|= 1;
        if (rip == self.last.rip and rsp == self.last.rsp) return null;
        self.trips +|= 1;
        const finding: Finding = .{ .expected = self.last, .found = .{ .rip = rip, .rsp = rsp }, .trip = self.trips };
        // Re-baseline so one foreign write is one finding, not one per step.
        self.last = finding.found;
        return finding;
    }
};

test "a tripwire is silent while only its executor writes" {
    var tripwire: Tripwire = .{};
    try std.testing.expect(tripwire.check(1, 2) == null);
    tripwire.arm(0x1403ecb4e, 0x1c40b3d90);
    try std.testing.expect(tripwire.check(0x1403ecb4e, 0x1c40b3d90) == null);
    try std.testing.expectEqual(@as(u64, 1), tripwire.checks);
    try std.testing.expectEqual(@as(u64, 0), tripwire.trips);
}

test "a write between steps is one finding with both register sets" {
    var tripwire: Tripwire = .{};
    tripwire.arm(0x1403ecb4e, 0x1c40b3d90);
    const finding = tripwire.check(0x1443c4198, 0x1c40b3d80).?;
    try std.testing.expectEqual(@as(u64, 0x1403ecb4e), finding.expected.rip);
    try std.testing.expectEqual(@as(u64, 0x1443c4198), finding.found.rip);
    try std.testing.expectEqual(@as(u64, 1), finding.trip);
    // The new values are the baseline now.
    try std.testing.expect(tripwire.check(0x1443c4198, 0x1c40b3d80) == null);
}

test "a disarmed tripwire accepts a waker's write" {
    var tripwire: Tripwire = .{};
    tripwire.arm(0x140001000, 0x20000);
    tripwire.disarm();
    try std.testing.expect(tripwire.check(0x140002000, 0x20008) == null);
    try std.testing.expectEqual(@as(u64, 0), tripwire.trips);
}
