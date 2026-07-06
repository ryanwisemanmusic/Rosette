const std = @import("std");

/// IA-32 memory models and addressing modes
/// This module provides comprehensive support for IA-32 (x86) memory models
/// as defined in Intel SDM Vol. 3A §3.3, including:
/// - Operating modes (real-address, protected, virtual-8086, SMM)
/// - Memory models (flat, segmented, real-address)
/// - Addressing forms (16-bit, 32-bit, SIB)
/// - Logical to linear address translation
/// - Segment management
pub const memory = @import("ia32_memory.zig");
pub const addressing = @import("ia32_addressing.zig");

// Re-export commonly used types
pub const OperatingMode = memory.OperatingMode;
pub const MemoryModel = memory.MemoryModel;
pub const MemoryModelConfig = memory.MemoryModelConfig;
pub const LogicalAddress = memory.LogicalAddress;
pub const LinearAddress = memory.LinearAddress;
pub const SegmentRegister = memory.SegmentRegister;
pub const SegmentDescriptor = memory.SegmentDescriptor;

pub const AddressingForm = addressing.AddressingForm;
pub const EffectiveAddress = addressing.EffectiveAddress;
pub const AddressingCapabilities = addressing.AddressingCapabilities;
pub const SegmentOverride = addressing.SegmentOverride;
pub const AddressSize = memory.AddressSize;
pub const OperandSize = memory.OperandSize;
pub const SizeOverridePrefix = memory.SizeOverridePrefix;

/// Combined memory and addressing configuration
pub const ModeConfig = struct {
    memory: memory.MemoryModelConfig,

    /// Create default IA-32 configuration
    pub fn defaultIA32() ModeConfig {
        return .{
            .memory = memory.protectedModeFlatDefaults(),
        };
    }

    /// Create real-address mode configuration
    pub fn realAddressMode() ModeConfig {
        return .{
            .memory = memory.realAddressModeDefaults(),
        };
    }

    /// Create protected mode configuration with specific memory model
    pub fn protectedMode(model: MemoryModel) ModeConfig {
        const mem_config = switch (model) {
            .flat => memory.protectedModeFlatDefaults(),
            .segmented => memory.protectedModeSegmentedDefaults(),
            .real_address => unreachable, // Not valid for protected mode
        };
        return .{
            .memory = mem_config,
        };
    }

    /// Create protected mode configuration with PAE
    pub fn protectedModePAE() ModeConfig {
        return .{
            .memory = memory.protectedModePAEDefaults(),
        };
    }

    /// Translate logical address to linear address
    pub fn logicalToLinear(self: *const ModeConfig, logical: memory.LogicalAddress) !LinearAddress {
        return memory.logicalToLinear(&self.memory, logical);
    }

    /// Compute effective address with segment handling
    pub fn computeEffectiveAddress(
        self: *const ModeConfig,
        form: AddressingForm,
        ea: EffectiveAddress,
        override: SegmentOverride,
    ) !LinearAddress {
        return addressing.computeAddressWithSegment(&self.memory, form, ea, override);
    }

    /// Check if addressing form is available
    pub fn isAddressingFormAvailable(self: *const ModeConfig, form: AddressingForm) bool {
        return addressing.isAddressingFormAvailable(form, self.memory.operating_mode, self.memory.effectiveAddressSize());
    }

    /// Apply address size override
    pub fn applyAddressSizeOverride(self: *ModeConfig) void {
        self.memory.applyAddressSizeOverride();
    }

    /// Apply operand size override
    pub fn applyOperandSizeOverride(self: *ModeConfig) void {
        self.memory.applyOperandSizeOverride();
    }

    /// Clear size overrides
    pub fn clearSizeOverrides(self: *ModeConfig) void {
        self.memory.clearSizeOverrides();
    }

    /// Get effective address size
    pub fn effectiveAddressSize(self: *const ModeConfig) AddressSize {
        return self.memory.effectiveAddressSize();
    }

    /// Get effective operand size
    pub fn effectiveOperandSize(self: *const ModeConfig) OperandSize {
        return self.memory.effectiveOperandSize();
    }
};

test "mode config exports work correctly" {
    const config = ModeConfig.defaultIA32();
    try std.testing.expectEqual(MemoryModel.flat, config.memory.memory_model);
    try std.testing.expectEqual(AddressSize.bits32, config.effectiveAddressSize());

    const real_config = ModeConfig.realAddressMode();
    try std.testing.expectEqual(OperatingMode.real_address, real_config.memory.operating_mode);
    try std.testing.expectEqual(AddressSize.bits16, real_config.effectiveAddressSize());
}

test "mode config logical to linear translation" {
    const config = ModeConfig.realAddressMode();
    const logical = memory.LogicalAddress.init(0x1000, 0x0200);
    const linear = try config.logicalToLinear(logical);
    try std.testing.expectEqual(@as(u32, 0x10200), linear);
}

test "mode config effective address computation" {
    var config = ModeConfig.protectedMode(.flat);
    config.memory.ds.cache.base = 0x1000;
    config.memory.ds.cache.limit = 0xFFFF;
    config.memory.ds.cache.granularity = false;

    const ea = EffectiveAddress{
        .base = 0x0200,
        .displacement = 0x10,
    };

    const addr = try config.computeEffectiveAddress(.indirect, ea, .none);
    try std.testing.expectEqual(@as(u32, 0x1000 + 0x0200 + 0x10), addr);
}

test "mode config PAE configuration" {
    const config = ModeConfig.protectedModePAE();
    try std.testing.expectEqual(memory.PagingModel.pae, config.memory.paging_model);
    try std.testing.expectEqual(memory.PhysicalAddressSize.bits36, config.memory.physical_addr_size);
    try std.testing.expect(config.memory.cr4_pae);
}

test "mode config size overrides" {
    var config = ModeConfig.defaultIA32();
    try std.testing.expectEqual(AddressSize.bits32, config.effectiveAddressSize());

    config.applyAddressSizeOverride();
    try std.testing.expectEqual(AddressSize.bits16, config.effectiveAddressSize());

    config.applyOperandSizeOverride();
    try std.testing.expectEqual(OperandSize.bits16, config.effectiveOperandSize());

    config.clearSizeOverrides();
    try std.testing.expectEqual(AddressSize.bits32, config.effectiveAddressSize());
    try std.testing.expectEqual(OperandSize.bits32, config.effectiveOperandSize());
}
