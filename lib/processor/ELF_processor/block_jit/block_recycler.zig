//! Block memory that only ever holds a block.
//!
//! A chain link names the block it hops to (`core.Link`): the hop reads that
//! block's `hop` line directly instead of a table slot first. That is only
//! safe if a link can never read memory that has become something else, so a
//! block that leaves its table for good is not freed: `freeTranslatedBlock`
//! frees its instruction and byte lists and gives the `Block` itself here,
//! scrubbed (`hop.rip` cleared, the chain disarmed), and the translator takes
//! it back for its next block. A stale link then reads a block for another
//! address, which fails the hop's `rip` comparison; a disarmed or rewritten
//! one, which fails its generation; or one compiled for the same address since,
//! which is the block the hop should enter. Only the translator's teardown,
//! after which no link exists, frees the memory.
//!
//! A block can leave another thread's table (`blockJitDropMappedSource` runs
//! from the thread that unmaps the source), so the free list takes a lock.
//! The lock is uncontended in practice: blocks leave tables rarely.
const std = @import("std");

pub fn Recycler(comptime Block: type) type {
    return struct {
        const Self = @This();

        lock: std.atomic.Value(bool) = .init(false),
        free: std.ArrayListUnmanaged(*Block) = .empty,
        /// Blocks given back, blocks reused, and blocks that could not be
        /// listed and were leaked rather than freed (must read zero).
        recycled: u64 = 0,
        reused: u64 = 0,
        leaked: u64 = 0,

        fn acquire(self: *Self) void {
            while (self.lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
        }

        fn release(self: *Self) void {
            self.lock.store(false, .release);
        }

        /// Memory for the next block, or null to allocate it.
        pub fn take(self: *Self) ?*Block {
            self.acquire();
            defer self.release();
            const block = self.free.pop() orelse return null;
            self.reused +|= 1;
            return block;
        }

        /// `block` left its table for good. No hop enters it from now on,
        /// and its memory waits for the next block.
        pub fn give(self: *Self, allocator: std.mem.Allocator, block: *Block) void {
            block.disarmChain();
            @atomicStore(u64, &block.hop.rip, 0, .release);
            // Its code's header is disarmed: the next life writes its own.
            if (@hasField(Block, "links")) block.links = .{};
            self.acquire();
            defer self.release();
            self.free.append(allocator, block) catch {
                // Freeing it could let a stale link read freed memory; a
                // leaked block cannot.
                self.leaked +|= 1;
                return;
            };
            self.recycled +|= 1;
        }

        /// The translator is gone, and every link with it.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (self.free.items) |block| allocator.destroy(block);
            self.free.deinit(allocator);
        }
    };
}
