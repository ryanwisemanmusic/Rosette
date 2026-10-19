//! Bounded code-space islands. Opt-in by the x64 direct-link compiler.
//! A 64 KiB pool at each 64 MiB region holds 4096 16-byte veneers. Blocks
//! keep their original spacing within each region: no per-block padding.
//! Pool exhaustion falls back to the caller's ordinary indirect route.
const std = @import("std");
pub const region_bytes: usize = 64 << 20;
pub const pool_bytes: usize = 64 << 10;
pub const veneer_bytes: usize = 16;
pub const minimum_capacity: usize = 128 << 20;
const Region = struct { reserved: bool = false, used: u16 = 0 };
pub const State = struct {
    regions: [32]Region = @splat(.{}),
    pub fn place(self: *@This(), capacity: usize, used: usize, bytes: usize) error{OutOfCodeSpace}!usize {
        if (bytes > region_bytes - pool_bytes) return error.OutOfCodeSpace;
        var at = std.mem.alignForward(usize, used, 16);
        while (at <= capacity and bytes <= capacity - at) {
            const index = at / region_bytes;
            if (index >= self.regions.len) return at;
            const start = index * region_bytes;
            const region = &self.regions[index];
            if (!region.reserved) {
                // A non-island/split allocation may already occupy the
                // region. Never claim its existing bytes as a pool.
                if (used > start) {
                    at = start + region_bytes;
                    continue;
                }
                if (start + pool_bytes > capacity) return error.OutOfCodeSpace;
                region.reserved = true;
            }
            at = @max(at, start + pool_bytes);
            if (at + bytes > start + region_bytes) {
                at = start + region_bytes;
                continue;
            }
            if (at > capacity or bytes > capacity - at) return error.OutOfCodeSpace;
            return at;
        }
        return error.OutOfCodeSpace;
    }
    pub fn peek(self: *@This(), memory: []u8, from: usize) ?[]u32 {
        const base = @intFromPtr(memory.ptr);
        if (from < base or from - base >= memory.len) return null;
        const index = (from - base) / region_bytes;
        if (index >= self.regions.len) return null;
        const r = &self.regions[index];
        if (!r.reserved or r.used >= pool_bytes / veneer_bytes) return null;
        const at = index * region_bytes + @as(usize, r.used) * veneer_bytes;
        if (at + veneer_bytes > memory.len) return null;
        return @as([*]u32, @ptrCast(@alignCast(memory.ptr + at)))[0..4];
    }
    pub fn take(self: *@This(), memory: []u8, from: usize) ?[]u32 {
        const out = self.peek(memory, from) orelse return null;
        const index = (from - @intFromPtr(memory.ptr)) / region_bytes;
        self.regions[index].used += 1;
        return out;
    }
    pub fn existing(self: *const @This(), memory: []u8, address: usize) ?[]u32 {
        const base = @intFromPtr(memory.ptr);
        if (address < base or address - base >= memory.len) return null;
        const offset = address - base;
        const index = offset / region_bytes;
        if (index >= self.regions.len or !self.regions[index].reserved) return null;
        const in_pool = offset % region_bytes;
        if (in_pool % veneer_bytes != 0 or in_pool / veneer_bytes >= self.regions[index].used) return null;
        return @as([*]u32, @ptrCast(@alignCast(memory.ptr + offset)))[0..4];
    }
};

test "branch islands preserve block spacing skip occupied regions and bound exhaustion" {
    const t = std.testing;
    var s: State = .{};
    try t.expectEqual(pool_bytes, try s.place(region_bytes * 3, 0, 100));
    try t.expectEqual(pool_bytes + 112, try s.place(region_bytes * 3, pool_bytes + 100, 80));
    try t.expectEqual(region_bytes + pool_bytes, try s.place(region_bytes * 3, region_bytes - 16, 80));
    var occupied: State = .{};
    try t.expectEqual(region_bytes + pool_bytes, try occupied.place(region_bytes * 3, 4096, 80));
    try t.expectError(error.OutOfCodeSpace, s.place(region_bytes * 3, 0, region_bytes));
    const raw = try t.allocator.alignedAlloc(u8, .@"16", pool_bytes);
    defer t.allocator.free(raw);
    for (0..pool_bytes / veneer_bytes) |_| try t.expect(s.take(raw, @intFromPtr(raw.ptr)) != null);
    try t.expect(s.take(raw, @intFromPtr(raw.ptr)) == null);
    try t.expect(s.existing(raw, @intFromPtr(raw.ptr) + pool_bytes - 16) != null);
    try t.expect(s.existing(raw, @intFromPtr(raw.ptr) + 1) == null);
    try t.expect(s.peek(raw, @intFromPtr(raw.ptr) - 1) == null);
    s = .{};
    try t.expect(s.existing(raw, @intFromPtr(raw.ptr)) == null);
}
