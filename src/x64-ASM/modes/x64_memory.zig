const std = @import("std");

/// Intel 64 operating modes as defined in Intel SDM Vol. 3A §3.3.3
pub const OperatingMode = enum {
    /// 64-bit mode - full 64-bit operation
    long_mode,
    /// Compatibility mode - 32-bit protected mode semantics in long mode
    compatibility,
    /// System Management Mode - separate address space (SMRAM)
    system_management,
};

/// Memory models in 64-bit mode as defined in Intel SDM Vol. 3A §3.3.3
pub const MemoryModel = enum {
    /// Flat 64-bit linear address space
    /// Segmentation generally disabled (CS, DS, ES, SS bases = 0)
    /// Linear address = effective address
    flat_64,
    /// Compatibility mode segmentation (32-bit protected mode semantics)
    compatibility_segmented,
    /// SMM memory model (similar to real-address mode)
    system_management,
};

/// 64-bit linear address
pub const LinearAddress = u64;

/// Physical address (implementation-specific, may be < 64 bits)
pub const PhysicalAddress = u64;

/// Canonical address check (Intel SDM Vol. 3A §3.3.7.1)
/// In 64-bit mode, addresses must be canonical
/// (bits 63:48 must match bit 47)
pub fn isCanonicalAddress(addr: u64) bool {
    const sign_extended = @as(i64, @bitCast(addr));
    const truncated = @as(i48, @truncate(sign_extended));
    const re_extended = @as(i64, truncated);
    return sign_extended == re_extended;
}

/// Canonical address range
pub const CanonicalRange = struct {
    lower: u64,
    upper: u64,

    pub fn contains(self: *const CanonicalRange, addr: u64) bool {
        return addr >= self.lower and addr <= self.upper;
    }
};

/// Get canonical address ranges
pub fn getCanonicalRanges() [2]CanonicalRange {
    // Lower canonical region: 0x0000_0000_0000_0000 to 0x0000_7FFF_FFFF_FFFF
    // Upper canonical region: 0xFFFF_8000_0000_0000 to 0xFFFF_FFFF_FFFF_FFFF
    return .{
        .{ .lower = 0, .upper = 0x0000_7FFF_FFFF_FFFF },
        .{ .lower = 0xFFFF_8000_0000_0000, .upper = 0xFFFF_FFFF_FFFF_FFFF },
    };
}

/// Check if address is in canonical range
pub fn isInCanonicalRange(addr: u64) bool {
    const ranges = getCanonicalRanges();
    for (ranges) |range| {
        if (range.contains(addr)) return true;
    }
    return false;
}

/// Segment register for 64-bit mode
/// In 64-bit mode, CS, DS, ES, SS bases are forced to 0
/// FS and GS bases can be set via MSRs
pub const SegmentRegister64 = struct {
    selector: u16 = 0,
    /// Hidden base (only FS/GS can be non-zero in 64-bit mode)
    base: u64 = 0,
    /// Limit (not used in 64-bit mode for CS/DS/ES/SS)
    limit: u32 = 0,

    pub fn isBaseZeroForced(self: *const SegmentRegister64, mode: OperatingMode) bool {
        _ = self;
        // In 64-bit mode, CS, DS, ES, SS bases are forced to 0
        // FS and GS can have non-zero bases
        return switch (mode) {
            .long_mode => true,
            .compatibility => false,
            .system_management => false,
        };
    }
};

/// Model-specific registers for segment bases in 64-bit mode
pub const SegmentBaseMsr = enum(u32) {
    fs_base = 0xC0000100,
    gs_base = 0xC0000101,
    kernel_gs_base = 0xC0000102,
};

/// Paging models in 64-bit mode
pub const PagingModel = enum {
    /// 4-level paging (standard in x86-64)
    four_level,
    /// 5-level paging (LA57)
    five_level,
    /// Paging disabled
    disabled,
};

/// Physical address size (implementation-specific)
pub const PhysicalAddressSize = enum(u8) {
    bits36 = 36,
    bits40 = 40,
    bits42 = 42,
    bits44 = 44,
    bits46 = 46,
    bits48 = 48,
    bits52 = 52,
    bits57 = 57,
};

/// Memory model configuration for x64
pub const MemoryModelConfig = struct {
    operating_mode: OperatingMode,
    memory_model: MemoryModel,
    paging_enabled: bool,
    paging_model: PagingModel = .four_level,

    /// Physical address size (implementation-specific)
    physical_addr_size: PhysicalAddressSize = .bits48,

    /// Segment registers (CS, DS, ES, SS bases are 0 in 64-bit mode)
    cs: SegmentRegister64 = .{},
    ds: SegmentRegister64 = .{},
    es: SegmentRegister64 = .{},
    ss: SegmentRegister64 = .{},
    fs: SegmentRegister64 = .{},
    gs: SegmentRegister64 = .{},

    /// Control register bits
    cr0_pe: bool = true, // Protection Enable (always set in long mode)
    cr0_pg: bool = true, // Paging Enable
    cr4_pae: bool = true, // Physical Address Extension
    cr4_la57: bool = false, // 5-level paging enable
    efer_lme: bool = true, // Long Mode Enable
    efer_lma: bool = true, // Long Mode Active

    /// Maximum linear address
    pub fn maxLinearAddress(self: *const MemoryModelConfig) u64 {
        return switch (self.paging_model) {
            .four_level => 0x0000_FFFF_FFFF_FFFF,
            .five_level => 0x00FF_FFFF_FFFF_FFFF,
            .disabled => 0xFFFF_FFFF_FFFF_FFFF,
        };
    }

    /// Maximum physical address
    pub fn maxPhysicalAddress(self: *const MemoryModelConfig) u64 {
        return switch (self.physical_addr_size) {
            .bits36 => 0x0000_0000_000F_FFFF,
            .bits40 => 0x0000_0000_FFFF_FFFF,
            .bits42 => 0x0000_0003_FFFF_FFFF,
            .bits44 => 0x0000_000F_FFFF_FFFF,
            .bits46 => 0x0000_003F_FFFF_FFFF,
            .bits48 => 0x0000_FFFF_FFFF_FFFF,
            .bits52 => 0x000F_FFFF_FFFF_FFFF,
            .bits57 => 0x01FF_FFFF_FFFF_FFFF,
        };
    }
};

/// Default configuration for 64-bit long mode
pub fn longModeDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .long_mode,
        .memory_model = .flat_64,
        .paging_enabled = true,
        .paging_model = .four_level,
        .physical_addr_size = .bits48,
        .cr0_pe = true,
        .cr0_pg = true,
        .cr4_pae = true,
        .efer_lme = true,
        .efer_lma = true,
    };
}

/// Default configuration for compatibility mode
pub fn compatibilityModeDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .compatibility,
        .memory_model = .compatibility_segmented,
        .paging_enabled = true,
        .paging_model = .four_level,
        .physical_addr_size = .bits48,
        .cr0_pe = true,
        .cr0_pg = true,
        .cr4_pae = true,
        .efer_lme = true,
        .efer_lma = false, // Not active in compatibility mode
    };
}

/// Default configuration for 5-level paging (LA57)
pub fn longMode5LevelDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .long_mode,
        .memory_model = .flat_64,
        .paging_enabled = true,
        .paging_model = .five_level,
        .physical_addr_size = .bits52,
        .cr0_pe = true,
        .cr0_pg = true,
        .cr4_pae = true,
        .cr4_la57 = true,
        .efer_lme = true,
        .efer_lma = true,
    };
}

/// Default configuration for System Management Mode
pub fn systemManagementDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .system_management,
        .memory_model = .system_management,
        .paging_enabled = false,
        .paging_model = .disabled,
        .physical_addr_size = .bits48,
        .cr0_pe = false,
        .cr0_pg = false,
        .cr4_pae = false,
        .efer_lme = false,
        .efer_lma = false,
    };
}

/// Effective address to linear address translation in 64-bit mode
/// In 64-bit mode, linear address = effective address (for CS/DS/ES/SS)
/// For FS/GS, linear address = segment_base + effective address
pub fn effectiveToLinear(config: *const MemoryModelConfig, effective: u64, segment: enum { cs, ds, es, ss, fs, gs }) !LinearAddress {
    // Check canonicality
    if (!isCanonicalAddress(effective)) {
        return error.NonCanonicalAddress;
    }

    // In 64-bit mode, CS/DS/ES/SS bases are forced to 0
    // FS/GS can have non-zero bases
    const seg_base = switch (segment) {
        .cs, .ds, .es, .ss => return effective, // Base is 0
        .fs => config.fs.base,
        .gs => config.gs.base,
    };

    const linear = seg_base + effective;

    // Check canonicality of result
    if (!isCanonicalAddress(linear)) {
        return error.NonCanonicalAddress;
    }

    return linear;
}

/// Compatibility mode logical to linear translation
/// Uses 32-bit protected mode semantics
pub fn compatibilityLogicalToLinear(config: *const MemoryModelConfig, selector: u16, offset: u32) !LinearAddress {
    // In compatibility mode, use 32-bit protected mode segmentation
    // Segment base comes from segment descriptor
    // For simplicity, assume selector maps to segment register
    const seg_reg = switch (selector & 0x07) {
        0 => &config.es,
        1 => &config.cs,
        2 => &config.ss,
        3 => &config.ds,
        4 => &config.fs,
        5 => &config.gs,
        else => &config.ds,
    };

    const base = seg_reg.base;
    const linear = base + offset;

    // Sign-extend to 64 bits for compatibility mode
    const sign_extended: i64 = @bitCast(@as(i32, @bitCast(@as(u32, @truncate(linear)))));
    return @as(u64, @bitCast(sign_extended));
}

/// Check if memory model is valid for operating mode
pub fn isValidModelForMode(mode: OperatingMode, model: MemoryModel) bool {
    return switch (mode) {
        .long_mode => model == .flat_64,
        .compatibility => model == .compatibility_segmented,
        .system_management => model == .system_management,
    };
}

test "canonical address check" {
    // Lower canonical region
    try std.testing.expect(isCanonicalAddress(0x0000_0000_0000_0000));
    try std.testing.expect(isCanonicalAddress(0x0000_7FFF_FFFF_FFFF));
    try std.testing.expect(!isCanonicalAddress(0x0000_8000_0000_0000));

    // Upper canonical region
    try std.testing.expect(isCanonicalAddress(0xFFFF_8000_0000_0000));
    try std.testing.expect(isCanonicalAddress(0xFFFF_FFFF_FFFF_FFFF));
    try std.testing.expect(!isCanonicalAddress(0xFFFF_7FFF_FFFF_FFFF));
}

test "canonical ranges" {
    const ranges = getCanonicalRanges();
    try std.testing.expect(ranges[0].contains(0x0000_0000_0000_0000));
    try std.testing.expect(ranges[0].contains(0x0000_7FFF_FFFF_FFFF));
    try std.testing.expect(!ranges[0].contains(0x0000_8000_0000_0000));

    try std.testing.expect(ranges[1].contains(0xFFFF_8000_0000_0000));
    try std.testing.expect(ranges[1].contains(0xFFFF_FFFF_FFFF_FFFF));
    try std.testing.expect(!ranges[1].contains(0xFFFF_7FFF_FFFF_FFFF));
}

test "effective to linear translation in 64-bit mode" {
    var config = longModeDefaults();

    // CS/DS/ES/SS: base is 0
    const linear_cs = try effectiveToLinear(&config, 0x4000, .cs);
    try std.testing.expectEqual(@as(u64, 0x4000), linear_cs);

    // FS with non-zero base
    config.fs.base = 0x1000;
    const linear_fs = try effectiveToLinear(&config, 0x4000, .fs);
    try std.testing.expectEqual(@as(u64, 0x5000), linear_fs);
}

test "non-canonical address error" {
    const config = longModeDefaults();
    const result = effectiveToLinear(&config, 0x0000_8000_0000_0000, .cs);
    try std.testing.expectError(error.NonCanonicalAddress, result);
}

test "max linear address calculation" {
    const config4 = longModeDefaults();
    try std.testing.expectEqual(@as(u64, 0x0000_FFFF_FFFF_FFFF), config4.maxLinearAddress());

    const config5 = longMode5LevelDefaults();
    try std.testing.expectEqual(@as(u64, 0x00FF_FFFF_FFFF_FFFF), config5.maxLinearAddress());
}

test "max physical address calculation" {
    var config = longModeDefaults();
    config.physical_addr_size = .bits48;
    try std.testing.expectEqual(@as(u64, 0x0000_FFFF_FFFF_FFFF), config.maxPhysicalAddress());

    config.physical_addr_size = .bits52;
    try std.testing.expectEqual(@as(u64, 0x000F_FFFF_FFFF_FFFF), config.maxPhysicalAddress());
}

test "memory model validation" {
    try std.testing.expect(isValidModelForMode(.long_mode, .flat_64));
    try std.testing.expect(!isValidModelForMode(.long_mode, .compatibility_segmented));
    try std.testing.expect(isValidModelForMode(.compatibility, .compatibility_segmented));
    try std.testing.expect(!isValidModelForMode(.compatibility, .flat_64));
}

test "default configurations" {
    const long = longModeDefaults();
    try std.testing.expectEqual(OperatingMode.long_mode, long.operating_mode);
    try std.testing.expectEqual(MemoryModel.flat_64, long.memory_model);
    try std.testing.expect(long.paging_enabled);
    try std.testing.expect(long.efer_lma);

    const compat = compatibilityModeDefaults();
    try std.testing.expectEqual(OperatingMode.compatibility, compat.operating_mode);
    try std.testing.expectEqual(MemoryModel.compatibility_segmented, compat.memory_model);
    try std.testing.expect(!compat.efer_lma);

    const la57 = longMode5LevelDefaults();
    try std.testing.expectEqual(PagingModel.five_level, la57.paging_model);
    try std.testing.expect(la57.cr4_la57);
}
