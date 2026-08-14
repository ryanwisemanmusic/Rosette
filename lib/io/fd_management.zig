const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

extern "c" fn dirfd(directory: *std.c.DIR) c_int;

const INITIAL_FD_TABLE_SIZE: usize = 64;
pub const STREAM_FD_COUNT: usize = 3;

pub const FdKind = enum {
    file,
    directory,
    pipe,
    socket,
    shared_memory,
    unknown,
};

pub const FdEntry = struct {
    host_fd: i32 = -1,
    kind: FdKind = .unknown,
    directory: ?*std.c.DIR = null,
    guest_dirent: u64 = 0,
    close_on_exec: bool = true,
    flags: u32 = 0,
    generation: u64 = 0,
};

pub const BorrowedDescriptor = struct {
    host_fd: c_int,
    generation: u64,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    entries: []FdEntry,
    capacity: usize,
    next_hint: u64,
    next_generation: u64,
    rejected_full: u64 = 0,
    translated: u64 = 0,
    closed: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Manager {
        const entries = allocator.alloc(FdEntry, INITIAL_FD_TABLE_SIZE) catch blk: {
            machoCapturePrint("macho-processor: fd_management OOM on init, falling back to page_allocator\n", .{});
            break :blk std.heap.page_allocator.alloc(FdEntry, INITIAL_FD_TABLE_SIZE) catch @panic("fd_management: page_allocator OOM");
        };
        for (0..STREAM_FD_COUNT) |i| {
            entries[i] = .{
                .host_fd = @intCast(i),
                .kind = .file,
                .generation = i + 1,
            };
        }
        for (STREAM_FD_COUNT..INITIAL_FD_TABLE_SIZE) |i| {
            entries[i] = .{};
        }
        return .{
            .allocator = allocator,
            .entries = entries,
            .capacity = INITIAL_FD_TABLE_SIZE,
            .next_hint = STREAM_FD_COUNT,
            .next_generation = STREAM_FD_COUNT + 1,
        };
    }

    pub fn deinit(self: *Manager) void {
        for (self.entries) |entry| {
            if (entry.directory) |directory| {
                _ = std.c.closedir(directory);
            } else if (entry.host_fd >= STREAM_FD_COUNT) {
                _ = std.c.close(entry.host_fd);
            }
        }
        self.allocator.free(self.entries);
        self.* = undefined;
    }

    pub fn register(self: *Manager, host_fd: c_int, kind: FdKind) ?u64 {
        if (host_fd < 0) return null;

        const slot = self.findSlot() orelse {
            self.rejected_full += 1;
            _ = std.c.close(host_fd);
            return null;
        };

        self.entries[slot] = .{
            .host_fd = host_fd,
            .kind = kind,
            .generation = self.takeGeneration(),
        };
        self.next_hint = @intCast(slot + 1);
        self.translated += 1;
        return slot;
    }

    pub fn registerDirectory(self: *Manager, directory: *std.c.DIR) ?u64 {
        const host_fd = dirfd(directory);
        if (host_fd < 0) return null;
        const slot = self.findSlot() orelse {
            self.rejected_full += 1;
            _ = std.c.closedir(directory);
            return null;
        };
        self.entries[slot] = .{
            .host_fd = host_fd,
            .kind = .directory,
            .directory = directory,
            .generation = self.takeGeneration(),
        };
        self.next_hint = @intCast(slot + 1);
        self.translated += 1;
        return slot;
    }

    pub fn lookup(self: *Manager, guest_fd: u64) ?*FdEntry {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity or self.entries[index].host_fd < 0) return null;
        return &self.entries[index];
    }

    pub fn hostFd(self: *const Manager, guest_fd: u64) ?c_int {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity) return null;
        const entry = &self.entries[index];
        if (entry.host_fd < 0) return null;
        return entry.host_fd;
    }

    pub fn hostFdWithKind(self: *const Manager, guest_fd: u64, kind: FdKind) ?c_int {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity) return null;
        const entry = &self.entries[index];
        if (entry.host_fd < 0) return null;
        if (entry.kind != kind and kind != .unknown) return null;
        return entry.host_fd;
    }

    pub fn close(self: *Manager, guest_fd: u64) c_int {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity) return -1;
        const entry = &self.entries[index];
        if (entry.host_fd < 0) return -1;

        const host_fd = entry.host_fd;
        if (entry.directory) |directory| {
            const rc = std.c.closedir(directory);
            entry.* = .{};
            self.closed += 1;
            if (guest_fd < self.next_hint) self.next_hint = @max(guest_fd, STREAM_FD_COUNT);
            return rc;
        }
        entry.* = .{};
        if (host_fd >= STREAM_FD_COUNT) {
            const rc = std.c.close(host_fd);
            self.closed += 1;
            if (guest_fd < self.next_hint) self.next_hint = @max(guest_fd, STREAM_FD_COUNT);
            return rc;
        }
        self.closed += 1;
        return 0;
    }

    /// Borrows the descriptor for a stdio stream without removing its guest
    /// descriptor-table identity. POSIX `fdopen` associates a stream with the
    /// existing descriptor; `fileno(stream)` must therefore continue to return
    /// the same descriptor until `fclose` closes it.
    pub fn borrowForStream(self: *const Manager, guest_fd: u64) ?BorrowedDescriptor {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity) return null;
        const entry = self.entries[index];
        if (entry.host_fd < 0 or entry.directory != null) return null;
        return .{ .host_fd = entry.host_fd, .generation = entry.generation };
    }

    pub fn generationMatches(self: *const Manager, guest_fd: u64, generation: u64) bool {
        const index = std.math.cast(usize, guest_fd) orelse return false;
        if (index >= self.capacity) return false;
        const entry = self.entries[index];
        return entry.host_fd >= 0 and entry.generation == generation;
    }

    /// Closes only the descriptor generation originally associated with an
    /// owner, never an unrelated file that later reused the same guest number.
    pub fn closeGeneration(self: *Manager, guest_fd: u64, generation: u64) c_int {
        if (!self.generationMatches(guest_fd, generation)) return -1;
        return self.close(guest_fd);
    }

    pub fn dup(self: *Manager, guest_fd: u64) ?u64 {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity) return null;
        const entry = &self.entries[index];
        if (entry.host_fd < 0) return null;

        const host_dup = std.c.dup(entry.host_fd);
        if (host_dup < 0) return null;

        const new_slot = self.findSlot() orelse {
            _ = std.c.close(host_dup);
            self.rejected_full += 1;
            return null;
        };

        self.entries[new_slot] = .{
            .host_fd = host_dup,
            .kind = entry.kind,
            .close_on_exec = entry.close_on_exec,
            .flags = entry.flags,
            .generation = self.takeGeneration(),
        };
        self.next_hint = @intCast(new_slot + 1);
        return new_slot;
    }

    pub fn dupTo(self: *Manager, old_guest_fd: u64, new_guest_fd: u64) ?u64 {
        const old_index = @as(usize, @intCast(old_guest_fd));
        const new_index = @as(usize, @intCast(new_guest_fd));
        if (old_index >= self.capacity or new_index >= self.capacity) return null;

        const old_entry = &self.entries[old_index];
        if (old_entry.host_fd < 0) return null;

        const new_entry = &self.entries[new_index];
        if (new_entry.host_fd >= 0) {
            _ = self.close(new_guest_fd);
        }

        const host_dup = std.c.dup(old_entry.host_fd);
        if (host_dup < 0) return null;

        new_entry.* = .{
            .host_fd = host_dup,
            .kind = old_entry.kind,
            .close_on_exec = old_entry.close_on_exec,
            .flags = old_entry.flags,
            .generation = self.takeGeneration(),
        };
        return new_guest_fd;
    }

    pub fn setFlags(self: *Manager, guest_fd: u64, flags: u32) bool {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity) return false;
        if (self.entries[index].host_fd < 0) return false;
        self.entries[index].flags = flags;
        return true;
    }

    pub fn getFlags(self: *const Manager, guest_fd: u64) ?u32 {
        const index = @as(usize, @intCast(guest_fd));
        if (index >= self.capacity) return null;
        if (self.entries[index].host_fd < 0) return null;
        return self.entries[index].flags;
    }

    pub fn logSummary(self: *const Manager) void {
        var live: usize = 0;
        for (self.entries) |entry| {
            if (entry.host_fd >= 0) live += 1;
        }
        machoCapturePrint(
            "macho-processor: fd management: table_size={d} live={d} translated={d} closed={d} rejected_full={d}\n",
            .{ self.capacity, live, self.translated, self.closed, self.rejected_full },
        );
    }

    fn findSlot(self: *Manager) ?usize {
        var slot: usize = @intCast(@max(self.next_hint, STREAM_FD_COUNT));
        while (slot < self.capacity) {
            if (self.entries[slot].host_fd < 0) return slot;
            slot += 1;
        }
        const old = self.entries;
        const new_cap = self.capacity * 2;
        const new_entries = self.allocator.alloc(FdEntry, new_cap) catch return null;
        @memcpy(new_entries[0..old.len], old);
        for (old.len..new_cap) |i| new_entries[i] = .{};
        self.allocator.free(old);
        self.entries = new_entries;
        self.capacity = new_cap;
        return old.len;
    }

    fn takeGeneration(self: *Manager) u64 {
        const generation = self.next_generation;
        self.next_generation +%= 1;
        if (self.next_generation == 0) self.next_generation = 1;
        return generation;
    }
};

test "fd management lifecycle" {
    var mgr = Manager.init(std.testing.allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(c_int, 0), mgr.hostFd(0).?);
    try std.testing.expectEqual(@as(c_int, 1), mgr.hostFd(1).?);
    try std.testing.expectEqual(@as(c_int, 2), mgr.hostFd(2).?);

    var fds: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));

    const guest = mgr.register(fds[0], .pipe).?;
    try std.testing.expect(guest >= 3);

    const dup_fd = mgr.dup(guest).?;
    try std.testing.expect(dup_fd != guest);
    const h1 = mgr.hostFd(guest).?;
    const h2 = mgr.hostFd(dup_fd).?;
    try std.testing.expect(h1 != h2);
    try std.testing.expectEqual(@as(c_int, 0), mgr.close(guest));
    try std.testing.expectEqual(@as(c_int, 0), mgr.close(dup_fd));
    try std.testing.expect(mgr.hostFd(guest) == null);
    _ = std.c.close(fds[1]);
}

test "fd table grows dynamically" {
    var mgr = Manager.init(std.testing.allocator);
    defer mgr.deinit();

    var last: u64 = 0;
    for (0..100) |i| {
        const guest = mgr.register(@intCast(i + 100), .file).?;
        last = guest;
    }
    try std.testing.expect(last >= 64);
    try std.testing.expect(mgr.capacity >= 128);
}

test "fdopen borrowing preserves descriptor identity until fclose" {
    var mgr = Manager.init(std.testing.allocator);
    defer mgr.deinit();

    var fds: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));
    const guest = mgr.register(fds[0], .pipe).?;
    const borrowed = mgr.borrowForStream(guest).?;
    try std.testing.expectEqual(fds[0], borrowed.host_fd);
    try std.testing.expectEqual(fds[0], mgr.hostFd(guest).?);
    try std.testing.expect(mgr.generationMatches(guest, borrowed.generation));
    try std.testing.expectEqual(@as(c_int, 0), mgr.closeGeneration(guest, borrowed.generation));
    try std.testing.expect(mgr.hostFd(guest) == null);
    _ = std.c.close(fds[1]);
}

test "stale stdio generation cannot close a reused descriptor" {
    var mgr = Manager.init(std.testing.allocator);
    defer mgr.deinit();

    var first_pipe: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&first_pipe));
    const guest = mgr.register(first_pipe[0], .pipe).?;
    const borrowed = mgr.borrowForStream(guest).?;
    try std.testing.expectEqual(@as(c_int, 0), mgr.close(guest));
    _ = std.c.close(first_pipe[1]);

    var second_pipe: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&second_pipe));
    const reused_guest = mgr.register(second_pipe[0], .pipe).?;
    try std.testing.expectEqual(guest, reused_guest);
    try std.testing.expectEqual(@as(c_int, -1), mgr.closeGeneration(guest, borrowed.generation));
    try std.testing.expectEqual(second_pipe[0], mgr.hostFd(reused_guest).?);
    try std.testing.expectEqual(@as(c_int, 0), mgr.close(reused_guest));
    _ = std.c.close(second_pipe[1]);
}
