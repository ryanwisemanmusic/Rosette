const std = @import("std");
const builtin = @import("builtin");
const runtime_abi = @import("runtime_abi_handshake");

pub const GUEST_ADDR_BITS: u6 = 48;
pub const RADIX_BITS: u8 = 4;
pub const RADIX_FANOUT: u8 = 16;
pub const RADIX_LEVELS: u6 = GUEST_ADDR_BITS / RADIX_BITS;
pub const NODE_CACHE_LINE: usize = 64;

pub const NodeType = enum(u2) {
    node4 = 0,
    node16 = 1,
    node48 = 2,
    leaf = 3,
};

pub const TranslateFlags = packed struct(u16) {
    executable: bool = false,
    writable: bool = false,
    valid: bool = false,
    pending: bool = false,
    padding: u12 = 0,
};

pub const TranslationEntry = extern struct {
    guest_pc: u64 align(NODE_CACHE_LINE),
    host_pc: u64,
    hit_count: u64,
    last_access: u64,
    thread_refs: u32,
    flags: TranslateFlags,
    _pad: [6]u8,

    comptime {
        if (@sizeOf(@This()) != NODE_CACHE_LINE)
            @compileError("TranslationEntry must be 64 bytes");
    }
};

const ChildPtr = u64;

const InternalNode = extern struct {
    type_tag: u64 align(NODE_CACHE_LINE),
    count: u8,
    _pad: [7]u8,
    keys: [16]u8,
    children: [16]ChildPtr,

    fn nodeType(self: *const InternalNode) NodeType {
        return @as(NodeType, @enumFromInt(@as(u2, @truncate(self.type_tag))));
    }

    fn setNodeType(self: *InternalNode, nt: NodeType) void {
        const masked = self.type_tag & ~@as(u64, 3);
        self.type_tag = masked | @as(u64, @intFromEnum(nt));
    }
};

fn extractNibble(addr: u64, level: u6) u8 {
    const shift: u6 = @intCast(RADIX_LEVELS - 1 - level);
    return @as(u8, @intCast((addr >> @intCast(shift * RADIX_BITS)) & 0xF));
}

fn allocateNode(allocator: std.mem.Allocator, nt: NodeType) !*align(64) InternalNode {
    const node = try allocator.create(InternalNode);
    node.* = std.mem.zeroInit(InternalNode, .{});
    node.setNodeType(nt);
    return node;
}

pub const RadixTree = struct {
    root: *InternalNode,
    allocator: std.mem.Allocator,
    entry_count: u64,

    pub fn init(allocator: std.mem.Allocator) !RadixTree {
        return RadixTree{
            .root = try allocateNode(allocator, .node4),
            .allocator = allocator,
            .entry_count = 0,
        };
    }

    pub fn deinit(self: *RadixTree) void {
        self.freeNodeRecursive(self.root, 0);
    }

    fn freeNodeRecursive(self: *RadixTree, node: *InternalNode, level: u6) void {
        if (level >= RADIX_LEVELS) return;
        if (level == RADIX_LEVELS - 1) {
            for (0..node.count) |i| {
                const child = node.children[i];
                if (child != 0) {
                    self.allocator.destroy(@as(*TranslationEntry, @ptrFromInt(child)));
                }
            }
            self.allocator.destroy(node);
            return;
        }
        for (0..node.count) |i| {
            const child = node.children[i];
            if (child != 0) {
                self.freeNodeRecursive(@as(*InternalNode, @ptrFromInt(child)), level + 1);
            }
        }
        self.allocator.destroy(node);
    }

    fn findChild(node: *InternalNode, key: u8) ?ChildPtr {
        const count = @atomicLoad(u8, &node.count, .acquire);
        if (count == 0) return null;
        for (0..count) |i| {
            if (node.keys[i] == key) {
                const child = @atomicLoad(u64, &node.children[i], .acquire);
                // A zero child is an empty slot, which is how `remove` leaves
                // one and what `freeNodeRecursive` has always assumed. Handing
                // it back as a found child made every caller build a pointer
                // from zero: `lookup` and `insert` both dereference it, so a
                // removed key whose nibble is zero crashed the next lookup
                // rather than reporting a miss.
                if (child == 0) return null;
                return child;
            }
        }
        return null;
    }

    fn insertChild(node: *InternalNode, key: u8, child: ChildPtr) void {
        const count = @atomicLoad(u8, &node.count, .monotonic);
        if (count >= 16) return;
        for (0..count) |i| {
            if (node.keys[i] == key) {
                @atomicStore(u64, &node.children[i], child, .release);
                return;
            }
        }
        @atomicStore(u8, &node.keys[count], key, .release);
        @atomicStore(u64, &node.children[count], child, .release);
        // A weak compare-exchange may fail spuriously, and the result was
        // discarded: the slot would be written and then never published,
        // making the child permanently invisible to `findChild`.
        _ = @cmpxchgStrong(u8, &node.count, count, count + 1, .release, .monotonic);
    }

    pub fn lookup(self: *RadixTree, guest_pc: u64) ?*TranslationEntry {
        var node = self.root;
        var level: u6 = 0;
        while (level < RADIX_LEVELS - 1) {
            const nibble = extractNibble(guest_pc, level);
            const child = findChild(node, nibble) orelse return null;
            node = @as(*InternalNode, @ptrFromInt(child));
            level += 1;
        }
        const nibble = extractNibble(guest_pc, level);
        const child = findChild(node, nibble) orelse return null;
        const entry = @as(*TranslationEntry, @ptrFromInt(child));
        if (@atomicLoad(u64, &entry.guest_pc, .acquire) != guest_pc) return null;
        return entry;
    }

    pub fn insert(self: *RadixTree, guest_pc: u64, host_pc: u64) !*TranslationEntry {
        var node = self.root;
        var level: u6 = 0;
        while (level < RADIX_LEVELS - 1) {
            const nibble = extractNibble(guest_pc, level);
            const existing = findChild(node, nibble);
            if (existing) |child| {
                node = @as(*InternalNode, @ptrFromInt(child));
            } else {
                const new_node = try allocateNode(self.allocator, .node4);
                insertChild(node, nibble, @intFromPtr(new_node));
                node = new_node;
            }
            level += 1;
        }
        const leaf_nibble = extractNibble(guest_pc, level);
        const existing = findChild(node, leaf_nibble);
        if (existing) |child| {
            const entry = @as(*TranslationEntry, @ptrFromInt(child));
            @atomicStore(u64, &entry.guest_pc, guest_pc, .release);
            @atomicStore(u64, &entry.host_pc, host_pc, .release);
            @atomicStore(u64, &entry.hit_count, 0, .release);
            @atomicStore(u64, &entry.last_access, 0, .release);
            @atomicStore(u32, &entry.thread_refs, 0, .release);
            return entry;
        }
        const entry = try self.allocator.create(TranslationEntry);
        entry.* = TranslationEntry{
            .guest_pc = guest_pc,
            .host_pc = host_pc,
            .hit_count = 0,
            .last_access = 0,
            .thread_refs = 0,
            .flags = TranslateFlags{ .valid = true, .executable = true },
            ._pad = [_]u8{0} ** 6,
        };
        insertChild(node, leaf_nibble, @intFromPtr(entry));
        _ = @atomicRmw(u64, &self.entry_count, .Add, 1, .monotonic);
        return entry;
    }

    pub fn remove(self: *RadixTree, guest_pc: u64) void {
        var node = self.root;
        var level: u6 = 0;
        while (level < RADIX_LEVELS - 1) {
            const nibble = extractNibble(guest_pc, level);
            const child = findChild(node, nibble) orelse return;
            node = @as(*InternalNode, @ptrFromInt(child));
            level += 1;
        }
        const leaf_nibble = extractNibble(guest_pc, level);
        const count = @atomicLoad(u8, &node.count, .acquire);
        for (0..count) |i| {
            if (node.keys[i] == leaf_nibble) {
                const child = @atomicLoad(u64, &node.children[i], .acquire);
                if (child == 0) return;
                const entry = @as(*TranslationEntry, @ptrFromInt(child));
                // Empty the slot but keep its key, so a later insert of the
                // same nibble reuses it instead of appending a second slot for
                // a key this node already lists.
                @atomicStore(u64, &node.children[i], 0, .release);
                // Allocated with `create`; `deinit` frees it with `destroy`.
                // Re-deriving a slice to hand to `free` describes a different
                // allocation than the one that was made.
                self.allocator.destroy(entry);
                _ = @atomicRmw(u64, &self.entry_count, .Sub, 1, .monotonic);
                return;
            }
        }
    }

    pub fn recordHit(self: *RadixTree, guest_pc: u64) void {
        const entry = self.lookup(guest_pc) orelse return;
        _ = @atomicRmw(u64, &entry.hit_count, .Add, 1, .monotonic);
        _ = @atomicRmw(u64, &entry.last_access, .Xchg, @truncate(timestamp()), .release);
    }

    pub fn threadRefAdd(self: *RadixTree, guest_pc: u64) void {
        const entry = self.lookup(guest_pc) orelse return;
        _ = @atomicRmw(u32, &entry.thread_refs, .Add, 1, .release);
    }

    pub fn threadRefSub(self: *RadixTree, guest_pc: u64) void {
        const entry = self.lookup(guest_pc) orelse return;
        _ = @atomicRmw(u32, &entry.thread_refs, .Sub, 1, .release);
    }

    pub fn threadRefCount(self: *RadixTree, guest_pc: u64) u32 {
        const entry = self.lookup(guest_pc) orelse return 0;
        return @atomicLoad(u32, &entry.thread_refs, .acquire);
    }
};

const SpinLock = struct {
    state: u8,

    fn init() SpinLock {
        return .{ .state = 0 };
    }

    fn lock(self: *SpinLock) void {
        while (@atomicRmw(u8, &self.state, .Xchg, 1, .acquire) != 0) {
            while (@atomicLoad(u8, &self.state, .monotonic) != 0) {}
        }
    }

    fn unlock(self: *SpinLock) void {
        @atomicStore(u8, &self.state, 0, .release);
    }
};

const SEGMENT_CACHE_SIZE: usize = 32;

pub const SegmentRefCounters = struct {
    bases: [SEGMENT_CACHE_SIZE]u64,
    counts: [SEGMENT_CACHE_SIZE]u32,
    lock: SpinLock,

    pub fn init() SegmentRefCounters {
        return SegmentRefCounters{
            .bases = [_]u64{0} ** SEGMENT_CACHE_SIZE,
            .counts = [_]u32{0} ** SEGMENT_CACHE_SIZE,
            .lock = SpinLock.init(),
        };
    }

    pub fn addRef(self: *SegmentRefCounters, segment_base: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        for (&self.bases, &self.counts) |*base, *count| {
            if (base.* == segment_base) {
                count.* += 1;
                return;
            }
            if (base.* == 0) {
                base.* = segment_base;
                count.* = 1;
                return;
            }
        }
    }

    pub fn subRef(self: *SegmentRefCounters, segment_base: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        for (&self.bases, &self.counts) |*base, *count| {
            if (base.* == segment_base) {
                if (count.* > 1) {
                    count.* -= 1;
                } else {
                    base.* = 0;
                    count.* = 0;
                }
                return;
            }
        }
    }

    pub fn getRef(self: *SegmentRefCounters, segment_base: u64) u32 {
        self.lock.lock();
        defer self.lock.unlock();
        for (&self.bases, &self.counts) |*base, *count| {
            if (base.* == segment_base) return count.*;
        }
        return 0;
    }
};

pub const VmRegion = extern struct {
    base: u64,
    size: u64,
    prot: u8,
    is_jit: bool,
    _pad: [6]u8,

    pub fn init(base: u64, size: u64, prot: u8, is_jit: bool) VmRegion {
        return VmRegion{
            .base = base,
            .size = size,
            .prot = prot,
            .is_jit = is_jit,
            ._pad = [_]u8{0} ** 6,
        };
    }

    comptime {
        if (@sizeOf(@This()) != 24)
            @compileError("VmRegion must be 24 bytes");
    }
};

const VM_REGION_MAX: usize = 64;

pub const VmMapTracker = struct {
    regions: [VM_REGION_MAX]VmRegion,
    count: u32,
    lock: SpinLock,

    pub fn init() VmMapTracker {
        const zero_region = VmRegion.init(0, 0, 0, false);
        return VmMapTracker{
            .regions = [_]VmRegion{zero_region} ** VM_REGION_MAX,
            .count = 0,
            .lock = SpinLock.init(),
        };
    }

    pub fn trackRegion(self: *VmMapTracker, region: VmRegion) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.count >= VM_REGION_MAX) return;
        self.regions[self.count] = region;
        self.count += 1;
    }

    pub fn removeRegion(self: *VmMapTracker, base: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        for (&self.regions, 0..self.count) |*reg, i| {
            if (reg.base == base) {
                self.regions[i] = self.regions[self.count - 1];
                self.count -= 1;
                return;
            }
        }
    }

    pub fn findRegion(self: *VmMapTracker, addr: u64) ?VmRegion {
        self.lock.lock();
        defer self.lock.unlock();
        for (self.regions[0..self.count]) |reg| {
            if (addr >= reg.base and addr < reg.base + reg.size) return reg;
        }
        return null;
    }
};

pub const DyldCacheTree = struct {
    translations: RadixTree,
    segment_refs: SegmentRefCounters,
    vm_tracker: VmMapTracker,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !DyldCacheTree {
        return DyldCacheTree{
            .translations = try RadixTree.init(allocator),
            .segment_refs = SegmentRefCounters.init(),
            .vm_tracker = VmMapTracker.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DyldCacheTree) void {
        self.translations.deinit();
    }

    pub fn mapTranslation(self: *DyldCacheTree, guest_pc: u64, host_pc: u64) !*TranslationEntry {
        return self.translations.insert(guest_pc, host_pc);
    }

    pub fn resolveTranslation(self: *DyldCacheTree, guest_pc: u64) ?*TranslationEntry {
        return self.translations.lookup(guest_pc);
    }

    pub fn evictTranslation(self: *DyldCacheTree, guest_pc: u64) void {
        self.translations.remove(guest_pc);
    }

    pub fn touchTranslation(self: *DyldCacheTree, guest_pc: u64) void {
        self.translations.recordHit(guest_pc);
    }
};

fn timestamp() u64 {
    if (builtin.target.os.tag == .macos) {
        return std.c.mach_absolute_time();
    }
    var ts: std.os.timespec = undefined;
    std.os.clock_gettime(std.os.CLOCK_MONOTONIC, &ts) catch {};
    return @as(u64, @intCast(ts.tv_sec * 1_000_000_000 + ts.tv_nsec));
}

export fn rosette_dyld_cache_tree_create() ?*DyldCacheTree {
    const allocator = std.heap.page_allocator;
    const tree = allocator.create(DyldCacheTree) catch return null;
    tree.* = DyldCacheTree.init(allocator) catch {
        allocator.destroy(tree);
        return null;
    };
    return tree;
}

export fn rosette_dyld_cache_tree_destroy(tree: *DyldCacheTree) void {
    tree.deinit();
    tree.allocator.destroy(tree);
}

export fn rosette_dyld_cache_map(tree: *DyldCacheTree, guest_pc: u64, host_pc: u64) ?*TranslationEntry {
    return tree.mapTranslation(guest_pc, host_pc) catch null;
}

export fn rosette_dyld_cache_resolve(tree: *DyldCacheTree, guest_pc: u64) ?*TranslationEntry {
    return tree.resolveTranslation(guest_pc);
}

export fn rosette_dyld_cache_evict(tree: *DyldCacheTree, guest_pc: u64) void {
    tree.evictTranslation(guest_pc);
}

export fn rosette_dyld_cache_touch(tree: *DyldCacheTree, guest_pc: u64) void {
    tree.touchTranslation(guest_pc);
}

test "extractNibble extracts correct 4-bit fragments" {
    const addr: u64 = 0x123456789ABC;
    try std.testing.expectEqual(@as(u8, 0x1), extractNibble(addr, 0));
    try std.testing.expectEqual(@as(u8, 0x2), extractNibble(addr, 1));
    try std.testing.expectEqual(@as(u8, 0x3), extractNibble(addr, 2));
    try std.testing.expectEqual(@as(u8, 0x4), extractNibble(addr, 3));
    try std.testing.expectEqual(@as(u8, 0x5), extractNibble(addr, 4));
    try std.testing.expectEqual(@as(u8, 0x6), extractNibble(addr, 5));
    try std.testing.expectEqual(@as(u8, 0x7), extractNibble(addr, 6));
    try std.testing.expectEqual(@as(u8, 0x8), extractNibble(addr, 7));
    try std.testing.expectEqual(@as(u8, 0x9), extractNibble(addr, 8));
    try std.testing.expectEqual(@as(u8, 0xA), extractNibble(addr, 9));
    try std.testing.expectEqual(@as(u8, 0xB), extractNibble(addr, 10));
    try std.testing.expectEqual(@as(u8, 0xC), extractNibble(addr, 11));
}

test "RadixTree basic insert and lookup" {
    const allocator = std.testing.allocator;
    var tree = try RadixTree.init(allocator);
    defer tree.deinit();

    const entry = try tree.insert(0x1000, 0x8000);
    try std.testing.expectEqual(@as(u64, 0x1000), entry.guest_pc);
    try std.testing.expectEqual(@as(u64, 0x8000), entry.host_pc);

    const found = tree.lookup(0x1000);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(u64, 0x1000), found.?.guest_pc);
    try std.testing.expectEqual(@as(u64, 0x8000), found.?.host_pc);

    try std.testing.expect(tree.lookup(0x2000) == null);
}

test "RadixTree multiple entries across levels" {
    const allocator = std.testing.allocator;
    var tree = try RadixTree.init(allocator);
    defer tree.deinit();

    const addrs = [_]u64{ 0x1000, 0x2000, 0x10000, 0x100000, 0x7FFF0000, 0xABCD1234, 0xDEADBEEF };
    const targets = [_]u64{ 0x8000, 0x9000, 0xA000, 0xB000, 0xC000, 0xD000, 0xE000 };

    for (addrs, targets) |guest, host| {
        _ = try tree.insert(guest, host);
    }

    for (addrs, targets) |guest, host| {
        const entry = tree.lookup(guest) orelse return error.TestFailed;
        try std.testing.expectEqual(host, entry.host_pc);
    }

    try std.testing.expectEqual(@as(u64, addrs.len), tree.entry_count);
}

test "RadixTree insert over existing guest_pc updates entry" {
    const allocator = std.testing.allocator;
    var tree = try RadixTree.init(allocator);
    defer tree.deinit();

    _ = try tree.insert(0x1000, 0x8000);
    _ = try tree.insert(0x1000, 0x9000);

    const entry = tree.lookup(0x1000) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 0x9000), entry.host_pc);
    try std.testing.expectEqual(@as(u64, 1), tree.entry_count);
}

test "RadixTree remove and reinsert" {
    const allocator = std.testing.allocator;
    var tree = try RadixTree.init(allocator);
    defer tree.deinit();

    _ = try tree.insert(0x1000, 0x8000);
    try std.testing.expectEqual(@as(u64, 1), tree.entry_count);

    tree.remove(0x1000);
    try std.testing.expectEqual(@as(u64, 0), tree.entry_count);
    try std.testing.expect(tree.lookup(0x1000) == null);

    _ = try tree.insert(0x1000, 0xA000);
    try std.testing.expectEqual(@as(u64, 1), tree.entry_count);
    const entry = tree.lookup(0x1000) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 0xA000), entry.host_pc);
}

test "RadixTree hit counter increments via recordHit" {
    const allocator = std.testing.allocator;
    var tree = try RadixTree.init(allocator);
    defer tree.deinit();

    _ = try tree.insert(0x1000, 0x8000);
    try std.testing.expectEqual(@as(u64, 0), tree.lookup(0x1000).?.hit_count);

    tree.recordHit(0x1000);
    try std.testing.expectEqual(@as(u64, 1), tree.lookup(0x1000).?.hit_count);

    tree.recordHit(0x1000);
    tree.recordHit(0x1000);
    try std.testing.expectEqual(@as(u64, 3), tree.lookup(0x1000).?.hit_count);
}

test "RadixTree thread ref counters through API" {
    const allocator = std.testing.allocator;
    var tree = try RadixTree.init(allocator);
    defer tree.deinit();

    _ = try tree.insert(0x1000, 0x8000);

    tree.threadRefAdd(0x1000);
    try std.testing.expectEqual(@as(u32, 1), tree.threadRefCount(0x1000));

    tree.threadRefAdd(0x1000);
    tree.threadRefAdd(0x1000);
    try std.testing.expectEqual(@as(u32, 3), tree.threadRefCount(0x1000));

    tree.threadRefSub(0x1000);
    try std.testing.expectEqual(@as(u32, 2), tree.threadRefCount(0x1000));
}

test "TranslationEntry is 64 bytes" {
    try std.testing.expectEqual(@as(usize, NODE_CACHE_LINE), @sizeOf(TranslationEntry));
}

test "DyldCacheTree full round trip" {
    const allocator = std.testing.allocator;
    var tree = try DyldCacheTree.init(allocator);
    defer tree.deinit();

    const entry = try tree.mapTranslation(0x1234, 0x5678);
    try std.testing.expectEqual(@as(u64, 0x1234), entry.guest_pc);
    try std.testing.expectEqual(@as(u64, 0x5678), entry.host_pc);

    const resolved = tree.resolveTranslation(0x1234) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 0x5678), resolved.host_pc);
    try std.testing.expect(tree.resolveTranslation(0xFFFF) == null);

    tree.touchTranslation(0x1234);
    try std.testing.expectEqual(@as(u64, 1), resolved.hit_count);

    tree.evictTranslation(0x1234);
    try std.testing.expect(tree.resolveTranslation(0x1234) == null);
}
