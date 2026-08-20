//! Guest-visible GPU interrupt and wait-state bookkeeping.
//!
//! Xenos completion events can either wake a registered callback or satisfy a
//! polling `WAIT_REG_MEM`.  The controller is kept separate from the PM4
//! decoder so a driver-facing fence and a guest-facing interrupt remain two
//! observable stages instead of one optimistic counter.

const std = @import("std");

pub const EventKind = enum(u8) { draw_complete, resolve_complete, swap_complete, fence, custom };

pub const Event = struct {
    kind: EventKind,
    id: u32,
    value: u32,
    sequence: u64,
};

pub const Callback = *const fn (context: *anyopaque, event: Event) void;

pub const Wait = struct {
    register: u32,
    mask: u32,
    reference: u32,
    equal: bool,
    active: bool = true,

    pub fn satisfied(self: Wait, value: u32) bool {
        const matches = value & self.mask == self.reference & self.mask;
        return if (self.equal) matches else !matches;
    }
};

pub const Controller = struct {
    callback: ?Callback = null,
    callback_context: ?*anyopaque = null,
    pending: [64]Event = undefined,
    pending_count: u8 = 0,
    sequence: u64 = 0,
    delivered: u64 = 0,
    coalesced: u64 = 0,
    dropped: u64 = 0,
    last_event: ?Event = null,
    wait: ?Wait = null,
    wait_satisfied_count: u64 = 0,

    pub fn register(self: *Controller, callback: Callback, context: *anyopaque) void {
        self.callback = callback;
        self.callback_context = context;
    }

    pub fn unregister(self: *Controller) void {
        self.callback = null;
        self.callback_context = null;
    }

    pub fn armWait(self: *Controller, wait: Wait) void {
        self.wait = wait;
    }

    pub fn cancelWait(self: *Controller) void {
        self.wait = null;
    }

    pub fn publish(self: *Controller, kind: EventKind, id: u32, value: u32) void {
        self.sequence +%= 1;
        const event = Event{ .kind = kind, .id = id, .value = value, .sequence = self.sequence };
        self.last_event = event;
        if (self.wait) |*wait| {
            if (wait.active and wait.register == id and wait.satisfied(value)) {
                wait.active = false;
                self.wait_satisfied_count +%= 1;
            }
        }
        // Coalesce events for the same source while one is already queued. This
        // mirrors GPU interrupt moderation without losing the most recent value.
        var index: usize = 0;
        while (index < self.pending_count) : (index += 1) {
            if (self.pending[index].kind == kind and self.pending[index].id == id) {
                self.pending[index] = event;
                self.coalesced +%= 1;
                return;
            }
        }
        if (self.pending_count == self.pending.len) {
            self.dropped +%= 1;
            return;
        }
        self.pending[self.pending_count] = event;
        self.pending_count += 1;
    }

    pub fn drain(self: *Controller, max_events: u8) u8 {
        var delivered_now: u8 = 0;
        while (delivered_now < max_events and self.pending_count != 0) {
            const event = self.pending[0];
            if (self.pending_count > 1) std.mem.copyForwards(Event, self.pending[0 .. self.pending_count - 1], self.pending[1..self.pending_count]);
            self.pending_count -= 1;
            delivered_now += 1;
            self.delivered +%= 1;
            if (self.callback) |callback| callback(self.callback_context orelse @ptrCast(@constCast(self)), event);
        }
        return delivered_now;
    }

    pub fn waitSatisfied(self: *const Controller) bool {
        return if (self.wait) |wait| !wait.active else false;
    }
};

test "interrupts coalesce per source and satisfy register waits" {
    var controller: Controller = .{};
    controller.armWait(.{ .register = 7, .mask = 0xFF, .reference = 3, .equal = true });
    controller.publish(.draw_complete, 7, 1);
    controller.publish(.draw_complete, 7, 3);
    try std.testing.expect(controller.waitSatisfied());
    try std.testing.expectEqual(@as(u64, 1), controller.coalesced);
    try std.testing.expectEqual(@as(u8, 1), controller.drain(8));
    try std.testing.expectEqual(@as(u64, 1), controller.delivered);
}
