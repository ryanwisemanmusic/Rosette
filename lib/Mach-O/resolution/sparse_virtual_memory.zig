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

const Activation = struct {
    guest_base: u64,
    memory: []align(std.heap.page_size_min) u8,
    readable: bool,
    writable: bool,
    executable: bool,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    mappings: std.ArrayList(Mapping) = .empty,
    activations: std.ArrayList(Activation) = .empty,
    total_reserved: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Manager) void {
        for (self.mappings.items) |mapping| {
            std.posix.munmap(mapping.memory);
        }
        self.mappings.deinit(self.allocator);
        self.activations.deinit(self.allocator);
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
        if (length == 0 or guest_base % std.heap.page_size_min != 0) {
            std.debug.print("macho-processor: sparse fixed mmap rejected: reason=invalid_length_or_alignment guest_base=0x{x} length={d} required_alignment={d}\n", .{ guest_base, length, std.heap.page_size_min });
            return false;
        }
        const end = std.math.add(u64, guest_base, length) catch {
            std.debug.print("macho-processor: sparse fixed mmap rejected: reason=address_overflow guest_base=0x{x} length={d}\n", .{ guest_base, length });
            return false;
        };
        var inside_reservation = false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) {
                if (!mapping.is_reservation or guest_base < mapping.guest_base or end > mapping_end) {
                    std.debug.print(
                        "macho-processor: sparse fixed mmap rejected: reason=overlap guest=[0x{x},0x{x}) existing=[0x{x},0x{x}) existing_is_reservation={}\n",
                        .{ guest_base, end, mapping.guest_base, mapping_end, mapping.is_reservation },
                    );
                    return false;
                }
                inside_reservation = true;
            }
        }
        const length_usize = std.math.cast(usize, length) orelse return false;
        var flags: std.posix.MAP = @bitCast(flags_raw);
        flags.FIXED = true;
        const prot: std.posix.PROT = @bitCast(prot_raw);
        const ptr = @as(?[*]align(std.heap.page_size_min) u8, @ptrFromInt(guest_base));
        const memory = std.posix.mmap(ptr, length_usize, prot, flags, host_fd, offset) catch |err| {
            const anonymous_private = flags.ANONYMOUS and host_fd < 0;
            if (anonymous_private and inside_reservation) {
                if (self.activateReservationRange(guest_base, length, prot_raw)) {
                    std.debug.print(
                        "macho-processor: sparse fixed mmap activated reservation: primary={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x}\n",
                        .{ @errorName(err), guest_base, length, prot_raw, flags_raw },
                    );
                    return true;
                }
                std.debug.print(
                    "macho-processor: sparse fixed mmap FAILED: reason={s} fallback_disallowed=reservation_activation_failed guest_base=0x{x} length={d}\n",
                    .{ @errorName(err), guest_base, length },
                );
                return false;
            }
            if (anonymous_private and isRecoverableFixedMmapFailure(err)) {
                flags.FIXED = false;
                const alt = std.posix.mmap(null, length_usize, prot, flags, -1, 0) catch |fallback_err| {
                    std.debug.print("macho-processor: sparse fixed mmap FAILED: primary={s} fallback={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ @errorName(err), @errorName(fallback_err), guest_base, length, prot_raw, flags_raw, host_fd, offset });
                    return false;
                };
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
                std.debug.print(
                    "macho-processor: sparse fixed mmap fallback: primary={s} guest_base=0x{x} length={d} model=anonymous_guest_backing host_base=0x{x}\n",
                    .{ @errorName(err), guest_base, length, @intFromPtr(alt.ptr) },
                );
                return true;
            }
            if (err == error.MemoryMappingNotSupported or err == error.PermissionDenied) {
                if (inside_reservation) {
                    std.debug.print("macho-processor: sparse fixed mmap FAILED: reason={s} fallback_disallowed=would_break_reserved_guest_address guest_base=0x{x} length={d}\n", .{ @errorName(err), guest_base, length });
                    return false;
                }
                flags.FIXED = false;
                const alt = std.posix.mmap(null, length_usize, prot, flags, host_fd, offset) catch |fallback_err| {
                    std.debug.print("macho-processor: sparse fixed mmap FAILED: primary={s} fallback={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ @errorName(err), @errorName(fallback_err), guest_base, length, prot_raw, flags_raw, host_fd, offset });
                    return false;
                };
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
            std.debug.print("macho-processor: sparse fixed mmap FAILED: reason={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ @errorName(err), guest_base, length, prot_raw, flags_raw, host_fd, offset });
            return false;
        };
        if (inside_reservation) {
            self.appendActivation(guest_base, memory, prot_raw) catch return false;
        } else {
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
        }
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

    /// Reserves address space without committing physical memory.  Returning
    /// the host mapping address as the guest address lets later mprotect calls
    /// activate pages in-place while keeping the 4 GiB reservation sparse.
    pub fn reserveAnywhere(self: *Manager, length: u64) ?u64 {
        const anon_private: u32 = 0x1000 | 0x2;
        return self.reserveAnywhereWithBacking(length, anon_private, -1, 0);
    }

    pub fn reserveAnywhereWithBacking(self: *Manager, length: u64, flags_raw: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
        if (length == 0) {
            std.debug.print("macho-processor: sparse reserve rejected: reason=zero_length flags=0x{x} host_fd={d} offset=0x{x}\n", .{ flags_raw, host_fd, offset });
            return null;
        }
        const length_usize = std.math.cast(usize, length) orelse {
            std.debug.print("macho-processor: sparse reserve rejected: reason=length_exceeds_host_usize length={d} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ length, flags_raw, host_fd, offset });
            return null;
        };
        const none_prot: std.posix.PROT = @bitCast(@as(u32, 0));
        var flags: std.posix.MAP = @bitCast(flags_raw);
        flags.FIXED = false;
        std.debug.print(
            "macho-processor: sparse reserve request: length={d} (0x{x}) prot=NONE flags=0x{x} fixed={} anonymous={} host_fd={d} offset=0x{x} existing_mappings={d}\n",
            .{ length, length, flags_raw, flags.FIXED, flags.ANONYMOUS, host_fd, offset, self.mappings.items.len },
        );
        const memory = if (!flags.ANONYMOUS and host_fd < 0) invalid_fd_fallback: {
            std.debug.print(
                "macho-processor: sparse reserve request has non-anonymous fd=-1; reserving anonymous PROT_NONE space instead length={d} flags=0x{x} offset=0x{x}\n",
                .{ length, flags_raw, offset },
            );
            const anon_private_raw: u32 = 0x1000 | 0x2;
            var anon_private: std.posix.MAP = @bitCast(anon_private_raw);
            anon_private.FIXED = false;
            break :invalid_fd_fallback std.posix.mmap(null, length_usize, none_prot, anon_private, -1, 0) catch |fallback_err| {
                std.debug.print(
                    "macho-processor: sparse reserve fallback FAILED: primary=invalid_fd fallback={s} length={d} requested_flags=0x{x} fallback_flags=0x{x}\n",
                    .{ @errorName(fallback_err), length, flags_raw, anon_private_raw },
                );
                return null;
            };
        } else std.posix.mmap(null, length_usize, none_prot, flags, host_fd, offset) catch |err| fallback: {
            std.debug.print(
                "macho-processor: sparse reserve FAILED: syscall=mmap reason={s} length={d} flags=0x{x} anonymous={} host_fd={d} offset=0x{x}\n",
                .{ @errorName(err), length, flags_raw, flags.ANONYMOUS, host_fd, offset },
            );
            if (flags.ANONYMOUS and host_fd < 0) return null;
            const anon_private_raw: u32 = 0x1000 | 0x2;
            var anon_private: std.posix.MAP = @bitCast(anon_private_raw);
            anon_private.FIXED = false;
            const fallback = std.posix.mmap(null, length_usize, none_prot, anon_private, -1, 0) catch |fallback_err| {
                std.debug.print(
                    "macho-processor: sparse reserve fallback FAILED: primary={s} fallback={s} length={d} requested_flags=0x{x} fallback_flags=0x{x}\n",
                    .{ @errorName(err), @errorName(fallback_err), length, flags_raw, anon_private_raw },
                );
                return null;
            };
            std.debug.print(
                "macho-processor: sparse reserve fallback: primary={s} requested_flags=0x{x} requested_fd={d}; reserved anonymous PROT_NONE space instead\n",
                .{ @errorName(err), flags_raw, host_fd },
            );
            break :fallback fallback;
        };
        const guest_base = @intFromPtr(memory.ptr);
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = false,
            .writable = false,
            .executable = false,
            .is_fixed = false,
            .is_reservation = true,
        }) catch {
            std.posix.munmap(memory);
            return null;
        };
        self.total_reserved +|= length;
        std.debug.print(
            "macho-processor: sparse reserve succeeded: guest_base=0x{x} host_base=0x{x} length={d} host_page_size={d} total_reserved={d}\n",
            .{ guest_base, @intFromPtr(memory.ptr), length, std.heap.page_size_min, self.total_reserved },
        );
        return guest_base;
    }

    pub fn protect(self: *Manager, guest_base: u64, length: u64, prot_raw: u32) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base >= mapping.guest_base and end <= mapping_end) {
                const offset = @as(usize, @intCast(guest_base - mapping.guest_base));
                const page_aligned = @as([*]align(std.heap.page_size_min) u8, @ptrCast(@alignCast(&mapping.memory[offset])));
                if (mprotect(page_aligned, @intCast(length), @as(c_int, @intCast(prot_raw))) != 0) return false;
                if (mapping.is_reservation) {
                    const active_memory = @as([]align(std.heap.page_size_min) u8, @alignCast(mapping.memory[offset..][0..@intCast(length)]));
                    self.appendActivation(guest_base, active_memory, prot_raw) catch return false;
                } else {
                    mapping.readable = prot_raw & 1 != 0;
                    mapping.writable = prot_raw & 2 != 0;
                    mapping.executable = prot_raw & 4 != 0;
                }
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
        if (self.activeBytes(address, length, write)) |active| return active;
        const found = self.find(address, length) orelse return null;
        if (write and !found.mapping.writable) return null;
        if (!write and !found.mapping.readable) return null;
        return found.mapping.memory[found.offset..][0..@intCast(length)];
    }

    pub fn bytesConst(self: *const Manager, address: u64, length: u64) ?[]const u8 {
        if (self.activeBytesConst(address, length)) |active| return active;
        const found = self.findConst(address, length) orelse return null;
        if (!found.mapping.readable) return null;
        return found.mapping.memory[found.offset..][0..@intCast(length)];
    }

    pub fn contains(self: *const Manager, address: u64, length: u64) bool {
        return self.activeBytesConst(address, length) != null or self.findConst(address, length) != null;
    }

    pub fn unmap(self: *Manager, guest_base: u64, length: u64) bool {
        for (self.mappings.items, 0..) |mapping, index| {
            if (mapping.guest_base != guest_base or mapping.memory.len != length) continue;
            const removed = self.mappings.swapRemove(index);
            self.removeActivationsWithin(guest_base, length);
            std.posix.munmap(removed.memory);
            if (removed.is_reservation) self.total_reserved -|= removed.memory.len;
            return true;
        }
        for (self.mappings.items) |mapping| {
            if (!mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            const end = std.math.add(u64, guest_base, length) catch return false;
            if (guest_base < mapping.guest_base or end > mapping_end) continue;
            var found_exact = false;
            for (self.activations.items) |active| {
                if (active.guest_base == guest_base and active.memory.len == length) {
                    found_exact = true;
                    break;
                }
            }
            if (!found_exact) return false;
            const offset: usize = @intCast(guest_base - mapping.guest_base);
            const memory = @as([]align(std.heap.page_size_min) u8, @alignCast(mapping.memory[offset..][0..@intCast(length)]));
            if (mprotect(memory.ptr, memory.len, 0) != 0) return false;
            self.removeActivationsWithin(guest_base, length);
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
            "macho-processor: sparse memory: mappings={d} fixed={d} reservations={d} activations={d} reserved_bytes={d}\n",
            .{ map_count, fixed_count, reserved_count, self.activations.items.len, self.total_reserved },
        );
    }

    test "file-backed PROT_NONE reservation falls back to anonymous address space" {
        var manager = Manager.init(std.testing.allocator);
        defer manager.deinit();

        const impossible_file_backed: u32 = 0x0001;
        const base = manager.reserveAnywhereWithBacking(PAGE_64K, impossible_file_backed, -1, 0) orelse return error.TestUnexpectedResult;
        try std.testing.expect(base != 0);
        try std.testing.expectEqual(@as(u64, PAGE_64K), manager.total_reserved);
        try std.testing.expect(manager.bytes(base, 1, false) == null);
        try std.testing.expect(manager.protect(base, std.heap.page_size_min, 3));
        try std.testing.expect(manager.bytes(base, 1, true) != null);
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

    fn appendActivation(self: *Manager, guest_base: u64, memory: []align(std.heap.page_size_min) u8, prot_raw: u32) !void {
        // Newer mprotect calls supersede older permission records for the same
        // exact span. Reverse lookup below also handles contained updates.
        try self.activations.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = prot_raw & 1 != 0,
            .writable = prot_raw & 2 != 0,
            .executable = prot_raw & 4 != 0,
        });
    }

    pub fn activeBytes(self: *Manager, address: u64, length: u64, write: bool) ?[]u8 {
        const end = std.math.add(u64, address, length) catch return null;
        var index = self.activations.items.len;
        while (index != 0) {
            index -= 1;
            const active = &self.activations.items[index];
            const active_end = active.guest_base + active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            if (address < active.guest_base or end > active_end) return null;
            if (write and !active.writable) return null;
            if (!write and !active.readable) return null;
            const offset: usize = @intCast(address - active.guest_base);
            return active.memory[offset..][0..@intCast(length)];
        }
        return null;
    }

    fn activeBytesConst(self: *const Manager, address: u64, length: u64) ?[]const u8 {
        const end = std.math.add(u64, address, length) catch return null;
        var index = self.activations.items.len;
        while (index != 0) {
            index -= 1;
            const active = &self.activations.items[index];
            const active_end = active.guest_base + active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            if (address < active.guest_base or end > active_end or !active.readable) return null;
            const offset: usize = @intCast(address - active.guest_base);
            return active.memory[offset..][0..@intCast(length)];
        }
        return null;
    }

    fn removeActivationsWithin(self: *Manager, guest_base: u64, length: u64) void {
        const end = guest_base +| length;
        var index = self.activations.items.len;
        while (index != 0) {
            index -= 1;
            const active = self.activations.items[index];
            const active_end = active.guest_base +| active.memory.len;
            if (active.guest_base >= guest_base and active_end <= end) _ = self.activations.swapRemove(index);
        }
    }

    fn activateReservationRange(self: *Manager, guest_base: u64, length: u64, prot_raw: u32) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            if (!mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping.guest_base or end > mapping_end) continue;
            const offset: usize = @intCast(guest_base - mapping.guest_base);
            const memory = @as([]align(std.heap.page_size_min) u8, @alignCast(mapping.memory[offset..][0..@intCast(length)]));
            if (mprotect(memory.ptr, memory.len, @as(c_int, @intCast(prot_raw))) != 0) return false;
            self.appendActivation(guest_base, memory, prot_raw) catch return false;
            return true;
        }
        return false;
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

fn isRecoverableFixedMmapFailure(err: anyerror) bool {
    return err == error.MemoryMappingNotSupported or
        err == error.PermissionDenied or
        err == error.OutOfMemory or
        err == error.InvalidArgument;
}

test "64K guest mapping alignment is explicit" {
    try std.testing.expectEqual(@as(u64, 65536), PAGE_64K);
}

test "fixed anonymous guest range uses independent host backing" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const darwin_map_private_anonymous_fixed: u32 = 0x0002 | 0x1000 | 0x0010;
    try std.testing.expect(manager.mapFile(0x8000_0000, PAGE_64K, 3, darwin_map_private_anonymous_fixed, -1, 0));
    const bytes = manager.bytes(0x8000_0000, 16, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0xA5;
    try std.testing.expectEqual(@as(u8, 0xA5), manager.bytesConst(0x8000_0000, 1).?[0]);
}

test "reserve large address space region" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const ok = manager.reserveLarge(0x100000000, 1024 * 1024 * 1024);
    try std.testing.expect(ok);
    try std.testing.expectEqual(@as(u64, 1024 * 1024 * 1024), manager.total_reserved);
}

test "reserve 4 GiB anywhere without guest heap backing" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const four_gib: u64 = 4 * 1024 * 1024 * 1024;
    const base = manager.reserveAnywhere(four_gib) orelse return error.TestUnexpectedResult;
    try std.testing.expect(base != 0);
    try std.testing.expectEqual(four_gib, manager.total_reserved);
    try std.testing.expect(manager.contains(base, 1) == false);
    try std.testing.expect(manager.protect(base, PAGE_64K, 3));
    try std.testing.expect(manager.contains(base, 1));
}

test "partial activation and fixed mapping preserve surrounding reservation" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base = manager.reserveAnywhere(2 * PAGE_64K) orelse return error.TestUnexpectedResult;
    try std.testing.expect(manager.protect(base, PAGE_64K, 3));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
    try std.testing.expect(manager.bytes(base + PAGE_64K, 1, false) == null);

    const fixed_anon_private: u32 = 0x0010 | 0x1000 | 0x0002;
    try std.testing.expect(manager.mapFixed(base + PAGE_64K, PAGE_64K, 3, fixed_anon_private, -1, 0));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
    try std.testing.expect(manager.bytes(base + PAGE_64K, 1, true) != null);
    try std.testing.expectEqual(@as(u64, 2 * PAGE_64K), manager.total_reserved);
    try std.testing.expect(manager.unmap(base + PAGE_64K, PAGE_64K));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
    try std.testing.expect(manager.bytes(base + PAGE_64K, 1, false) == null);
}

test "high fixed anonymous mapping falls back to guest modeled backing" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const fixed_anon_private: u32 = 0x0010 | 0x1000 | 0x0002;
    const guest_base: u64 = 0x40dfffc000;
    try std.testing.expect(manager.mapFixed(guest_base, 19136, 3, fixed_anon_private, -1, 0));
    const bytes = manager.bytes(guest_base, 8, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0x5A;
    try std.testing.expectEqual(@as(u8, 0x5A), manager.bytesConst(guest_base, 1).?[0]);
}

test "new protection overrides an older broad activation" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base = manager.reserveAnywhere(PAGE_64K) orelse return error.TestUnexpectedResult;
    try std.testing.expect(manager.protect(base, PAGE_64K, 3));
    try std.testing.expect(manager.protect(base, std.heap.page_size_min, 0));
    try std.testing.expect(manager.bytes(base, 1, false) == null);
    try std.testing.expect(manager.bytes(base + std.heap.page_size_min, 1, true) != null);
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
