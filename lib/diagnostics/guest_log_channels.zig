//! Per-guest-thread storage for Xenia's synchronous formatted log bridge.
//!
//! Xenia asks for a thread buffer, writes a complete formatted record into it,
//! and then asks Rosette to append that record. Returning one process-global
//! buffer lets cooperative guest threads overwrite one another between those
//! calls, creating syntactically plausible but false PM4, wait-object and
//! ownership evidence. This bounded registry preserves the API's thread-local
//! contract without allocating on the log append path.

const std = @import("std");

pub const max_channels: usize = 128;

pub const Channel = struct {
    occupied: bool = false,
    thread: u64 = 0,
    address: u64 = 0,
    emissions: u64 = 0,
    failed_emissions: u64 = 0,
};

pub const Summary = struct {
    channels: u64,
    get_requests: u64,
    get_hits: u64,
    append_requests: u64,
    emissions: u64,
    failed_emissions: u64,
    missing_appends: u64,
    overflow: u64,

    pub fn isolated(self: Summary) bool {
        return self.missing_appends == 0 and self.overflow == 0;
    }
};

pub const Registry = struct {
    entries: [max_channels]Channel = [_]Channel{.{}} ** max_channels,
    channel_count: usize = 0,
    get_requests: u64 = 0,
    get_hits: u64 = 0,
    append_requests: u64 = 0,
    emissions: u64 = 0,
    failed_emissions: u64 = 0,
    missing_appends: u64 = 0,
    overflow: u64 = 0,

    fn find(self: *Registry, thread: u64) ?*Channel {
        for (self.entries[0..self.channel_count]) |*entry| {
            if (entry.occupied and entry.thread == thread) return entry;
        }
        return null;
    }

    pub fn lookupForGet(self: *Registry, thread: u64) ?u64 {
        self.get_requests +|= 1;
        const entry = self.find(thread) orelse return null;
        self.get_hits +|= 1;
        return entry.address;
    }

    pub fn bind(self: *Registry, thread: u64, address: u64) bool {
        if (address == 0) return false;
        if (self.find(thread)) |entry| {
            entry.address = address;
            return true;
        }
        if (self.channel_count == self.entries.len) {
            self.overflow +|= 1;
            return false;
        }
        self.entries[self.channel_count] = .{
            .occupied = true,
            .thread = thread,
            .address = address,
        };
        self.channel_count += 1;
        return true;
    }

    pub fn addressForAppend(self: *Registry, thread: u64) ?u64 {
        self.append_requests +|= 1;
        const entry = self.find(thread) orelse {
            self.missing_appends +|= 1;
            return null;
        };
        return entry.address;
    }

    pub fn noteEmission(self: *Registry, thread: u64, emitted: bool) void {
        const entry = self.find(thread) orelse return;
        if (emitted) {
            entry.emissions +|= 1;
            self.emissions +|= 1;
        } else {
            entry.failed_emissions +|= 1;
            self.failed_emissions +|= 1;
        }
    }

    pub fn summary(self: *const Registry) Summary {
        return .{
            .channels = @intCast(self.channel_count),
            .get_requests = self.get_requests,
            .get_hits = self.get_hits,
            .append_requests = self.append_requests,
            .emissions = self.emissions,
            .failed_emissions = self.failed_emissions,
            .missing_appends = self.missing_appends,
            .overflow = self.overflow,
        };
    }
};

test "guest threads receive isolated channels" {
    var registry = Registry{};
    try std.testing.expect(registry.bind(7, 0x1000));
    try std.testing.expect(registry.bind(8, 0x2000));
    try std.testing.expectEqual(@as(?u64, 0x1000), registry.lookupForGet(7));
    try std.testing.expectEqual(@as(?u64, 0x2000), registry.lookupForGet(8));
    try std.testing.expectEqual(@as(?u64, 0x1000), registry.addressForAppend(7));
    registry.noteEmission(7, true);
    const totals = registry.summary();
    try std.testing.expectEqual(@as(u64, 2), totals.channels);
    try std.testing.expectEqual(@as(u64, 1), totals.emissions);
    try std.testing.expect(totals.isolated());
}

test "append without a thread channel is rejected and counted" {
    var registry = Registry{};
    try std.testing.expectEqual(@as(?u64, null), registry.addressForAppend(99));
    try std.testing.expectEqual(@as(u64, 1), registry.summary().missing_appends);
}
