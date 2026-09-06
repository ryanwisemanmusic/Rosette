//! Process-core library: extracted from lib/Mach-O/process/
//! Each sub-module handles a specific domain of Mach-O guest process execution.
//! Uses `anytype` for `self` parameter (inferred as `*MachOState` at call sites).

pub const compat_handlers = @import("compat_handlers.zig");
pub const bounded_dispatch_fst = @import("bounded_dispatch_fst.zig");
pub const memory_access = @import("memory_access.zig");
pub const near_null_causality = @import("near_null_causality.zig");
pub const near_null_predictor = @import("near_null_predictor.zig");
pub const livelock_predictor = @import("livelock_predictor.zig");
pub const vtable_clobber_predictor = @import("vtable_clobber_predictor.zig");
pub const import_binding_predictor = @import("import_binding_predictor.zig");
pub const swap_health = @import("swap_health.zig");
pub const crash_diag = @import("crash_diag.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const execute = @import("execute.zig");
pub const generated_endian_contract = @import("generated_endian_contract.zig");
pub const guest_log = @import("guest_log.zig");
pub const host_termination = @import("host_termination.zig");
pub const native_crash = @import("native_crash.zig");
pub const initializers = @import("initializers.zig");
pub const native_window = @import("native_window.zig");
pub const scheduling = @import("scheduling.zig");
pub const signal_handling = @import("signal_handling.zig");
pub const syscalls = @import("syscalls.zig");

// Rooted so these run rather than merely compile. Until this block existed the
// module had no test target at all: every test in it type-checked as part of
// the processor build and none of them was ever executed, which is the failure
// mode where a test file's presence is mistaken for its coverage.
test {
    _ = host_termination;
    _ = native_crash;
    _ = memory_access;
    _ = near_null_predictor;
    _ = livelock_predictor;
    _ = vtable_clobber_predictor;
    _ = import_binding_predictor;
    _ = swap_health;
    _ = guest_log;
}
