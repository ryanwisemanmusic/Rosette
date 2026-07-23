const std = @import("std");
const types = @import("types.zig");

const GuestAddress = types.GuestAddress;
const HostAddress = types.HostAddress;
const JitEvent = types.JitEvent;
const JitEventKind = types.JitEventKind;
const GuestFunction = types.GuestFunction;
const CodeCacheRegion = types.CodeCacheRegion;

pub const Monitor = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayListUnmanaged(JitEvent) = .empty,
    is_recording: bool = false,
    event_count_by_kind: [event_kind_count]u64 = [_]u64{0} ** event_kind_count,

    const event_kind_count = std.meta.fields(JitEventKind).len;

    pub fn init(allocator: std.mem.Allocator) Monitor {
        return Monitor{ .allocator = allocator };
    }

    pub fn deinit(self: *Monitor) void {
        self.events.deinit(self.allocator);
    }

    pub fn startRecording(self: *Monitor) void {
        self.is_recording = true;
    }

    pub fn stopRecording(self: *Monitor) void {
        self.is_recording = false;
    }

    pub fn recordEvent(self: *Monitor, event: JitEvent) !void {
        if (!self.is_recording) return;
        try self.events.append(self.allocator, event);
        const kind_index = @as(usize, @intFromEnum(event.kind));
        if (kind_index < self.event_count_by_kind.len) {
            self.event_count_by_kind[kind_index] += 1;
        }
    }

    pub fn clearEvents(self: *Monitor) void {
        self.events.clearAndFree(self.allocator);
        for (&self.event_count_by_kind) |*count| {
            count.* = 0;
        }
    }

    pub fn eventCount(self: *const Monitor) usize {
        return self.events.items.len;
    }

    pub fn countByKind(self: *const Monitor, kind: JitEventKind) u64 {
        const kind_index = @as(usize, @intFromEnum(kind));
        if (kind_index < self.event_count_by_kind.len) {
            return self.event_count_by_kind[kind_index];
        }
        return 0;
    }

    pub fn getEventsByKind(self: *const Monitor, kind: JitEventKind, allocator: std.mem.Allocator) ![]JitEvent {
        var result: std.ArrayListUnmanaged(JitEvent) = .empty;
        defer result.deinit(allocator);
        for (self.events.items) |event| {
            if (event.kind == kind) {
                try result.append(allocator, event);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn getEventsInRange(self: *const Monitor, start_ns: u64, end_ns: u64, allocator: std.mem.Allocator) ![]JitEvent {
        var result: std.ArrayListUnmanaged(JitEvent) = .empty;
        defer result.deinit(allocator);
        for (self.events.items) |event| {
            if (event.timestamp_ns >= start_ns and event.timestamp_ns <= end_ns) {
                try result.append(allocator, event);
            }
        }
        return result.toOwnedSlice(allocator);
    }
};

test "Monitor records and retrieves events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var monitor = Monitor.init(allocator);
    defer monitor.deinit();

    monitor.startRecording();
    try monitor.recordEvent(.{
        .kind = .function_compiled,
        .timestamp_ns = 1000,
        .guest_addr = 0x82000000,
        .host_addr = 0x10000,
        .size = 4096,
    });
    try monitor.recordEvent(.{
        .kind = .code_cache_allocated,
        .timestamp_ns = 2000,
        .host_addr = 0x10000,
        .size = 65536,
    });

    try std.testing.expectEqual(@as(usize, 2), monitor.eventCount());
    try std.testing.expectEqual(@as(u64, 1), monitor.countByKind(.function_compiled));
    try std.testing.expectEqual(@as(u64, 1), monitor.countByKind(.code_cache_allocated));

    const compiled = try monitor.getEventsByKind(.function_compiled, allocator);
    defer allocator.free(compiled);
    try std.testing.expectEqual(@as(usize, 1), compiled.len);
    try std.testing.expectEqual(@as(GuestAddress, 0x82000000), compiled[0].guest_addr);
}

test "Monitor ignores events when not recording" {
    var monitor = Monitor.init(std.testing.allocator);
    defer monitor.deinit();

    try monitor.recordEvent(.{
        .kind = .function_compiled,
        .timestamp_ns = 1000,
    });
    try std.testing.expectEqual(@as(usize, 0), monitor.eventCount());
}

test "Monitor clearEvents resets all state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var monitor = Monitor.init(allocator);
    defer monitor.deinit();

    monitor.startRecording();
    try monitor.recordEvent(.{
        .kind = .function_compiled,
        .timestamp_ns = 1000,
    });
    try std.testing.expectEqual(@as(usize, 1), monitor.eventCount());

    monitor.clearEvents();
    try std.testing.expectEqual(@as(usize, 0), monitor.eventCount());
    try std.testing.expectEqual(@as(u64, 0), monitor.countByKind(.function_compiled));
}

test "Monitor records multiple event kinds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var monitor = Monitor.init(allocator);
    defer monitor.deinit();
    monitor.startRecording();

    const kinds = [_]JitEventKind{
        .function_compiled,
        .function_executed,
        .code_cache_allocated,
        .thunk_generated,
        .guest_to_host_trampoline,
        .host_to_guest_call,
    };

    for (kinds) |kind| {
        try monitor.recordEvent(.{ .kind = kind, .timestamp_ns = 0 });
    }

    for (kinds) |kind| {
        try std.testing.expectEqual(@as(u64, 1), monitor.countByKind(kind));
    }
}
