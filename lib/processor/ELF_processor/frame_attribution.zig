//! Bounded snapshots that line up guest work and input activity with the
//! host-PC samples collected around each presented frame. This ledger is only
//! populated when the opt-in host sampler is running.

const std = @import("std");

pub const max_threads: usize = 64;
pub const history_len: usize = 16;
pub const name_capacity: usize = 64;

pub const InputSnapshot = struct {
    polls: u64 = 0,
    bridged: u64 = 0,
    invalid: u64 = 0,
    nonzero: u64 = 0,
    key_down: u64 = 0,
    key_up: u64 = 0,
    focus_gains: u64 = 0,
    focus_losses: u64 = 0,
    rejected: u64 = 0,
    packet: u32 = 0,
    buttons: u16 = 0,
    left_trigger: u8 = 0,
    right_trigger: u8 = 0,
    thumb_lx: i16 = 0,
    thumb_ly: i16 = 0,
    thumb_rx: i16 = 0,
    thumb_ry: i16 = 0,
    focused: bool = false,
    active: bool = false,
};

/// Atomics make the frame-boundary reader independent of whichever guest
/// worker most recently polled the native input bridge. Callback counters
/// are cumulative in the bridge, so fetchMax tolerates readers arriving out
/// of order on parallel workers.
pub const InputActivity = struct {
    polls: std.atomic.Value(u64) = .init(0),
    bridged: std.atomic.Value(u64) = .init(0),
    invalid: std.atomic.Value(u64) = .init(0),
    nonzero: std.atomic.Value(u64) = .init(0),
    key_down: std.atomic.Value(u64) = .init(0),
    key_up: std.atomic.Value(u64) = .init(0),
    focus_gains: std.atomic.Value(u64) = .init(0),
    focus_losses: std.atomic.Value(u64) = .init(0),
    rejected: std.atomic.Value(u64) = .init(0),
    packet: std.atomic.Value(u32) = .init(0),
    buttons: std.atomic.Value(u16) = .init(0),
    left_trigger: std.atomic.Value(u8) = .init(0),
    right_trigger: std.atomic.Value(u8) = .init(0),
    thumb_lx: std.atomic.Value(i16) = .init(0),
    thumb_ly: std.atomic.Value(i16) = .init(0),
    thumb_rx: std.atomic.Value(i16) = .init(0),
    thumb_ry: std.atomic.Value(i16) = .init(0),
    focused: std.atomic.Value(bool) = .init(false),

    pub fn noteInvalidPoll(self: *InputActivity) void {
        _ = self.polls.fetchAdd(1, .monotonic);
        _ = self.invalid.fetchAdd(1, .monotonic);
    }

    pub fn noteSuccessfulPoll(self: *InputActivity, input: InputSnapshot) void {
        _ = self.polls.fetchAdd(1, .monotonic);
        _ = self.bridged.fetchAdd(1, .monotonic);
        if (input.active) _ = self.nonzero.fetchAdd(1, .monotonic);
        _ = self.key_down.fetchMax(input.key_down, .monotonic);
        _ = self.key_up.fetchMax(input.key_up, .monotonic);
        _ = self.focus_gains.fetchMax(input.focus_gains, .monotonic);
        _ = self.focus_losses.fetchMax(input.focus_losses, .monotonic);
        _ = self.rejected.fetchMax(input.rejected, .monotonic);
        self.packet.store(input.packet, .release);
        self.buttons.store(input.buttons, .release);
        self.left_trigger.store(input.left_trigger, .release);
        self.right_trigger.store(input.right_trigger, .release);
        self.thumb_lx.store(input.thumb_lx, .release);
        self.thumb_ly.store(input.thumb_ly, .release);
        self.thumb_rx.store(input.thumb_rx, .release);
        self.thumb_ry.store(input.thumb_ry, .release);
        self.focused.store(input.focused, .release);
    }

    pub fn snapshot(self: *const InputActivity) InputSnapshot {
        return .{
            .polls = self.polls.load(.acquire),
            .bridged = self.bridged.load(.acquire),
            .invalid = self.invalid.load(.acquire),
            .nonzero = self.nonzero.load(.acquire),
            .key_down = self.key_down.load(.acquire),
            .key_up = self.key_up.load(.acquire),
            .focus_gains = self.focus_gains.load(.acquire),
            .focus_losses = self.focus_losses.load(.acquire),
            .rejected = self.rejected.load(.acquire),
            .packet = self.packet.load(.acquire),
            .buttons = self.buttons.load(.acquire),
            .left_trigger = self.left_trigger.load(.acquire),
            .right_trigger = self.right_trigger.load(.acquire),
            .thumb_lx = self.thumb_lx.load(.acquire),
            .thumb_ly = self.thumb_ly.load(.acquire),
            .thumb_rx = self.thumb_rx.load(.acquire),
            .thumb_ry = self.thumb_ry.load(.acquire),
            .focused = self.focused.load(.acquire),
            .active = false,
        };
    }
};

pub const ThreadSnapshot = struct {
    handle: u64 = 0,
    instructions: u64 = 0,
    name: []const u8 = "",
};

pub const ThreadDelta = struct {
    handle: u64 = 0,
    instructions: u64 = 0,
    name: [name_capacity]u8 = @splat(0),
    name_len: u8 = 0,
};

pub const InputDelta = struct {
    polls: u64 = 0,
    bridged: u64 = 0,
    invalid: u64 = 0,
    nonzero: u64 = 0,
    key_down: u64 = 0,
    key_up: u64 = 0,
    focus_gains: u64 = 0,
    focus_losses: u64 = 0,
    rejected: u64 = 0,
    packet: u32 = 0,
    buttons: u16 = 0,
    left_trigger: u8 = 0,
    right_trigger: u8 = 0,
    thumb_lx: i16 = 0,
    thumb_ly: i16 = 0,
    thumb_rx: i16 = 0,
    thumb_ry: i16 = 0,
    focused: bool = false,
};

pub const Record = struct {
    swap_index: u64 = 0,
    host_epoch: u64 = 0,
    elapsed_ns: u64 = 0,
    guest_instructions: u64 = 0,
    owner_instructions: u64 = 0,
    input: InputDelta = .{},
    threads: [max_threads]ThreadDelta = @splat(.{}),
};

/// The input/output edge is written by a guest worker while other guest
/// workers may be live. The ledger is only touched at that edge, while the
/// sampler itself writes its independent host-PC buckets.
pub const Ledger = struct {
    records: [history_len]Record = @splat(.{}),
    next: usize = 0,
    count: usize = 0,
    has_baseline: bool = false,
    previous_wall_ns: u64 = 0,
    previous_guest_instructions: u64 = 0,
    previous_owner_instructions: u64 = 0,
    previous_input: InputSnapshot = .{},
    previous_handles: [max_threads]u64 = @splat(0),
    previous_thread_instructions: [max_threads]u64 = @splat(0),

    pub fn noteBoundary(
        self: *Ledger,
        swap_index: u64,
        host_epoch: u64,
        wall_ns: u64,
        guest_instructions: u64,
        owner_instructions: u64,
        threads: []const ThreadSnapshot,
        input: InputSnapshot,
    ) void {
        if (!self.has_baseline) {
            self.has_baseline = true;
            self.updateBaseline(wall_ns, guest_instructions, owner_instructions, threads, input);
            return;
        }

        var record: Record = .{
            .swap_index = swap_index,
            .host_epoch = host_epoch,
            .elapsed_ns = wall_ns -| self.previous_wall_ns,
            .guest_instructions = guest_instructions -| self.previous_guest_instructions,
            .owner_instructions = owner_instructions -| self.previous_owner_instructions,
            .input = inputDelta(input, self.previous_input),
        };
        for (threads[0..@min(threads.len, max_threads)], 0..) |thread, slot| {
            if (thread.handle == 0) continue;
            const delta = if (thread.handle == self.previous_handles[slot])
                thread.instructions -| self.previous_thread_instructions[slot]
            else
                0;
            const name_len = @min(thread.name.len, name_capacity);
            @memcpy(record.threads[slot].name[0..name_len], thread.name[0..name_len]);
            record.threads[slot].handle = thread.handle;
            record.threads[slot].instructions = delta;
            record.threads[slot].name_len = @intCast(name_len);
        }

        self.records[self.next] = record;
        self.next = (self.next + 1) % history_len;
        if (self.count < history_len) self.count += 1;
        self.updateBaseline(wall_ns, guest_instructions, owner_instructions, threads, input);
    }

    pub fn recent(self: *const Ledger, age: usize) ?*const Record {
        if (age >= self.count) return null;
        const index = (self.next + history_len - 1 - age) % history_len;
        return &self.records[index];
    }

    fn updateBaseline(
        self: *Ledger,
        wall_ns: u64,
        guest_instructions: u64,
        owner_instructions: u64,
        threads: []const ThreadSnapshot,
        input: InputSnapshot,
    ) void {
        self.previous_wall_ns = wall_ns;
        self.previous_guest_instructions = guest_instructions;
        self.previous_owner_instructions = owner_instructions;
        self.previous_input = input;
        @memset(&self.previous_handles, 0);
        @memset(&self.previous_thread_instructions, 0);
        for (threads[0..@min(threads.len, max_threads)], 0..) |thread, slot| {
            self.previous_handles[slot] = thread.handle;
            self.previous_thread_instructions[slot] = thread.instructions;
        }
    }
};

fn inputDelta(current: InputSnapshot, previous: InputSnapshot) InputDelta {
    return .{
        .polls = current.polls -| previous.polls,
        .bridged = current.bridged -| previous.bridged,
        .invalid = current.invalid -| previous.invalid,
        .nonzero = current.nonzero -| previous.nonzero,
        .key_down = current.key_down -| previous.key_down,
        .key_up = current.key_up -| previous.key_up,
        .focus_gains = current.focus_gains -| previous.focus_gains,
        .focus_losses = current.focus_losses -| previous.focus_losses,
        .rejected = current.rejected -| previous.rejected,
        .packet = current.packet,
        .buttons = current.buttons,
        .left_trigger = current.left_trigger,
        .right_trigger = current.right_trigger,
        .thumb_lx = current.thumb_lx,
        .thumb_ly = current.thumb_ly,
        .thumb_rx = current.thumb_rx,
        .thumb_ry = current.thumb_ry,
        .focused = current.focused,
    };
}

test "frame ledger keeps bounded deltas correlated by guest thread handle" {
    var ledger: Ledger = .{};
    const before = [_]ThreadSnapshot{
        .{ .handle = 0x10, .instructions = 100, .name = "MAIN_THREAD" },
        .{ .handle = 0x20, .instructions = 50, .name = "RENDER" },
    };
    ledger.noteBoundary(1, 0, 1_000, 150, 90, &before, .{});
    const after = [_]ThreadSnapshot{
        .{ .handle = 0x10, .instructions = 180, .name = "MAIN_THREAD" },
        .{ .handle = 0x21, .instructions = 80, .name = "replacement" },
    };
    ledger.noteBoundary(2, 1, 2_500, 260, 140, &after, .{ .polls = 4, .bridged = 4, .nonzero = 2, .key_down = 3, .key_up = 2, .focused = true, .buttons = 8 });
    const record = ledger.recent(0).?;
    try std.testing.expectEqual(@as(u64, 2), record.swap_index);
    try std.testing.expectEqual(@as(u64, 1), record.host_epoch);
    try std.testing.expectEqual(@as(u64, 1_500), record.elapsed_ns);
    try std.testing.expectEqual(@as(u64, 110), record.guest_instructions);
    try std.testing.expectEqual(@as(u64, 50), record.owner_instructions);
    try std.testing.expectEqual(@as(u64, 80), record.threads[0].instructions);
    try std.testing.expectEqualStrings("MAIN_THREAD", record.threads[0].name[0..record.threads[0].name_len]);
    try std.testing.expectEqual(@as(u64, 0), record.threads[1].instructions);
    try std.testing.expectEqual(@as(u64, 4), record.input.polls);
    try std.testing.expectEqual(@as(u64, 3), record.input.key_down);
    try std.testing.expect(record.input.focused);
}

test "input activity publishes atomic cumulative counters and the latest pad state" {
    var activity: InputActivity = .{};
    activity.noteInvalidPoll();
    activity.noteSuccessfulPoll(.{
        .polls = 1,
        .bridged = 1,
        .key_down = 4,
        .key_up = 2,
        .focus_gains = 1,
        .packet = 12,
        .buttons = 8,
        .thumb_rx = -1000,
        .focused = true,
        .active = true,
    });
    // A racing worker can return an older snapshot later. Cumulative events
    // retain their high-water marks, while the per-poll counters stay exact.
    activity.noteSuccessfulPoll(.{ .key_down = 3, .packet = 11, .thumb_rx = -1000, .focused = false });
    const current = activity.snapshot();
    try std.testing.expectEqual(@as(u64, 3), current.polls);
    try std.testing.expectEqual(@as(u64, 2), current.bridged);
    try std.testing.expectEqual(@as(u64, 1), current.invalid);
    try std.testing.expectEqual(@as(u64, 4), current.key_down);
    try std.testing.expectEqual(@as(u64, 2), current.key_up);
    try std.testing.expectEqual(@as(u64, 1), current.nonzero);
    try std.testing.expectEqual(@as(u32, 11), current.packet);
    try std.testing.expect(!current.focused);
    try std.testing.expectEqual(@as(i16, -1000), current.thumb_rx);
}

test "frame ledger reports only its newest bounded window" {
    var ledger: Ledger = .{};
    ledger.noteBoundary(0, 0, 1, 0, 0, &.{}, .{});
    for (1..history_len + 5) |swap_index| {
        ledger.noteBoundary(swap_index, swap_index - 1, swap_index + 1, swap_index, 0, &.{}, .{});
    }
    try std.testing.expectEqual(history_len, ledger.count);
    try std.testing.expectEqual(@as(u64, history_len + 4), ledger.recent(0).?.swap_index);
    try std.testing.expectEqual(@as(u64, 5), ledger.recent(history_len - 1).?.swap_index);
    try std.testing.expect(ledger.recent(history_len) == null);
}
