//! pthread — Guest POSIX thread runtime and wait profiling library.
//!
//! Manages guest-thread lifecycle (creation, suspension, resumption),
//! thread-numeric-id mapping, deferred thread startup, and wait-state
//! profiling for deadlock/starvation detection.
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - scheduler  (for cooperative time-slice management)
//!   - event_log  (shared logging)

pub const pthread_runtime = @import("pthread_runtime.zig");
pub const thread_wait_profiler = @import("thread_wait_profiler.zig");

test {
    _ = pthread_runtime;
    _ = thread_wait_profiler;
}
