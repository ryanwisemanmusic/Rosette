const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const TableEntry = struct {
    address: u64,
    ordinal: u32,
};

pub const RecoveryAction = enum {
    none,
    skip_assertion,
    table_was_resized,
};

pub const TableProfile = struct {
    table_address: u64,
    current_size: u32,
    needed_size: u32,
    last_ordinal: u32,
};

pub const Manager = struct {
    tables: [16]TableProfile = [_]TableProfile{.{ .table_address = 0, .current_size = 0, .needed_size = 0, .last_ordinal = 0 }} ** 16,
    resizes: u64 = 0,
    skips: u64 = 0,
    last_action: RecoveryAction = .none,

    pub fn recordTable(self: *Manager, table_address: u64, current_size: u32, ordinal: u32) RecoveryAction {
        if (ordinal < current_size) return .none;
        for (&self.tables) |*entry| {
            if (entry.table_address == table_address) {
                if (ordinal >= entry.current_size) {
                    entry.current_size = ordinal + 1;
                    if (ordinal > entry.needed_size) entry.needed_size = ordinal;
                    entry.last_ordinal = ordinal;
                    self.resizes += 1;
                    self.last_action = .table_was_resized;
                    return .table_was_resized;
                }
                return .none;
            }
        }
        for (&self.tables) |*entry| {
            if (entry.table_address == 0) {
                entry.* = .{
                    .table_address = table_address,
                    .current_size = ordinal + 1,
                    .needed_size = ordinal,
                    .last_ordinal = ordinal,
                };
                self.resizes += 1;
                self.last_action = .table_was_resized;
                return .table_was_resized;
            }
        }
        self.last_action = .skip_assertion;
        return .skip_assertion;
    }

    pub fn diagnoseExportOrdinalBounds(
        self: *Manager,
        ordinal: u32,
        table_size: u32,
        table_address: u64,
    ) RecoveryAction {
        if (ordinal < table_size) return .none;
        const needed = ordinal + 1;
        for (&self.tables) |*entry| {
            if (entry.table_address == table_address) {
                if (needed > entry.current_size) {
                    entry.current_size = needed;
                    if (ordinal > entry.needed_size) entry.needed_size = ordinal;
                    entry.last_ordinal = ordinal;
                    self.resizes += 1;
                    self.last_action = .table_was_resized;
                    return .table_was_resized;
                }
                return .none;
            }
        }
        for (&self.tables) |*entry| {
            if (entry.table_address == 0) {
                entry.* = .{
                    .table_address = table_address,
                    .current_size = needed,
                    .needed_size = ordinal,
                    .last_ordinal = ordinal,
                };
                self.resizes += 1;
                self.last_action = .table_was_resized;
                return .table_was_resized;
            }
        }
        self.last_action = .skip_assertion;
        return .skip_assertion;
    }

    pub fn logSummary(self: *const Manager) void {
        if (self.resizes == 0 and self.skips == 0) return;
        machoCapturePrint(
            "macho-processor: export table manager summary: resizes={d} skips={d} tracked_tables={d}\n",
            .{ self.resizes, self.skips, self.trackedTableCount() },
        );
    }

    fn trackedTableCount(self: *const Manager) usize {
        var count: usize = 0;
        for (&self.tables) |entry| {
            if (entry.table_address != 0) count += 1;
        }
        return count;
    }
};

test "export table manager tracks size growth" {
    var manager = Manager{};
    try std.testing.expectEqual(RecoveryAction.table_was_resized, manager.recordTable(0x1000, 5, 10));
    try std.testing.expectEqual(@as(u64, 1), manager.resizes);
}

test "export table manager reuses existing entries" {
    var manager = Manager{};
    try std.testing.expectEqual(RecoveryAction.none, manager.diagnoseExportOrdinalBounds(3, 10, 0x2000));
    try std.testing.expectEqual(RecoveryAction.table_was_resized, manager.diagnoseExportOrdinalBounds(20, 10, 0x2000));
    try std.testing.expectEqual(@as(u64, 1), manager.resizes);
}
