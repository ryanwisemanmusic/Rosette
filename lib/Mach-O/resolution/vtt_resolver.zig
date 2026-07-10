const std = @import("std");

pub const DeferredBinding = struct {
    address: u64,
    symbol: []const u8,
    resolved: bool,
};

pub const VttBindingResolver = struct {
    allocator: std.mem.Allocator,
    deferred: std.ArrayList(DeferredBinding) = .empty,
    resolved_count: usize = 0,
    failed_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) VttBindingResolver {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *VttBindingResolver) void {
        for (self.deferred.items) |*item| {
            self.allocator.free(item.symbol);
        }
        self.deferred.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn record(self: *VttBindingResolver, address: u64, symbol: []const u8) !void {
        const owned = try self.allocator.dupe(u8, symbol);
        try self.deferred.append(self.allocator, .{
            .address = address,
            .symbol = owned,
            .resolved = false,
        });
    }

    pub fn lookupSymbol(name: []const u8) ?u64 {
        var buf: [2048]u8 = undefined;
        if (name.len >= buf.len) return null;
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        const symbol_z: [*:0]u8 = @ptrCast(&buf);
        const RTLD_DEFAULT = @as(*anyopaque, @ptrFromInt(@as(usize, @bitCast(@as(isize, -2)))));
        const addr = dlsym(RTLD_DEFAULT, symbol_z);
        return if (addr) |ptr| @intFromPtr(ptr) else null;
    }

    pub fn totalDeferred(self: *const VttBindingResolver) usize {
        return self.deferred.items.len;
    }

    pub fn logSummary(self: *const VttBindingResolver) void {
        std.debug.print(
            "macho-processor: VTT resolver: recorded={d} resolved={d} failed={d}\n",
            .{ self.deferred.items.len, self.resolved_count, self.failed_count },
        );
        if (self.failed_count > 0) {
            for (self.deferred.items) |item| {
                if (!item.resolved) {
                    std.debug.print(
                        "  unresolved VTT binding: address=0x{x} symbol={s}\n",
                        .{ item.address, item.symbol },
                    );
                }
            }
        }
    }
};

extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;

test "VTT resolver records deferred bindings" {
    var resolver = VttBindingResolver.init(std.testing.allocator);
    defer resolver.deinit();
    try resolver.record(0x1000, "__ZTVNSt3__19basic_iosIcNS_11char_traitsIcEEEE");
    try std.testing.expectEqual(@as(usize, 1), resolver.totalDeferred());
}

test "VTT resolver lookup finds symbols or returns null" {
    const result = VttBindingResolver.lookupSymbol("malloc");
    try std.testing.expect(result != null);
    const missing = VttBindingResolver.lookupSymbol("__nonexistent_symbol_xyz123");
    try std.testing.expect(missing == null);
}

test "VTT resolver inlines resolution correctly" {
    var resolver = VttBindingResolver.init(std.testing.allocator);
    defer resolver.deinit();
    try resolver.record(0x8000, "malloc");
    try resolver.record(0x9000, "__nonexistent_vtt_xyz");

    var resolved_count: usize = 0;
    for (resolver.deferred.items) |*item| {
        if (item.resolved) continue;
        if (VttBindingResolver.lookupSymbol(item.symbol)) |_| {
            item.resolved = true;
            resolved_count += 1;
        }
    }
    resolver.resolved_count = resolved_count;
    try std.testing.expectEqual(@as(usize, 1), resolved_count);
    try std.testing.expect(resolver.deferred.items[0].resolved);
    try std.testing.expect(!resolver.deferred.items[1].resolved);
}
