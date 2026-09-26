//! Host-thread concurrency for Rosette: how threads sleep, lock, stop each
//! other and are watched.
//!
//! Rosette runs Windows guest threads on their own host threads. Everything
//! those threads share - the runtime's tables, guest memory's layout, the
//! main thread's AppKit queue - is coordinated through this package, so
//! every wait in the process parks the same way, can be interrupted the same
//! way, and is visible to the same watchdog. See README.md for the rules
//! that keep it deadlock-free.

pub const futex = @import("futex.zig");
pub const park = @import("park.zig");
pub const watch = @import("watch.zig");
pub const mutex = @import("mutex.zig");
pub const condition = @import("condition.zig");
pub const event = @import("event.zig");
pub const safepoint = @import("safepoint.zig");
pub const counter = @import("counter.zig");
pub const stall = @import("stall.zig");

pub const Mutex = mutex.Mutex;
pub const Condition = condition.Condition;
pub const EpochEvent = event.EpochEvent;
pub const Gate = safepoint.Gate;
pub const Service = park.Service;
pub const Watchdog = stall.Watchdog;
pub const monotonicNanoseconds = futex.monotonicNanoseconds;
pub const currentThreadId = mutex.currentThreadId;

test {
    _ = futex;
    _ = park;
    _ = watch;
    _ = mutex;
    _ = condition;
    _ = event;
    _ = safepoint;
    _ = counter;
    _ = stall;
}
