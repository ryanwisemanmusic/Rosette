const std = @import("std");

/// IA-32 Operating Modes as defined in Intel SDM Vol. 3A
pub const OperatingMode = enum {
    /// Real-address mode - compatibility with Intel 8086
    real_address,
    /// Protected mode - modern protected operation with segmentation/paging
    protected,
    /// Virtual-8086 mode - protected mode with real-address memory model
    virtual_8086,
    /// System Management Mode - separate address space (SMRAM)
    system_management,
};

/// IA-32 Memory Models as defined in Intel SDM Vol. 3A §3.3.1
pub const MemoryModel = enum {
    /// Flat memory model - single continuous address space
    /// Code, data, and stacks in one linear address space
    /// Byte addressable from 0 to 2^32 - 1
    flat,
    /// Segmented memory model - independent address spaces (segments)
    /// Code, data, stacks typically in separate segments
    /// Logical address = segment selector + offset (far pointer)
    /// Up to 16,383 segments, each up to 2^32 bytes
    segmented,
    /// Real-address mode memory model - Intel 8086 compatibility
    /// Array of segments up to 64 KB each
    /// Maximum linear address space: 2^20 bytes (1 MB)
    real_address,
};

/// Segment descriptor for protected mode segmentation
pub const SegmentDescriptor = struct {
    base: u32 = 0,
    limit: u32 = 0,
    /// Segment type (code, data, system, etc.)
    type: SegmentType = .data_read_write,
    /// Descriptor privilege level (0-3)
    dpl: u2 = 0,
    /// Present flag
    present: bool = true,
    /// 64-bit code segment (long mode)
    long_mode: bool = false,
    /// Default operation size (0 = 16-bit, 1 = 32-bit)
    default_size: bool = true,
    /// Granularity (0 = byte limit, 1 = 4KB page limit)
    granularity: bool = false,
};

pub const SegmentType = enum(u4) {
    data_read_only = 0,
    data_read_only_accessed = 1,
    data_read_write = 2,
    data_read_write_accessed = 3,
    data_expand_down_read_only = 4,
    data_expand_down_read_only_accessed = 5,
    data_expand_down_read_write = 6,
    data_expand_down_read_write_accessed = 7,
    code_execute_only = 8,
    code_execute_only_accessed = 9,
    code_execute_read = 10,
    code_execute_read_accessed = 11,
    code_conforming_execute_only = 12,
    code_conforming_execute_only_accessed = 13,
    code_conforming_execute_read = 14,
    code_conforming_execute_read_accessed = 15,
};

/// Segment register as used in logical addresses
pub const SegmentRegister = struct {
    selector: u16 = 0,
    /// Hidden descriptor cache (base, limit, access rights)
    cache: SegmentDescriptor = .{},

    pub fn base(self: *const SegmentRegister) u32 {
        return self.cache.base;
    }

    pub fn limit(self: *const SegmentRegister) u32 {
        return if (self.cache.granularity)
            self.cache.limit * 4096
        else
            self.cache.limit;
    }
};

/// Logical address: segment selector + offset
pub const LogicalAddress = struct {
    segment: u16,
    offset: u32,

    pub fn init(segment: u16, offset: u32) LogicalAddress {
        return .{ .segment = segment, .offset = offset };
    }
};

/// Linear address in IA-32 (32-bit)
pub const LinearAddress = u32;

/// Physical address size (implementation-specific)
pub const PhysicalAddress = u32;

/// Segment table for protected mode
pub const SegmentTable = struct {
    base: u32,
    limit: u16,

    pub fn descriptorCount(self: *const SegmentTable) usize {
        return @as(usize, self.limit + 1) / @sizeOf(SegmentDescriptor);
    }
};

/// Global Descriptor Table register
pub const Gdtr = struct {
    base: u32 = 0,
    limit: u16 = 0,
};

/// Local Descriptor Table register
pub const Ldtr = struct {
    selector: u16 = 0,
    base: u32 = 0,
    limit: u16 = 0,
};

/// Memory model configuration for a given operating mode
pub const MemoryModelConfig = struct {
    operating_mode: OperatingMode,
    memory_model: MemoryModel,
    segmentation_enabled: bool,
    paging_enabled: bool,

    /// Segment registers (CS, DS, ES, FS, GS, SS)
    cs: SegmentRegister = .{ .selector = 0 },
    ds: SegmentRegister = .{ .selector = 0 },
    es: SegmentRegister = .{ .selector = 0 },
    fs: SegmentRegister = .{ .selector = 0 },
    gs: SegmentRegister = .{ .selector = 0 },
    ss: SegmentRegister = .{ .selector = 0 },

    /// Descriptor tables
    gdtr: Gdtr = .{},
    ldtr: Ldtr = .{},

    /// Control register bits affecting memory model
    cr0_pe: bool = false, // Protection Enable
    cr0_pg: bool = false, // Paging Enable
    cr4_pae: bool = false, // Physical Address Extension
};

/// Default configuration for real-address mode
pub fn realAddressModeDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .real_address,
        .memory_model = .real_address,
        .segmentation_enabled = true,
        .paging_enabled = false,
        .cr0_pe = false,
        .cr0_pg = false,
    };
}

/// Default configuration for protected mode with flat memory model
pub fn protectedModeFlatDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .protected,
        .memory_model = .flat,
        .segmentation_enabled = true,
        .paging_enabled = false,
        .cr0_pe = true,
        .cr0_pg = false,
    };
}

/// Default configuration for protected mode with segmented memory model
pub fn protectedModeSegmentedDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .protected,
        .memory_model = .segmented,
        .segmentation_enabled = true,
        .paging_enabled = false,
        .cr0_pe = true,
        .cr0_pg = false,
    };
}

/// Default configuration for protected mode with paging (flat + paging)
pub fn protectedModePagedDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .protected,
        .memory_model = .flat,
        .segmentation_enabled = true,
        .paging_enabled = true,
        .cr0_pe = true,
        .cr0_pg = true,
    };
}

/// Default configuration for virtual-8086 mode
pub fn virtual8086Defaults() MemoryModelConfig {
    return .{
        .operating_mode = .virtual_8086,
        .memory_model = .real_address,
        .segmentation_enabled = true,
        .paging_enabled = true,
        .cr0_pe = true,
        .cr0_pg = true,
    };
}

/// Default configuration for System Management Mode
pub fn systemManagementDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .system_management,
        .memory_model = .real_address,
        .segmentation_enabled = true,
        .paging_enabled = false,
        .cr0_pe = false,
        .cr0_pg = false,
    };
}

/// Translate logical address to linear address based on memory model
pub fn logicalToLinear(config: *const MemoryModelConfig, logical: LogicalAddress) !LinearAddress {
    return switch (config.memory_model) {
        .flat => {
            // In flat model, segmentation base is typically 0
            // Segment selector is effectively ignored for translation
            const seg_reg = getSegmentRegister(config, logical.segment);
            return seg_reg.base() + logical.offset;
        },
        .segmented => {
            // Full segmentation: linear = segment_base + offset
            const seg_reg = getSegmentRegister(config, logical.segment);
            const base = seg_reg.base();
            const limit = seg_reg.limit();

            // Check limit
            if (logical.offset > limit) {
                return error.SegmentLimitExceeded;
            }

            return base + logical.offset;
        },
        .real_address => {
            // Real-address mode: segment * 16 + offset
            // Each segment is effectively 64KB (shifted by 4)
            const segment_base = @as(u32, logical.segment) * 16;
            return segment_base + logical.offset;
        },
    };
}

/// Get segment register by selector value
fn getSegmentRegister(config: *const MemoryModelConfig, selector: u16) *const SegmentRegister {
    // Simplified: in real implementation, would decode selector to index
    // For now, return based on common conventions
    const index = selector & 0x07; // Lower 3 bits for TI=0 (GDT)
    return switch (index) {
        0 => &config.es,
        1 => &config.cs,
        2 => &config.ss,
        3 => &config.ds,
        4 => &config.fs,
        5 => &config.gs,
        else => &config.ds, // Default
    };
}

/// Check if memory model is valid for given operating mode
pub fn isValidModelForMode(mode: OperatingMode, model: MemoryModel) bool {
    return switch (mode) {
        .real_address => model == .real_address,
        .protected => true, // Protected mode supports all models
        .virtual_8086 => model == .real_address,
        .system_management => model == .real_address,
    };
}

/// Get maximum linear address space for memory model
pub fn maxLinearAddress(model: MemoryModel) u32 {
    return switch (model) {
        .flat => 0xFFFF_FFFF, // 2^32 - 1
        .segmented => 0xFFFF_FFFF, // 2^32 - 1
        .real_address => 0x000F_FFFF, // 2^20 - 1 (1 MB)
    };
}

/// Get maximum segment size for memory model
pub fn maxSegmentSize(model: MemoryModel) u32 {
    return switch (model) {
        .flat => 0xFFFF_FFFF, // Entire linear space
        .segmented => 0xFFFF_FFFF, // 2^32 bytes per segment
        .real_address => 0xFFFF, // 64 KB
    };
}

test "memory model validation" {
    try std.testing.expect(isValidModelForMode(.real_address, .real_address));
    try std.testing.expect(!isValidModelForMode(.real_address, .flat));
    try std.testing.expect(isValidModelForMode(.protected, .flat));
    try std.testing.expect(isValidModelForMode(.protected, .segmented));
    try std.testing.expect(isValidModelForMode(.virtual_8086, .real_address));
    try std.testing.expect(!isValidModelForMode(.virtual_8086, .segmented));
}

test "linear address space limits" {
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), maxLinearAddress(.flat));
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), maxLinearAddress(.segmented));
    try std.testing.expectEqual(@as(u32, 0x000F_FFFF), maxLinearAddress(.real_address));
}

test "segment size limits" {
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), maxSegmentSize(.flat));
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), maxSegmentSize(.segmented));
    try std.testing.expectEqual(@as(u32, 0xFFFF), maxSegmentSize(.real_address));
}

test "real-address mode logical to linear translation" {
    const config = realAddressModeDefaults();
    const logical = LogicalAddress.init(0x1000, 0x0200);
    const linear = try logicalToLinear(&config, logical);
    // segment * 16 + offset = 0x1000 * 16 + 0x0200 = 0x10000 + 0x0200 = 0x10200
    try std.testing.expectEqual(@as(u32, 0x10200), linear);
}

test "flat model logical to linear translation" {
    var config = protectedModeFlatDefaults();
    config.cs.cache.base = 0;
    const logical = LogicalAddress.init(0, 0x4000);
    const linear = try logicalToLinear(&config, logical);
    try std.testing.expectEqual(@as(u32, 0x4000), linear);
}

test "segmented model logical to linear translation" {
    var config = protectedModeSegmentedDefaults();
    config.ds.cache.base = 0x1000;
    config.ds.cache.limit = 0x0FFF;
    config.ds.cache.granularity = false;

    const logical = LogicalAddress.init(0x001B, 0x0200); // Selector with lower 3 bits = 3 -> DS
    const linear = try logicalToLinear(&config, logical);
    try std.testing.expectEqual(@as(u32, 0x1200), linear);
}

test "segmented model limit check" {
    var config = protectedModeSegmentedDefaults();
    config.ds.cache.base = 0x1000;
    config.ds.cache.limit = 0x0FFF;
    config.ds.cache.granularity = false;

    const logical = LogicalAddress.init(0x0010, 0x2000); // Beyond limit
    const result = logicalToLinear(&config, logical);
    try std.testing.expectError(error.SegmentLimitExceeded, result);
}

test "default configurations" {
    const real = realAddressModeDefaults();
    try std.testing.expectEqual(OperatingMode.real_address, real.operating_mode);
    try std.testing.expectEqual(MemoryModel.real_address, real.memory_model);
    try std.testing.expect(!real.paging_enabled);

    const protected_flat = protectedModeFlatDefaults();
    try std.testing.expectEqual(OperatingMode.protected, protected_flat.operating_mode);
    try std.testing.expectEqual(MemoryModel.flat, protected_flat.memory_model);
    try std.testing.expect(protected_flat.cr0_pe);

    const protected_paged = protectedModePagedDefaults();
    try std.testing.expect(protected_paged.paging_enabled);
    try std.testing.expect(protected_paged.cr0_pg);
}
