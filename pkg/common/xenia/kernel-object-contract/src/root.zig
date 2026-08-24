//! Route-independent: the Xbox 360 kernel handle format and object type set.
//!
//! Handles are 32-bit values the title carries around and hands back to the
//! kernel. Their shape is an ABI, not an implementation choice.
//!
//! ## Why the handle *shape* matters and not just the value
//!
//! Guest handles are 32-bit. Host handles on a 64-bit Mac are not. Every place
//! the two meet is somewhere a host pointer can be truncated into a plausible
//! guest handle, or a guest handle sign-extended into a host pointer that
//! happens to be mapped. Neither faults. Keeping the guest handle a distinct
//! 32-bit type with an explicit validity predicate is what makes the boundary
//! visible at the point it is crossed.
//!
//! The pseudo-handles are the other half. `NtCurrentProcess` is `0xFFFFFFFF` —
//! the same bit pattern as an invalid handle. A table lookup that does not
//! check for pseudo-handles first will treat "the current process" as garbage,
//! and the failure surfaces as a title that cannot query itself.
//!
//! ## What this package is not
//!
//! * It is not a handle table. It maps nothing to anything; the live table is
//!   mutable state in `lib/`.
//! * It does not allocate handles. Which value a new object receives depends on
//!   what is already live, which is not a fact.
//! * It does not say a handle is open. `isPlausibleHandle` is a shape check.
//!   Only the live table knows whether a well-shaped handle names anything.
//!
//! Reference counting for the objects these handles name is
//! `pkg/common/xenia/ob-contract`.

const std = @import("std");

/// A guest kernel handle. 32-bit, and deliberately its own type so a host
/// pointer cannot be assigned to one without a visible cast.
pub const Handle = u32;

/// No object. Distinct from invalid: a null handle is an absent one.
pub const null_handle: Handle = 0;

/// The pseudo-handle for the calling process, and the value a failed call
/// returns. Same bit pattern, different meanings by context — which is exactly
/// why a lookup must test for pseudo-handles before consulting the table.
pub const invalid_handle: Handle = 0xFFFF_FFFF;
pub const current_process: Handle = 0xFFFF_FFFF;
pub const current_thread: Handle = 0xFFFF_FFFE;

/// Handles are granular: the low two bits are not part of the index. A value
/// that is not a multiple of four was never produced by the kernel.
pub const handle_granularity: Handle = 4;

/// The first handle the kernel hands out. Low values are reserved so that a
/// small integer mistaken for a handle fails the shape check instead of
/// naming object zero.
pub const first_handle: Handle = 0x0000_0100;

pub const ObjectType = enum(u8) {
    event,
    semaphore,
    mutant,
    timer,
    thread,
    process,
    file,
    directory,
    device,
    io_completion,
    symbolic_link,
    module,
    socket,

    /// Whether a wait can be satisfied by this object.
    ///
    /// A title that waits on a non-dispatcher object gets a status code, not a
    /// block. Waiting on a file handle is the common mistake and it looks like
    /// a hang if the wait is allowed to proceed.
    pub fn isDispatcher(self: ObjectType) bool {
        return switch (self) {
            .event, .semaphore, .mutant, .timer, .thread, .process => true,
            .file, .directory, .device, .io_completion, .symbolic_link, .module, .socket => false,
        };
    }

    /// Whether the object carries ownership that must be released by the same
    /// thread that took it.
    pub fn hasThreadAffinity(self: ObjectType) bool {
        return self == .mutant;
    }
};

/// Whether a handle is one of the kernel's pseudo-handles.
///
/// Must be consulted before any table lookup.
pub fn isPseudoHandle(handle: Handle) bool {
    return handle == current_process or handle == current_thread;
}

/// Whether a handle has the shape the kernel produces.
///
/// Shape only. A true answer says the value could have come from the kernel,
/// never that it names a live object — this package cannot see the table and
/// must not appear to.
pub fn isPlausibleHandle(handle: Handle) bool {
    if (handle == null_handle) return false;
    if (isPseudoHandle(handle)) return false;
    if (handle < first_handle) return false;
    return handle % handle_granularity == 0;
}

/// Whether a 64-bit value could be a guest handle that survived a host round
/// trip intact.
///
/// The check that catches a truncated host pointer. A host pointer with
/// anything in its high 32 bits is not a guest handle, and calling it one is
/// how a mapped host address becomes a "valid" handle.
pub fn isGuestHandleWidth(value: u64) bool {
    return value <= std.math.maxInt(u32);
}

pub fn contractIsWellFormed() bool {
    if (first_handle % handle_granularity != 0) return false;
    if (isPlausibleHandle(null_handle)) return false;
    if (isPlausibleHandle(invalid_handle)) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "null and invalid are different absences" {
    try std.testing.expectEqual(@as(Handle, 0), null_handle);
    try std.testing.expectEqual(@as(Handle, 0xFFFF_FFFF), invalid_handle);
    try std.testing.expect(null_handle != invalid_handle);
    try std.testing.expect(!isPlausibleHandle(null_handle));
    try std.testing.expect(!isPlausibleHandle(invalid_handle));
}

test "the current-process pseudo-handle shares invalid's bit pattern" {
    // The trap. These are the same 32 bits, and only context separates them,
    // so a lookup that does not check for pseudo-handles first turns "query
    // myself" into "bad handle".
    try std.testing.expectEqual(invalid_handle, current_process);
    try std.testing.expect(isPseudoHandle(current_process));
    try std.testing.expect(isPseudoHandle(current_thread));
    try std.testing.expect(!isPseudoHandle(first_handle));
    // A pseudo-handle is never table-plausible; it must be resolved earlier.
    try std.testing.expect(!isPlausibleHandle(current_process));
    try std.testing.expect(!isPlausibleHandle(current_thread));
}

test "small integers are not handles" {
    // A loop counter or an errno that reaches a handle parameter must fail
    // the shape check rather than naming an object.
    try std.testing.expect(!isPlausibleHandle(1));
    try std.testing.expect(!isPlausibleHandle(4));
    try std.testing.expect(!isPlausibleHandle(0xFF));
    try std.testing.expect(isPlausibleHandle(first_handle));
}

test "handles are four-byte granular" {
    try std.testing.expect(isPlausibleHandle(0x100));
    try std.testing.expect(isPlausibleHandle(0x104));
    try std.testing.expect(!isPlausibleHandle(0x101));
    try std.testing.expect(!isPlausibleHandle(0x102));
    try std.testing.expect(!isPlausibleHandle(0x103));
}

test "a host pointer is not a guest handle" {
    // The 64/32 boundary. A host pointer truncated to 32 bits can land on a
    // perfectly well-shaped handle, so the width check has to happen before
    // the shape check, on the original value.
    try std.testing.expect(!isGuestHandleWidth(0x0000_7FFF_1234_5000));
    try std.testing.expect(!isGuestHandleWidth(0xFFFF_F600_0000_0021));
    try std.testing.expect(isGuestHandleWidth(0x0000_0100));
    try std.testing.expect(isGuestHandleWidth(std.math.maxInt(u32)));

    // Truncation alone would have made the first one look fine.
    const truncated: Handle = @truncate(@as(u64, 0x0000_7FFF_1234_5000));
    try std.testing.expect(isPlausibleHandle(truncated));
}

test "only dispatcher objects can be waited on" {
    try std.testing.expect(ObjectType.event.isDispatcher());
    try std.testing.expect(ObjectType.semaphore.isDispatcher());
    try std.testing.expect(ObjectType.mutant.isDispatcher());
    try std.testing.expect(ObjectType.timer.isDispatcher());
    try std.testing.expect(ObjectType.thread.isDispatcher());
    try std.testing.expect(ObjectType.process.isDispatcher());

    // Waiting on these returns a status, not a block. Letting a wait proceed
    // on a file handle presents as a hang with no wait graph entry.
    try std.testing.expect(!ObjectType.file.isDispatcher());
    try std.testing.expect(!ObjectType.io_completion.isDispatcher());
    try std.testing.expect(!ObjectType.module.isDispatcher());
    try std.testing.expect(!ObjectType.socket.isDispatcher());
}

test "only a mutant is owned by the thread that took it" {
    try std.testing.expect(ObjectType.mutant.hasThreadAffinity());
    try std.testing.expect(!ObjectType.semaphore.hasThreadAffinity());
    try std.testing.expect(!ObjectType.event.hasThreadAffinity());
}
