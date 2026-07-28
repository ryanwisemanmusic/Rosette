//! Process-core library: extracted from lib/Mach-O/process/
//! Each sub-module handles a specific domain of Mach-O guest process execution.
//! Uses `anytype` for `self` parameter (inferred as `*MachOState` at call sites).

pub const compat_handlers = @import("compat_handlers.zig");
pub const memory_access = @import("memory_access.zig");
pub const near_null_causality = @import("near_null_causality.zig");
pub const crash_diag = @import("crash_diag.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const execute = @import("execute.zig");
pub const guest_log = @import("guest_log.zig");
pub const initializers = @import("initializers.zig");
pub const native_window = @import("native_window.zig");
pub const scheduling = @import("scheduling.zig");
pub const signal_handling = @import("signal_handling.zig");
pub const syscalls = @import("syscalls.zig");
