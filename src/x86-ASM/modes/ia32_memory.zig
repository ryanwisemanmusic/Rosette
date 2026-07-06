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

/// Address size (Intel SDM Vol. 3A §3.3.5)
pub const AddressSize = enum(u8) {
    /// 16-bit addressing (max offset: 0xFFFF)
    bits16 = 16,
    /// 32-bit addressing (max offset: 0xFFFFFFFF)
    bits32 = 32,

    /// Get maximum offset for this address size
    pub fn maxOffset(self: AddressSize) u32 {
        return switch (self) {
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFF_FFFF,
        };
    }

    /// Get the effective address size for a given mode and override
    pub fn effectiveAddressSize(default_size: AddressSize, override: ?AddressSize) AddressSize {
        return override orelse default_size;
    }
};

/// Operand size (Intel SDM Vol. 3A §3.3.5)
pub const OperandSize = enum(u8) {
    /// 8-bit or 16-bit operands
    bits16 = 16,
    /// 8-bit or 32-bit operands
    bits32 = 32,

    /// Get the effective operand size for a given mode and override
    pub fn effectiveOperandSize(default_size: OperandSize, override: ?OperandSize) OperandSize {
        return override orelse default_size;
    }
};

/// Instruction prefixes for size overrides (Intel SDM Vol. 3A §3.3.5)
pub const SizeOverridePrefix = enum {
    /// 0x67 - Address-size override prefix
    address_size,
    /// 0x66 - Operand-size override prefix
    operand_size,
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

/// Physical address (32-bit standard, 36-bit with PAE)
pub const PhysicalAddress = u64;

/// Paging models in IA-32 (Intel SDM Vol. 3A §3.3.6)
pub const PagingModel = enum {
    /// Standard 32-bit paging (4KB pages, 32-bit physical addresses)
    standard,
    /// PAE paging (Physical Address Extension, 36-bit physical addresses)
    /// Allows up to 64 GB (2^36 bytes) of physical memory
    pae,
    /// Paging disabled
    disabled,
};

/// Physical address size (Intel SDM Vol. 3A §3.3.6)
pub const PhysicalAddressSize = enum(u8) {
    bits32 = 32, // Standard 32-bit physical addressing (4GB max)
    bits36 = 36, // PAE extended physical addressing (64GB max)

    /// Get maximum physical address for this size
    pub fn maxPhysicalAddress(self: PhysicalAddressSize) u64 {
        return switch (self) {
            .bits32 => 0xFFFF_FFFF,
            .bits36 => 0x0000_000F_FFFF_FFFF, // 36 bits = 64GB
        };
    }
};

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

    /// Address size (default for current mode)
    default_address_size: AddressSize = .bits32,
    /// Operand size (default for current mode)
    default_operand_size: OperandSize = .bits32,
    /// Current address size override (from instruction prefix)
    address_size_override: ?AddressSize = null,
    /// Current operand size override (from instruction prefix)
    operand_size_override: ?OperandSize = null,

    /// Paging model (when paging is enabled)
    paging_model: PagingModel = .standard,
    /// Physical address size
    physical_addr_size: PhysicalAddressSize = .bits32,

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

    /// Get effective address size (respecting overrides)
    pub fn effectiveAddressSize(self: *const MemoryModelConfig) AddressSize {
        return AddressSize.effectiveAddressSize(self.default_address_size, self.address_size_override);
    }

    /// Get effective operand size (respecting overrides)
    pub fn effectiveOperandSize(self: *const MemoryModelConfig) OperandSize {
        return OperandSize.effectiveOperandSize(self.default_operand_size, self.operand_size_override);
    }

    /// Apply address size override prefix
    pub fn applyAddressSizeOverride(self: *MemoryModelConfig) void {
        self.address_size_override = switch (self.default_address_size) {
            .bits16 => .bits32,
            .bits32 => .bits16,
        };
    }

    /// Apply operand size override prefix
    pub fn applyOperandSizeOverride(self: *MemoryModelConfig) void {
        self.operand_size_override = switch (self.default_operand_size) {
            .bits16 => .bits32,
            .bits32 => .bits16,
        };
    }

    /// Clear size overrides
    pub fn clearSizeOverrides(self: *MemoryModelConfig) void {
        self.address_size_override = null;
        self.operand_size_override = null;
    }

    /// Get maximum physical address
    pub fn maxPhysicalAddress(self: *const MemoryModelConfig) u64 {
        return self.physical_addr_size.maxPhysicalAddress();
    }
};

/// Default configuration for real-address mode
pub fn realAddressModeDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .real_address,
        .memory_model = .real_address,
        .segmentation_enabled = true,
        .paging_enabled = false,
        .default_address_size = .bits16, // Real-address mode defaults to 16-bit
        .default_operand_size = .bits16,
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
        .default_address_size = .bits32,
        .default_operand_size = .bits32,
        .paging_model = .standard,
        .cr0_pe = true,
        .cr0_pg = true,
    };
}

/// Default configuration for protected mode with PAE paging
pub fn protectedModePAEDefaults() MemoryModelConfig {
    return .{
        .operating_mode = .protected,
        .memory_model = .flat,
        .segmentation_enabled = true,
        .paging_enabled = true,
        .default_address_size = .bits32,
        .default_operand_size = .bits32,
        .paging_model = .pae,
        .physical_addr_size = .bits36,
        .cr0_pe = true,
        .cr0_pg = true,
        .cr4_pae = true,
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
    // Check if offset fits in effective address size
    const addr_size = config.effectiveAddressSize();
    const max_offset = addr_size.maxOffset();

    // In real-address mode with 32-bit addressing, max linear address is still 1MB
    const effective_max_offset = if (config.operating_mode == .real_address and
        config.address_size_override == .bits32)
        0x000F_FFFF // 1MB limit even with 32-bit addressing
    else
        max_offset;

    if (logical.offset > effective_max_offset) {
        return error.AddressSizeExceeded;
    }

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
    try std.testing.expectEqual(AddressSize.bits16, real.default_address_size);

    const protected_flat = protectedModeFlatDefaults();
    try std.testing.expectEqual(OperatingMode.protected, protected_flat.operating_mode);
    try std.testing.expectEqual(MemoryModel.flat, protected_flat.memory_model);
    try std.testing.expect(protected_flat.cr0_pe);
    try std.testing.expectEqual(AddressSize.bits32, protected_flat.default_address_size);

    const protected_paged = protectedModePagedDefaults();
    try std.testing.expect(protected_paged.paging_enabled);
    try std.testing.expect(protected_paged.cr0_pg);

    const protected_pae = protectedModePAEDefaults();
    try std.testing.expectEqual(PagingModel.pae, protected_pae.paging_model);
    try std.testing.expectEqual(PhysicalAddressSize.bits36, protected_pae.physical_addr_size);
    try std.testing.expect(protected_pae.cr4_pae);
}

test "address size max offset" {
    try std.testing.expectEqual(@as(u32, 0xFFFF), AddressSize.bits16.maxOffset());
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), AddressSize.bits32.maxOffset());
}

test "address size override" {
    var config = protectedModeFlatDefaults();
    try std.testing.expectEqual(AddressSize.bits32, config.effectiveAddressSize());

    config.applyAddressSizeOverride();
    try std.testing.expectEqual(AddressSize.bits16, config.effectiveAddressSize());

    config.clearSizeOverrides();
    try std.testing.expectEqual(AddressSize.bits32, config.effectiveAddressSize());
}

test "operand size override" {
    var config = protectedModeFlatDefaults();
    try std.testing.expectEqual(OperandSize.bits32, config.effectiveOperandSize());

    config.applyOperandSizeOverride();
    try std.testing.expectEqual(OperandSize.bits16, config.effectiveOperandSize());

    config.clearSizeOverrides();
    try std.testing.expectEqual(OperandSize.bits32, config.effectiveOperandSize());
}

test "real-address mode default sizes" {
    const config = realAddressModeDefaults();
    try std.testing.expectEqual(AddressSize.bits16, config.default_address_size);
    try std.testing.expectEqual(OperandSize.bits16, config.default_operand_size);
}

test "physical address size limits" {
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF), PhysicalAddressSize.bits32.maxPhysicalAddress());
    try std.testing.expectEqual(@as(u64, 0x0000_000F_FFFF_FFFF), PhysicalAddressSize.bits36.maxPhysicalAddress());
}

test "PAE configuration physical address limit" {
    const config = protectedModePAEDefaults();
    try std.testing.expectEqual(@as(u64, 0x0000_000F_FFFF_FFFF), config.maxPhysicalAddress());
}

test "address size constraint in translation" {
    var config = protectedModeFlatDefaults();
    // Try to use offset beyond 32-bit address size (this is not possible since offset is u32)
    // Instead, test with 16-bit addressing
    config.default_address_size = .bits16;
    
    const logical = LogicalAddress.init(0, 0x10000); // Beyond 16-bit
    const result = logicalToLinear(&config, logical);
    try std.testing.expectError(error.AddressSizeExceeded, result);
}

test "real-address mode 32-bit addressing constraint" {
    var config = realAddressModeDefaults();
    config.applyAddressSizeOverride(); // Switch to 32-bit addressing

    // Even with 32-bit addressing, max linear address is 1MB in real mode
    const logical = LogicalAddress.init(0x1000, 0x100000); // 1MB offset
    const result = logicalToLinear(&config, logical);
    try std.testing.expectError(error.AddressSizeExceeded, result);

    // Valid address within 1MB limit
    const valid_logical = LogicalAddress.init(0x1000, 0x0F000);
    const linear = try logicalToLinear(&config, valid_logical);
    try std.testing.expectEqual(@as(u32, 0x10000 + 0x0F000), linear);
}

test "protected mode 16-bit addressing" {
    var config = protectedModeFlatDefaults();
    config.default_address_size = .bits16;

    // Offset beyond 16-bit should fail
    const logical = LogicalAddress.init(0, 0x10000);
    const result = logicalToLinear(&config, logical);
    try std.testing.expectError(error.AddressSizeExceeded, result);

    // Valid 16-bit offset
    const valid_logical = LogicalAddress.init(0, 0x0FFF);
    const linear = try logicalToLinear(&config, valid_logical);
    try std.testing.expectEqual(@as(u32, 0x0FFF), linear);
}
