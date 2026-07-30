const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const Allocation = struct {
    size: u64,
    alignment: u64,
};

pub const ContainingAllocation = struct {
    base: u64,
    size: u64,
    offset: u64,
};

const FreeBlock = struct {
    address: u64,
    size: u64,
};

pub const Summary = struct {
    allocations: u64,
    reallocations: u64,
    frees: u64,
    reused_blocks: u64,
    overlap_rejections: u64,
    invalid_frees: u64,
    live_allocations: usize,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    allocations: std.AutoHashMap(u64, Allocation),
    free_blocks: std.ArrayList(FreeBlock) = .empty,
    allocation_count: u64 = 0,
    reallocation_count: u64 = 0,
    free_count: u64 = 0,
    reused_block_count: u64 = 0,
    overlap_rejection_count: u64 = 0,
    invalid_free_count: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{
            .allocator = allocator,
            .allocations = std.AutoHashMap(u64, Allocation).init(allocator),
        };
    }

    pub fn deinit(self: *Manager) void {
        self.allocations.deinit();
        self.free_blocks.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn allocate(self: *Manager, state: anytype, requested_size: u64, requested_alignment: u64) ?u64 {
        const size = @max(requested_size, 1);
        const alignment = normalizeAlignment(requested_alignment) orelse return null;
        const address = self.reuseBlock(size, alignment) orelse state.guestAlloc(size, alignment) orelse return null;
        // Never let a stale free-list entry or a regressed backing allocator
        // replace metadata for a still-live object. Such replacement used to
        // turn later clears into apparently inexplicable near-null
        // "collisions".
        if (self.findLiveOverlap(address, size) != null) {
            self.overlap_rejection_count +|= 1;
            return null;
        }
        // A recycled allocation address must not inherit pointer provenance
        // from the object that previously occupied it.
        state.forgetMemoryWriteProvenance(address, size);
        const result = self.allocations.getOrPut(address) catch return null;
        if (result.found_existing) {
            self.overlap_rejection_count +|= 1;
            return null;
        }
        result.value_ptr.* = .{ .size = size, .alignment = alignment };
        self.allocation_count +|= 1;
        return address;
    }

    pub fn allocateZeroed(self: *Manager, state: anytype, count: u64, element_size: u64) ?u64 {
        const size = std.math.mul(u64, count, element_size) catch return null;
        // calloc promises storage suitable for any ordinary object; the
        // element size is not an alignment request.  Using element_size here
        // rejects every non-power-of-two-sized struct in allocate(), including
        // Capstone's cs_struct, and makes cs_open report CS_ERR_MEM.
        const address = self.allocate(state, size, 16) orelse return null;
        const storage = state.guestMemory(address, @max(size, 1)) orelse return null;
        @memset(storage, 0);
        return address;
    }

    pub fn reallocate(self: *Manager, state: anytype, address: u64, requested_size: u64) ?u64 {
        self.reallocation_count +|= 1;
        if (address == 0) return self.allocate(state, requested_size, 16);
        if (requested_size == 0) {
            self.release(address);
            return 0;
        }

        const old = self.allocations.get(address) orelse return null;
        if (requested_size <= old.size) {
            if (self.allocations.getPtr(address)) |allocation| allocation.size = requested_size;
            if (old.size > requested_size) {
                self.addFreeBlock(.{ .address = address + requested_size, .size = old.size - requested_size });
            }
            return address;
        }

        const replacement = self.allocate(state, requested_size, old.alignment) orelse return null;
        const source = state.guestMemoryConst(address, old.size) orelse return null;
        const destination = state.guestMemory(replacement, old.size) orelse return null;
        std.mem.copyForwards(u8, destination, source);
        self.release(address);
        return replacement;
    }

    pub fn release(self: *Manager, address: u64) void {
        if (address == 0) return;
        const removed = self.allocations.fetchRemove(address) orelse {
            self.invalid_free_count +|= 1;
            return;
        };
        self.addFreeBlock(.{ .address = address, .size = removed.value.size });
        self.free_count +|= 1;
    }

    pub fn allocationSize(self: *const Manager, address: u64) ?u64 {
        const allocation = self.allocations.get(address) orelse return null;
        return allocation.size;
    }

    /// Finds the live forwarded allocation containing an interior address.
    /// This is diagnostic-only and intentionally linear: it runs only while
    /// explaining a terminal fault, never on the guest execution hot path.
    pub fn containingAllocation(self: *const Manager, address: u64) ?ContainingAllocation {
        var iterator = self.allocations.iterator();
        while (iterator.next()) |entry| {
            const base = entry.key_ptr.*;
            const size = entry.value_ptr.size;
            const end = std.math.add(u64, base, size) catch continue;
            if (address >= base and address < end) {
                return .{
                    .base = base,
                    .size = size,
                    .offset = address - base,
                };
            }
        }
        return null;
    }

    pub fn summary(self: *const Manager) Summary {
        return .{
            .allocations = self.allocation_count,
            .reallocations = self.reallocation_count,
            .frees = self.free_count,
            .reused_blocks = self.reused_block_count,
            .overlap_rejections = self.overlap_rejection_count,
            .invalid_frees = self.invalid_free_count,
            .live_allocations = self.allocations.count(),
        };
    }

    pub fn logSummary(self: *const Manager) void {
        const totals = self.summary();
        machoCapturePrint(
            "macho-processor: memory forwarding: alloc={d} realloc={d} free={d} reused={d} live={d} collision_guard(overlap_rejections/invalid_frees)={d}/{d}\n",
            .{
                totals.allocations,
                totals.reallocations,
                totals.frees,
                totals.reused_blocks,
                totals.live_allocations,
                totals.overlap_rejections,
                totals.invalid_frees,
            },
        );
    }

    fn reuseBlock(self: *Manager, size: u64, alignment: u64) ?u64 {
        var index: usize = 0;
        while (index < self.free_blocks.items.len) {
            const block = self.free_blocks.items[index];
            const aligned = alignForward(block.address, alignment) orelse {
                _ = self.free_blocks.swapRemove(index);
                self.overlap_rejection_count +|= 1;
                continue;
            };
            const prefix_size = aligned - block.address;
            if (prefix_size > block.size or size > block.size - prefix_size) {
                index += 1;
                continue;
            }
            const block_end = std.math.add(u64, block.address, block.size) catch {
                _ = self.free_blocks.swapRemove(index);
                self.overlap_rejection_count +|= 1;
                continue;
            };
            const allocation_end = std.math.add(u64, aligned, size) catch {
                _ = self.free_blocks.swapRemove(index);
                self.overlap_rejection_count +|= 1;
                continue;
            };
            if (self.findLiveOverlap(aligned, size) != null) {
                // Quarantine the whole stale block. Splitting it would retain
                // the same contradictory lifetime information and could
                // produce another collision later.
                _ = self.free_blocks.swapRemove(index);
                self.overlap_rejection_count +|= 1;
                continue;
            }
            _ = self.free_blocks.swapRemove(index);
            if (prefix_size != 0) self.addFreeBlock(.{ .address = block.address, .size = prefix_size });
            if (allocation_end < block_end) {
                self.addFreeBlock(.{ .address = allocation_end, .size = block_end - allocation_end });
            }
            self.reused_block_count +|= 1;
            return aligned;
        }
        return null;
    }

    fn addFreeBlock(self: *Manager, block: FreeBlock) void {
        if (block.size == 0) return;
        var merged = block;
        var index: usize = 0;
        while (index < self.free_blocks.items.len) {
            const existing = self.free_blocks.items[index];
            const merged_end = std.math.add(u64, merged.address, merged.size) catch return;
            const existing_end =
                std.math.add(u64, existing.address, existing.size) catch {
                    _ = self.free_blocks.swapRemove(index);
                    self.overlap_rejection_count +|= 1;
                    continue;
                };
            if (merged_end < existing.address or existing_end < merged.address) {
                index += 1;
                continue;
            }
            const start = @min(merged.address, existing.address);
            const end = @max(merged_end, existing_end);
            merged = .{ .address = start, .size = end - start };
            _ = self.free_blocks.swapRemove(index);
        }
        self.free_blocks.append(self.allocator, merged) catch {};
    }

    fn findLiveOverlap(self: *const Manager, address: u64, size: u64) ?ContainingAllocation {
        const end = std.math.add(u64, address, size) catch return .{
            .base = address,
            .size = size,
            .offset = 0,
        };
        var iterator = self.allocations.iterator();
        while (iterator.next()) |entry| {
            const live_base = entry.key_ptr.*;
            const live_size = entry.value_ptr.size;
            const live_end = std.math.add(u64, live_base, live_size) catch continue;
            if (address < live_end and live_base < end) {
                return .{
                    .base = live_base,
                    .size = live_size,
                    .offset = if (address >= live_base) address - live_base else 0,
                };
            }
        }
        return null;
    }
};

fn normalizeAlignment(alignment: u64) ?u64 {
    const normalized = @max(alignment, 1);
    if (!std.math.isPowerOfTwo(normalized)) return null;
    return normalized;
}

fn alignForward(address: u64, alignment: u64) ?u64 {
    const mask = alignment - 1;
    return (std.math.add(u64, address, mask) catch return null) & ~mask;
}

const TestState = struct {
    memory: [4096]u8 = [_]u8{0} ** 4096,
    heap_next: u64 = 64,

    pub fn guestAlloc(self: *TestState, size: u64, alignment: u64) ?u64 {
        const address = alignForward(self.heap_next, alignment) orelse return null;
        if (address + size > self.memory.len) return null;
        self.heap_next = address + size;
        return address;
    }

    pub fn guestMemory(self: *TestState, address: u64, size: u64) ?[]u8 {
        if (address + size > self.memory.len) return null;
        return self.memory[@intCast(address)..@intCast(address + size)];
    }

    pub fn guestMemoryConst(self: *const TestState, address: u64, size: u64) ?[]const u8 {
        if (address + size > self.memory.len) return null;
        return self.memory[@intCast(address)..@intCast(address + size)];
    }

    pub fn forgetMemoryWriteProvenance(_: *TestState, _: u64, _: u64) void {}
};

test "reallocate preserves guest bytes" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    var state = TestState{};
    const original = manager.allocate(&state, 8, 16).?;
    @memcpy(state.guestMemory(original, 4).?, "test");

    const replacement = manager.reallocate(&state, original, 32).?;
    try std.testing.expectEqualStrings("test", state.guestMemoryConst(replacement, 4).?);
    try std.testing.expectEqual(@as(u64, 32), manager.allocationSize(replacement).?);
}

test "freed guest blocks are reused with alignment" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    var state = TestState{};
    const first = manager.allocate(&state, 64, 16).?;
    manager.release(first);
    const second = manager.allocate(&state, 16, 16).?;

    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(u64, 1), manager.summary().reused_blocks);
}

test "calloc rejects overflow and zeroes storage" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    var state = TestState{};
    try std.testing.expect(manager.allocateZeroed(&state, std.math.maxInt(u64), 2) == null);

    // Struct sizes are commonly not powers of two. They must not be treated
    // as an alignment value (Capstone's allocator callback relies on this).
    const non_power_of_two = manager.allocateZeroed(&state, 1, 136).?;
    try std.testing.expectEqual(@as(u64, 0), non_power_of_two % 16);
    for (state.guestMemoryConst(non_power_of_two, 136).?) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
    const address = manager.allocateZeroed(&state, 4, 8).?;
    for (state.guestMemoryConst(address, 32).?) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "stale free blocks cannot overlap live allocations" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    var state = TestState{};
    const live = manager.allocate(&state, 64, 16).?;

    // Simulate contradictory lifetime metadata produced by an upstream
    // double-retirement bug. The guard must quarantine it, not hand the live
    // range to a second allocation.
    try manager.free_blocks.append(std.testing.allocator, .{
        .address = live,
        .size = 64,
    });
    const next = manager.allocate(&state, 32, 16).?;
    try std.testing.expect(next != live);
    try std.testing.expectEqual(@as(u64, 1), manager.summary().overlap_rejections);
}

test "adjacent free blocks coalesce and invalid frees are counted" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    var state = TestState{};
    const first = manager.allocate(&state, 32, 16).?;
    const second = manager.allocate(&state, 32, 16).?;
    manager.release(first);
    manager.release(second);
    try std.testing.expectEqual(@as(usize, 1), manager.free_blocks.items.len);
    try std.testing.expectEqual(@as(u64, 64), manager.free_blocks.items[0].size);

    manager.release(first);
    try std.testing.expectEqual(@as(u64, 1), manager.summary().invalid_frees);
}
