const std = @import("std");
const types = @import("types.zig");

const SlotIndex = types.SlotIndex;
const Handler = types.Handler;
const Result = types.Result;

pub const PrimitiveTable = struct {
    handlers: []?Handler = &.{},
    slot_count: SlotIndex = 0,

    pub fn init(handlers_slice: []?Handler) PrimitiveTable {
        return .{
            .handlers = handlers_slice,
            .slot_count = @intCast(handlers_slice.len),
        };
    }

    pub fn register(self: *PrimitiveTable, slot: SlotIndex, handler: Handler) void {
        if (slot >= self.slot_count) return;
        self.handlers[slot] = handler;
    }

    pub fn lookup(self: *const PrimitiveTable, slot: SlotIndex) ?Handler {
        if (slot >= self.slot_count) return null;
        return self.handlers[slot];
    }

    pub fn dispatch(self: *const PrimitiveTable, slot: SlotIndex, ctx: *const PrimitiveContext) Result {
        const handler = self.lookup(slot) orelse return .fallback;
        return handler(slot, ctx);
    }

    pub fn count(self: *const PrimitiveTable) usize {
        var c: usize = 0;
        for (self.handlers) |h| {
            if (h != null) c += 1;
        }
        return c;
    }
};

const PrimitiveContext = types.PrimitiveContext;

test "table: register and lookup" {
    const HandlerA = struct {
        fn handle(_: SlotIndex, _: *const PrimitiveContext) Result {
            return .handled;
        }
    };

    var storage: [4]?Handler = .{null} ** 4;
    var pt = PrimitiveTable.init(&storage);
    try std.testing.expectEqual(@as(usize, 0), pt.count());
    try std.testing.expectEqual(Result.fallback, pt.dispatch(0, undefined));

    pt.register(2, HandlerA.handle);
    try std.testing.expectEqual(@as(SlotIndex, 4), pt.slot_count);
    try std.testing.expect(pt.lookup(2) != null);
    try std.testing.expectEqual(@as(usize, 1), pt.count());
    try std.testing.expectEqual(Result.fallback, pt.dispatch(1, undefined));
    try std.testing.expectEqual(Result.handled, pt.dispatch(2, undefined));
}

test "table: out of bounds slot is silently ignored" {
    var storage: [1]?Handler = .{null} ** 1;
    var pt = PrimitiveTable.init(&storage);
    pt.register(999, undefined);
    try std.testing.expectEqual(Result.fallback, pt.dispatch(999, undefined));
}
