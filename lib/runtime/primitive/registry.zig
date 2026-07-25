const std = @import("std");
const types = @import("types.zig");
const table = @import("table.zig");

const Handler = types.Handler;

pub const PrimitiveDef = struct {
    name_pattern: []const u8,
    handler: Handler,
};

pub const PrimitiveRegistry = struct {
    defs: []const PrimitiveDef,

    pub fn init(defs: []const PrimitiveDef) PrimitiveRegistry {
        return .{ .defs = defs };
    }

    pub fn matchSymbol(self: *const PrimitiveRegistry, symbol_name: []const u8) ?Handler {
        for (self.defs) |def| {
            if (std.mem.indexOf(u8, symbol_name, def.name_pattern) != null) {
                return def.handler;
            }
        }
        return null;
    }

    pub fn populateTable(self: *const PrimitiveRegistry, pt: *table.PrimitiveTable, symbol_names: []const []const u8) usize {
        var registered: usize = 0;
        for (symbol_names, 0..) |name, slot| {
            if (slot >= pt.slot_count) break;
            if (pt.handlers[slot] != null) continue;
            if (self.matchSymbol(name)) |handler| {
                pt.handlers[slot] = handler;
                registered += 1;
            }
        }
        return registered;
    }
};

const builtin_primitives = [_]PrimitiveDef{
    .{ .name_pattern = "strlen", .handler = @import("handlers.zig").strlen },
    .{ .name_pattern = "memcmp", .handler = @import("handlers.zig").memcmp },
    .{ .name_pattern = "strcmp", .handler = @import("handlers.zig").strcmp },
    .{ .name_pattern = "strncmp", .handler = @import("handlers.zig").strncmp },
    .{ .name_pattern = "__cxa_guard_acquire", .handler = @import("handlers.zig").cxaGuardAcquire },
    .{ .name_pattern = "__cxa_guard_release", .handler = @import("handlers.zig").cxaGuardRelease },
    .{ .name_pattern = "__cxa_guard_abort", .handler = @import("handlers.zig").cxaGuardAbort },
};

pub fn builtin() PrimitiveRegistry {
    return PrimitiveRegistry.init(&builtin_primitives);
}

test "registry: match symbol by pattern" {
    const reg = builtin();
    try std.testing.expect(reg.matchSymbol("_strlen") != null);
    try std.testing.expect(reg.matchSymbol("__cxa_guard_acquire") != null);
    try std.testing.expect(reg.matchSymbol("_unknown_function") == null);
}

test "registry: populate table from symbol names" {
    var storage: [5]?Handler = .{null} ** 5;
    var pt = table.PrimitiveTable.init(&storage);

    const symbols = [_][]const u8{
        "_strlen",
        "_memcmp",
        "__cxa_guard_acquire",
        "__cxa_guard_release",
        "strncmp",
    };

    const reg = builtin();
    const count = reg.populateTable(&pt, &symbols);
    try std.testing.expectEqual(@as(usize, 5), count);
    try std.testing.expect(pt.handlers[0] != null);
    try std.testing.expect(pt.handlers[1] != null);
    try std.testing.expect(pt.handlers[2] != null);
    try std.testing.expect(pt.handlers[3] != null);
    try std.testing.expect(pt.handlers[4] != null);
}

test "registry: out of bounds slots do not register" {
    var storage: [1]?Handler = .{null} ** 1;
    var pt = table.PrimitiveTable.init(&storage);

    const symbols = [_][]const u8{ "_strlen", "__cxa_guard_acquire" };
    const reg = builtin();
    const count = reg.populateTable(&pt, &symbols);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "registry: empty defs list matches nothing" {
    const reg = PrimitiveRegistry.init(&.{});
    try std.testing.expect(reg.matchSymbol("_strlen") == null);
}
