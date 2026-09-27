//! Bounded evidence for the Win32 UI-message handoff used by Xenia.
//!
//! Xenia schedules startup and presenter work onto its UI thread by posting
//! WM_USER to a message-only window. Keeping these counters outside the large
//! PE process state makes that handoff independently testable.
//!
//! With guest threads on their own host threads the handoff crosses threads
//! for real: the Emulator thread posts and waits, the UI thread dequeues,
//! runs the function in its WndProc and returns. Each leg is timed, so a
//! handoff that stalls says which leg it stalled in.

const std = @import("std");

pub const xenia_pending_function_message: u32 = 0x0400; // WM_USER

/// The class Xenia's `Win32WindowedAppContext` registers for the window its
/// pending functions are posted to. SDL and Xenia's other subsystems create
/// message-only windows too; this one is identified by its class, not by
/// being the latest.
pub const xenia_pending_function_class = "XeniaPendingFunctionsWindowClass";

/// How many posted-but-not-dequeued handoffs keep their post time.
const post_time_capacity = 16;
/// How deeply pending-function dispatches may nest (a pending function that
/// runs a modal loop dispatches the next one inside itself).
const dispatch_time_capacity = 8;

pub const Ledger = struct {
    class_registrations: u64 = 0,
    windows_created: u64 = 0,
    message_windows_created: u64 = 0,
    post_attempts: u64 = 0,
    posted: u64 = 0,
    post_drops: u64 = 0,
    dequeued: u64 = 0,
    dispatch_attempts: u64 = 0,
    dispatch_without_wndproc: u64 = 0,
    callback_frame_refusals: u64 = 0,
    callback_returns: u64 = 0,
    pending_function_posts: u64 = 0,
    pending_function_post_drops: u64 = 0,
    pending_function_dequeues: u64 = 0,
    pending_function_dispatches: u64 = 0,
    pending_function_dispatch_without_wndproc: u64 = 0,
    pending_function_frame_refusals: u64 = 0,
    pending_function_returns: u64 = 0,
    message_window_handle: u64 = 0,
    message_window_wndproc: u64 = 0,
    message_window_user_data: u64 = 0,
    last_post_hwnd: u64 = 0,
    last_post_message: u32 = 0,
    last_pending_post_wparam: u64 = 0,
    last_pending_post_lparam: u64 = 0,
    last_pending_post_thread: u64 = 0,
    last_pending_post_return_rip: u64 = 0,
    last_pending_post_step: u64 = 0,
    last_pending_dequeue_wparam: u64 = 0,
    last_pending_dequeue_lparam: u64 = 0,
    last_pending_dequeue_thread: u64 = 0,
    last_dispatch_hwnd: u64 = 0,
    last_dispatch_message: u32 = 0,
    last_dispatch_wndproc: u64 = 0,
    last_pending_dispatch_wparam: u64 = 0,
    last_pending_dispatch_lparam: u64 = 0,
    last_pending_dispatch_thread: u64 = 0,
    /// Monotonic ns of each queued pending-function post, oldest first, so a
    /// dequeue can say how long its message waited.
    post_times: [post_time_capacity]u64 = @splat(0),
    post_time_count: usize = 0,
    dispatch_times: [dispatch_time_capacity]u64 = @splat(0),
    dispatch_time_depth: usize = 0,
    /// Post to dequeue, and dispatch to return, for pending functions.
    queued_ns_total: u64 = 0,
    queued_ns_max: u64 = 0,
    ran_ns_total: u64 = 0,
    ran_ns_max: u64 = 0,
    /// The legs of the most recent pending function, for a report.
    last_queued_ns: u64 = 0,
    last_ran_ns: u64 = 0,
    /// A pending function has been dispatched and has not returned: the UI
    /// thread is inside it (Xenia's presenter creation runs here).
    pending_function_in_progress_since_ns: u64 = 0,

    pub fn noteClassRegistered(self: *Ledger) void {
        self.class_registrations +|= 1;
    }

    /// `pending_functions_window` is true for the window of Xenia's own
    /// pending-functions class. Without one, the first message-only window
    /// stands in; a later one never replaces the one being followed.
    pub fn noteWindowCreated(self: *Ledger, handle: u64, message_only: bool, wndproc: u64, user_data: u64, pending_functions_window: bool) void {
        self.windows_created +|= 1;
        if (!message_only) return;
        self.message_windows_created +|= 1;
        if (!pending_functions_window and self.message_window_handle != 0) return;
        self.message_window_handle = handle;
        self.message_window_wndproc = wndproc;
        self.message_window_user_data = user_data;
    }

    pub fn notePost(self: *Ledger, hwnd: u64, message: u32, wparam: u64, lparam: u64, thread: u64, return_rip: u64, step: u64, accepted: bool) void {
        self.post_attempts +|= 1;
        self.last_post_hwnd = hwnd;
        self.last_post_message = message;
        if (accepted) {
            self.posted +|= 1;
        } else {
            self.post_drops +|= 1;
        }
        if (!self.isPendingFunctionMessage(hwnd, message)) return;
        self.last_pending_post_wparam = wparam;
        self.last_pending_post_lparam = lparam;
        self.last_pending_post_thread = thread;
        self.last_pending_post_return_rip = return_rip;
        self.last_pending_post_step = step;
        if (accepted) {
            self.pending_function_posts +|= 1;
        } else {
            self.pending_function_post_drops +|= 1;
        }
    }

    /// Time a pending-function post that was accepted into the queue.
    pub fn notePendingPostTime(self: *Ledger, now_ns: u64) void {
        if (self.post_time_count == post_time_capacity) {
            std.mem.copyForwards(u64, self.post_times[0 .. post_time_capacity - 1], self.post_times[1..]);
            self.post_time_count -= 1;
        }
        self.post_times[self.post_time_count] = now_ns;
        self.post_time_count += 1;
    }

    /// A pending-function message left the queue: how long it waited there,
    /// or null when its post was not timed.
    pub fn notePendingDequeueTime(self: *Ledger, now_ns: u64) ?u64 {
        if (self.post_time_count == 0) return null;
        const posted = self.post_times[0];
        std.mem.copyForwards(u64, self.post_times[0 .. self.post_time_count - 1], self.post_times[1..self.post_time_count]);
        self.post_time_count -= 1;
        const queued = now_ns -| posted;
        self.queued_ns_total +|= queued;
        self.queued_ns_max = @max(self.queued_ns_max, queued);
        self.last_queued_ns = queued;
        return queued;
    }

    pub fn notePendingDispatchTime(self: *Ledger, now_ns: u64) void {
        if (self.dispatch_time_depth < dispatch_time_capacity) self.dispatch_times[self.dispatch_time_depth] = now_ns;
        self.dispatch_time_depth += 1;
        if (self.dispatch_time_depth == 1) self.pending_function_in_progress_since_ns = now_ns;
    }

    /// A pending function's WndProc returned: how long it ran, or null when
    /// its dispatch was not timed.
    pub fn notePendingReturnTime(self: *Ledger, now_ns: u64) ?u64 {
        if (self.dispatch_time_depth == 0) return null;
        self.dispatch_time_depth -= 1;
        if (self.dispatch_time_depth == 0) self.pending_function_in_progress_since_ns = 0;
        if (self.dispatch_time_depth >= dispatch_time_capacity) return null;
        const ran = now_ns -| self.dispatch_times[self.dispatch_time_depth];
        self.ran_ns_total +|= ran;
        self.ran_ns_max = @max(self.ran_ns_max, ran);
        self.last_ran_ns = ran;
        return ran;
    }

    pub fn noteDequeued(self: *Ledger, hwnd: u64, message: u32, wparam: u64, lparam: u64, thread: u64) void {
        self.dequeued +|= 1;
        if (!self.isPendingFunctionMessage(hwnd, message)) return;
        self.pending_function_dequeues +|= 1;
        self.last_pending_dequeue_wparam = wparam;
        self.last_pending_dequeue_lparam = lparam;
        self.last_pending_dequeue_thread = thread;
    }

    pub fn noteDispatch(self: *Ledger, hwnd: u64, message: u32, wparam: u64, lparam: u64, thread: u64, wndproc: u64) bool {
        self.dispatch_attempts +|= 1;
        self.last_dispatch_hwnd = hwnd;
        self.last_dispatch_message = message;
        self.last_dispatch_wndproc = wndproc;
        if (wndproc == 0) self.dispatch_without_wndproc +|= 1;
        if (!self.isPendingFunctionMessage(hwnd, message)) return false;
        self.last_pending_dispatch_wparam = wparam;
        self.last_pending_dispatch_lparam = lparam;
        self.last_pending_dispatch_thread = thread;
        if (wndproc == 0) {
            self.pending_function_dispatch_without_wndproc +|= 1;
        } else {
            self.pending_function_dispatches +|= 1;
        }
        return true;
    }

    pub fn noteCallbackFrameRefused(self: *Ledger, pending_function: bool) void {
        self.callback_frame_refusals +|= 1;
        if (pending_function) self.pending_function_frame_refusals +|= 1;
    }

    pub fn noteCallbackReturned(self: *Ledger, pending_function: bool) void {
        self.callback_returns +|= 1;
        if (pending_function) self.pending_function_returns +|= 1;
    }

    pub fn isPendingFunctionMessage(self: *const Ledger, hwnd: u64, message: u32) bool {
        return self.message_window_handle != 0 and
            hwnd == self.message_window_handle and
            message == xenia_pending_function_message;
    }
};

test "Xenia pending-function handoff is counted through dispatch return" {
    var ledger = Ledger{};
    ledger.noteWindowCreated(0x100, true, 0x200, 0x300, true);
    ledger.notePost(0x100, xenia_pending_function_message, 0, 0, 0x400, 0x600, 77, true);
    ledger.noteDequeued(0x100, xenia_pending_function_message, 0, 0, 0x500);
    const pending = ledger.noteDispatch(0x100, xenia_pending_function_message, 0, 0, 0x500, 0x200);
    ledger.noteCallbackReturned(pending);

    try std.testing.expectEqual(@as(u64, 1), ledger.pending_function_posts);
    try std.testing.expectEqual(@as(u64, 1), ledger.pending_function_dequeues);
    try std.testing.expectEqual(@as(u64, 1), ledger.pending_function_dispatches);
    try std.testing.expectEqual(@as(u64, 1), ledger.pending_function_returns);
    try std.testing.expectEqual(@as(u64, 0x400), ledger.last_pending_post_thread);
    try std.testing.expectEqual(@as(u64, 0x600), ledger.last_pending_post_return_rip);
    try std.testing.expectEqual(@as(u64, 77), ledger.last_pending_post_step);
    try std.testing.expectEqual(@as(u64, 0x500), ledger.last_pending_dispatch_thread);
}

test "unrelated window messages do not count as Xenia pending work" {
    var ledger = Ledger{};
    ledger.noteWindowCreated(0x100, true, 0x200, 0x300, true);
    ledger.notePost(0x100, 0x0010, 0, 0, 0, 0, 0, true);
    ledger.notePost(0x101, xenia_pending_function_message, 0, 0, 0, 0, 0, true);

    try std.testing.expectEqual(@as(u64, 2), ledger.posted);
    try std.testing.expectEqual(@as(u64, 0), ledger.pending_function_posts);
}

test "a later message-only window does not replace Xenia's pending-functions window" {
    var ledger = Ledger{};
    // An unnamed message-only window first, then Xenia's, then SDL's helper.
    ledger.noteWindowCreated(0x10, true, 0x20, 0, false);
    try std.testing.expectEqual(@as(u64, 0x10), ledger.message_window_handle);
    ledger.noteWindowCreated(0x13, true, 0x1403eca00, 0x1c40b3e68, true);
    ledger.noteWindowCreated(0x58, true, 0x14100e170, 0, false);
    try std.testing.expectEqual(@as(u64, 0x13), ledger.message_window_handle);
    try std.testing.expect(ledger.isPendingFunctionMessage(0x13, xenia_pending_function_message));
    try std.testing.expect(!ledger.isPendingFunctionMessage(0x58, xenia_pending_function_message));
    try std.testing.expectEqual(@as(u64, 3), ledger.message_windows_created);
}

test "each leg of a pending-function handoff is timed" {
    var ledger = Ledger{};
    ledger.notePendingPostTime(1_000);
    ledger.notePendingPostTime(2_000);
    try std.testing.expectEqual(@as(?u64, 4_000), ledger.notePendingDequeueTime(5_000));
    ledger.notePendingDispatchTime(6_000);
    try std.testing.expectEqual(@as(u64, 6_000), ledger.pending_function_in_progress_since_ns);
    try std.testing.expectEqual(@as(?u64, 3_000), ledger.notePendingReturnTime(9_000));
    try std.testing.expectEqual(@as(u64, 0), ledger.pending_function_in_progress_since_ns);
    try std.testing.expectEqual(@as(?u64, 8_000), ledger.notePendingDequeueTime(10_000));
    try std.testing.expectEqual(@as(?u64, null), ledger.notePendingDequeueTime(11_000));
    try std.testing.expectEqual(@as(u64, 8_000), ledger.queued_ns_max);
    try std.testing.expectEqual(@as(?u64, null), ledger.notePendingReturnTime(12_000));
}
