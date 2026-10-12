//! Targeted routing from a signalled Win32 wait object to its guest worker.
//!
//! This isolates the runnable-slot transition from the large Win32 wait
//! implementation and records the slot for notification after the runtime
//! lock is released.

const process = @import("../../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const process_impl_lifecycle = @import("../lifecycle.zig");

/// Wake one matching worker while retaining the handle and one-shot result
/// long enough for its original wait import to return correctly. Null means
/// this thread did not wait on the object; true means a wait-all recheck.
pub fn wakeWindowsGuestWaiterForHandle(self: *ElfState, thread: *WindowsGuestThread, slot: usize, handle: u64) ?bool {
    if (thread.status != .blocked or !thread.waitsOnHandle(handle)) return null;
    const recheck = thread.blocked_wait_handle_count != 0 and thread.blocked_wait_all;
    thread.status = .runnable;
    process_impl_lifecycle.noteWindowsGuestWorkerWake(self, slot);
    thread.blocked_wait_handle = 0;
    thread.blocked_wait_timeout = 0;
    thread.blocked_wait_deadline = 0;
    thread.blocked_srw_lock = 0;
    thread.blocked_condition = 0;
    thread.blocked_wait_handle_count = 0;
    thread.blocked_wait_all = false;
    thread.wait_resume = true;
    thread.wait_resume_handle = handle;
    thread.wait_resume_timeout = false;
    thread.wait_resume_recheck = recheck;
    self.windows_thread_unblocks +|= 1;
    self.windows_wait_unblocks +|= 1;
    return recheck;
}
