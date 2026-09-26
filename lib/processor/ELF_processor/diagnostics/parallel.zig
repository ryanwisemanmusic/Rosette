//! Diagnostics for guest threads running on their own host threads.
//!
//! - `lock_holds`: which runtime calls held the runtime lock, and how long.
//! - `register_tripwire`: a guest thread's registers written by another host
//!   thread between two of its own steps.
//! - `thread_pulse`: a periodic line per host thread from the watchdog.
//!
//! The rules these check are in lib/concurrency/README.md and
//! lib/guest_context/README.md.

pub const lock_holds = @import("parallel/lock_holds.zig");
pub const register_tripwire = @import("parallel/register_tripwire.zig");
pub const thread_pulse = @import("parallel/thread_pulse.zig");

test {
    _ = lock_holds;
    _ = register_tripwire;
    _ = thread_pulse;
}
