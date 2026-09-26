//! What ended a run, recorded at the place that decided it, and the notable
//! events that led up to it.
//!
//! A run used to end with only `termination_reason`, an enum shared by ~30
//! decision sites. When one of them was `runtime_invariant_failure`, the exit
//! report could say nothing but "Rosette stopped without recording a
//! concrete terminal event" - the 2026-09-24 Halo 3 run, which was the
//! guest's own `abort()` after `operator new` was refused 10.8 GB, read
//! exactly like an unexplained Rosette fault.
//!
//! Now the deciding site records a `TerminalEvent`: what kind of stop it was,
//! a short label, a free-text detail, and where (step, thread, rip, caller).
//! The first event of a run wins, because it is the decision; later ones are
//! only counted. Separately, the runtime keeps the last few `Notable` events
//! (refused allocations, double frees, C++ throws, null-page accesses, stack
//! overflows, memory-model violations) so the exit report can show what the
//! guest was reacting to when it stopped.

const std = @import("std");

pub const Kind = enum(u8) {
    none,
    /// The guest called abort().
    guest_abort,
    /// The guest's C++ runtime gave up: std::terminate, __std_terminate or a
    /// pure virtual call.
    guest_terminate,
    /// Rosette's fatal-point policy stopped the run at a named condition.
    fatal_point,
    /// A Rosette runtime check refused to continue.
    runtime_invariant,
    /// A guest thread overflowed its stack into the no-access guard.
    guest_stack_overflow,
    /// The guest accessed memory it may not, and nothing handled it.
    guest_access_violation,
    /// The guest asked to exit.
    guest_exit,
};

pub fn kindLabel(kind: Kind) []const u8 {
    return switch (kind) {
        .none => "none",
        .guest_abort => "guest called abort()",
        .guest_terminate => "guest C++ runtime terminated (std::terminate / pure virtual call)",
        .fatal_point => "Rosette fatal-point policy",
        .runtime_invariant => "Rosette runtime invariant",
        .guest_stack_overflow => "guest stack overflow",
        .guest_access_violation => "unhandled guest access violation",
        .guest_exit => "guest exit",
    };
}

/// Where an event happened. `thread_slot` is the worker slot, null for the
/// process owner's context.
pub const Site = struct {
    step: u64 = 0,
    rip: u64 = 0,
    /// The guest caller, when the site knows it (an import's return address).
    return_address: u64 = 0,
    thread_slot: ?u16 = null,
    thread_handle: u64 = 0,
};

fn copyInto(storage: []u8, text: []const u8) u16 {
    const count = @min(storage.len, text.len);
    @memcpy(storage[0..count], text[0..count]);
    return @intCast(count);
}

pub const TerminalEvent = struct {
    kind: Kind = .none,
    label_storage: [64]u8 = undefined,
    label_len: u16 = 0,
    detail_storage: [512]u8 = undefined,
    detail_len: u16 = 0,
    site: Site = .{},
    /// Every terminal decision the run made, the first included. More than
    /// one means a later site also tried to stop the run.
    decisions: u32 = 0,

    /// Record the run's terminal event. Only the first is kept; returns false
    /// for a later one.
    pub fn record(self: *TerminalEvent, kind: Kind, label_text: []const u8, detail_text: []const u8, site: Site) bool {
        self.decisions +|= 1;
        if (self.kind != .none) return false;
        self.kind = kind;
        self.label_len = copyInto(&self.label_storage, label_text);
        self.detail_len = copyInto(&self.detail_storage, detail_text);
        self.site = site;
        return true;
    }

    pub fn recorded(self: *const TerminalEvent) bool {
        return self.kind != .none;
    }

    pub fn label(self: *const TerminalEvent) []const u8 {
        return self.label_storage[0..self.label_len];
    }

    pub fn detail(self: *const TerminalEvent) []const u8 {
        return self.detail_storage[0..self.detail_len];
    }
};

pub const NotableKind = enum(u8) {
    heap_refusal,
    heap_double_free,
    heap_unknown_free,
    cxx_throw,
    null_page_access,
    fatal_runtime_call,
    stack_overflow,
    tso_violation,
    access_violation,
    fatal_point,
    /// Output the guest could not have meant: a control byte in a file
    /// name, NUL bytes in a text file.
    io_integrity,
    /// A worker's slice changed the process owner's register file.
    context_violation,
    /// A guest heap block's guard bytes changed: something wrote past it.
    heap_overrun,
};

pub const Notable = struct {
    kind: NotableKind = .heap_refusal,
    site: Site = .{},
    text_storage: [240]u8 = undefined,
    text_len: u16 = 0,

    pub fn text(self: *const Notable) []const u8 {
        return self.text_storage[0..self.text_len];
    }
};

/// The last `capacity` notable events, oldest overwritten first, plus a count
/// of every one ever recorded per kind.
pub fn NotableRing(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        entries: [capacity]Notable = @splat(.{}),
        next: usize = 0,
        total: u64 = 0,
        per_kind: [@typeInfo(NotableKind).@"enum".fields.len]u64 = @splat(0),

        pub fn push(self: *Self, kind: NotableKind, site: Site, text_value: []const u8) void {
            const entry = &self.entries[self.next];
            entry.kind = kind;
            entry.site = site;
            entry.text_len = copyInto(&entry.text_storage, text_value);
            self.next = (self.next + 1) % capacity;
            self.total +|= 1;
            self.per_kind[@intFromEnum(kind)] +|= 1;
        }

        pub fn count(self: *const Self) usize {
            return @intCast(@min(self.total, capacity));
        }

        /// Oldest first.
        pub fn chronological(self: *const Self, index: usize) ?*const Notable {
            const held = self.count();
            if (index >= held) return null;
            const first = if (self.total <= capacity) 0 else self.next;
            return &self.entries[(first + index) % capacity];
        }

        pub fn countOf(self: *const Self, kind: NotableKind) u64 {
            return self.per_kind[@intFromEnum(kind)];
        }
    };
}

test "the first terminal event of a run is the one kept" {
    var event: TerminalEvent = .{};
    try std.testing.expect(!event.recorded());
    try std.testing.expect(event.record(.guest_abort, "abort", "operator new was refused", .{ .step = 10, .rip = 0x1400 }));
    try std.testing.expect(!event.record(.runtime_invariant, "later", "ignored", .{ .step = 11 }));
    try std.testing.expectEqual(Kind.guest_abort, event.kind);
    try std.testing.expectEqualStrings("abort", event.label());
    try std.testing.expectEqualStrings("operator new was refused", event.detail());
    try std.testing.expectEqual(@as(u64, 10), event.site.step);
    try std.testing.expectEqual(@as(u32, 2), event.decisions);
}

test "long labels and details are truncated, never overflowed" {
    var event: TerminalEvent = .{};
    const long = [_]u8{'x'} ** 1000;
    _ = event.record(.fatal_point, &long, &long, .{});
    try std.testing.expectEqual(@as(usize, 64), event.label().len);
    try std.testing.expectEqual(@as(usize, 512), event.detail().len);
}

test "the notable ring keeps the newest events in order and counts every kind" {
    var ring: NotableRing(3) = .{};
    try std.testing.expect(ring.chronological(0) == null);
    ring.push(.heap_refusal, .{ .step = 1 }, "one");
    ring.push(.cxx_throw, .{ .step = 2 }, "two");
    try std.testing.expectEqual(@as(usize, 2), ring.count());
    try std.testing.expectEqualStrings("one", ring.chronological(0).?.text());
    ring.push(.heap_double_free, .{ .step = 3 }, "three");
    ring.push(.heap_refusal, .{ .step = 4 }, "four");
    try std.testing.expectEqual(@as(usize, 3), ring.count());
    try std.testing.expectEqualStrings("two", ring.chronological(0).?.text());
    try std.testing.expectEqualStrings("four", ring.chronological(2).?.text());
    try std.testing.expectEqual(@as(u64, 2), ring.countOf(.heap_refusal));
    try std.testing.expectEqual(@as(u64, 4), ring.total);
}
