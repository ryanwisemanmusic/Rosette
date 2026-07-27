const std = @import("std");

const Snapshot = struct {
    page_offset: usize,
    bytes: []u8,
};

pub const Journal = struct {
    allocator: std.mem.Allocator,
    page_size: usize,
    snapshots: std.ArrayList(Snapshot) = .empty,
    pages: std.AutoHashMap(usize, void),
    active: bool = false,
    capture_failed: bool = false,

    pub fn init(allocator: std.mem.Allocator, page_size: usize) Journal {
        return .{
            .allocator = allocator,
            .page_size = page_size,
            .pages = std.AutoHashMap(usize, void).init(allocator),
        };
    }

    pub fn deinit(self: *Journal) void {
        self.discard();
        self.snapshots.deinit(self.allocator);
        self.pages.deinit();
        self.* = undefined;
    }

    pub fn begin(self: *Journal) void {
        self.discard();
        self.active = true;
        self.capture_failed = false;
    }

    pub fn capture(self: *Journal, memory: []const u8, offset: usize, length: usize) void {
        if (!self.active or length == 0 or self.capture_failed) return;
        if (offset > memory.len or length > memory.len - offset) {
            self.capture_failed = true;
            return;
        }

        const first_page = offset / self.page_size;
        const last_page = (offset + length - 1) / self.page_size;
        for (first_page..last_page + 1) |page| {
            if (self.pages.contains(page)) continue;
            const page_offset = page * self.page_size;
            const page_end = @min(page_offset + self.page_size, memory.len);
            const snapshot = self.allocator.dupe(u8, memory[page_offset..page_end]) catch {
                self.capture_failed = true;
                return;
            };
            self.snapshots.append(self.allocator, .{
                .page_offset = page_offset,
                .bytes = snapshot,
            }) catch {
                self.allocator.free(snapshot);
                self.capture_failed = true;
                return;
            };
            self.pages.put(page, {}) catch {
                const removed = self.snapshots.pop().?;
                self.allocator.free(removed.bytes);
                self.capture_failed = true;
                return;
            };
        }
    }

    pub fn rollback(self: *Journal, memory: []u8) bool {
        if (!self.active) return true;
        const complete = !self.capture_failed;
        for (self.snapshots.items) |snapshot| {
            @memcpy(memory[snapshot.page_offset..][0..snapshot.bytes.len], snapshot.bytes);
        }
        self.discard();
        return complete;
    }

    pub fn commit(self: *Journal) bool {
        if (!self.active) return true;
        const complete = !self.capture_failed;
        self.discard();
        return complete;
    }

    fn discard(self: *Journal) void {
        for (self.snapshots.items) |snapshot| self.allocator.free(snapshot.bytes);
        self.snapshots.clearRetainingCapacity();
        self.pages.clearRetainingCapacity();
        self.active = false;
        self.capture_failed = false;
    }
};

test "page journal rolls back only captured pages" {
    var memory = [_]u8{0} ** 32;
    memory[3] = 7;
    memory[20] = 9;
    var journal = Journal.init(std.testing.allocator, 8);
    defer journal.deinit();

    journal.begin();
    journal.capture(&memory, 3, 18);
    memory[3] = 70;
    memory[20] = 90;
    try std.testing.expect(journal.rollback(&memory));
    try std.testing.expectEqual(@as(u8, 7), memory[3]);
    try std.testing.expectEqual(@as(u8, 9), memory[20]);
}

test "page journal commit preserves writes" {
    var memory = [_]u8{0} ** 16;
    var journal = Journal.init(std.testing.allocator, 8);
    defer journal.deinit();

    journal.begin();
    journal.capture(&memory, 4, 1);
    memory[4] = 42;
    try std.testing.expect(journal.commit());
    try std.testing.expectEqual(@as(u8, 42), memory[4]);
}
