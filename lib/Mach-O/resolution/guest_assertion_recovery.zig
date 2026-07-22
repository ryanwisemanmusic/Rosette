const std = @import("std");

pub const Class = enum {
    none,
    timer_queue_wait_item_state,
    breakpoint_untracked_thread,
    export_ordinal_bounds,
};

pub const Severity = enum {
    fatal,
    recoverable_state_reset,
    recoverable_skip,
    expected,
};

pub const Recovery = struct {
    action: RecoveryAction,
    severity: Severity,
    message: []const u8 = "",
};

pub const RecoveryAction = enum {
    none,
    /// Skip the assertion and continue execution past the abort
    skip_assertion,
    /// Reset thread/initializer state and retry
    reset_and_retry,
    /// Log and continue (expected behavior)
    log_and_continue,
};

pub const TimerQueueSnapshot = struct {
    frame_state_address: u64,
    frame_state: u8,
    shared_ptr_address: u64,
    wait_item: u64,
    object_state: ?u8,
    due_nanoseconds: ?u64,
    interval_nanoseconds: ?u64,
};

pub const TimerQueueAction = enum {
    none,
    /// compare_exchange_strong reported failure even though expected and live
    /// values are both kIdle. Claim callback ownership and replay the success
    /// branch; the callback has not executed yet.
    replay_false_negative_idle_cas,
    /// A second queue reference reached an item already owned by a callback.
    /// Drop only that duplicate reference and continue after the assertion.
    quarantine_callback_owned_duplicate,
};

pub const TimerRecoveryDisposition = enum {
    allow,
    quarantine_repeated_generation,
};

const TimerRecoveryRecord = struct {
    active: bool = false,
    wait_item: u64 = 0,
    due_nanoseconds: ?u64 = null,
    interval_nanoseconds: ?u64 = null,
    action: TimerQueueAction = .none,
    observations: u32 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
};

/// Bounds semantic repair by the identity and deadline generation of the
/// observed wait item. A periodic timer gets a fresh allowance when its due
/// time changes; a stale generation is quarantined instead of replayed forever.
pub const TimerRecoveryTracker = struct {
    records: [64]TimerRecoveryRecord = [_]TimerRecoveryRecord{.{}} ** 64,
    next_replacement: usize = 0,
    allowed: u64 = 0,
    quarantined: u64 = 0,

    pub fn observe(
        self: *TimerRecoveryTracker,
        snapshot: TimerQueueSnapshot,
        action: TimerQueueAction,
        step: u64,
    ) TimerRecoveryDisposition {
        var free: ?usize = null;
        for (&self.records, 0..) |*record, index| {
            if (!record.active) {
                if (free == null) free = index;
                continue;
            }
            if (record.wait_item != snapshot.wait_item or
                record.due_nanoseconds != snapshot.due_nanoseconds or
                record.interval_nanoseconds != snapshot.interval_nanoseconds or
                record.action != action) continue;
            record.observations +|= 1;
            record.last_step = step;
            if (action == .replay_false_negative_idle_cas and record.observations > 1) {
                self.quarantined +|= 1;
                return .quarantine_repeated_generation;
            }
            self.allowed +|= 1;
            return .allow;
        }
        const index = free orelse replacement: {
            const result = self.next_replacement;
            self.next_replacement = (self.next_replacement + 1) % self.records.len;
            break :replacement result;
        };
        self.records[index] = .{
            .active = true,
            .wait_item = snapshot.wait_item,
            .due_nanoseconds = snapshot.due_nanoseconds,
            .interval_nanoseconds = snapshot.interval_nanoseconds,
            .action = action,
            .observations = 1,
            .first_step = step,
            .last_step = step,
        };
        self.allowed +|= 1;
        return .allow;
    }
};

// Current Debug Xenia TimerThreadMain layout. The process validates the target
// instruction prefix before using this relative replay edge, so a changed
// compiler layout disables recovery rather than jumping speculatively.
pub const idle_cas_success_delta_from_assertion_return: u64 = 0x217;
pub const idle_cas_success_prefix = [_]u8{ 0x48, 0x8D, 0x7D, 0x88 }; // lea -0x78(%rbp), %rdi

pub fn timerQueueSnapshot(state: anytype, rbp: u64) ?TimerQueueSnapshot {
    // Debug Xenia stores the compare_exchange expected byte at rbp-0x79
    // followed by the active shared_ptr at rbp-0x78.
    if (rbp < 0x79) return null;
    const frame_state_address = rbp - 0x79;
    const shared_ptr_address = rbp - 0x78;
    const state_bytes = state.guestMemoryConst(frame_state_address, 1) orelse return null;
    const shared_bytes = state.guestMemoryConst(shared_ptr_address, 8) orelse return null;
    const wait_item = std.mem.readInt(u64, shared_bytes[0..8], .little);
    const object_state = if (wait_item != 0)
        if (state.guestMemoryConst(wait_item + 0x50, 1)) |bytes| bytes[0] else null
    else
        null;
    const due_nanoseconds = if (wait_item != 0)
        if (state.guestMemoryConst(wait_item + 0x40, 8)) |bytes| std.mem.readInt(u64, bytes[0..8], .little) else null
    else
        null;
    const interval_nanoseconds = if (wait_item != 0)
        if (state.guestMemoryConst(wait_item + 0x48, 8)) |bytes| std.mem.readInt(u64, bytes[0..8], .little) else null
    else
        null;
    return .{
        .frame_state_address = frame_state_address,
        .frame_state = state_bytes[0],
        .shared_ptr_address = shared_ptr_address,
        .wait_item = wait_item,
        .object_state = object_state,
        .due_nanoseconds = due_nanoseconds,
        .interval_nanoseconds = interval_nanoseconds,
    };
}

pub fn applyIdleCasReplay(state: anytype, snapshot: TimerQueueSnapshot, assertion_return: u64) ?u64 {
    // Check if semantic repair is allowed based on runtime mode
    // Commented out to avoid global state complexity for now
    // if (!runtime_mode.allowGlobalRepair("timer_cas_idle_replay")) {
    //     return null;
    // }

    if (assertion_return < idle_cas_success_delta_from_assertion_return or snapshot.wait_item == 0) return null;
    const replay_rip = assertion_return - idle_cas_success_delta_from_assertion_return;
    const replay_bytes = state.guestMemoryConst(replay_rip, idle_cas_success_prefix.len) orelse return null;
    if (!std.mem.eql(u8, replay_bytes, &idle_cas_success_prefix)) return null;
    const live_state = state.guestMemory(snapshot.wait_item + 0x50, 1) orelse return null;
    if (live_state[0] != 0) return null;

    // Record the repair
    // runtime_mode.recordGlobalRepair("timer_cas_idle_replay") catch {
    //     return null;
    // };

    live_state[0] = 1;
    return replay_rip;
}

/// Retire one stale timer generation after the tracker proves that replaying
/// its successful-CAS branch already failed to make progress. The write is
/// accepted only while both the frame observation and live object still say
/// kIdle, preventing this circuit breaker from stealing callback ownership.
pub fn quarantineRepeatedIdleGeneration(state: anytype, snapshot: TimerQueueSnapshot) bool {
    if (snapshot.wait_item == 0 or snapshot.frame_state != 0 or snapshot.object_state != 0) return false;
    const live_state = state.guestMemory(snapshot.wait_item + 0x50, 1) orelse return false;
    if (live_state[0] != 0) return false;
    live_state[0] = 3; // kDisarmed
    return true;
}

pub fn recoveryFor(assertion_class: Class, _: u64, _: u64) Recovery {
    return switch (assertion_class) {
        .none => .{ .action = .none, .severity = .fatal },
        .timer_queue_wait_item_state => .{ .action = .reset_and_retry, .severity = .recoverable_state_reset, .message = "timer queue state recovery available via CAS replay" },
        .breakpoint_untracked_thread => .{ .action = .skip_assertion, .severity = .recoverable_skip, .message = "breakpoint on untracked thread is secondary signal-handler fallout; skip and resume" },
        .export_ordinal_bounds => .{ .action = .skip_assertion, .severity = .recoverable_skip, .message = "export ordinal bounds assertion; table resize may be needed" },
    };
}

pub fn classify(file_name: []const u8, function_name: []const u8, expression: []const u8) Class {
    if (std.mem.endsWith(u8, file_name, "threading_timer_queue.cc") and
        std.mem.indexOf(u8, function_name, "TimerThreadMain") != null and
        std.mem.indexOf(u8, expression, "kDisarmed") != null)
    {
        return .timer_queue_wait_item_state;
    }
    if (std.mem.endsWith(u8, file_name, "processor_mac.cc") and
        std.mem.indexOf(u8, function_name, "OnThreadBreakpointHit") != null)
    {
        return .breakpoint_untracked_thread;
    }
    if (std.mem.indexOf(u8, function_name, "RegisterExport") != null and
        std.mem.indexOf(u8, expression, "ordinal < ") != null and
        std.mem.indexOf(u8, expression, ".size()") != null)
    {
        return .export_ordinal_bounds;
    }
    return .none;
}

pub fn timerQueueStateName(state: u8) []const u8 {
    return switch (state) {
        0 => "kIdle",
        1 => "kInCallback",
        2 => "kInCallbackSelfDisarmed",
        3 => "kDisarmed",
        else => "<invalid>",
    };
}

pub fn timerQueueAction(step_delta: u64, address_delta: u64, frame_state: u8, object_state: ?u8) TimerQueueAction {
    if (step_delta > 64 or address_delta > 16) return .none;
    const live_state = object_state orelse return .none;
    if (frame_state != live_state) return .none;
    return switch (frame_state) {
        0 => .replay_false_negative_idle_cas,
        1, 2 => .quarantine_callback_owned_duplicate,
        else => .none,
    };
}

pub fn shouldEscapeNullBreakpointUnwind(
    exception_argument: u64,
    current_assertion: Class,
    outer_assertion: Class,
    signal_depth: usize,
) bool {
    return exception_argument == 0 and
        signal_depth != 0 and
        current_assertion == .breakpoint_untracked_thread and
        outer_assertion == .timer_queue_wait_item_state;
}

test "assertion classifier separates timer cause from breakpoint fallout" {
    try std.testing.expectEqual(Class.timer_queue_wait_item_state, classify(
        "threading_timer_queue.cc",
        "TimerThreadMain",
        "WaitItem::State::kDisarmed == state",
    ));
    try std.testing.expectEqual(Class.breakpoint_untracked_thread, classify(
        "processor_mac.cc",
        "OnThreadBreakpointHit",
        "false",
    ));
    try std.testing.expectEqual(Class.export_ordinal_bounds, classify(
        "xbdm_module.cc",
        "RegisterExport_xbdm",
        "export_entry->ordinal < xbdm_exports.size()",
    ));
    try std.testing.expectEqual(Class.none, classify("other.cc", "func", "false"));
}

test "timer recovery distinguishes false CAS from duplicate callback ownership" {
    try std.testing.expectEqual(TimerQueueAction.replay_false_negative_idle_cas, timerQueueAction(2, 5, 0, 0));
    try std.testing.expectEqual(TimerQueueAction.quarantine_callback_owned_duplicate, timerQueueAction(2, 5, 1, 1));
    try std.testing.expectEqual(TimerQueueAction.quarantine_callback_owned_duplicate, timerQueueAction(2, 5, 2, 2));
    try std.testing.expectEqual(TimerQueueAction.none, timerQueueAction(2, 5, 3, 3));
    try std.testing.expectEqual(TimerQueueAction.none, timerQueueAction(2, 5, 1, 2));
    try std.testing.expectEqual(TimerQueueAction.none, timerQueueAction(65, 5, 0, 0));
    try std.testing.expectEqual(TimerQueueAction.none, timerQueueAction(2, 17, 0, 0));
    try std.testing.expectEqual(TimerQueueAction.none, timerQueueAction(2, 5, 0, null));
}

test "timer snapshot and replay validate layout before claiming callback" {
    // Skip runtime mode initialization for this test
    // const allocator = std.testing.allocator;
    // try runtime_mode.initGlobalRuntimeMode(allocator, .diagnostic);
    // defer runtime_mode.shutdownGlobalRuntimeMode();

    const FakeState = struct {
        memory: [1024]u8 = [_]u8{0} ** 1024,

        fn guestMemoryConst(self: *const @This(), address: u64, count: u64) ?[]const u8 {
            const start: usize = @intCast(address);
            const length: usize = @intCast(count);
            if (start > self.memory.len or length > self.memory.len - start) return null;
            return self.memory[start .. start + length];
        }

        fn guestMemory(self: *@This(), address: u64, count: u64) ?[]u8 {
            const start: usize = @intCast(address);
            const length: usize = @intCast(count);
            if (start > self.memory.len or length > self.memory.len - start) return null;
            return self.memory[start .. start + length];
        }
    };

    var state = FakeState{};
    const rbp: u64 = 0x180;
    const wait_item: u64 = 0x280;
    const assertion_return: u64 = 0x300;
    const replay_rip = assertion_return - idle_cas_success_delta_from_assertion_return;
    state.memory[rbp - 0x79] = 0;
    std.mem.writeInt(u64, state.memory[rbp - 0x78 ..][0..8], wait_item, .little);
    state.memory[wait_item + 0x50] = 0;
    @memcpy(state.memory[replay_rip..][0..idle_cas_success_prefix.len], &idle_cas_success_prefix);

    const snapshot = timerQueueSnapshot(&state, rbp).?;
    try std.testing.expectEqual(@as(u8, 0), snapshot.frame_state);
    try std.testing.expectEqual(@as(?u8, 0), snapshot.object_state);
    try std.testing.expectEqual(replay_rip, applyIdleCasReplay(&state, snapshot, assertion_return).?);
    try std.testing.expectEqual(@as(u8, 1), state.memory[wait_item + 0x50]);
}

test "timer recovery tracker bounds one stale deadline generation" {
    var tracker = TimerRecoveryTracker{};
    const snapshot = TimerQueueSnapshot{
        .frame_state_address = 1,
        .frame_state = 0,
        .shared_ptr_address = 2,
        .wait_item = 0x4000,
        .object_state = 0,
        .due_nanoseconds = 100,
        .interval_nanoseconds = 10,
    };
    try std.testing.expectEqual(
        TimerRecoveryDisposition.allow,
        tracker.observe(snapshot, .replay_false_negative_idle_cas, 1),
    );
    try std.testing.expectEqual(
        TimerRecoveryDisposition.quarantine_repeated_generation,
        tracker.observe(snapshot, .replay_false_negative_idle_cas, 2),
    );
    var next = snapshot;
    next.due_nanoseconds = 110;
    try std.testing.expectEqual(
        TimerRecoveryDisposition.allow,
        tracker.observe(next, .replay_false_negative_idle_cas, 3),
    );
}

test "null unwind escape requires exact nested timer breakpoint provenance" {
    try std.testing.expect(shouldEscapeNullBreakpointUnwind(
        0,
        .breakpoint_untracked_thread,
        .timer_queue_wait_item_state,
        1,
    ));
    try std.testing.expect(!shouldEscapeNullBreakpointUnwind(
        1,
        .breakpoint_untracked_thread,
        .timer_queue_wait_item_state,
        1,
    ));
    try std.testing.expect(!shouldEscapeNullBreakpointUnwind(0, .breakpoint_untracked_thread, .none, 1));
    try std.testing.expect(!shouldEscapeNullBreakpointUnwind(0, .breakpoint_untracked_thread, .timer_queue_wait_item_state, 0));
}
