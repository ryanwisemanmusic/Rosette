//! Descriptor pool/set bookkeeping for the guest-to-host bridge.
//!
//! Vulkan descriptor updates are pointer-rich and easy to lose while translating
//! an x86 guest call.  This module records the semantic binding separately from
//! the host marshaller: UBO/SSBO/image/sampler writes can be validated, cached,
//! and replayed after a device or swapchain rebuild.

const std = @import("std");

pub const DescriptorType = enum(u8) {
    sampler,
    combined_image_sampler,
    sampled_image,
    storage_image,
    uniform_texel_buffer,
    storage_texel_buffer,
    uniform_buffer,
    storage_buffer,
    uniform_buffer_dynamic,
    storage_buffer_dynamic,
    input_attachment,
    inline_uniform_block,
};

pub const Binding = struct {
    binding: u16,
    descriptor_type: DescriptorType,
    descriptor_count: u16,
    stage_flags: u32,
};

pub const Resource = union(enum) {
    none,
    buffer: struct { handle: u64, offset: u64, range: u64 },
    image: struct { image: u64, view: u64, sampler: u64, layout: u32 },
    sampler: u64,
    inline_bytes: struct { offset: u32, length: u32 },
};

pub const Set = struct {
    handle: u64 = 0,
    layout: u64 = 0,
    pool: u64 = 0,
    resources: [64]Resource = [_]Resource{.none} ** 64,
    valid_mask: u64 = 0,
    generation: u64 = 0,

    pub fn update(self: *Set, binding: u16, array_element: u16, resource: Resource) error{InvalidBinding}!void {
        const index = @as(usize, binding) + array_element;
        if (index >= self.resources.len) return error.InvalidBinding;
        self.resources[index] = resource;
        self.valid_mask |= @as(u64, 1) << @intCast(index % 64);
        self.generation +%= 1;
    }

    pub fn isBound(self: *const Set, binding: u16, array_element: u16) bool {
        const index = @as(usize, binding) + array_element;
        return index < self.resources.len and (self.valid_mask & (@as(u64, 1) << @intCast(index % 64))) != 0;
    }
};

pub const Pool = struct {
    handle: u64 = 0,
    max_sets: u32 = 0,
    allocated_sets: u32 = 0,
    generation: u64 = 0,
    reset_count: u64 = 0,

    pub fn allocate(self: *Pool, set: *Set, layout: u64, handle: u64) error{OutOfSets}!void {
        if (self.allocated_sets >= self.max_sets) return error.OutOfSets;
        set.* = .{ .handle = handle, .layout = layout, .pool = self.handle };
        self.allocated_sets += 1;
        self.generation +%= 1;
    }

    pub fn reset(self: *Pool) void {
        self.allocated_sets = 0;
        self.generation +%= 1;
        self.reset_count +%= 1;
    }
};

pub const CacheEntry = struct {
    hash: u64 = 0,
    set: u64 = 0,
    generation: u64 = 0,
};

pub const Cache = struct {
    entries: [256]CacheEntry = [_]CacheEntry{.{}} ** 256,
    hits: u64 = 0,
    misses: u64 = 0,

    pub fn lookup(self: *Cache, hash: u64, generation: u64) ?u64 {
        for (self.entries) |entry| {
            if (entry.hash == hash and entry.generation == generation and entry.set != 0) {
                self.hits +%= 1;
                return entry.set;
            }
        }
        self.misses +%= 1;
        return null;
    }

    pub fn put(self: *Cache, hash: u64, generation: u64, set: u64) void {
        for (&self.entries) |*entry| {
            if (entry.set == 0 or entry.hash == hash) {
                entry.* = .{ .hash = hash, .generation = generation, .set = set };
                return;
            }
        }
    }
};

test "descriptor updates preserve buffer and image semantics" {
    var pool = Pool{ .handle = 1, .max_sets = 2 };
    var set: Set = .{};
    try pool.allocate(&set, 3, 9);
    try set.update(0, 0, .{ .buffer = .{ .handle = 11, .offset = 64, .range = 256 } });
    try set.update(1, 0, .{ .image = .{ .image = 12, .view = 13, .sampler = 14, .layout = shader_read_layout } });
    try std.testing.expect(set.isBound(0, 0));
    try std.testing.expect(set.isBound(1, 0));
    try std.testing.expectEqual(@as(u32, 1), pool.allocated_sets);
}

const shader_read_layout: u32 = 5;
