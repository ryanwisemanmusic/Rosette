const std = @import("std");

pub fn check(comptime Entry: type) !void {
    var map: [1]Entry = @splat(.{});
    try std.testing.expectEqual(Entry.InsertResult.inserted, Entry.alloc(&map, 11, 101));
    for (0..10) |_| try std.testing.expectEqual(@as(?u64, 101), Entry.findReal(&map, 11));
    try std.testing.expectEqual(Entry.InsertResult.replaced, Entry.alloc(&map, 11, 102));
    try std.testing.expectEqual(@as(?u64, 102), Entry.findReal(&map, 11));
    try std.testing.expect(Entry.remove(&map, 11));
    try std.testing.expectEqual(Entry.InsertResult.inserted, Entry.alloc(&map, 12, 201));
    try std.testing.expectEqual(@as(?u64, null), Entry.findReal(&map, 11));
    try std.testing.expectEqual(@as(?u64, 201), Entry.findReal(&map, 12));
    Entry.clear(&map);
    try std.testing.expectEqual(@as(?u64, null), Entry.findReal(&map, 12));
    try std.testing.expectEqual(Entry.InsertResult.inserted, Entry.alloc(&map, 11, 103));
    try std.testing.expectEqual(@as(?u64, 103), Entry.findReal(&map, 11));

    const Shared = struct {
        slots: [1]Entry = @splat(.{}),
        done: std.atomic.Value(bool) = .init(false),
        errors: std.atomic.Value(u64) = .init(0),
        fn writer(self: *@This()) void {
            for (0..10000) |_| {
                _ = Entry.alloc(&self.slots, 11, 101);
                _ = Entry.remove(&self.slots, 11);
                _ = Entry.alloc(&self.slots, 12, 201);
                _ = Entry.remove(&self.slots, 12);
            }
            self.done.store(true, .release);
        }
        fn reader(self: *@This()) void {
            while (!self.done.load(.acquire)) {
                if (Entry.findReal(&self.slots, 11)) |value| if (value != 101) {
                    _ = self.errors.fetchAdd(1, .monotonic);
                };
                if (Entry.findReal(&self.slots, 12)) |value| if (value != 201) {
                    _ = self.errors.fetchAdd(1, .monotonic);
                };
                if (Entry.findSynthetic(&self.slots, 101)) |value| if (value != 11) {
                    _ = self.errors.fetchAdd(1, .monotonic);
                };
                if (Entry.findSynthetic(&self.slots, 201)) |value| if (value != 12) {
                    _ = self.errors.fetchAdd(1, .monotonic);
                };
            }
        }
    };
    var shared = Shared{};
    const reader = try std.Thread.spawn(.{}, Shared.reader, .{&shared});
    Shared.writer(&shared);
    reader.join();
    try std.testing.expectEqual(@as(u64, 0), shared.errors.load(.monotonic));
}
