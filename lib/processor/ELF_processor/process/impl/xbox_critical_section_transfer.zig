const std = @import("std");
const process = @import("../../process.zig");
const ElfState = process.ElfState;
const guest_diagnostics = @import("guest_diagnostics.zig");
const kernel_services = @import("kernel_services.zig");
const windows_sync = @import("windows_sync.zig");
const protocol = process.__ProcessInternals._xbox_critical_section;
const SectionAccess = ElfState.__StateInternals._XboxSectionAccess;

/// What the translated call does next (`core.emitHookedTargetCheck`).
pub const Outcome = enum(u32) {
    /// The interpreter runs the call.
    decline = 0,
    /// Observed: the call template pushes the return address and leaves for
    /// the per-step Xbox hook, which owns the lock protocol from there.
    observed = 1,
    /// The export ran here, as the hook would have run it: the call goes on
    /// at its return address without leaving translated code.
    completed = 2,
};

/// Translated calls may complete an uncontended Enter or Leave themselves;
/// false keeps every call on the per-step hook (offline comparisons).
pub var completion_enabled: bool = true;

/// Record the interpreter's call-side observations for pinned Xbox enter and
/// leave trampolines, then run the export in place when it needs no wait and
/// no wake: a recursion or a claim of a free section, a release with no
/// waiter counted. Halo 3's MAIN_THREAD makes about six million of these
/// calls a run (2026-10-19), and each used to leave translated code twice:
/// at the call, for the hook, and at the hook's return. Anything else - a
/// section another thread holds, a release that must wake a waiter, a
/// thread with a grant pending, a context or section Rosette cannot read -
/// declines before changing anything, and the hook runs exactly as before.
pub fn observe(state_ptr: *anyopaque, target: u64, return_rip: u64) callconv(.c) u32 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    if (!self.parallel_guest_execution or !self.windows_runtime_enabled or
        self.trace_calls or self.block_jit_transfer_traced or tracingActive(self) or
        self.call_probes.armed()) return @intFromEnum(Outcome.decline);
    // Every call to a target outside Xenia's code cache asks here, so a
    // Vulkan command thunk can be answered in place too.
    const api = self.xbox_critical_section_hooks.at(target) orelse return @import("vulkan_call_lane.zig").transfer(self, target, return_rip);
    if (api != .enter and api != .leave) return @intFromEnum(Outcome.decline);

    if (guest_diagnostics.isGuestMilestoneAddress(self, target)) {
        guest_diagnostics.noteGuestMilestoneEntry(self, target);
    }
    guest_diagnostics.noteXeniaEmulatorSetupCall(self, target, return_rip);
    kernel_services.noteGuestKernelCall(self, target);
    self.xbox_critical_section_hooks.noteJitDirect(api);
    return @intFromEnum(if (completion_enabled and complete(self, api)) Outcome.completed else Outcome.observed);
}

/// The hook's work for an uncontended call, minus the return it simulates.
fn complete(self: *ElfState, api: protocol.Export) bool {
    const call = windows_sync.decodeXboxCriticalSectionCall(self) orelse return false;
    if (call.section == 0) return false;
    const access: SectionAccess = .{ .state = self, .section = call.section };
    const me = windows_sync.xboxCurrentKthread(self, call);
    const stats = &self.xbox_critical_section_stats;
    switch (api) {
        .enter => {
            if (windows_sync.xboxPendingWait(self) == call.section) return false;
            switch (protocol.enterUncontended(access, me) orelse return false) {
                .acquired => protocol.Stats.bump(&stats.acquired),
                .recursed => protocol.Stats.bump(&stats.recursed),
                .counted => unreachable,
            }
        },
        .leave => {
            const result = protocol.leaveUncontended(access, me) orelse return false;
            if (!result.owner_matched) protocol.Stats.bump(&stats.leave_mismatches);
        },
        else => return false,
    }
    self.xbox_critical_section_hooks.noteHandled(api);
    self.xbox_critical_section_hooks.noteJitCompleted(api);
    return true;
}

fn tracingActive(self: *const ElfState) bool {
    return self.trace_rip_start != null or self.trace_ring_enabled or self.trace_string_memory or
        self.trace_formatter or self.trace_vector or self.trace_utf8;
}

comptime {
    std.debug.assert(@intFromEnum(Outcome.observed) == 1);
}
