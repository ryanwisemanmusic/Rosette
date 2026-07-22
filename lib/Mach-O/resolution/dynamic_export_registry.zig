const std = @import("std");

pub const ExportRecord = struct {
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: u8 = 0,
    ordinal: u32 = 0,
    function_address: u64 = 0,
    from_assertion: bool = false,
};

pub const ResolveResult = struct {
    address: u64,
    ordinal: u32,
    name: []const u8,
    matched_by_ordinal: bool,
};

pub const Registry = struct {
    entries: [64]ExportRecord = [_]ExportRecord{.{}} ** 64,
    count: usize = 0,
    fallback_attempts: u64 = 0,
    fallback_hits: u64 = 0,

    pub fn register(
        self: *Registry,
        ordinal: u32,
        name: []const u8,
        function_address: u64,
        from_assertion: bool,
    ) void {
        for (0..self.count) |i| {
            const e = &self.entries[i];
            if (e.ordinal == ordinal) {
                const namelen = @min(name.len, e.name.len - 1);
                @memcpy(e.name[0..namelen], name[0..namelen]);
                e.name_len = @intCast(namelen);
                if (function_address != 0) e.function_address = function_address;
                if (from_assertion) e.from_assertion = true;
                return;
            }
        }
        if (self.count < self.entries.len) {
            const e = &self.entries[self.count];
            const namelen = @min(name.len, e.name.len - 1);
            @memcpy(e.name[0..namelen], name[0..namelen]);
            e.name_len = @intCast(namelen);
            e.ordinal = ordinal;
            e.function_address = function_address;
            e.from_assertion = from_assertion;
            self.count += 1;
        }
    }

    pub fn resolve(self: *const Registry, ordinal: u32, name: []const u8) ?ResolveResult {
        {
            var best_ordinal: ?ResolveResult = null;
            for (0..self.count) |i| {
                const e = self.entries[i];
                if (e.ordinal == ordinal) {
                    const entry_name = std.mem.sliceTo(&e.name, 0);
                    best_ordinal = .{
                        .address = e.function_address,
                        .ordinal = e.ordinal,
                        .name = entry_name,
                        .matched_by_ordinal = true,
                    };
                    if (name.len == 0) return best_ordinal;
                    if (std.mem.eql(u8, entry_name, name)) return best_ordinal;
                }
            }
            if (best_ordinal != null and name.len == 0) return best_ordinal;
        }

        if (name.len > 0) {
            for (0..self.count) |i| {
                const e = self.entries[i];
                const entry_name = std.mem.sliceTo(&e.name, 0);
                if (name.len > 0 and std.mem.eql(u8, entry_name, name)) {
                    return .{
                        .address = e.function_address,
                        .ordinal = e.ordinal,
                        .name = entry_name,
                        .matched_by_ordinal = false,
                    };
                }
            }
        }

        return null;
    }

    pub fn resolveByName(self: *const Registry, name: []const u8) ?ResolveResult {
        if (name.len == 0) return null;
        for (0..self.count) |i| {
            const e = self.entries[i];
            const entry_name = std.mem.sliceTo(&e.name, 0);
            if (std.mem.eql(u8, entry_name, name)) {
                return .{
                    .address = e.function_address,
                    .ordinal = e.ordinal,
                    .name = entry_name,
                    .matched_by_ordinal = false,
                };
            }
        }
        return null;
    }

    pub fn resolveByOrdinal(self: *const Registry, ordinal: u32) ?ResolveResult {
        for (0..self.count) |i| {
            const e = self.entries[i];
            if (e.ordinal == ordinal) {
                const entry_name = std.mem.sliceTo(&e.name, 0);
                return .{
                    .address = e.function_address,
                    .ordinal = e.ordinal,
                    .name = entry_name,
                    .matched_by_ordinal = true,
                };
            }
        }
        return null;
    }

    pub fn fallbackResolve(self: *Registry, ordinal: u32, name: []const u8) ResolveResult {
        self.fallback_attempts += 1;
        const existing = self.resolve(ordinal, name);
        if (existing) |res| {
            self.fallback_hits += 1;
            return res;
        }
        self.register(ordinal, name, 0, true);
        return .{
            .address = 0,
            .ordinal = ordinal,
            .name = name,
            .matched_by_ordinal = if (ordinal != 0) true else (name.len > 0),
        };
    }

    pub fn logSummary(self: *const Registry) void {
        if (self.count == 0) return;
        std.debug.print(
            "macho-processor: dynamic export registry: entries={d} fallback_attempts={d} fallback_hits={d}\n",
            .{ self.count, self.fallback_attempts, self.fallback_hits },
        );
        for (0..@min(self.count, 8)) |i| {
            const e = self.entries[i];
            const ename = std.mem.sliceTo(&e.name, 0);
            std.debug.print(
                "macho-processor:   entry[{d}] ordinal={d} name={s} addr=0x{x} from_assert={}\n",
                .{ i, e.ordinal, ename, e.function_address, e.from_assertion },
            );
        }
    }
};

test "dynamic export registry records exports" {
    var reg = Registry{};
    reg.register(0, "xbdm_export_1", 0, true);
    try std.testing.expectEqual(@as(usize, 1), reg.count);
}

test "dynamic export registry resolves by ordinal" {
    var reg = Registry{};
    reg.register(3, "xbdm_export_3", 0x1000, true);
    const res = reg.resolveByOrdinal(3) orelse @panic("not found");
    try std.testing.expectEqual(@as(u64, 0x1000), res.address);
    try std.testing.expect(res.matched_by_ordinal);
}

test "dynamic export registry resolves by name" {
    var reg = Registry{};
    reg.register(5, "xbdm_export_5", 0x2000, true);
    const res = reg.resolveByName("xbdm_export_5") orelse @panic("not found");
    try std.testing.expectEqual(@as(u64, 0x2000), res.address);
    try std.testing.expect(!res.matched_by_ordinal);
}

test "dynamic export registry fallback creates stub" {
    var reg = Registry{};
    const res = reg.fallbackResolve(7, "xbdm_export_7");
    try std.testing.expectEqual(@as(u64, 0), res.address);
    try std.testing.expectEqual(@as(u64, 1), reg.fallback_attempts);
    try std.testing.expectEqual(@as(u64, 0), reg.fallback_hits);
}

test "dynamic export registry fallback reuses existing" {
    var reg = Registry{};
    reg.register(9, "xbdm_export_9", 0x3000, true);
    const res = reg.fallbackResolve(9, "");
    try std.testing.expectEqual(@as(u64, 0x3000), res.address);
    try std.testing.expectEqual(@as(u64, 1), reg.fallback_attempts);
    try std.testing.expectEqual(@as(u64, 1), reg.fallback_hits);
}
