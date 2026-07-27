//! mode — Runtime mode configuration library.
//!
//! Provides a global runtime mode flag that controls diagnostic verbosity,
//! strictness enforcement, and compatibility behavior during guest execution.
//! Designed to be set once during startup and queried throughout the runtime.
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - event_log  (shared logging)

pub const runtime_mode = @import("runtime_mode.zig");

test {
    _ = runtime_mode;
}
