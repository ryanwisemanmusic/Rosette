//! The PE executor's stop-the-world gate, and the per-thread depth table the
//! Windows runtime lock tracks its reentrancy with.
//!
//! The gate itself is `lib/concurrency`'s safepoint `Gate`. The one that used
//! to live here admitted every guest step through a compare-and-swap on one
//! shared word and three scans of a thread-local table; with four host
//! threads that word bounced between cores on every instruction, and its
//! waits spun. The safepoint gate keeps the same API - step leases, reentrant
//! mutations that do not wait for their own thread's steps - with a step path
//! that writes only the calling thread's own cache line, and adds safe
//! regions for threads that must block mid-step.

const std = @import("std");
const concurrency = @import("concurrency");

pub const GuestExecutionGate = concurrency.Gate;

/// Per-host-thread nesting counts for owner-scoped operations. A fixed stack
/// makes nested guest callbacks and multi-process callbacks allocation-free.
///
/// Each level is either *pinned* - a critical section that must stay closed
/// until it unwinds - or a *dispatch* level, which only routes a call into
/// its handler: the step loop's import dispatch and the runtime's own entry
/// wrappers. A blocking wait deep inside a handler may let the underlying
/// lock go only when every level this thread holds is a dispatch level. The
/// Windows runtime's `GetMessage` never blocked on 2026-09-26 because the
/// step's dispatch and `tryFunction` together made the depth two, and the
/// wait refused anything but one.
pub const OwnerDepthStack = struct {
    const capacity = 32;
    const Entry = struct {
        owner: ?*anyopaque = null,
        depth: usize = 0,
        pinned: usize = 0,
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,

    pub fn find(self: *const OwnerDepthStack, owner: *anyopaque) ?usize {
        for (self.entries, 0..) |entry, index| {
            if (entry.owner == owner) return index;
        }
        return null;
    }

    pub fn contains(self: *const OwnerDepthStack, owner: *anyopaque) bool {
        return self.find(owner) != null;
    }

    pub fn depth(self: *const OwnerDepthStack, owner: *anyopaque) usize {
        const index = self.find(owner) orelse return 0;
        return self.entries[index].depth;
    }

    /// How many of `owner`'s levels are pinned critical sections.
    pub fn pinnedDepth(self: *const OwnerDepthStack, owner: *anyopaque) usize {
        const index = self.find(owner) orelse return 0;
        return self.entries[index].pinned;
    }

    pub fn push(self: *OwnerDepthStack, owner: *anyopaque, pinned: bool) usize {
        const pin: usize = @intFromBool(pinned);
        if (self.find(owner)) |index| {
            self.entries[index].depth += 1;
            self.entries[index].pinned += pin;
            return index;
        }
        for (&self.entries, 0..) |*entry, index| {
            if (entry.owner == null) {
                entry.* = .{ .owner = owner, .depth = 1, .pinned = pin };
                return index;
            }
        }
        @panic("guest execution gate nesting exceeded fixed TLS capacity");
    }

    /// Unwind one level, of the kind `push` recorded for it.
    pub fn pop(self: *OwnerDepthStack, index: usize, owner: *anyopaque, pinned: bool) void {
        std.debug.assert(index < self.entries.len);
        const entry = &self.entries[index];
        std.debug.assert(entry.owner == owner and entry.depth != 0);
        if (pinned) {
            std.debug.assert(entry.pinned != 0);
            entry.pinned -= 1;
        }
        entry.depth -= 1;
        if (entry.depth == 0) entry.* = .{};
    }
};

test "the processor's gate is the safepoint gate and keeps its lease API" {
    var gate: GuestExecutionGate = .{};
    var step = gate.enterStep();
    try std.testing.expectEqual(@as(usize, 1), gate.activeSteps());
    var mutation = gate.enterMutation();
    try std.testing.expect(gate.mutationPending());
    mutation.unlock();
    step.unlock();
    try std.testing.expectEqual(@as(usize, 0), gate.activeSteps());
    try std.testing.expect(!gate.mutationPending());
}

test "owner depth stacks count nesting per owner" {
    var stack: OwnerDepthStack = .{};
    var a: u8 = 0;
    var b: u8 = 0;
    const first = stack.push(@ptrCast(&a), true);
    const again = stack.push(@ptrCast(&a), true);
    try std.testing.expectEqual(first, again);
    try std.testing.expectEqual(@as(usize, 2), stack.depth(@ptrCast(&a)));
    const other = stack.push(@ptrCast(&b), true);
    try std.testing.expect(other != first);
    stack.pop(again, @ptrCast(&a), true);
    stack.pop(first, @ptrCast(&a), true);
    try std.testing.expect(!stack.contains(@ptrCast(&a)));
    stack.pop(other, @ptrCast(&b), true);
    try std.testing.expect(!stack.contains(@ptrCast(&b)));
}

test "dispatch levels leave a lock releasable and a pinned level does not" {
    var stack: OwnerDepthStack = .{};
    var owner: u8 = 0;
    // The step loop's import dispatch, then the runtime's entry wrapper: the
    // 2026-09-26 GetMessage shape, depth two and nothing pinned.
    const step_dispatch = stack.push(@ptrCast(&owner), false);
    const entry_wrapper = stack.push(@ptrCast(&owner), false);
    try std.testing.expectEqual(@as(usize, 2), stack.depth(@ptrCast(&owner)));
    try std.testing.expectEqual(@as(usize, 0), stack.pinnedDepth(@ptrCast(&owner)));
    // A handler's own critical section pins it.
    const critical = stack.push(@ptrCast(&owner), true);
    try std.testing.expectEqual(@as(usize, 1), stack.pinnedDepth(@ptrCast(&owner)));
    stack.pop(critical, @ptrCast(&owner), true);
    try std.testing.expectEqual(@as(usize, 0), stack.pinnedDepth(@ptrCast(&owner)));
    stack.pop(entry_wrapper, @ptrCast(&owner), false);
    stack.pop(step_dispatch, @ptrCast(&owner), false);
    try std.testing.expect(!stack.contains(@ptrCast(&owner)));
}
