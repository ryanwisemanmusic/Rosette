//! Producer evidence needs the current step and caller, not a clock snapshot:
//! Ledger.signal deliberately ignores its legacy ticks argument.
const process = @import("../../process.zig");
const life = @import("lifecycle.zig");
const reporting = @import("run_reporting.zig");
pub threadlocal var legacy_clock = false; // offline comparison only
pub fn note(self: *process.ElfState, key: u64) void {
    const thread_handle = if (life.guestContextField(self, "windows_active_guest_thread_slot").*) |slot|
        self.windows_guest_threads[slot].handle
    else
        life.guestContextField(self, "active_guest_thread").*;
    self.windows_wait_cost.signal(key, reporting.totalInterpretedSteps(self), if (legacy_clock) life.windowsGuestClockTicks(self) else 0, .{ .thread_handle = thread_handle, .rip = life.guestContextField(self, "last_instruction_rip").* });
}
