const std = @import("std");

pub const Class = enum {
    none,
    timer_queue_wait_item_state,
    breakpoint_untracked_thread,
    export_ordinal_bounds,
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

/// Apple's assertion entry point is declared `noreturn`. A translated program
/// may therefore place padding, a trap, or the next unrelated function directly
/// after the call. Returning into these patterns can never be a valid recovery.
pub fn isUnsafeNoreturnContinuation(bytes: []const u8) bool {
    if (bytes.len == 0) return true;
    if (bytes[0] == 0x90 or bytes[0] == 0xCC or bytes[0] == 0x00) return true;
    if (bytes.len >= 2 and bytes[0] == 0x0F and
        (bytes[1] == 0x0B or bytes[1] == 0x1F))
    {
        return true;
    }
    return bytes.len >= 3 and bytes[0] == 0x66 and
        bytes[1] == 0x0F and bytes[2] == 0x1F;
}

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

pub fn classify(function_name: []const u8, expression: []const u8) Class {

    // Match on expression content and function name rather than Xenia source file paths.
    // The key semantic content (kDisarmed, ordinal bounds, breakpoint handler) is
    // embedded in the expression string passed by Apple's __assert_rtn.
    if (std.mem.indexOf(u8, expression, "kDisarmed") != null and
        std.mem.indexOf(u8, function_name, "TimerThread") != null)
    {
        return .timer_queue_wait_item_state;
    }
    if (std.mem.indexOf(u8, function_name, "OnThreadBreakpointHit") != null) {
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

test "assertion classifier separates timer cause from breakpoint fallout" {
    try std.testing.expectEqual(Class.timer_queue_wait_item_state, classify(
        "TimerThreadMain",
        "WaitItem::State::kDisarmed == state",
    ));
    try std.testing.expectEqual(Class.breakpoint_untracked_thread, classify(
        "OnThreadBreakpointHit",
        "false",
    ));
    try std.testing.expectEqual(Class.export_ordinal_bounds, classify(
        "RegisterExport_xbdm",
        "export_entry->ordinal < xbdm_exports.size()",
    ));
    try std.testing.expectEqual(Class.none, classify("func", "false"));
}

test "noreturn assertion continuation rejects padding and traps only" {
    try std.testing.expect(isUnsafeNoreturnContinuation(&.{ 0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00 }));
    try std.testing.expect(isUnsafeNoreturnContinuation(&.{ 0x0F, 0x1F, 0x40, 0x00 }));
    try std.testing.expect(isUnsafeNoreturnContinuation(&.{ 0x0F, 0x0B }));
    try std.testing.expect(isUnsafeNoreturnContinuation(&.{0xCC}));
    try std.testing.expect(!isUnsafeNoreturnContinuation(&.{ 0x48, 0x8B, 0x45, 0xF8 }));
    try std.testing.expect(!isUnsafeNoreturnContinuation(&.{ 0xE9, 0x10, 0x00, 0x00, 0x00 }));
}

test "timer snapshot is diagnostic-only and does not mutate state" {
    const FakeState = struct {
        memory: [1024]u8 = [_]u8{0} ** 1024,

        fn guestMemoryConst(self: *const @This(), address: u64, count: u64) ?[]const u8 {
            const start: usize = @intCast(address);
            const length: usize = @intCast(count);
            if (start > self.memory.len or length > self.memory.len - start) return null;
            return self.memory[start .. start + length];
        }
    };

    var state = FakeState{};
    const rbp: u64 = 0x180;
    const wait_item: u64 = 0x280;
    state.memory[rbp - 0x79] = 0;
    std.mem.writeInt(u64, state.memory[rbp - 0x78 ..][0..8], wait_item, .little);
    state.memory[wait_item + 0x50] = 0;

    const snapshot = timerQueueSnapshot(&state, rbp).?;
    try std.testing.expectEqual(@as(u8, 0), snapshot.frame_state);
    try std.testing.expectEqual(@as(?u8, 0), snapshot.object_state);
    try std.testing.expectEqual(@as(u8, 0), state.memory[wait_item + 0x50]);
}
