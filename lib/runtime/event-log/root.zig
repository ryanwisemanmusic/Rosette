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

// The asynchronous diagnostic transport. Installed by the process rather than
// imported here: the ring lives in the diagnostics module, which depends on
// this one, so a direct import would be a cycle.
pub const OfferFn = el.OfferFn;
pub const FlushFn = el.FlushFn;
pub const ClassifyFn = el.ClassifyFn;
pub const installAsyncTransport = el.installAsyncTransport;
pub const clearAsyncTransport = el.clearAsyncTransport;
pub const asyncTransportInstalled = el.asyncTransportInstalled;
pub const flushAsyncTransport = el.flushAsyncTransport;

test {
    _ = el;
}
