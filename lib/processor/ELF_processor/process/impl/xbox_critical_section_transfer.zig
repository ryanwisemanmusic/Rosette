const process = @import("../../process.zig");
const ElfState = process.ElfState;
const guest_diagnostics = @import("guest_diagnostics.zig");
const kernel_services = @import("kernel_services.zig");

/// Record the interpreter's call-side observations for pinned Xbox enter and
/// leave trampolines. The translated call still exits through the normal
/// step hook, which owns the guest lock protocol.
pub fn observe(state_ptr: *anyopaque, target: u64, return_rip: u64) callconv(.c) u32 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    if (!self.parallel_guest_execution or !self.windows_runtime_enabled or
        self.trace_calls or self.block_jit_transfer_traced or tracingActive(self) or
        self.call_probes.armed()) return 0;
    const api = self.xbox_critical_section_hooks.at(target) orelse return 0;
    if (api != .enter and api != .leave) return 0;

    if (guest_diagnostics.isGuestMilestoneAddress(self, target)) {
        guest_diagnostics.noteGuestMilestoneEntry(self, target);
    }
    guest_diagnostics.noteXeniaEmulatorSetupCall(self, target, return_rip);
    kernel_services.noteGuestKernelCall(self, target);
    self.xbox_critical_section_hooks.noteJitDirect(api);
    return 1;
}

fn tracingActive(self: *const ElfState) bool {
    return self.trace_rip_start != null or self.trace_ring_enabled or self.trace_string_memory or
        self.trace_formatter or self.trace_vector or self.trace_utf8;
}
