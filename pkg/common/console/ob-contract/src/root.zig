//! Route-independent: the Xbox 360 object manager's reference-counting rules.
//!
//! The kernel counts references to an object in *two* independent ways, and the
//! object is destroyed when both reach zero. That rule is the whole package.
//!
//! ## Why two counts, and why this is worth pinning
//!
//! A handle is a name a title holds; a pointer reference is one the kernel or a
//! driver holds. `NtClose` retires the name. `ObDereferenceObject` releases the
//! pointer. They are not the same count, and collapsing them into one — the
//! obvious simplification — produces exactly two bugs, both bad:
//!
//! * Merged so that closing a handle frees the object: a thread still running
//!   inside it keeps using freed memory. This is the shape behind
//!   "`pthread_join` returned early and the caller freed an object a live
//!   thread still uses" — the object outlived its handle, and it was supposed
//!   to.
//! * Merged the other way, so nothing frees: every object the title ever
//!   opened leaks, and a long run dies of address-space exhaustion far from
//!   the leak.
//!
//! Neither reports anything at the moment the mistake is made. A transition
//! function that a test can exhaustively drive is the only cheap way to be
//! sure the rule is the one the kernel implements.
//!
//! ## What this package is not
//!
//! * It is not an object table. It stores no objects and no counts; the live
//!   table is mutable process state and belongs in `lib/`.
//! * It does not free anything. `shouldDestroy` reports that the condition for
//!   destruction is met; performing it is an effect.
//! * It does not allocate handles. Which handle value a new object gets is a
//!   decision about live state, not a fact.

const std = @import("std");

/// A kernel object's two reference counts.
///
/// A value, not a record of anything: the caller owns the storage and this
/// package only says how the numbers move.
pub const ReferenceCounts = struct {
    /// Names the title holds. Incremented by an open or duplicate, decremented
    /// by a close.
    handle_count: u32 = 0,
    /// Pointers the kernel holds. Incremented by a reference, decremented by a
    /// dereference.
    pointer_count: u32 = 0,

    /// Whether the object may be destroyed.
    ///
    /// Both, not either. This single `and` is the rule the package exists for.
    pub fn shouldDestroy(self: ReferenceCounts) bool {
        return self.handle_count == 0 and self.pointer_count == 0;
    }

    /// Whether the title can still name the object.
    pub fn isNamed(self: ReferenceCounts) bool {
        return self.handle_count > 0;
    }
};

pub const Transition = enum {
    /// A handle was created: `NtCreate*`, `NtOpen*`, or a duplicate.
    open_handle,
    /// `NtClose`.
    close_handle,
    /// `ObReferenceObject`.
    reference,
    /// `ObDereferenceObject`.
    dereference,
};

pub const TransitionError = error{
    /// A close with no handle outstanding, or a dereference with no reference.
    /// Always a defect in the caller: the kernel has nothing to decrement, and
    /// wrapping to `0xFFFFFFFF` would make the object immortal.
    UnderflowedReferenceCount,
    /// The count saturated. Refusing is correct — wrapping to zero would free
    /// a live object.
    OverflowedReferenceCount,
};

/// Apply one transition, returning the new counts.
///
/// Pure: it takes counts and returns counts. Underflow is an error rather than
/// a saturating floor, because a spurious close is a real bug in the caller and
/// silently clamping it to zero hides the double-close that caused it.
pub fn applyTransition(counts: ReferenceCounts, transition: Transition) TransitionError!ReferenceCounts {
    var next = counts;
    switch (transition) {
        .open_handle => {
            if (next.handle_count == std.math.maxInt(u32)) return error.OverflowedReferenceCount;
            next.handle_count += 1;
        },
        .close_handle => {
            if (next.handle_count == 0) return error.UnderflowedReferenceCount;
            next.handle_count -= 1;
        },
        .reference => {
            if (next.pointer_count == std.math.maxInt(u32)) return error.OverflowedReferenceCount;
            next.pointer_count += 1;
        },
        .dereference => {
            if (next.pointer_count == 0) return error.UnderflowedReferenceCount;
            next.pointer_count -= 1;
        },
    }
    return next;
}

/// The counts a freshly created object starts with.
///
/// One handle and one pointer. The creating call holds both: the title gets the
/// handle back, and the kernel's own reference is what keeps the object alive
/// across the return.
pub const created: ReferenceCounts = .{ .handle_count = 1, .pointer_count = 1 };

/// The standard package entry point.
///
/// The invariant that matters is the `and` in `shouldDestroy`: an object dies
/// only when *both* counts reach zero. Collapsing it to `or` frees objects a
/// running thread still holds, which is the use-after-free this package was
/// written to prevent, so it is checked at startup rather than assumed.
pub fn contractIsWellFormed() bool {
    const both_held = ReferenceCounts{ .handle_count = 1, .pointer_count = 1 };
    if (both_held.shouldDestroy()) return false;
    const handle_only = ReferenceCounts{ .handle_count = 1 };
    if (handle_only.shouldDestroy()) return false;
    const pointer_only = ReferenceCounts{ .pointer_count = 1 };
    if (pointer_only.shouldDestroy()) return false;
    const released = ReferenceCounts{};
    if (!released.shouldDestroy()) return false;
    if (created.shouldDestroy()) return false;
    return true;
}

test "a new object is not destroyable" {
    try std.testing.expect(!created.shouldDestroy());
    try std.testing.expect(created.isNamed());
}

test "closing the last handle does not destroy an object the kernel still holds" {
    // The rule that keeps a running thread's object alive after the title
    // closed its handle. Merging the counts breaks exactly this case, and the
    // symptom is a use-after-free inside the thread, nowhere near the close.
    const after_close = try applyTransition(created, .close_handle);
    try std.testing.expectEqual(@as(u32, 0), after_close.handle_count);
    try std.testing.expectEqual(@as(u32, 1), after_close.pointer_count);
    try std.testing.expect(!after_close.shouldDestroy());
    try std.testing.expect(!after_close.isNamed());

    // Only when the kernel lets go too.
    const after_deref = try applyTransition(after_close, .dereference);
    try std.testing.expect(after_deref.shouldDestroy());
}

test "dereferencing to zero does not destroy an object the title still names" {
    // The mirror image: the kernel is done, the title is not.
    const after_deref = try applyTransition(created, .dereference);
    try std.testing.expectEqual(@as(u32, 1), after_deref.handle_count);
    try std.testing.expect(!after_deref.shouldDestroy());
    try std.testing.expect(after_deref.isNamed());

    const after_close = try applyTransition(after_deref, .close_handle);
    try std.testing.expect(after_close.shouldDestroy());
}

test "destruction requires both counts, in either order" {
    // Order independence is the property. Whichever side releases last is the
    // one that destroys, and both orders must reach the same place.
    const close_first = try applyTransition(try applyTransition(created, .close_handle), .dereference);
    const deref_first = try applyTransition(try applyTransition(created, .dereference), .close_handle);
    try std.testing.expect(close_first.shouldDestroy());
    try std.testing.expect(deref_first.shouldDestroy());
    try std.testing.expectEqual(close_first, deref_first);
}

test "a double close is refused rather than wrapped" {
    // Wrapping would take the count to 0xFFFFFFFF and make the object
    // immortal — a leak that presents as memory exhaustion much later.
    const once = try applyTransition(created, .close_handle);
    try std.testing.expectError(error.UnderflowedReferenceCount, applyTransition(once, .close_handle));
    // And a stray dereference, likewise.
    const zeroed = ReferenceCounts{};
    try std.testing.expectError(error.UnderflowedReferenceCount, applyTransition(zeroed, .dereference));
    try std.testing.expectError(error.UnderflowedReferenceCount, applyTransition(zeroed, .close_handle));
}

test "saturating counts are refused rather than wrapped to zero" {
    // Wrapping the other way frees a live object.
    const saturated = ReferenceCounts{
        .handle_count = std.math.maxInt(u32),
        .pointer_count = std.math.maxInt(u32),
    };
    try std.testing.expectError(error.OverflowedReferenceCount, applyTransition(saturated, .open_handle));
    try std.testing.expectError(error.OverflowedReferenceCount, applyTransition(saturated, .reference));
}

test "many opens need exactly as many closes" {
    var counts = ReferenceCounts{};
    var index: u32 = 0;
    while (index < 100) : (index += 1) {
        counts = try applyTransition(counts, .open_handle);
    }
    try std.testing.expectEqual(@as(u32, 100), counts.handle_count);
    try std.testing.expect(!counts.shouldDestroy());

    index = 0;
    while (index < 99) : (index += 1) {
        counts = try applyTransition(counts, .close_handle);
    }
    try std.testing.expect(!counts.shouldDestroy());
    counts = try applyTransition(counts, .close_handle);
    try std.testing.expect(counts.shouldDestroy());
}

test "the two counts do not interfere" {
    // A reference must not satisfy a close, and vice versa. This is the
    // property that a single merged counter silently violates.
    var counts = created;
    counts = try applyTransition(counts, .reference);
    counts = try applyTransition(counts, .reference);
    try std.testing.expectEqual(@as(u32, 1), counts.handle_count);
    try std.testing.expectEqual(@as(u32, 3), counts.pointer_count);

    counts = try applyTransition(counts, .close_handle);
    try std.testing.expectEqual(@as(u32, 0), counts.handle_count);
    try std.testing.expectEqual(@as(u32, 3), counts.pointer_count);
    try std.testing.expect(!counts.shouldDestroy());
}
