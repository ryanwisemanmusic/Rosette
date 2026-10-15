//! CPU admission ledgers share the existing reporting boundary.
pub fn report(state: anytype) void {
    @import("register_import.zig").report(state);
    @import("atomic_admission.zig").report(state);
    @import("pause_recheck.zig").report(state);
    @import("scalar_cache_report.zig").report(state);
}
