//! Independent subsystem coverage, separate from the sequential frontier.
//!
//! A frontier tells us how far one run got.  It does not tell us whether a
//! later subsystem was armed, whether its producer was alive, or whether a
//! zero count means "not reached" versus "observer lost the event".  This
//! board keeps those answers as bounded, typed state and refuses to turn an
//! incomplete observation into an authentic negative claim.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const capacity: usize = 128;
pub const name_capacity: usize = 48;

pub const State = enum(u8) {
    declared,
    observed,
    not_reached,
    blocked,
    unobservable,
    unsupported,
    suppressed,
    incomplete,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .declared => "declared",
            .observed => "observed",
            .not_reached => "not-reached",
            .blocked => "blocked",
            .unobservable => "unobservable",
            .unsupported => "unsupported",
            .suppressed => "suppressed",
            .incomplete => "incomplete",
        };
    }

    pub fn permitsAuthenticNegative(self: State) bool {
        return self == .not_reached or self == .observed;
    }

    pub fn blocksAuthentic(self: State) bool {
        return switch (self) {
            .unobservable, .suppressed, .incomplete, .blocked => true,
            .declared, .observed, .not_reached, .unsupported => false,
        };
    }
};

pub const Source = enum(u8) {
    manifest,
    xenia_structured,
    rosette_structured,
    replay,
    diagnostic_text,
    harness,
    unknown,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .manifest => "manifest",
            .xenia_structured => "xenia-structured",
            .rosette_structured => "rosette-structured",
            .replay => "replay",
            .diagnostic_text => "diagnostic-text",
            .harness => "harness",
            .unknown => "unknown",
        };
    }

    pub fn authoritative(self: Source) bool {
        return switch (self) {
            .manifest, .xenia_structured, .rosette_structured, .replay, .harness => true,
            .diagnostic_text, .unknown => false,
        };
    }
};

pub const Entry = struct {
    id: u64 = 0,
    name: [name_capacity]u8 = [_]u8{0} ** name_capacity,
    name_len: u8 = 0,
    capability_id: u16 = 0,
    source: Source = .unknown,
    required_for_authentic: bool = false,
    state: State = .declared,
    armed_before: bool = false,
    armed_after: bool = false,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_producer_sequence: u64 = 0,
    last_producer_sequence: u64 = 0,
    producer_heartbeats: u64 = 0,
    observations: u64 = 0,
    drops: u64 = 0,
    parser_errors: u64 = 0,
    duplicate_records: u64 = 0,
    unarmed_records: u64 = 0,
    state_changes: u64 = 0,

    pub fn nameSlice(self: *const Entry) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn observerIntact(self: Entry) bool {
        return self.armed_before and self.armed_after and
            self.producer_heartbeats >= 2 and self.drops == 0 and
            self.parser_errors == 0 and self.unarmed_records == 0;
    }

    pub fn negativeClaimAllowed(self: Entry) bool {
        return self.state.permitsAuthenticNegative() and self.observerIntact();
    }
};

pub const Summary = struct {
    declared: u64 = 0,
    observed: u64 = 0,
    not_reached: u64 = 0,
    blocked: u64 = 0,
    unobservable: u64 = 0,
    unsupported: u64 = 0,
    suppressed: u64 = 0,
    incomplete: u64 = 0,
    observer_failures: u64 = 0,
};

pub const Board = struct {
    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    next_id: u64 = 1,
    rejected: u64 = 0,
    schema: u16 = schema_version,

    pub fn declare(self: *Board, name: []const u8, capability_id: u16, source: Source) ?u64 {
        if (name.len == 0 or name.len > name_capacity or self.count >= capacity) {
            self.rejected +|= 1;
            return null;
        }
        var entry = Entry{ .id = self.next_id, .capability_id = capability_id, .source = source };
        self.next_id +|= 1;
        @memcpy(entry.name[0..name.len], name);
        entry.name_len = @intCast(name.len);
        self.entries[self.count] = entry;
        self.count += 1;
        return entry.id;
    }

    pub fn find(self: *Board, id: u64) ?*Entry {
        for (self.entries[0..self.count]) |*entry| if (entry.id == id) return entry;
        return null;
    }

    pub fn findByCapability(self: *Board, capability_id: u16) ?*Entry {
        for (self.entries[0..self.count]) |*entry| if (entry.capability_id == capability_id) return entry;
        return null;
    }

    pub fn arm(self: *Board, id: u64, step: u64) bool {
        const entry = self.find(id) orelse return false;
        if (!entry.armed_before) {
            entry.armed_before = true;
            entry.first_step = step;
        }
        entry.last_step = step;
        return true;
    }

    pub fn heartbeat(self: *Board, id: u64, producer_sequence: u64, step: u64) bool {
        const entry = self.find(id) orelse return false;
        if (!entry.armed_before) entry.unarmed_records +|= 1;
        if (entry.producer_heartbeats == 0) entry.first_producer_sequence = producer_sequence;
        entry.last_producer_sequence = producer_sequence;
        entry.producer_heartbeats +|= 1;
        entry.last_step = step;
        entry.armed_after = true;
        return true;
    }

    pub fn observe(self: *Board, id: u64, producer_sequence: u64, step: u64) bool {
        const entry = self.find(id) orelse return false;
        if (!entry.armed_before) entry.unarmed_records +|= 1;
        if (entry.observations == 0) entry.first_producer_sequence = producer_sequence;
        entry.last_producer_sequence = producer_sequence;
        entry.observations +|= 1;
        entry.last_step = step;
        entry.armed_after = true;
        entry.state = .observed;
        return true;
    }

    pub fn setState(self: *Board, id: u64, state: State, step: u64) bool {
        const entry = self.find(id) orelse return false;
        if (entry.state != state) entry.state_changes +|= 1;
        entry.state = state;
        entry.last_step = step;
        if (state == .not_reached and entry.observations == 0) entry.last_step = step;
        return true;
    }

    pub fn setRequired(self: *Board, id: u64, required: bool) bool {
        const entry = self.find(id) orelse return false;
        entry.required_for_authentic = required;
        return true;
    }

    pub fn noteDrop(self: *Board, id: u64, count: u64) bool {
        const entry = self.find(id) orelse return false;
        entry.drops +|= count;
        if (count != 0) entry.state = .incomplete;
        return true;
    }

    pub fn noteParserError(self: *Board, id: u64, count: u64) bool {
        const entry = self.find(id) orelse return false;
        entry.parser_errors +|= count;
        if (count != 0) entry.state = .unobservable;
        return true;
    }

    pub fn noteDuplicate(self: *Board, id: u64, count: u64) bool {
        const entry = self.find(id) orelse return false;
        entry.duplicate_records +|= count;
        if (count != 0) entry.state = .incomplete;
        return true;
    }

    pub fn summary(self: *const Board) Summary {
        var result = Summary{};
        for (self.entries[0..self.count]) |entry| {
            switch (entry.state) {
                .declared => result.declared += 1,
                .observed => result.observed += 1,
                .not_reached => result.not_reached += 1,
                .blocked => result.blocked += 1,
                .unobservable => result.unobservable += 1,
                .unsupported => result.unsupported += 1,
                .suppressed => result.suppressed += 1,
                .incomplete => result.incomplete += 1,
            }
            if (!entry.observerIntact()) result.observer_failures += 1;
        }
        return result;
    }

    pub fn authenticReady(self: *const Board) bool {
        for (self.entries[0..self.count]) |entry| {
            if (entry.state.blocksAuthentic()) return false;
            if (entry.state == .declared) return false;
            if (entry.state == .unsupported and entry.required_for_authentic) return false;
            if (entry.state == .observed and !entry.observerIntact()) return false;
        }
        return self.rejected == 0;
    }
};

test "coverage board keeps not reached distinct from unobservable" {
    var board = Board{};
    const target = board.declare("target", 3, .rosette_structured).?;
    const swap = board.declare("swap", 4, .rosette_structured).?;
    try std.testing.expect(board.arm(target, 10));
    try std.testing.expect(board.heartbeat(target, 1, 10));
    try std.testing.expect(board.heartbeat(target, 2, 20));
    try std.testing.expect(board.setState(target, .not_reached, 20));
    try std.testing.expect(board.setState(swap, .unobservable, 20));
    try std.testing.expect(board.entries[0].negativeClaimAllowed());
    try std.testing.expect(!board.entries[1].negativeClaimAllowed());
    try std.testing.expect(!board.authenticReady());
}

test "coverage board rejects an observation before its armed interval" {
    var board = Board{};
    const id = board.declare("callback", 7, .xenia_structured).?;
    try std.testing.expect(board.observe(id, 1, 4));
    try std.testing.expectEqual(@as(u64, 1), board.entries[0].unarmed_records);
    try std.testing.expect(!board.entries[0].negativeClaimAllowed());
}

test "coverage drops and parser errors are gate-visible" {
    var board = Board{};
    const id = board.declare("journal", 8, .rosette_structured).?;
    try std.testing.expect(board.arm(id, 1));
    try std.testing.expect(board.heartbeat(id, 1, 1));
    try std.testing.expect(board.heartbeat(id, 2, 2));
    try std.testing.expect(board.noteDrop(id, 1));
    try std.testing.expect(board.noteParserError(id, 1));
    const entry = board.find(id).?;
    try std.testing.expectEqual(State.unobservable, entry.state);
    try std.testing.expectEqual(@as(u64, 1), board.summary().observer_failures);
}

test "unsupported host capability is not a hidden authentic negative" {
    var board = Board{};
    const id = board.declare("optional-rhi", 9, .manifest).?;
    try std.testing.expect(board.setState(id, .unsupported, 0));
    try std.testing.expect(board.authenticReady());
    try std.testing.expect(Source.manifest.authoritative());
    // A manifest-owned unsupported capability is explicit; it is not a
    // missing observer and therefore does not poison unrelated evidence.
    try std.testing.expect(!board.entries[0].negativeClaimAllowed());
}

test "coverage board reports every state in its summary" {
    var board = Board{};
    const states = [_]State{ .declared, .observed, .not_reached, .blocked, .unobservable, .unsupported, .suppressed, .incomplete };
    for (states, 0..) |state, index| {
        const id = board.declare("row", @intCast(index), .harness).?;
        try std.testing.expect(board.setState(id, state, @intCast(index)));
    }
    const result = board.summary();
    try std.testing.expectEqual(@as(u64, 1), result.declared);
    try std.testing.expectEqual(@as(u64, 1), result.observed);
    try std.testing.expectEqual(@as(u64, 1), result.not_reached);
    try std.testing.expectEqual(@as(u64, 1), result.blocked);
    try std.testing.expectEqual(@as(u64, 1), result.unobservable);
    try std.testing.expectEqual(@as(u64, 1), result.unsupported);
    try std.testing.expectEqual(@as(u64, 1), result.suppressed);
    try std.testing.expectEqual(@as(u64, 1), result.incomplete);
}
