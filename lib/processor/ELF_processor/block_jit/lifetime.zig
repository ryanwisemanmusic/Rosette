//! When a translated block may be freed, and when the code memory may be
//! reset.
//!
//! A translated block is in use until its `entry()` returns: the host is
//! executing its code, `r_helpers` points at the helper table inside its
//! `Block`, and the interpret helper indexes its instruction list. A helper
//! can run guest code of its own before it returns. A wait import reached
//! through `call [iat]` inside a block services the other guest threads, and
//! since 2026-09-25 their slices run translated blocks too. Whatever such a
//! nested slice drops, evicts or resets must outlive the outer block: its
//! helper returns into its code, reloads its helper table and reads its
//! instructions.
//!
//! `Lifetime` counts the executions live on the host stack. A block that
//! leaves the table while any is live is retired instead of freed, and a
//! reset asked for while any is live is deferred. Both happen when the
//! outermost execution returns, the first point where nothing translated
//! is running.
//!
//! A retired block also cannot be entered by mistake. Chain links check
//! that the slot they name still holds the block they recorded, and a
//! retired block stays allocated, so no newer block can take its address
//! and pass that check in its place.

const std = @import("std");

pub const Stats = struct {
    /// Executions entered while another was already live.
    nested_executions: u64 = 0,
    /// The deepest nesting seen.
    nesting_peak: u32 = 0,
    /// Blocks kept past their drop because an execution was live.
    deferred_frees: u64 = 0,
    retired_peak: usize = 0,
    /// Resets asked for under a live execution (a repeat while one is
    /// already pending is not counted again).
    deferred_resets: u64 = 0,
    /// Blocks that could not be listed for later and were leaked rather
    /// than freed under a live execution. Must read zero.
    retire_leaks: u64 = 0,
};

/// `free` releases a block the table no longer holds.
pub fn Lifetime(comptime Block: type, comptime free: fn (std.mem.Allocator, *Block) void) type {
    return struct {
        const Self = @This();

        /// Translated executions on the host stack right now.
        active_executions: u32 = 0,
        /// Blocks that left the table while an execution was live.
        retired: std.ArrayListUnmanaged(*Block) = .empty,
        /// The code memory filled while an execution was live. Nothing may
        /// be compiled into it until the reset has run.
        reset_pending: bool = false,
        stats: Stats = .{},

        pub fn live(self: *const Self) bool {
            return self.active_executions != 0;
        }

        pub fn enter(self: *Self) void {
            if (self.active_executions != 0) self.stats.nested_executions +|= 1;
            self.active_executions += 1;
            self.stats.nesting_peak = @max(self.stats.nesting_peak, self.active_executions);
        }

        /// Leave an execution. The outermost one frees what nesting
        /// retired; true means a reset is pending and the caller runs it
        /// now.
        pub fn leave(self: *Self, allocator: std.mem.Allocator) bool {
            std.debug.assert(self.active_executions != 0);
            self.active_executions -= 1;
            if (self.active_executions != 0) return false;
            self.freeRetired(allocator);
            return self.reset_pending;
        }

        /// A block left the table: free it, or keep it until the outermost
        /// live execution returns.
        pub fn retire(self: *Self, allocator: std.mem.Allocator, block: *Block) void {
            if (self.active_executions == 0) {
                free(allocator, block);
                return;
            }
            self.retired.append(allocator, block) catch {
                // Freeing it here could free code on the host stack; a
                // leaked block is the failure that cannot corrupt anything.
                self.stats.retire_leaks +|= 1;
                return;
            };
            self.stats.deferred_frees +|= 1;
            self.stats.retired_peak = @max(self.stats.retired_peak, self.retired.items.len);
        }

        /// True when the code memory may be reset now. Otherwise the reset
        /// is pending until the outermost execution returns.
        pub fn requestReset(self: *Self) bool {
            if (self.active_executions != 0) {
                if (!self.reset_pending) self.stats.deferred_resets +|= 1;
                self.reset_pending = true;
                return false;
            }
            self.reset_pending = false;
            return true;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.freeRetired(allocator);
            self.retired.deinit(allocator);
        }

        fn freeRetired(self: *Self, allocator: std.mem.Allocator) void {
            for (self.retired.items) |block| free(allocator, block);
            self.retired.clearRetainingCapacity();
        }
    };
}

const TestBlock = struct {
    id: u32,

    var freed: u32 = 0;

    fn create(id: u32) !*TestBlock {
        const block = try std.testing.allocator.create(TestBlock);
        block.* = .{ .id = id };
        return block;
    }

    fn destroy(allocator: std.mem.Allocator, block: *TestBlock) void {
        freed += 1;
        allocator.destroy(block);
    }
};

const TestLifetime = Lifetime(TestBlock, TestBlock.destroy);

test "a block that leaves the table outside any execution is freed at once" {
    TestBlock.freed = 0;
    var lifetime: TestLifetime = .{};
    defer lifetime.deinit(std.testing.allocator);
    lifetime.retire(std.testing.allocator, try TestBlock.create(1));
    try std.testing.expectEqual(@as(u32, 1), TestBlock.freed);
    try std.testing.expectEqual(@as(usize, 0), lifetime.retired.items.len);
    try std.testing.expect(lifetime.requestReset());
}

test "blocks dropped under a live execution are freed when the outermost returns" {
    TestBlock.freed = 0;
    var lifetime: TestLifetime = .{};
    defer lifetime.deinit(std.testing.allocator);
    lifetime.enter();
    lifetime.enter(); // a nested slice's block
    const outer = try TestBlock.create(1);
    lifetime.retire(std.testing.allocator, outer);
    lifetime.retire(std.testing.allocator, try TestBlock.create(2));
    try std.testing.expectEqual(@as(u32, 0), TestBlock.freed);
    // Still readable: the outer block's helper returns into it.
    try std.testing.expectEqual(@as(u32, 1), outer.id);
    try std.testing.expect(!lifetime.leave(std.testing.allocator));
    try std.testing.expectEqual(@as(u32, 0), TestBlock.freed);
    try std.testing.expect(!lifetime.leave(std.testing.allocator));
    // The testing allocator fails the test if either was left allocated.
    try std.testing.expectEqual(@as(u32, 2), TestBlock.freed);
    try std.testing.expectEqual(@as(usize, 0), lifetime.retired.items.len);
    try std.testing.expectEqual(@as(u64, 1), lifetime.stats.nested_executions);
    try std.testing.expectEqual(@as(u32, 2), lifetime.stats.nesting_peak);
    try std.testing.expectEqual(@as(u64, 2), lifetime.stats.deferred_frees);
    try std.testing.expectEqual(@as(usize, 2), lifetime.stats.retired_peak);
    try std.testing.expectEqual(@as(u64, 0), lifetime.stats.retire_leaks);
}

test "a reset asked for under a live execution waits for the outermost" {
    var lifetime: TestLifetime = .{};
    defer lifetime.deinit(std.testing.allocator);
    lifetime.enter();
    try std.testing.expect(!lifetime.requestReset());
    try std.testing.expect(lifetime.reset_pending);
    lifetime.enter();
    try std.testing.expect(!lifetime.requestReset());
    try std.testing.expectEqual(@as(u64, 1), lifetime.stats.deferred_resets);
    try std.testing.expect(!lifetime.leave(std.testing.allocator));
    // The outermost return hands the reset to the caller, which runs it.
    try std.testing.expect(lifetime.leave(std.testing.allocator));
    try std.testing.expect(lifetime.requestReset());
    try std.testing.expect(!lifetime.reset_pending);
}

test "blocks still retired when the table is destroyed are freed" {
    TestBlock.freed = 0;
    var lifetime: TestLifetime = .{};
    lifetime.enter();
    lifetime.retire(std.testing.allocator, try TestBlock.create(1));
    lifetime.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), TestBlock.freed);
}
