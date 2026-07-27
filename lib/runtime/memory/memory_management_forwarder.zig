const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const Allocation = struct {
    size: u64,
    alignment: u64,
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
        // A recycled allocation address must not inherit pointer provenance
        // from the object that previously occupied it.
        state.forgetMemoryWriteProvenance(address);
        self.allocations.put(address, .{ .size = size, .alignment = alignment }) catch return null;
        self.allocation_count +|= 1;
        return address;
    }

    pub fn allocateZeroed(self: *Manager, state: anytype, count: u64, element_size: u64) ?u64 {
        const size = std.math.mul(u64, count, element_size) catch return null;
        const alignment = @max(element_size, 16);
        const address = self.allocate(state, size, alignment) orelse return null;
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
        const removed = self.allocations.fetchRemove(address) orelse return;
        self.addFreeBlock(.{ .address = address, .size = removed.value.size });
        self.free_count +|= 1;
    }

    pub fn allocationSize(self: *const Manager, address: u64) ?u64 {
        const allocation = self.allocations.get(address) orelse return null;
        return allocation.size;
    }

    pub fn summary(self: *const Manager) Summary {
        return .{
            .allocations = self.allocation_count,
            .reallocations = self.reallocation_count,
            .frees = self.free_count,
            .reused_blocks = self.reused_block_count,
            .live_allocations = self.allocations.count(),
        };
    }

    pub fn logSummary(self: *const Manager) void {
        const totals = self.summary();
        machoCapturePrint(
            "macho-processor: memory forwarding: alloc={d} realloc={d} free={d} reused={d} live={d}\n",
            .{ totals.allocations, totals.reallocations, totals.frees, totals.reused_blocks, totals.live_allocations },
        );
    }

    fn reuseBlock(self: *Manager, size: u64, alignment: u64) ?u64 {
        for (self.free_blocks.items, 0..) |block, index| {
            const aligned = alignForward(block.address, alignment) orelse continue;
            const prefix_size = aligned - block.address;
            if (prefix_size > block.size or size > block.size - prefix_size) continue;
            const block_end = block.address + block.size;
            const allocation_end = aligned + size;
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
        self.free_blocks.append(self.allocator, block) catch {};
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

    pub fn forgetMemoryWriteProvenance(_: *TestState, _: u64) void {}
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
    const address = manager.allocateZeroed(&state, 4, 8).?;
    for (state.guestMemoryConst(address, 32).?) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}
