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

/// The base every guest object handle carries.
///
/// Xenia's object table adds this to a slot index, so a guest handle is
/// `0xF8000000 | slot`. This is emulator-specific and is *not* the generic
/// NT convention of small four-byte-granular handles — a shape check written
/// from that convention accepts values the table can never produce and
/// rejects every real one.
///
/// `lib/gpu/kernel_surface.zig` sees these in the wild: the run's wait-object
/// report names `handle=0xf8000000`, which is slot zero.
pub const handle_base: Handle = 0xF800_0000;

/// The base host-side objects use, for objects the guest never names.
pub const handle_host_base: Handle = 0x0100_0000;

/// The slot index a guest handle carries.
pub fn slotOf(handle: Handle) Handle {
    return handle & ~handle_base;
}

/// Whether a handle belongs to the host rather than the guest.
///
/// Strictly between the two bases. A host handle that reaches a guest-facing
/// call is a leak of emulator internals into the title's address space.
pub fn isHostHandle(handle: Handle) bool {
    return handle > handle_host_base and handle < handle_base;
}

/// The object types the kernel tracks, in the emulator's own order.
///
/// Ordinals matter: they are serialised into save states and compared across
/// the object table, so this is the order `XObject::Type` declares rather than
/// a tidier one.
pub const ObjectType = enum(u32) {
    undefined = 0,
    enumerator = 1,
    event = 2,
    file = 3,
    io_completion = 4,
    module = 5,
    mutant = 6,
    notify_listener = 7,
    semaphore = 8,
    session = 9,
    socket = 10,
    symbolic_link = 11,
    thread = 12,
    timer = 13,
    device = 14,

    /// Whether the object carries a dispatcher header, and so can be waited on.
    ///
    /// A title that waits on a non-dispatcher object gets a status code, not a
    /// block. Waiting on a file handle is the common mistake and it looks like
    /// a hang if the wait is allowed to proceed.
    ///
    /// Note there is no process type: the console runs one title, so a wait on
    /// "the process" has no object behind it.
    pub fn isDispatcher(self: ObjectType) bool {
        return switch (self) {
            .event, .mutant, .semaphore, .thread, .timer => true,
            .undefined,
            .enumerator,
            .file,
            .io_completion,
            .module,
            .notify_listener,
            .session,
            .socket,
            .symbolic_link,
            .device,
            => false,
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

/// Whether a handle has the shape the object table produces.
///
/// Shape only. A true answer says the value could have come from the table,
/// never that it names a live object — this package cannot see the table and
/// must not appear to.
pub fn isPlausibleHandle(handle: Handle) bool {
    if (handle == null_handle) return false;
    if (isPseudoHandle(handle)) return false;
    return handle & handle_base == handle_base;
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
    if (handle_host_base >= handle_base) return false;
    if (isPlausibleHandle(null_handle)) return false;
    if (isPlausibleHandle(invalid_handle)) return false;
    if (!isPlausibleHandle(handle_base)) return false;
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
    try std.testing.expect(!isPseudoHandle(handle_base));
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
    try std.testing.expect(!isPlausibleHandle(0x100));
}

test "a guest handle carries the object table's base" {
    // 0xF8000000 is slot zero, and it is the handle the run's wait-object
    // report actually names. A shape check written from the generic NT
    // convention — small, four-byte granular — accepts values the table can
    // never produce and rejects every real one.
    try std.testing.expectEqual(@as(Handle, 0xF800_0000), handle_base);
    try std.testing.expect(isPlausibleHandle(handle_base));
    try std.testing.expect(isPlausibleHandle(handle_base | 1));
    try std.testing.expect(isPlausibleHandle(handle_base | 0x1234));
    try std.testing.expectEqual(@as(Handle, 0), slotOf(handle_base));
    try std.testing.expectEqual(@as(Handle, 0x1234), slotOf(handle_base | 0x1234));
}

test "host handles sit between the two bases" {
    // A host handle reaching a guest-facing call leaks emulator internals
    // into the title's address space, where it will be used as an object.
    try std.testing.expect(isHostHandle(handle_host_base + 1));
    try std.testing.expect(isHostHandle(0x0200_0000));
    // The bases themselves are not host handles.
    try std.testing.expect(!isHostHandle(handle_host_base));
    try std.testing.expect(!isHostHandle(handle_base));
    // Nor is a guest handle.
    try std.testing.expect(!isHostHandle(handle_base | 5));
    // A host handle is not a plausible guest handle.
    try std.testing.expect(!isPlausibleHandle(0x0200_0000));
}

test "a host pointer is not a guest handle" {
    // The 64/32 boundary. A host pointer truncated to 32 bits can land on a
    // perfectly well-shaped handle, so the width check has to happen before
    // the shape check, on the original value.
    try std.testing.expect(!isGuestHandleWidth(0x0000_7FFF_1234_5000));
    try std.testing.expect(!isGuestHandleWidth(0xFFFF_F600_0000_0021));
    try std.testing.expect(isGuestHandleWidth(0x0000_0100));
    try std.testing.expect(isGuestHandleWidth(std.math.maxInt(u32)));

    // Truncation of a host pointer does not land on a guest handle here,
    // because the base is checked — which is the practical benefit of the
    // emulator's high base over the generic small-integer convention.
    const truncated: Handle = @truncate(@as(u64, 0x0000_7FFF_1234_5000));
    try std.testing.expect(!isPlausibleHandle(truncated));
    // But a host pointer whose low word happens to carry the base would pass
    // the shape check, so the width test still has to run first.
    const colliding: Handle = @truncate(@as(u64, 0x0000_7FFF_F800_0001));
    try std.testing.expect(isPlausibleHandle(colliding));
    try std.testing.expect(!isGuestHandleWidth(0x0000_7FFF_F800_0001));
}

test "only dispatcher objects can be waited on" {
    try std.testing.expect(ObjectType.event.isDispatcher());
    try std.testing.expect(ObjectType.semaphore.isDispatcher());
    try std.testing.expect(ObjectType.mutant.isDispatcher());
    try std.testing.expect(ObjectType.timer.isDispatcher());
    try std.testing.expect(ObjectType.thread.isDispatcher());

    // Waiting on these returns a status, not a block. Letting a wait proceed
    // on a file handle presents as a hang with no wait graph entry.
    try std.testing.expect(!ObjectType.file.isDispatcher());
    try std.testing.expect(!ObjectType.io_completion.isDispatcher());
    try std.testing.expect(!ObjectType.module.isDispatcher());
    try std.testing.expect(!ObjectType.socket.isDispatcher());
    try std.testing.expect(!ObjectType.notify_listener.isDispatcher());
    try std.testing.expect(!ObjectType.device.isDispatcher());
}

test "the type ordinals are the emulator's, not a tidier order" {
    // They are serialised into save states and compared across the object
    // table, so the declaration order is load-bearing.
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(ObjectType.undefined));
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(ObjectType.event));
    try std.testing.expectEqual(@as(u32, 6), @intFromEnum(ObjectType.mutant));
    try std.testing.expectEqual(@as(u32, 12), @intFromEnum(ObjectType.thread));
    try std.testing.expectEqual(@as(u32, 14), @intFromEnum(ObjectType.device));
}

test "there is no process object" {
    // The console runs one title, so a wait on "the process" has no object
    // behind it. A contract that invents one makes such a wait look legal.
    inline for (@typeInfo(ObjectType).@"enum".fields) |field| {
        try std.testing.expect(!std.mem.eql(u8, field.name, "process"));
    }
}

test "only a mutant is owned by the thread that took it" {
    try std.testing.expect(ObjectType.mutant.hasThreadAffinity());
    try std.testing.expect(!ObjectType.semaphore.hasThreadAffinity());
    try std.testing.expect(!ObjectType.event.hasThreadAffinity());
}
