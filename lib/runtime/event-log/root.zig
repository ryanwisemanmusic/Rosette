//! event-log — Shared thread-local diagnostic logging module.
//!
//! This module provides a single, shared copy of the event_log utilities
//! used by all extracted libraries (dyld, cxx-abi, init, io, diagnostics).
//! Replace the local `event_log.zig` copies in each library with
//! `@import("event_log").machoCapturePrint` etc.

const el = @import("event_log.zig");
pub const machoCapturePrint = el.machoCapturePrint;
pub const primitiveCapturePrint = el.primitiveCapturePrint;
pub const setThreadFds = el.setThreadFds;
pub const resetThreadFds = el.resetThreadFds;
pub const checkPointSync = el.checkPointSync;
pub const Kind = el.Kind;
pub const Event = el.Event;
pub const Logger = el.Logger;

test {
    _ = el;
}
