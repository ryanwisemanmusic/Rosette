//! CPU admission ledgers share the existing reporting boundary.
pub fn report(state: anytype) void {
    @import("register_import.zig").report(state);
    @import("atomic_admission.zig").report(state);
    @import("pause_recheck.zig").report(state);
    @import("scalar_cache_report.zig").report(state);
    @import("arithmetic_report.zig").report(state);
    @import("native_path_report.zig").report(state);
    @import("operand_report.zig").report(state);
    @import("guest_register_writes.zig").report(state);
    @import("stdio_flush_report.zig").report(state);
    @import("vulkan_call_lane.zig").report(state);
}
