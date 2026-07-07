const std = @import("std");

pub const PAGE_64K: u64 = 64 * 1024;

const Mapping = struct {
    guest_base: u64,
    memory: []align(std.heap.page_size_min) u8,
    readable: bool,
    writable: bool,
    executable: bool,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    mappings: std.ArrayList(Mapping) = .empty,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Manager) void {
        for (self.mappings.items) |mapping| std.posix.munmap(mapping.memory);
        self.mappings.deinit(self.allocator);
    }

    pub fn mapFile(self: *Manager, guest_base: u64, length: u64, prot_raw: u32, flags_raw: u32, host_fd: std.posix.fd_t, offset: u64) bool {
        if (length == 0 or guest_base % PAGE_64K != 0 or offset % std.heap.page_size_min != 0) return false;
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) return false;
        }
        const length_usize = std.math.cast(usize, length) orelse return false;
        var flags: std.posix.MAP = @bitCast(flags_raw);
        // The requested address belongs to the emulated address space. The
        // host mapping may be placed anywhere, so MAP_FIXED must never escape.
        flags.FIXED = false;
        const prot: std.posix.PROT = @bitCast(prot_raw);
        const memory = std.posix.mmap(null, length_usize, prot, flags, host_fd, offset) catch return false;
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = prot_raw & 1 != 0,
            .writable = prot_raw & 2 != 0,
            .executable = prot_raw & 4 != 0,
        }) catch {
            std.posix.munmap(memory);
            return false;
        };
        return true;
    }

    pub fn bytes(self: *Manager, address: u64, length: u64, write: bool) ?[]u8 {
        const found = self.find(address, length) orelse return null;
        if (write and !found.mapping.writable) return null;
        if (!write and !found.mapping.readable) return null;
        return found.mapping.memory[found.offset..][0..@intCast(length)];
    }

    pub fn bytesConst(self: *const Manager, address: u64, length: u64) ?[]const u8 {
        const found = self.findConst(address, length) orelse return null;
        if (!found.mapping.readable) return null;
        return found.mapping.memory[found.offset..][0..@intCast(length)];
    }

    pub fn contains(self: *const Manager, address: u64, length: u64) bool {
        return self.findConst(address, length) != null;
    }

    pub fn unmap(self: *Manager, guest_base: u64, length: u64) bool {
        for (self.mappings.items, 0..) |mapping, index| {
            if (mapping.guest_base != guest_base or mapping.memory.len != length) continue;
            const removed = self.mappings.swapRemove(index);
            std.posix.munmap(removed.memory);
            return true;
        }
        return false;
    }

    fn find(self: *Manager, address: u64, length: u64) ?struct { mapping: *Mapping, offset: usize } {
        const end = std.math.add(u64, address, length) catch return null;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (address >= mapping.guest_base and end <= mapping_end)
                return .{ .mapping = mapping, .offset = @intCast(address - mapping.guest_base) };
        }
        return null;
    }

    fn findConst(self: *const Manager, address: u64, length: u64) ?struct { mapping: *const Mapping, offset: usize } {
        const end = std.math.add(u64, address, length) catch return null;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (address >= mapping.guest_base and end <= mapping_end)
                return .{ .mapping = mapping, .offset = @intCast(address - mapping.guest_base) };
        }
        return null;
    }
};

test "64K guest mapping alignment is explicit" {
    try std.testing.expectEqual(@as(u64, 65536), PAGE_64K);
}
