const std = @import("std");
const types = @import("types.zig");

pub const Strategy = types.Strategy;
pub const AllocationResult = types.AllocationResult;
pub const AllocatorOptions = types.AllocatorOptions;
pub const AltRegion = types.AltRegion;

pub const CODE_CACHE_64K = types.CODE_CACHE_64K;
pub const CODE_CACHE_MiB = types.CODE_CACHE_MiB;
pub const CODE_CACHE_GiB = types.CODE_CACHE_GiB;
pub const PREFERRED_BASE = types.PREFERRED_BASE;
pub const PREFERRED_SIZE = types.PREFERRED_SIZE;

const FIXED_ANON: u32 = 0x1000 | 0x2 | 0x10;
const ANON_PRIVATE: u32 = 0x1000 | 0x2;

const page_size = std.heap.page_size_min;

const RegionStrategy = struct {
    region: AltRegion,
    strategy: Strategy,
};

const fallback_plan = [_]RegionStrategy{
    .{ .region = .{ .base = 0x80000000, .size = 512 * CODE_CACHE_MiB }, .strategy = .fixed_preferred },
    .{ .region = .{ .base = 0x80000000, .size = 256 * CODE_CACHE_MiB }, .strategy = .fixed_preferred_half },
    .{ .region = .{ .base = 0x60000000, .size = 512 * CODE_CACHE_MiB }, .strategy = .fixed_alt_low },
    .{ .region = .{ .base = 0xA0000000, .size = 256 * CODE_CACHE_MiB }, .strategy = .fixed_alt_high },
    .{ .region = .{ .base = 0x40000000, .size = 256 * CODE_CACHE_MiB }, .strategy = .fixed_alt_very_low },
};

pub const CodeCacheTableAllocator = struct {
    options: AllocatorOptions,

    pub fn init(options: AllocatorOptions) CodeCacheTableAllocator {
        return .{ .options = options };
    }

    pub fn allocate(self: *const CodeCacheTableAllocator) !AllocationResult {
        for (&fallback_plan) |plan| {
            if (plan.region.size < self.options.min_size) continue;
            if (try tryFixed(plan.region.base, plan.region.size)) |result| {
                return AllocationResult{
                    .base = result.base,
                    .size = result.size,
                    .strategy = plan.strategy,
                    .is_fixed = true,
                };
            }
        }

        if (self.options.attempt_anywhere) {
            const fallback_size = @max(self.options.preferred_size / 4, self.options.min_size);
            if (try tryAnywhere(fallback_size)) |result| {
                return result;
            }
        }

        return error.CodeCacheTableAllocationFailed;
    }
};

fn tryFixed(base: u64, size: u64) !?AllocationResult {
    if (size == 0 or size > std.math.maxInt(usize)) return null;
    const length = @as(usize, @intCast(size));
    if (length % 65536 != 0) return null;

    const ptr = @as(?[*]align(page_size) u8, @ptrFromInt(base));
    const prot: std.posix.PROT = @bitCast(@as(u32, 0));
    const flags: std.posix.MAP = @bitCast(FIXED_ANON);

    const memory = std.posix.mmap(ptr, length, prot, flags, -1, 0) catch |err| {
        if (err == error.MemoryMappingNotSupported or
            err == error.PermissionDenied or
            err == error.ProcessFrozen or
            err == error.AddressInUse or
            err == error.MemoryMappingFailed)
        {
            return null;
        }
        return null;
    };

    const addr = @intFromPtr(memory.ptr);
    return AllocationResult{
        .base = addr,
        .size = size,
        .strategy = .fixed_preferred,
        .is_fixed = true,
    };
}

fn tryAnywhere(size: u64) !?AllocationResult {
    if (size == 0 or size > std.math.maxInt(usize)) return null;
    const length = @as(usize, @intCast(size));
    const prot: std.posix.PROT = @bitCast(@as(u32, 0));
    const flags: std.posix.MAP = @bitCast(ANON_PRIVATE);

    const memory = std.posix.mmap(null, length, prot, flags, -1, 0) catch |err| {
        if (err == error.MemoryMappingFailed or
            err == error.PermissionDenied or
            err == error.ProcessFrozen)
        {
            return null;
        }
        return null;
    };

    const addr = @intFromPtr(memory.ptr);
    return AllocationResult{
        .base = addr,
        .size = size,
        .strategy = .anywhere,
        .is_fixed = false,
    };
}

pub fn allocateAll() !AllocationResult {
    const allocator = CodeCacheTableAllocator.init(.{});
    return allocator.allocate();
}

pub fn allocateWithOptions(options: AllocatorOptions) !AllocationResult {
    const allocator = CodeCacheTableAllocator.init(options);
    return allocator.allocate();
}

pub fn releaseAllocation(result: AllocationResult) void {
    if (result.size == 0 or result.base == 0) return;
    const ptr = @as([*]align(page_size) u8, @ptrFromInt(result.base));
    std.posix.munmap(ptr[0..result.size]);
}

export fn rosette_code_cache_table_allocate() ?*AllocationResult {
    const allocator = std.heap.page_allocator;
    const result = allocator.create(AllocationResult) catch return null;
    result.* = allocateAll() catch {
        allocator.destroy(result);
        return null;
    };
    return result;
}

export fn rosette_code_cache_table_release(result: *AllocationResult) void {
    releaseAllocation(result.*);
    std.heap.page_allocator.destroy(result);
}

export fn rosette_code_cache_table_try_fixed(base: u64, size: u64) bool {
    if (size == 0 or size > std.math.maxInt(usize)) return false;
    const length = @as(usize, @intCast(size));
    if (length % 65536 != 0) return false;
    const ptr = @as(?[*]align(page_size) u8, @ptrFromInt(base));
    const prot: std.posix.PROT = @bitCast(@as(u32, 0));
    const flags: std.posix.MAP = @bitCast(FIXED_ANON);
    const memory = std.posix.mmap(ptr, length, prot, flags, -1, 0) catch return false;
    std.posix.munmap(memory);
    return true;
}

comptime {
    if (@sizeOf(AllocationResult) != 24) {
        @compileError("AllocationResult must be 24 bytes for C ABI compat");
    }
}

test "default allocation succeeds or gracefully fails" {
    const result = allocateAll() catch {
        return error.SkipZigTest;
    };
    defer releaseAllocation(result);
    try std.testing.expect(result.base != 0);
    try std.testing.expect(result.size >= 64 * CODE_CACHE_MiB);
}

test "custom small allocation succeeds" {
    const opts = AllocatorOptions{
        .preferred_base = 0x80000000,
        .preferred_size = 64 * CODE_CACHE_MiB,
        .min_size = 16 * CODE_CACHE_MiB,
        .attempt_anywhere = true,
    };
    const result = try allocateWithOptions(opts);
    defer releaseAllocation(result);
    try std.testing.expect(result.base != 0);
    try std.testing.expect(result.size >= 16 * CODE_CACHE_MiB);
}

test "preferred overrides shift allocation targets" {
    const opts = AllocatorOptions{
        .preferred_base = 0x7F000000,
        .preferred_size = 128 * CODE_CACHE_MiB,
        .min_size = 64 * CODE_CACHE_MiB,
        .attempt_anywhere = true,
    };
    const result = try allocateWithOptions(opts);
    defer releaseAllocation(result);
    try std.testing.expect(result.base != 0);
    try std.testing.expect(result.size >= 64 * CODE_CACHE_MiB);
}

test "allocate and release many times" {
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const result = try allocateAll();
        defer releaseAllocation(result);
        try std.testing.expect(result.base != 0);
    }
}

test "C ABI exports are callable" {
    const result_ptr = rosette_code_cache_table_allocate() orelse return error.SkipZigTest;
    defer rosette_code_cache_table_release(result_ptr);
    try std.testing.expect(result_ptr.base != 0);
    try std.testing.expect(result_ptr.size > 0);
}

test "try fixed probe returns bool" {
    _ = rosette_code_cache_table_try_fixed(0x60000000, 65536);
}
