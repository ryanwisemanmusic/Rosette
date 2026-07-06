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
pub const AddressSize = addressing.AddressSize;

/// Combined memory and addressing configuration
pub const ModeConfig = struct {
    memory: memory.MemoryModelConfig,
    address_size: AddressSize = .bits32,

    /// Create default IA-32 configuration
    pub fn defaultIA32() ModeConfig {
        return .{
            .memory = memory.protectedModeFlatDefaults(),
            .address_size = .bits32,
        };
    }

    /// Create real-address mode configuration
    pub fn realAddressMode() ModeConfig {
        return .{
            .memory = memory.realAddressModeDefaults(),
            .address_size = .bits16,
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
            .address_size = .bits32,
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
        return addressing.isAddressingFormAvailable(form, self.memory.operating_mode, self.address_size);
    }
};

test "mode config exports work correctly" {
    const config = ModeConfig.defaultIA32();
    try std.testing.expectEqual(MemoryModel.flat, config.memory.memory_model);
    try std.testing.expectEqual(AddressSize.bits32, config.address_size);

    const real_config = ModeConfig.realAddressMode();
    try std.testing.expectEqual(OperatingMode.real_address, real_config.memory.operating_mode);
    try std.testing.expectEqual(AddressSize.bits16, real_config.address_size);
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
