const std = @import("std");

pub const Work = enum {
    none,
    gtk_idle,
    deferred_thread,
    suspended_thread,
};

pub const Inputs = struct {
    pending_idle: usize = 0,
    /// A callback owns the UI handoff but may currently be suspended.
    callback_inflight: bool = false,
    /// The in-flight callback is the context executing right now.
    idle_callback_running: bool = false,
    deferred_threads: u64 = 0,
    suspended_threads: usize = 0,
};

/// Chooses work at a cooperative instruction-quantum boundary. GTK callbacks
/// retain exclusive ownership while running. Outside a callback, UI work has
/// first priority, newly created workers have second priority, and previously
/// started suspended contexts participate in round-robin rotation. Omitting
/// the last category lets a newly started spinner monopolize the interpreter
/// after the deferred queue becomes empty.
pub fn choose(inputs: Inputs) Work {
    if (inputs.idle_callback_running) return .none;
    if (inputs.pending_idle != 0 and !inputs.callback_inflight) return .gtk_idle;
    if (inputs.deferred_threads != 0) return .deferred_thread;
    if (inputs.suspended_threads != 0) return .suspended_thread;
    return .none;
}

test "cooperative rotation includes suspended contexts after deferred startup" {
    try std.testing.expectEqual(Work.gtk_idle, choose(.{ .pending_idle = 1, .suspended_threads = 3 }));
    try std.testing.expectEqual(Work.deferred_thread, choose(.{ .deferred_threads = 1, .suspended_threads = 3 }));
    try std.testing.expectEqual(Work.suspended_thread, choose(.{ .suspended_threads = 3 }));
    try std.testing.expectEqual(Work.none, choose(.{}));
}

test "active UI callback remains non-preemptible" {
    try std.testing.expectEqual(Work.none, choose(.{
        .pending_idle = 1,
        .idle_callback_running = true,
        .deferred_threads = 2,
        .suspended_threads = 4,
    }));
}

test "suspended UI callback does not freeze runnable workers" {
    try std.testing.expectEqual(Work.suspended_thread, choose(.{
        .pending_idle = 1,
        .callback_inflight = true,
        .idle_callback_running = false,
        .suspended_threads = 2,
    }));
}
