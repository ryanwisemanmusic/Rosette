//! Win32 mutex ownership in the wait model.
//!
//! Xenia backs every Xbox 360 mutant with a native Win32 mutex (`XMutant` ->
//! `xe::threading::Mutant` -> CreateMutex, WaitForSingleObjectEx, ReleaseMutex)
//! and has no recursion check of its own (`XObject::Wait`). A Win32 mutex is
//! owned and recursive:
//!   - its owner's wait is satisfied at once and counts one more acquisition;
//!   - only the owner may release it, once per acquisition (ERROR_NOT_OWNER);
//!   - the last release hands it to one waiter, which then owns it;
//!   - a thread that exits owning it abandons it to the next waiter.
//! Until 2026-10-12 Rosette modelled a mutex as an auto-reset flag with none of
//! this; see docs/halo3-mutex-stall-20261012.md for the stall that caused.
const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const WindowsWaitObject = __ProcessInternals._WindowsWaitObject;
const log = __ProcessInternals._log;
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_windows_sync = @import("windows_sync.zig");

/// A mutex's owner and acquisition count, for reports and tests.
pub const Ownership = struct { owner_thread_id: u64, recursion: u32 };

pub fn register(self: *ElfState, handle: u64, initially_owned: bool) void {
    if (process_impl_windows_sync.ensureWindowsWaitObject(self, handle)) |object| {
        object.* = .{
            .handle = handle,
            .kind = .mutex,
            .signaled = !initially_owned,
            // CreateMutex(bInitialOwner = TRUE) makes the caller the owner,
            // once: it may wait on its own mutex again and must release it
            // once more for every such wait.
            .owner_thread_id = if (initially_owned) process_impl_lifecycle.currentWindowsThreadId(self) else 0,
            .recursion = @intFromBool(initially_owned),
        };
        process_impl_windows_sync.noteWindowsWaitObjectCreated(self, object);
    }
}

pub fn owner(self: *const ElfState, handle: u64) ?Ownership {
    const index = process_impl_windows_sync.windowsWaitObjectIndex(self, handle) orelse return null;
    const object = self.windows_wait_objects[index];
    if (object.kind != .mutex) return null;
    return .{ .owner_thread_id = object.owner_thread_id, .recursion = object.recursion };
}

/// Whether the calling thread already owns `object`, a mutex.
pub fn ownedByCaller(self: *const ElfState, object: *const WindowsWaitObject) bool {
    return object.kind == .mutex and object.recursion != 0 and object.owner_thread_id != 0 and
        object.owner_thread_id == process_impl_lifecycle.currentWindowsThreadId(self);
}

/// The calling thread takes `object`, a mutex its wait found ready: it
/// becomes the owner, or, already owning it, acquires it once more.
pub fn take(self: *ElfState, object: *WindowsWaitObject) void {
    if (ownedByCaller(self, object)) {
        object.recursion +|= 1;
        object.recursive_acquisitions +|= 1;
    } else {
        object.owner_thread_id = process_impl_lifecycle.currentWindowsThreadId(self);
        object.recursion = 1;
    }
    object.signaled = false;
}

/// ReleaseMutex. Only the owning thread may release, once per acquisition;
/// anyone else gets FALSE and ERROR_NOT_OWNER. The last release frees it.
pub fn release(self: *ElfState, handle: u64) bool {
    const index = process_impl_windows_sync.windowsWaitObjectIndex(self, handle) orelse return false;
    const object = &self.windows_wait_objects[index];
    if (object.kind != .mutex) return false;
    if (!ownedByCaller(self, object)) {
        object.release_refusals +|= 1;
        process_impl_lifecycle.guestContextField(self, "windows_last_error").* = 288; // ERROR_NOT_OWNER
        return false;
    }
    object.recursion -= 1;
    if (object.recursion == 0) handOver(self, handle, object);
    return true;
}

/// A mutex its owner has finished with: hand it to one parked waiter, or
/// leave it signalled for the next wait. The hand-over is the transfer of
/// ownership itself. A resumed wait answers WAIT_OBJECT_0 without taking
/// anything, so a mutex left signalled after waking its waiter had two
/// owners as soon as any other thread waited on it. A wait-all waiter only
/// looks again, and takes the mutex when everything it waits on is ready.
fn handOver(self: *ElfState, handle: u64, object: *WindowsWaitObject) void {
    object.owner_thread_id = 0;
    object.recursion = 0;
    process_impl_windows_sync.noteWindowsWaitSignal(self, handle);
    process_impl_windows_sync.noteWindowsWaitObjectSignaled(self, object);
    object.signaled = true;
    process_impl_lifecycle.noteWindowsThreadWake(self);
    for (self.windows_guest_threads) |*thread| {
        const recheck = process_impl_windows_sync.wakeWindowsGuestWaiterForHandle(self, thread, handle) orelse continue;
        if (recheck) continue;
        // A slot without a thread id of its own cannot be named as the
        // owner: it resumes as it always did, with the mutex signalled.
        if (thread.thread_id == 0) return;
        object.owner_thread_id = thread.thread_id;
        object.recursion = 1;
        object.signaled = false;
        object.handoffs +|= 1;
        return;
    }
    process_impl_windows_sync.handOffToWaitingOwner(self, handle);
}

/// A thread that exits while owning mutexes abandons them: Windows frees
/// each one and hands it to the next waiter.
pub fn abandonOwnedBy(self: *ElfState, thread_id: u64) void {
    if (thread_id == 0) return;
    for (self.windows_wait_objects[0..self.windows_wait_object_high_water]) |*object| {
        if (object.kind != .mutex or object.recursion == 0 or object.owner_thread_id != thread_id) continue;
        object.abandoned +|= 1;
        handOver(self, object.handle, object);
    }
}

/// The ownership ledger across every live mutex, then each parked waiter's
/// mutex with its owner: a waiter parked behind a mutex its own thread holds
/// is a recursion the model must satisfy, and one behind a finished or
/// spinning owner is that owner's finding.
pub fn report(self: *const ElfState) void {
    var mutexes: u64 = 0;
    var owned: u64 = 0;
    var recursive: u64 = 0;
    var refusals: u64 = 0;
    var handoffs: u64 = 0;
    var abandoned: u64 = 0;
    for (self.windows_wait_objects[0..self.windows_wait_object_high_water]) |object| {
        if (object.kind != .mutex) continue;
        mutexes += 1;
        if (object.recursion != 0) owned += 1;
        recursive +|= object.recursive_acquisitions;
        refusals +|= object.release_refusals;
        handoffs +|= object.handoffs;
        abandoned +|= object.abandoned;
    }
    log.info("PE64 WINDOWS MUTEX OWNERSHIP: mutexes={d} owned={d} recursive_acquisitions={d} release_refusals={d} handoffs={d} abandoned={d}; owned and recursive as in Win32 (Xenia backs every Xbox 360 mutant with one): an owner's repeated wait is satisfied at once, a release by any other thread is refused with ERROR_NOT_OWNER, a last release hands the mutex to the waiter it wakes, and an exiting owner releases its mutexes. A nonzero release_refusals is a thread-identity mismatch to report", .{ mutexes, owned, recursive, refusals, handoffs, abandoned });
    for (self.windows_guest_threads) |*thread| {
        if (thread.status != .blocked or thread.blocked_wait_handle == 0) continue;
        const ownership = owner(self, thread.blocked_wait_handle) orelse continue;
        var owner_name: []const u8 = if (ownership.owner_thread_id == 0) "<free>" else "<not a guest worker>";
        var owner_status: []const u8 = "none";
        for (self.windows_guest_threads) |*candidate| {
            if (candidate.status == .vacant or candidate.thread_id != ownership.owner_thread_id) continue;
            owner_name = if (candidate.name_len != 0) candidate.nameText() else "<unnamed>";
            owner_status = @tagName(candidate.status);
            break;
        }
        log.info("PE64 WINDOWS MUTEX OWNERSHIP:   waiter='{s}' mutex=0x{x} owner_thread_id={d} owner='{s}' owner_status={s} recursion={d} waiter_is_owner={}", .{
            if (thread.name_len != 0) thread.nameText() else "<unnamed>",
            thread.blocked_wait_handle,
            ownership.owner_thread_id,
            owner_name,
            owner_status,
            ownership.recursion,
            ownership.owner_thread_id != 0 and ownership.owner_thread_id == thread.thread_id,
        });
    }
}
