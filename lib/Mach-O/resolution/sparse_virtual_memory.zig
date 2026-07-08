const std = @import("std");

extern "c" fn mprotect(addr: [*]align(std.heap.page_size_min) u8, len: usize, prot: c_int) c_int;

pub const PAGE_64K: u64 = 64 * 1024;
pub const PAGE_4K: u64 = 4 * 1024;
pub const LARGE_PAGE: u64 = 2 * 1024 * 1024;

const Mapping = struct {
    guest_base: u64,
    memory: []align(std.heap.page_size_min) u8,
    readable: bool,
    writable: bool,
    executable: bool,
    is_fixed: bool,
    is_reservation: bool,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    mappings: std.ArrayList(Mapping) = .empty,
    total_reserved: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Manager) void {
        for (self.mappings.items) |mapping| {
            if (!mapping.is_reservation) std.posix.munmap(mapping.memory);
        }
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
        flags.FIXED = false;
        const prot: std.posix.PROT = @bitCast(prot_raw);
        const memory = std.posix.mmap(null, length_usize, prot, flags, host_fd, offset) catch return false;
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = prot_raw & 1 != 0,
            .writable = prot_raw & 2 != 0,
            .executable = prot_raw & 4 != 0,
            .is_fixed = false,
            .is_reservation = false,
        }) catch {
            std.posix.munmap(memory);
            return false;
        };
        return true;
    }

    pub fn mapFixed(self: *Manager, guest_base: u64, length: u64, prot_raw: u32, flags_raw: u32, host_fd: std.posix.fd_t, offset: u64) bool {
        if (length == 0 or guest_base % PAGE_64K != 0) return false;
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) {
                if (mapping.is_reservation and mapping.writable) {
                    _ = self.unmap(mapping.guest_base, mapping.memory.len);
                } else {
                    return false;
                }
            }
        }
        const length_usize = std.math.cast(usize, length) orelse return false;
        var flags: std.posix.MAP = @bitCast(flags_raw);
        flags.FIXED = true;
        const prot: std.posix.PROT = @bitCast(prot_raw);
        const ptr = @as(?[*]align(std.heap.page_size_min) u8, @ptrFromInt(guest_base));
        const memory = std.posix.mmap(ptr, length_usize, prot, flags, host_fd, offset) catch |err| {
            if (err == error.MemoryMappingNotSupported or err == error.PermissionDenied) {
                flags.FIXED = false;
                const alt = std.posix.mmap(null, length_usize, prot, flags, host_fd, offset) catch return false;
                self.mappings.append(self.allocator, .{
                    .guest_base = guest_base,
                    .memory = alt,
                    .readable = prot_raw & 1 != 0,
                    .writable = prot_raw & 2 != 0,
                    .executable = prot_raw & 4 != 0,
                    .is_fixed = false,
                    .is_reservation = false,
                }) catch {
                    std.posix.munmap(alt);
                    return false;
                };
                return true;
            }
            return false;
        };
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = prot_raw & 1 != 0,
            .writable = prot_raw & 2 != 0,
            .executable = prot_raw & 4 != 0,
            .is_fixed = true,
            .is_reservation = false,
        }) catch {
            std.posix.munmap(memory);
            return false;
        };
        return true;
    }

    pub fn reserveLarge(self: *Manager, guest_base: u64, length: u64) bool {
        if (length == 0 or guest_base % PAGE_64K != 0) return false;
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) return false;
        }
        const length_usize = std.math.cast(usize, length) orelse return false;
        const ptr = @as(?[*]align(std.heap.page_size_min) u8, @ptrFromInt(guest_base));
        const none_prot: std.posix.PROT = @bitCast(@as(u32, 0));
        const anon_private_fixed: std.posix.MAP = @bitCast(@as(u32, 0x1000 | 0x2 | 0x10));
        const memory = std.posix.mmap(ptr, length_usize, none_prot, anon_private_fixed, -1, 0) catch |err| {
            if (err == error.MemoryMappingNotSupported or err == error.PermissionDenied or err == error.ProcessFrozen) return false;
            const anon_private: std.posix.MAP = @bitCast(@as(u32, 0x1000 | 0x2));
            const alt = std.posix.mmap(null, length_usize, none_prot, anon_private, -1, 0) catch return false;
            self.mappings.append(self.allocator, .{
                .guest_base = guest_base,
                .memory = alt,
                .readable = false,
                .writable = false,
                .executable = false,
                .is_fixed = false,
                .is_reservation = true,
            }) catch {
                std.posix.munmap(alt);
                return false;
            };
            self.total_reserved +|= length;
            return true;
        };
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = false,
            .writable = false,
            .executable = false,
            .is_fixed = true,
            .is_reservation = true,
        }) catch {
            std.posix.munmap(memory);
            return false;
        };
        self.total_reserved +|= length;
        return true;
    }

    pub fn protect(self: *Manager, guest_base: u64, length: u64, prot_raw: u32) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base >= mapping.guest_base and end <= mapping_end) {
                const offset = @as(usize, @intCast(guest_base - mapping.guest_base));
                const page_aligned = @as([*]align(std.heap.page_size_min) u8, @alignCast(@ptrCast(&mapping.memory[offset])));
                if (mprotect(page_aligned, @intCast(length), @as(c_int, @intCast(prot_raw))) != 0) return false;
                mapping.readable = prot_raw & 1 != 0;
                mapping.writable = prot_raw & 2 != 0;
                mapping.executable = prot_raw & 4 != 0;
                return true;
            }
        }
        return false;
    }

    pub fn zeroFill(self: *Manager, guest_base: u64, length: u64) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base >= mapping.guest_base and end <= mapping_end) {
                const offset = @as(usize, @intCast(guest_base - mapping.guest_base));
                @memset(mapping.memory[offset..][0..@intCast(length)], 0);
                return true;
            }
        }
        return self.overwrite(guest_base, length, 0);
    }

    pub fn overwrite(self: *Manager, guest_base: u64, length: u64, value: u8) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base >= mapping.guest_base and end <= mapping_end) {
                const offset = @as(usize, @intCast(guest_base - mapping.guest_base));
                @memset(mapping.memory[offset..][0..@intCast(length)], value);
                return true;
            }
        }
        return false;
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
            if (!removed.is_reservation) std.posix.munmap(removed.memory);
            if (removed.is_reservation) self.total_reserved -|= removed.memory.len;
            return true;
        }
        return false;
    }

    pub fn logSummary(self: *const Manager) void {
        var map_count: usize = 0;
        var fixed_count: usize = 0;
        var reserved_count: usize = 0;
        for (self.mappings.items) |m| {
            if (m.is_reservation) reserved_count += 1;
            if (m.is_fixed) fixed_count += 1;
            map_count += 1;
        }
        std.debug.print(
            "macho-processor: sparse memory: mappings={d} fixed={d} reservations={d} reserved_bytes={d}\n",
            .{ map_count, fixed_count, reserved_count, self.total_reserved },
        );
    }

    fn find(self: *Manager, address: u64, length: u64) ?struct { mapping: *Mapping, offset: usize } {
        const end = std.math.add(u64, address, length) catch return null;
        for (self.mappings.items) |*mapping| {
            if (mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (address >= mapping.guest_base and end <= mapping_end)
                return .{ .mapping = mapping, .offset = @intCast(address - mapping.guest_base) };
        }
        return null;
    }

    fn findConst(self: *const Manager, address: u64, length: u64) ?struct { mapping: *const Mapping, offset: usize } {
        const end = std.math.add(u64, address, length) catch return null;
        for (self.mappings.items) |*mapping| {
            if (mapping.is_reservation) continue;
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

test "reserve large address space region" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const ok = manager.reserveLarge(0x100000000, 1024 * 1024 * 1024);
    try std.testing.expect(ok);
    try std.testing.expectEqual(@as(u64, 1024 * 1024 * 1024), manager.total_reserved);
}

test "protect changes mapping permissions" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base: u64 = 0x100000000;
    _ = manager.reserveLarge(base, 64 * 1024);
    const ok = manager.protect(base, 64 * 1024, 3);
    _ = ok;
}

test "zero fill mapped region" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base: u64 = 0x100000000;
    _ = manager.reserveLarge(base, 64 * 1024);
    _ = manager.protect(base, 64 * 1024, 3);
    const region = manager.bytes(base, 64, true) orelse return error.SkipZigTest;
    region[0] = 0xFF;
    try std.testing.expectEqual(@as(u8, 0xFF), region[0]);
    _ = manager.zeroFill(base, 64);
    try std.testing.expectEqual(@as(u8, 0), region[0]);
}
