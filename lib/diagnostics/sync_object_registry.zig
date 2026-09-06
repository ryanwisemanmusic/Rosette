//! One identity per guest synchronization object, below every report that
//! talks about waits.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run has four views of its synchronization state.
//! `GUEST WAIT LIVENESS` aggregates 569 waits and 535 signals.
//! `WAIT AUDIT` reports `problems=0`, because it excludes finite polls by
//! design. `DEADLOCK PREDICTOR` reports `deadlocked=YES`. `SIGNAL EXPECTATION`
//! reports one orphan wait and two orphan signals. Each is right about its own
//! question, and read together they say nothing is wrong while a guest thread
//! polls object `0x40004BF4` a hundred and twelve times and receives nothing.
//!
//! What is missing is not a fifth view. It is identity — who created the
//! object, who owes it a signal, and what it is for. A never-notified idle
//! worker and a never-notified GPU completion are identical in every counter
//! and are opposite findings, and only the role separates them.
//!
//! The rule
//! --------
//! Classification is stated, never inferred from counters. An object nobody
//! classified stays `unclassified`, which blocks promotion to a primary cause
//! rather than permitting it. That is deliberately inconvenient: the
//! inconvenience is the work of classifying it, which is exactly the work the
//! run needed and did not have.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const ObjectKind = bridge.sync.ObjectKind;
pub const Role = bridge.sync.Role;
pub const WaitShape = bridge.sync.WaitShape;
pub const ObjectIdentity = bridge.sync.ObjectIdentity;
pub const Standing = bridge.sync.Standing;
pub const Activity = bridge.sync.Activity;
pub const Semantics = bridge.sync.Semantics;
pub const classify = bridge.sync.classify;
pub const Address = bridge.contract.Address;
pub const CodeLocation = bridge.contract.CodeLocation;

pub const max_objects: usize = 48;
pub const max_participants: usize = 4;

/// An operation emitted at the emulator boundary. The registry keeps these
/// counters separate from `Activity`: lifecycle lines are authoritative for
/// what Xenia called, while `Activity` remains the reconciled guest wait view.
pub const LifecycleOperation = enum(u8) {
    create,
    initialize,
    bind_handle,
    reference,
    wait_begin,
    wait_return,
    signal,
    reset,
    unknown,

    pub fn label(self: LifecycleOperation) []const u8 {
        return switch (self) {
            .create => "create",
            .initialize => "initialize",
            .bind_handle => "bind-handle",
            .reference => "reference",
            .wait_begin => "wait-begin",
            .wait_return => "wait-return",
            .signal => "signal",
            .reset => "reset",
            .unknown => "unknown",
        };
    }
};

/// Everything known about one object. Identity, provenance and counters kept
/// apart so a report can print any of them without implying the others.
pub const Entry = struct {
    identity: ObjectIdentity = .{},
    activity: Activity = .{},
    /// Where the object was created, when that was observed.
    creator: CodeLocation = .{},
    creator_thread: u64 = 0,
    created_step: u64 = 0,
    /// The code that is supposed to signal it, when someone has said.
    expected_notifier: CodeLocation = .{},
    notifier_stated: bool = false,
    /// Threads seen waiting and signalling. Bounded; the counts are durable.
    waiters: [max_participants]u64 = [_]u64{0} ** max_participants,
    waiter_count: u32 = 0,
    signallers: [max_participants]u64 = [_]u64{0} ** max_participants,
    signaller_count: u32 = 0,
    /// The site the newest waiter was at.
    wait_site: CodeLocation = .{},
    /// State the object holds, for the semantics the kind implies.
    signalled_state: bool = false,
    semaphore_count: i64 = 0,
    /// Times the emulator's behaviour disagreed with the kind's semantics.
    semantic_violations: u64 = 0,
    /// Xenia's raw lifecycle account. These are intentionally not folded into
    /// `activity`: a successful return is not automatically a blocked-then-
    /// released handoff, and a signal call is not proof that a waiter consumed
    /// it.
    lifecycle_events: u64 = 0,
    lifecycle_creates: u64 = 0,
    lifecycle_initializes: u64 = 0,
    lifecycle_bindings: u64 = 0,
    lifecycle_references: u64 = 0,
    lifecycle_wait_begins: u64 = 0,
    lifecycle_wait_returns: u64 = 0,
    lifecycle_success_returns: u64 = 0,
    lifecycle_signals: u64 = 0,
    lifecycle_resets: u64 = 0,
    lifecycle_last_operation: u8 = @intFromEnum(LifecycleOperation.unknown),
    lifecycle_last_step: u64 = 0,
    lifecycle_last_thread: u64 = 0,
    lifecycle_last_result_success: bool = false,
    lifecycle_last_state_after_valid: bool = false,
    lifecycle_last_state_after: u32 = 0,
    lifecycle_last_location: CodeLocation = .{},
    used: bool = false,

    pub fn standing(self: Entry) Standing {
        return classify(self.identity, self.activity);
    }

    pub fn addWaiter(self: *Entry, thread: u64) void {
        if (thread == 0) return;
        for (self.waiters[0..@min(self.waiter_count, max_participants)]) |existing| {
            if (existing == thread) return;
        }
        if (self.waiter_count < max_participants) {
            self.waiters[self.waiter_count] = thread;
        }
        self.waiter_count += 1;
    }

    pub fn addSignaller(self: *Entry, thread: u64) void {
        if (thread == 0) return;
        for (self.signallers[0..@min(self.signaller_count, max_participants)]) |existing| {
            if (existing == thread) return;
        }
        if (self.signaller_count < max_participants) {
            self.signallers[self.signaller_count] = thread;
        }
        self.signaller_count += 1;
    }

    /// The audit's acceptance criterion for the bounded-poll object: a named
    /// creator, a named expected notifier, and a guest-PC-backed explanation.
    pub fn fullyAttributed(self: Entry) bool {
        return self.created_step != 0 and
            self.notifier_stated and
            self.identity.roleOf() != .unclassified and
            (self.wait_site.citableAsGuestLocation() or self.wait_site.fallbackCallSite() != null);
    }
};

pub const Summary = struct {
    objects: usize = 0,
    dropped: u64 = 0,
    healthy: usize = 0,
    missing_notifier: usize = 0,
    quiet_by_role: usize = 0,
    orphan_signal: usize = 0,
    unclassified_silence: usize = 0,
    unobserved: usize = 0,
    /// Objects with a role stated. The list that shortens as the work gets
    /// done.
    classified: usize = 0,
    fully_attributed: usize = 0,
    semantic_violations: u64 = 0,

    /// Objects whose silence may be promoted to a cause.
    pub fn actionable(self: Summary) usize {
        return self.missing_notifier;
    }

    /// The work outstanding: objects nothing has classified.
    pub fn classificationDebt(self: Summary) usize {
        return self.objects -| self.classified;
    }
};

pub const Registry = struct {
    entries: [max_objects]Entry = [_]Entry{.{}} ** max_objects,
    count: usize = 0,
    dropped: u64 = 0,
    /// Address reuses that produced a new generation. Without these a
    /// destroyed-and-recreated object silently inherits the old waiters.
    generations_bumped: u64 = 0,

    fn find(self: *Registry, identity: ObjectIdentity) ?*Entry {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.entries[index].identity.sameObject(identity)) return &self.entries[index];
        }
        return null;
    }

    /// Get or create the entry for an object.
    pub fn intern(self: *Registry, identity: ObjectIdentity) ?*Entry {
        if (self.find(identity)) |existing| return existing;
        if (self.count >= max_objects) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.entries[self.count];
        self.count += 1;
        slot.* = .{ .identity = identity, .used = true };
        return slot;
    }

    /// Record that an address is being reused for a new object. The previous
    /// entry keeps its history under the old generation.
    pub fn recycle(self: *Registry, address: Address, handle: u32) u32 {
        var newest: u32 = 0;
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const entry = self.entries[index];
            if (!entry.identity.address.joins(address) and entry.identity.handle != handle) continue;
            if (entry.identity.generation > newest) newest = entry.identity.generation;
        }
        self.generations_bumped +|= 1;
        return newest + 1;
    }

    /// Retain one emulator lifecycle observation under the same identity used
    /// by the wait graph. No role is inferred here: a create followed by a
    /// quiet wait is still unclassified until a caller states what the object
    /// is for.
    pub fn observeLifecycle(
        self: *Registry,
        identity: ObjectIdentity,
        operation: LifecycleOperation,
        thread: u64,
        location: CodeLocation,
        step: u64,
        result_success: bool,
        state_after_valid: bool,
        state_after: u32,
    ) ?*Entry {
        const entry = self.intern(identity) orelse return null;
        entry.lifecycle_events +|= 1;
        entry.lifecycle_last_operation = @intFromEnum(operation);
        entry.lifecycle_last_step = step;
        entry.lifecycle_last_thread = thread;
        entry.lifecycle_last_result_success = result_success;
        entry.lifecycle_last_state_after_valid = state_after_valid;
        entry.lifecycle_last_state_after = state_after;
        entry.lifecycle_last_location = location;

        switch (operation) {
            .create => {
                entry.lifecycle_creates +|= 1;
                if (entry.created_step == 0 or entry.creator_thread == 0) {
                    entry.creator = location;
                    entry.creator_thread = thread;
                    entry.created_step = step;
                }
            },
            .initialize => {
                entry.lifecycle_initializes +|= 1;
                if (entry.created_step == 0) {
                    entry.creator = location;
                    entry.creator_thread = thread;
                    entry.created_step = step;
                }
            },
            .bind_handle => entry.lifecycle_bindings +|= 1,
            .reference => entry.lifecycle_references +|= 1,
            .wait_begin => {
                entry.lifecycle_references +|= 1;
                entry.lifecycle_wait_begins +|= 1;
                entry.addWaiter(thread);
                entry.wait_site = location;
            },
            .wait_return => {
                entry.lifecycle_references +|= 1;
                entry.lifecycle_wait_returns +|= 1;
                if (result_success) entry.lifecycle_success_returns +|= 1;
            },
            .signal => {
                entry.lifecycle_references +|= 1;
                entry.lifecycle_signals +|= 1;
                entry.addSignaller(thread);
            },
            .reset => {
                entry.lifecycle_references +|= 1;
                entry.lifecycle_resets +|= 1;
            },
            .unknown => {},
        }
        return entry;
    }

    pub fn retained(self: *const Registry) []const Entry {
        return self.entries[0..self.count];
    }

    pub fn summary(self: *const Registry) Summary {
        var out = Summary{ .objects = self.count, .dropped = self.dropped };
        for (self.retained()) |entry| {
            switch (entry.standing()) {
                .healthy => out.healthy += 1,
                .missing_notifier => out.missing_notifier += 1,
                .quiet_by_role => out.quiet_by_role += 1,
                .orphan_signal => out.orphan_signal += 1,
                .unclassified_silence => out.unclassified_silence += 1,
                .unobserved => out.unobserved += 1,
            }
            if (entry.identity.roleOf() != .unclassified) out.classified += 1;
            if (entry.fullyAttributed()) out.fully_attributed += 1;
            out.semantic_violations +|= entry.semantic_violations;
        }
        return out;
    }

    /// The object a reader should look at first: a missing notifier if there
    /// is one, otherwise the unclassified silence with the most waits. The
    /// second is a finding about the observation, and it is deliberately
    /// surfaced rather than hidden behind the first.
    pub fn firstSubject(self: *const Registry) ?Entry {
        var unclassified: ?Entry = null;
        for (self.retained()) |entry| {
            switch (entry.standing()) {
                .missing_notifier => return entry,
                .unclassified_silence => {
                    if (unclassified == null or entry.activity.waits > unclassified.?.activity.waits) {
                        unclassified = entry;
                    }
                },
                else => {},
            }
        }
        return unclassified;
    }

    /// Check one observation against the kind's semantics and record a
    /// violation. This is the differential harness's live half: the same rules
    /// the tests assert, applied to what the emulator actually did.
    pub fn checkRelease(
        self: *Registry,
        entry: *Entry,
        waiting_before: u32,
        released: u32,
    ) bool {
        _ = self;
        const expected = Semantics.waitersReleasedByOneSignal(entry.identity.kindOf(), waiting_before);
        if (released == expected) return true;
        entry.semantic_violations +|= 1;
        return false;
    }

    pub fn fingerprint(self: *const Registry) u64 {
        const totals = self.summary();
        var hash: u64 = totals.objects;
        hash = hash *% 31 +% totals.missing_notifier;
        hash = hash *% 31 +% totals.unclassified_silence;
        hash = hash *% 31 +% totals.classified;
        return hash;
    }
};

// The exact 2026-08-31 subject, and the three answers the same counters give
// depending on what nobody had said about the object.
test "the bounded poll's meaning is decided by its role and nothing else" {
    var registry = Registry{};
    const identity = ObjectIdentity{
        .address = .{ .guest_virtual = 0x4000_4BF4 },
        .handle = 0xF800_0154,
        .generation = 1,
        .kind = @intFromEnum(ObjectKind.manual_reset_event),
    };
    const entry = registry.intern(identity).?;
    entry.activity = .{ .waits = 112, .timeouts = 112, .signals = 0, .shape = .bounded_poll, .timeout_ms = 30 };
    entry.addWaiter(0x7fff_2140);

    try std.testing.expectEqual(Standing.unclassified_silence, entry.standing());
    try std.testing.expect(!entry.standing().promotableToCause());
    try std.testing.expectEqual(@as(usize, 1), registry.summary().classificationDebt());
    // The unclassified object is surfaced as the subject rather than hidden.
    try std.testing.expectEqual(Standing.unclassified_silence, registry.firstSubject().?.standing());

    entry.identity.role = @intFromEnum(Role.gpu_completion);
    try std.testing.expectEqual(Standing.missing_notifier, entry.standing());
    try std.testing.expect(entry.standing().promotableToCause());
    try std.testing.expectEqual(@as(usize, 1), registry.summary().actionable());
    try std.testing.expectEqual(@as(usize, 0), registry.summary().classificationDebt());

    entry.identity.role = @intFromEnum(Role.idle_worker);
    try std.testing.expectEqual(Standing.quiet_by_role, entry.standing());
    try std.testing.expectEqual(@as(usize, 0), registry.summary().actionable());
}

test "a recycled address gets a new generation and keeps the old history" {
    var registry = Registry{};
    const first = ObjectIdentity{ .address = .{ .guest_virtual = 0x3004_0018 }, .handle = 0xF800_0040, .generation = 1 };
    const original = registry.intern(first).?;
    original.activity.waits = 25;

    const generation = registry.recycle(first.address, first.handle);
    try std.testing.expectEqual(@as(u32, 2), generation);
    var second = first;
    second.generation = generation;
    const fresh = registry.intern(second).?;
    try std.testing.expectEqual(@as(u64, 0), fresh.activity.waits);
    try std.testing.expectEqual(@as(u64, 25), registry.entries[0].activity.waits);
    try std.testing.expectEqual(@as(usize, 2), registry.count);
}

test "an object is fully attributed only with a creator, a notifier and a site" {
    var registry = Registry{};
    const entry = registry.intern(.{
        .address = .{ .guest_virtual = 0x4000_4BF4 },
        .handle = 0xF800_0154,
        .generation = 1,
        .role = @intFromEnum(Role.gpu_completion),
    }).?;
    try std.testing.expect(!entry.fullyAttributed());

    entry.created_step = 3_100_000_000;
    entry.notifier_stated = true;
    // A seeded program counter is not citable, and the link register still
    // names the caller — which is enough to send a reader somewhere real.
    entry.wait_site = .{
        .guest_pc = 0x8258_A470,
        .guest_lr = 0x825A_E908,
        .provenance = @intFromEnum(CodeLocation.Provenance.guest_instruction),
        .quality = @intFromEnum(CodeLocation.Quality.seeded),
    };
    try std.testing.expect(!entry.wait_site.citableAsGuestLocation());
    try std.testing.expect(entry.fullyAttributed());
    try std.testing.expectEqual(@as(usize, 1), registry.summary().fully_attributed);
}

test "an auto-reset event releasing two waiters is a semantic violation" {
    var registry = Registry{};
    const entry = registry.intern(.{
        .handle = 0xF800_0058,
        .generation = 1,
        .kind = @intFromEnum(ObjectKind.auto_reset_event),
    }).?;
    try std.testing.expect(registry.checkRelease(entry, 3, 1));
    try std.testing.expect(!registry.checkRelease(entry, 3, 2));
    try std.testing.expectEqual(@as(u64, 1), entry.semantic_violations);
    try std.testing.expectEqual(@as(u64, 1), registry.summary().semantic_violations);

    const manual = registry.intern(.{
        .handle = 0xF800_0154,
        .generation = 1,
        .kind = @intFromEnum(ObjectKind.manual_reset_event),
    }).?;
    try std.testing.expect(registry.checkRelease(manual, 3, 3));
    try std.testing.expect(!registry.checkRelease(manual, 3, 1));
}

test "an orphan signal is recorded and never promoted to a cause" {
    var registry = Registry{};
    const entry = registry.intern(.{ .handle = 0xF800_016C, .generation = 1 }).?;
    entry.activity = .{ .signals = 662 };
    entry.addSignaller(0x7fff_2160);
    try std.testing.expectEqual(Standing.orphan_signal, entry.standing());
    try std.testing.expect(!entry.standing().promotableToCause());
    try std.testing.expectEqual(@as(usize, 1), registry.summary().orphan_signal);
    try std.testing.expect(registry.firstSubject() == null);
}

test "participants are deduplicated and the count survives the bound" {
    var registry = Registry{};
    const entry = registry.intern(.{ .handle = 1, .generation = 1 }).?;
    entry.addWaiter(0x10);
    entry.addWaiter(0x10);
    try std.testing.expectEqual(@as(u32, 1), entry.waiter_count);
    var index: u64 = 0;
    while (index < max_participants + 3) : (index += 1) entry.addWaiter(0x100 + index);
    try std.testing.expectEqual(@as(u32, max_participants + 4), entry.waiter_count);
    try std.testing.expectEqual(@as(u64, 0x10), entry.waiters[0]);
}

test "the registry is bounded and says how many objects it could not hold" {
    var registry = Registry{};
    var index: u32 = 0;
    while (index < max_objects) : (index += 1) {
        _ = registry.intern(.{ .handle = index + 1, .generation = 1 }).?;
    }
    try std.testing.expect(registry.intern(.{ .handle = 9999, .generation = 1 }) == null);
    try std.testing.expectEqual(@as(u64, 1), registry.dropped);
    try std.testing.expectEqual(max_objects, registry.retained().len);
}

test "a healthy object needs both halves of the handshake" {
    var registry = Registry{};
    const entry = registry.intern(.{ .handle = 0xF800_0168, .generation = 1 }).?;
    entry.activity = .{ .waits = 662, .signals = 662, .blocked_then_released = 654 };
    try std.testing.expectEqual(Standing.healthy, entry.standing());
    try std.testing.expectEqual(@as(usize, 1), registry.summary().healthy);
}

test "raw lifecycle returns stay separate from proven signal handoffs" {
    var registry = Registry{};
    const identity = ObjectIdentity{
        .address = .{ .guest_virtual = 0x4000_4BF4 },
        .handle = 0xF800_0154,
        .generation = 1,
        .kind = @intFromEnum(ObjectKind.manual_reset_event),
    };
    const location = CodeLocation{
        .guest_pc = 0x8258_A470,
        .guest_lr = 0x825A_E908,
        .provenance = @intFromEnum(CodeLocation.Provenance.guest_instruction),
        .quality = @intFromEnum(CodeLocation.Quality.direct),
    };
    _ = registry.observeLifecycle(identity, .create, 7, location, 100, true, false, 0);
    _ = registry.observeLifecycle(identity, .wait_begin, 7, location, 110, true, false, 0);
    _ = registry.observeLifecycle(identity, .wait_return, 7, location, 120, true, true, 0);
    _ = registry.observeLifecycle(identity, .signal, 9, location, 130, true, true, 1);

    const entry = registry.retained()[0];
    try std.testing.expectEqual(@as(u64, 4), entry.lifecycle_events);
    try std.testing.expectEqual(@as(u64, 1), entry.lifecycle_creates);
    try std.testing.expectEqual(@as(u64, 1), entry.lifecycle_wait_begins);
    try std.testing.expectEqual(@as(u64, 1), entry.lifecycle_wait_returns);
    try std.testing.expectEqual(@as(u64, 1), entry.lifecycle_success_returns);
    try std.testing.expectEqual(@as(u64, 1), entry.lifecycle_signals);
    try std.testing.expectEqual(@as(u32, 1), entry.waiter_count);
    try std.testing.expectEqual(@as(u32, 1), entry.signaller_count);
    // No lifecycle line is allowed to imply that a waiter consumed the signal.
    try std.testing.expectEqual(@as(u64, 0), entry.activity.blocked_then_released);
}
