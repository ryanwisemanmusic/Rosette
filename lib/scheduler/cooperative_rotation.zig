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
    /// Dispatch would be refused even though the queue is non-empty and no
    /// callback is in flight (for example while a completed handoff still owes
    /// its scheduling thread a resume). Choosing `gtk_idle` here yields without
    /// starting a callback, and because the queue is unchanged the same choice
    /// repeats at every boundary — a rotation that makes no progress and
    /// crowds out the ordinary thread quantum.
    idle_dispatch_blocked: bool = false,
    deferred_threads: u64 = 0,
    suspended_threads: usize = 0,
    /// Estimated work duration for each category (steps). 0 = unknown.
    estimated_gtk_idle_duration: u64 = 0,
    estimated_deferred_duration: u64 = 0,
    estimated_suspended_duration: u64 = 0,
    /// Priority ordering override: index into [gtk_idle, deferred, suspended].
    /// Default [0,1,2] = gtk_idle > deferred > suspended.
    priority_order: [3]u8 = .{ 0, 1, 2 },
};

/// Chooses work at a cooperative instruction-quantum boundary.  Uses the
/// configurable priority_order to determine which category to run first.
/// GTK callbacks retain exclusive ownership while running.  Duration hints
/// let short callbacks complete before expensive deferred work begins.
/// Omitting suspended_threads lets a newly started spinner monopolize the
/// interpreter after the deferred queue becomes empty.
pub fn choose(inputs: Inputs) Work {
    if (inputs.idle_callback_running) return .none;

    const work_items: [3]struct { Work, bool, u64 } = .{
        .{ .gtk_idle, inputs.pending_idle != 0 and !inputs.callback_inflight and !inputs.idle_dispatch_blocked, inputs.estimated_gtk_idle_duration },
        .{ .deferred_thread, inputs.deferred_threads != 0, inputs.estimated_deferred_duration },
        .{ .suspended_thread, inputs.suspended_threads != 0, inputs.estimated_suspended_duration },
    };

    // Try each work category in the configured priority order.
    for (&inputs.priority_order) |order_index| {
        if (order_index >= 3) continue;
        const item = work_items[order_index];
        if (item[1]) return item[0];
    }

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

test "a blocked idle queue rotates threads instead of re-choosing idle work" {
    // Same inputs, with and without the dispatch block: the queue is pending
    // and nothing is in flight, so only the block distinguishes them.
    try std.testing.expectEqual(Work.gtk_idle, choose(.{ .pending_idle = 2, .suspended_threads = 2 }));
    try std.testing.expectEqual(Work.suspended_thread, choose(.{
        .pending_idle = 2,
        .idle_dispatch_blocked = true,
        .suspended_threads = 2,
    }));
    try std.testing.expectEqual(Work.deferred_thread, choose(.{
        .pending_idle = 2,
        .idle_dispatch_blocked = true,
        .deferred_threads = 1,
        .suspended_threads = 2,
    }));
    try std.testing.expectEqual(Work.none, choose(.{ .pending_idle = 2, .idle_dispatch_blocked = true }));
}

test "suspended UI callback does not freeze runnable workers" {
    try std.testing.expectEqual(Work.suspended_thread, choose(.{
        .pending_idle = 1,
        .callback_inflight = true,
        .idle_callback_running = false,
        .suspended_threads = 2,
    }));
}
