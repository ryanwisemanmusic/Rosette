const std = @import("std");

pub const CODE_CACHE_64K: u64 = 64 * 1024;
pub const CODE_CACHE_MiB: u64 = 1024 * 1024;
pub const CODE_CACHE_GiB: u64 = CODE_CACHE_MiB * 1024;

pub const PREFERRED_BASE: u64 = 0x80000000;
pub const PREFERRED_SIZE: u64 = 512 * CODE_CACHE_MiB;
pub const PREFERRED_END: u64 = 0xA0000000;

pub const Strategy = enum(u8) {
    fixed_preferred = 0,
    fixed_preferred_half = 1,
    fixed_alt_low = 2,
    fixed_alt_high = 3,
    fixed_alt_very_low = 4,
    anywhere = 5,
    none = 0xFF,
};

pub const AllocationResult = extern struct {
    base: u64,
    size: u64,
    strategy: Strategy,
    is_fixed: bool,

    pub fn format(self: AllocationResult, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(
            \\CodeCacheIndirectionTable:
            \\  Base:     0x{X:0>8}
            \\  Size:     {} MiB
            \\  End:      0x{X:0>8}
            \\  Strategy: {s}
            \\  Fixed:    {}
            \\
        , .{
            self.base,
            self.size / CODE_CACHE_MiB,
            self.base + self.size,
            @tagName(self.strategy),
            self.is_fixed,
        });
    }

    pub fn isValid(self: *const AllocationResult) bool {
        return self.base != 0 and self.size > 0 and self.strategy != .none;
    }
};

pub const AllocatorOptions = struct {
    preferred_base: u64 = PREFERRED_BASE,
    preferred_size: u64 = PREFERRED_SIZE,
    min_size: u64 = 64 * CODE_CACHE_MiB,
    alignment: u64 = CODE_CACHE_64K,
    attempt_anywhere: bool = true,
};

pub const AltRegion = struct {
    base: u64,
    size: u64,
};
