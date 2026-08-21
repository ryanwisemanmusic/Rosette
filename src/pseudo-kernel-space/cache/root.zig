const std = @import("std");
const dyld = @import("dyld_cache_tree");

pub const system_defines = @import("system-defines/root.zig");
pub const IBTC = @import("IBTC/root.zig");

pub const MACHO_BLOCK_PINNED: u64 = 1 << 0;
pub const MACHO_BLOCK_JIT: u64 = 1 << 1;
pub const MACHO_BLOCK_DYLD_SHARED_CACHE: u64 = 1 << 2;

pub const MachOBlock = extern struct {
    block_id: u64,
    guest_base: u64,
    guest_size: u64,
    host_base: u64,
    host_size: u64,
    flags: u64,
    hit_count: u64,
    last_access: u64,
    ibtc_entries: u64,

    pub fn isPinned(self: *const MachOBlock) bool {
        return (self.flags & MACHO_BLOCK_PINNED) != 0;
    }
};

pub const EvictionStats = extern struct {
    macho_blocks_evicted: u64,
    ibtc_entries_evicted: u64,
    dyld_translations_evicted: u64,
    budget_pressure_events: u64,
};

pub const InitOptions = struct {
    profile: ?system_defines.HardwareProfile = null,
    budget_options: system_defines.BudgetOptions = .{},
    dyld_tree: ?*dyld.DyldCacheTree = null,
};

pub const TranslationCache = struct {
    allocator: std.mem.Allocator,
    profile: system_defines.HardwareProfile,
    budget: system_defines.CacheBudget,
    dyld_tree: ?*dyld.DyldCacheTree,
    ibtc: IBTC.IBTCCache,
    blocks: std.AutoHashMap(u64, MachOBlock),
    live_macho_bytes: u64,
    next_block_id: u64,
    clock: u64,
    stats: EvictionStats,

    pub fn init(allocator: std.mem.Allocator, options: InitOptions) !TranslationCache {
        const profile = options.profile orelse system_defines.detectHostProfile();
        const budget = system_defines.deriveBudget(profile, options.budget_options);
        return .{
            .allocator = allocator,
            .profile = profile,
            .budget = budget,
            .dyld_tree = options.dyld_tree,
            .ibtc = try IBTC.IBTCCache.init(allocator, budget.ibtc_bytes),
            .blocks = std.AutoHashMap(u64, MachOBlock).init(allocator),
            .live_macho_bytes = 0,
            .next_block_id = 1,
            .clock = 1,
            .stats = .{
                .macho_blocks_evicted = 0,
                .ibtc_entries_evicted = 0,
                .dyld_translations_evicted = 0,
                .budget_pressure_events = 0,
            },
        };
    }

    pub fn deinit(self: *TranslationCache) void {
        self.blocks.deinit();
        self.ibtc.deinit();
        self.* = undefined;
    }

    pub fn registerMachOBlock(self: *TranslationCache, guest_base: u64, guest_size: u64, host_base: u64, host_size: u64, flags: u64) !u64 {
        const block_id = self.next_block_id;
        self.next_block_id +%= 1;
        if (self.next_block_id == 0) self.next_block_id = 1;

        const resident_size = if (host_size != 0) host_size else guest_size;
        const block = MachOBlock{
            .block_id = block_id,
            .guest_base = guest_base,
            .guest_size = guest_size,
            .host_base = host_base,
            .host_size = resident_size,
            .flags = flags,
            .hit_count = 0,
            .last_access = self.nextTick(),
            .ibtc_entries = 0,
        };

        try self.blocks.put(block_id, block);
        self.live_macho_bytes += resident_size;
        self.enforceMachOBudget(block_id);
        return block_id;
    }

    pub fn touchMachOBlock(self: *TranslationCache, block_id: u64) void {
        const block = self.blocks.getPtr(block_id) orelse return;
        block.hit_count += 1;
        block.last_access = self.nextTick();
    }

    pub fn bindIndirectBranch(self: *TranslationCache, branch_guest_pc: u64, target_guest_pc: u64, address_space_id: u64, host_pc: u64, macho_block_id: u64, flags: u8) !*IBTC.IBTCEntry {
        if (!self.blocks.contains(macho_block_id)) return error.UnknownMachOBlock;

        const key = IBTC.IBTCKey.init(branch_guest_pc, target_guest_pc, address_space_id);
        const result = try self.ibtc.put(key, host_pc, macho_block_id, flags | IBTC.FLAG_EXECUTABLE, self.nextTick());
        if (result.evicted) |old_entry| {
            self.noteIBTCEviction(old_entry);
        }
        if (result.inserted) {
            self.incrementBlockIBTC(macho_block_id);
        } else if (result.previous_block_id) |previous_block_id| {
            if (previous_block_id != macho_block_id) {
                self.decrementBlockIBTC(previous_block_id);
                self.incrementBlockIBTC(macho_block_id);
            }
        }
        return result.entry;
    }

    pub fn resolveIndirectBranch(self: *TranslationCache, branch_guest_pc: u64, target_guest_pc: u64, address_space_id: u64) ?u64 {
        const key = IBTC.IBTCKey.init(branch_guest_pc, target_guest_pc, address_space_id);
        const entry = self.ibtc.lookup(key) orelse return null;
        const now = self.nextTick();
        entry.recordHit(now);
        self.touchMachOBlock(entry.macho_block_id);
        return entry.host_pc;
    }

    pub fn evictIndirectBranch(self: *TranslationCache, branch_guest_pc: u64, target_guest_pc: u64, address_space_id: u64, co_evict_macho_block: bool) bool {
        const key = IBTC.IBTCKey.init(branch_guest_pc, target_guest_pc, address_space_id);
        const old_entry = self.ibtc.evictKey(key) orelse return false;
        const block_id = old_entry.macho_block_id;
        self.noteIBTCEviction(old_entry);
        if (co_evict_macho_block) {
            _ = self.evictMachOBlock(block_id);
        }
        return true;
    }

    pub fn evictMachOBlock(self: *TranslationCache, block_id: u64) usize {
        const block = self.blocks.get(block_id) orelse return 0;
        const removed_ibtc = self.ibtc.evictBlockWithContext(block_id, self.dyld_tree, evictDyldPair);
        self.stats.ibtc_entries_evicted += removed_ibtc;
        self.stats.dyld_translations_evicted += @as(u64, @intCast(removed_ibtc)) * 2;

        if (self.dyld_tree) |tree| {
            tree.evictTranslation(block.guest_base);
            self.stats.dyld_translations_evicted += 1;
        }

        _ = self.blocks.remove(block_id);
        self.live_macho_bytes -|= block.host_size;
        self.stats.macho_blocks_evicted += 1;
        return removed_ibtc;
    }

    pub fn blockCount(self: *const TranslationCache) usize {
        return self.blocks.count();
    }

    fn enforceMachOBudget(self: *TranslationCache, protected_block_id: u64) void {
        while (self.live_macho_bytes > self.budget.macho_block_bytes) {
            const victim = self.chooseVictimBlock(protected_block_id) orelse return;
            self.stats.budget_pressure_events += 1;
            _ = self.evictMachOBlock(victim);
        }
    }

    fn chooseVictimBlock(self: *TranslationCache, protected_block_id: u64) ?u64 {
        var iterator = self.blocks.iterator();
        var victim_id: ?u64 = null;
        var victim_score: u128 = std.math.maxInt(u128);

        while (iterator.next()) |entry| {
            const block = entry.value_ptr;
            if (block.block_id == protected_block_id or block.isPinned()) continue;
            const age = if (self.clock > block.last_access) self.clock - block.last_access else 0;
            const score = (@as(u128, block.hit_count + block.ibtc_entries * 4) << 64) |
                @as(u128, std.math.maxInt(u64) - age);
            if (score < victim_score) {
                victim_score = score;
                victim_id = block.block_id;
            }
        }

        return victim_id;
    }

    fn noteIBTCEviction(self: *TranslationCache, entry: IBTC.IBTCEntry) void {
        self.decrementBlockIBTC(entry.macho_block_id);
        if (self.dyld_tree) |tree| {
            tree.evictTranslation(entry.branch_guest_pc);
            tree.evictTranslation(entry.target_guest_pc);
            self.stats.dyld_translations_evicted += 2;
        }
        self.stats.ibtc_entries_evicted += 1;
    }

    fn incrementBlockIBTC(self: *TranslationCache, block_id: u64) void {
        const block = self.blocks.getPtr(block_id) orelse return;
        block.ibtc_entries += 1;
    }

    fn decrementBlockIBTC(self: *TranslationCache, block_id: u64) void {
        const block = self.blocks.getPtr(block_id) orelse return;
        block.ibtc_entries -|= 1;
    }

    fn nextTick(self: *TranslationCache) u64 {
        const current = self.clock;
        self.clock +%= 1;
        if (self.clock == 0) self.clock = 1;
        return current;
    }
};

fn evictDyldPair(tree: ?*dyld.DyldCacheTree, entry: *const IBTC.IBTCEntry) void {
    if (tree) |dyld_tree| {
        dyld_tree.evictTranslation(entry.branch_guest_pc);
        dyld_tree.evictTranslation(entry.target_guest_pc);
    }
}

export fn rosette_cache_detect_hardware_profile() system_defines.HardwareProfile {
    return system_defines.detectHostProfile();
}

export fn rosette_cache_derive_budget(profile: *const system_defines.HardwareProfile) system_defines.CacheBudget {
    return system_defines.deriveDefaultBudget(profile.*);
}

export fn rosette_cache_create(dyld_tree: ?*dyld.DyldCacheTree) ?*TranslationCache {
    const allocator = std.heap.page_allocator;
    const cache = allocator.create(TranslationCache) catch return null;
    cache.* = TranslationCache.init(allocator, .{ .dyld_tree = dyld_tree }) catch {
        allocator.destroy(cache);
        return null;
    };
    return cache;
}

export fn rosette_cache_destroy(cache: *TranslationCache) void {
    cache.deinit();
    std.heap.page_allocator.destroy(cache);
}

export fn rosette_cache_register_macho_block(cache: *TranslationCache, guest_base: u64, guest_size: u64, host_base: u64, host_size: u64, flags: u64) u64 {
    return cache.registerMachOBlock(guest_base, guest_size, host_base, host_size, flags) catch 0;
}

export fn rosette_cache_bind_ibtc(cache: *TranslationCache, branch_guest_pc: u64, target_guest_pc: u64, address_space_id: u64, host_pc: u64, macho_block_id: u64, flags: u8) ?*IBTC.IBTCEntry {
    return cache.bindIndirectBranch(branch_guest_pc, target_guest_pc, address_space_id, host_pc, macho_block_id, flags) catch null;
}

export fn rosette_cache_resolve_ibtc(cache: *TranslationCache, branch_guest_pc: u64, target_guest_pc: u64, address_space_id: u64) u64 {
    return cache.resolveIndirectBranch(branch_guest_pc, target_guest_pc, address_space_id) orelse 0;
}

export fn rosette_cache_evict_macho_block(cache: *TranslationCache, block_id: u64) u64 {
    return @intCast(cache.evictMachOBlock(block_id));
}

export fn rosette_cache_evict_ibtc(cache: *TranslationCache, branch_guest_pc: u64, target_guest_pc: u64, address_space_id: u64, co_evict_macho_block: bool) bool {
    return cache.evictIndirectBranch(branch_guest_pc, target_guest_pc, address_space_id, co_evict_macho_block);
}

fn tinyProfile() system_defines.HardwareProfile {
    var profile = system_defines.HardwareProfile.initFallback();
    profile.l3_slc_bytes = 1 * system_defines.MiB;
    profile.ram_bytes = 2 * system_defines.GiB;
    return profile;
}

test "cache registers blocks and resolves IBTC entries" {
    var cache = try TranslationCache.init(std.testing.allocator, .{
        .profile = tinyProfile(),
        .budget_options = .{ .min_software_l3_bytes = 4 * system_defines.MiB },
    });
    defer cache.deinit();

    const block_id = try cache.registerMachOBlock(0x1000, 0x4000, 0x8000, 0x4000, MACHO_BLOCK_DYLD_SHARED_CACHE);
    _ = try cache.bindIndirectBranch(0x1100, 0x2100, 0, 0x9000, block_id, 0);

    try std.testing.expectEqual(@as(u64, 0x9000), cache.resolveIndirectBranch(0x1100, 0x2100, 0).?);
    try std.testing.expectEqual(@as(usize, 1), cache.blockCount());
    try std.testing.expectEqual(@as(usize, 1), cache.ibtc.live_count);
}

test "Mach-O eviction cascades through IBTC entries" {
    var cache = try TranslationCache.init(std.testing.allocator, .{
        .profile = tinyProfile(),
        .budget_options = .{ .min_software_l3_bytes = 4 * system_defines.MiB },
    });
    defer cache.deinit();

    const first = try cache.registerMachOBlock(0x1000, 0x1000, 0x8000, 0x1000, 0);
    const second = try cache.registerMachOBlock(0x3000, 0x1000, 0xA000, 0x1000, 0);
    _ = try cache.bindIndirectBranch(0x1010, 0x1020, 0, 0x8010, first, 0);
    _ = try cache.bindIndirectBranch(0x3010, 0x3020, 0, 0xA010, second, 0);

    const removed = cache.evictMachOBlock(first);
    try std.testing.expectEqual(@as(usize, 1), removed);
    try std.testing.expect(cache.resolveIndirectBranch(0x1010, 0x1020, 0) == null);
    try std.testing.expect(cache.resolveIndirectBranch(0x3010, 0x3020, 0) != null);
    try std.testing.expectEqual(@as(usize, 1), cache.blockCount());
}

test "co-evicting an IBTC entry removes its Mach-O block" {
    var cache = try TranslationCache.init(std.testing.allocator, .{
        .profile = tinyProfile(),
        .budget_options = .{ .min_software_l3_bytes = 4 * system_defines.MiB },
    });
    defer cache.deinit();

    const block_id = try cache.registerMachOBlock(0x5000, 0x1000, 0xB000, 0x1000, 0);
    _ = try cache.bindIndirectBranch(0x5010, 0x5020, 0, 0xB010, block_id, 0);

    try std.testing.expect(cache.evictIndirectBranch(0x5010, 0x5020, 0, true));
    try std.testing.expectEqual(@as(usize, 0), cache.blockCount());
    try std.testing.expectEqual(@as(usize, 0), cache.ibtc.live_count);
}

test "budget pressure evicts cold unpinned blocks" {
    var profile = tinyProfile();
    profile.l3_slc_bytes = 512 * system_defines.KiB;

    var cache = try TranslationCache.init(std.testing.allocator, .{
        .profile = profile,
        .budget_options = .{ .min_software_l3_bytes = 1 * system_defines.MiB, .max_software_l3_bytes = 1 * system_defines.MiB },
    });
    defer cache.deinit();

    // A 1 MiB software-L3 target leaves 640 KiB for Mach-O blocks once the
    // IBTC and dyld tables take their share, so the block size has to let two
    // blocks coexist and three not. At 400 KiB each, no two blocks fit and the
    // hot block was evicted right behind the cold one — the policy was doing
    // exactly what it should with a fixture that could not express the case.
    const block_bytes = 300 * system_defines.KiB;
    const cold = try cache.registerMachOBlock(0x1000, block_bytes, 0x8000, block_bytes, 0);
    const hot = try cache.registerMachOBlock(0x3000, block_bytes, 0xA000, block_bytes, 0);
    cache.touchMachOBlock(hot);

    _ = try cache.registerMachOBlock(0x5000, block_bytes, 0xC000, block_bytes, 0);

    try std.testing.expect(cache.blocks.get(cold) == null);
    try std.testing.expect(cache.blocks.get(hot) != null);
    try std.testing.expect(cache.stats.budget_pressure_events > 0);
}
