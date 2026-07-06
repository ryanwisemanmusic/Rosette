const std = @import("std");

/// Intel 64 (x64) memory models and addressing modes
/// This module provides comprehensive support for Intel 64 memory models
/// as defined in Intel SDM Vol. 3A §3.3.3, including:
/// - Operating modes (long mode, compatibility mode, SMM)
/// - Memory models (flat 64-bit, compatibility segmented, SMM)
/// - Addressing forms (64-bit, RIP-relative, SIB)
/// - Canonical address enforcement
/// - FS/GS base management
/// - 4-level and 5-level paging support
pub const memory = @import("x64_memory.zig");
pub const addressing = @import("x64_addressing.zig");

// Re-export commonly used types
pub const OperatingMode = memory.OperatingMode;
pub const MemoryModel = memory.MemoryModel;
pub const MemoryModelConfig = memory.MemoryModelConfig;
pub const LinearAddress = memory.LinearAddress;
pub const SegmentRegister64 = memory.SegmentRegister64;
pub const PagingModel = memory.PagingModel;
pub const PhysicalAddressSize = memory.PhysicalAddressSize;

pub const AddressingForm = addressing.AddressingForm;
pub const EffectiveAddress = addressing.EffectiveAddress;
pub const AddressingCapabilities = addressing.AddressingCapabilities;
pub const SegmentOverride = addressing.SegmentOverride;
pub const AddressSize = addressing.AddressSize;

/// Combined memory and addressing configuration
pub const ModeConfig = struct {
    memory: memory.MemoryModelConfig,
    address_size: AddressSize = .bits64,

    /// Create default x64 long mode configuration
    pub fn defaultX64() ModeConfig {
        return .{
            .memory = memory.longModeDefaults(),
            .address_size = .bits64,
        };
    }

    /// Create compatibility mode configuration
    pub fn compatibilityMode() ModeConfig {
        return .{
            .memory = memory.compatibilityModeDefaults(),
            .address_size = .bits32,
        };
    }

    /// Create 5-level paging (LA57) configuration
    pub fn longMode5Level() ModeConfig {
        return .{
            .memory = memory.longMode5LevelDefaults(),
            .address_size = .bits64,
        };
    }

    /// Create System Management Mode configuration
    pub fn systemManagementMode() ModeConfig {
        return .{
            .memory = memory.systemManagementDefaults(),
            .address_size = .bits32,
        };
    }

    /// Translate effective address to linear address
    pub fn effectiveToLinear(self: *const ModeConfig, effective: u64, segment: enum { cs, ds, es, ss, fs, gs }) !LinearAddress {
        return memory.effectiveToLinear(&self.memory, effective, switch (segment) {
            .cs => .cs,
            .ds => .ds,
            .es => .es,
            .ss => .ss,
            .fs => .fs,
            .gs => .gs,
        });
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

    /// Compute RIP-relative address
    pub fn computeRipRelative(self: *const ModeConfig, rip: u64, displacement: i32) !LinearAddress {
        _ = self;
        const addr = addressing.computeRipRelative(rip, displacement);
        if (!memory.isCanonicalAddress(addr)) {
            return error.NonCanonicalAddress;
        }
        return addr;
    }

    /// Check if addressing form is available
    pub fn isAddressingFormAvailable(self: *const ModeConfig, form: AddressingForm) bool {
        return addressing.isAddressingFormAvailable(form, self.memory.operating_mode, self.address_size);
    }

    /// Check if address is canonical
    pub fn isCanonical(self: *const ModeConfig, addr: u64) bool {
        _ = self;
        return memory.isCanonicalAddress(addr);
    }

    /// Get maximum linear address
    pub fn maxLinearAddress(self: *const ModeConfig) u64 {
        return self.memory.maxLinearAddress();
    }

    /// Get maximum physical address
    pub fn maxPhysicalAddress(self: *const ModeConfig) u64 {
        return self.memory.maxPhysicalAddress();
    }
};

test "mode config exports work correctly" {
    const config = ModeConfig.defaultX64();
    try std.testing.expectEqual(MemoryModel.flat_64, config.memory.memory_model);
    try std.testing.expectEqual(AddressSize.bits64, config.address_size);

    const compat_config = ModeConfig.compatibilityMode();
    try std.testing.expectEqual(OperatingMode.compatibility, compat_config.memory.operating_mode);
    try std.testing.expectEqual(AddressSize.bits32, compat_config.address_size);

    const la57_config = ModeConfig.longMode5Level();
    try std.testing.expectEqual(PagingModel.five_level, la57_config.memory.paging_model);
}

test "mode config effective to linear translation" {
    var config = ModeConfig.defaultX64();
    const linear = try config.effectiveToLinear(0x4000, .cs);
    try std.testing.expectEqual(@as(u64, 0x4000), linear);

    config.memory.fs.base = 0x1000;
    const linear_fs = try config.effectiveToLinear(0x4000, .fs);
    try std.testing.expectEqual(@as(u64, 0x5000), linear_fs);
}

test "mode config effective address computation" {
    var config = ModeConfig.defaultX64();
    config.memory.fs.base = 0x1000;

    const ea = EffectiveAddress{
        .base = 0x0200,
        .displacement = 0x10,
    };

    const addr = try config.computeEffectiveAddress(.indirect, ea, .fs);
    try std.testing.expectEqual(@as(u64, 0x1000 + 0x0200 + 0x10), addr);
}

test "mode config RIP-relative addressing" {
    var config = ModeConfig.defaultX64();
    const rip: u64 = 0x1_0000_4000;
    const displacement: i32 = 0x100;
    const addr = try config.computeRipRelative(rip, displacement);
    try std.testing.expectEqual(@as(u64, 0x1_0000_4100), addr);
}

test "mode config canonicality check" {
    var config = ModeConfig.defaultX64();
    try std.testing.expect(config.isCanonical(0x0000_0000_0000_0000));
    try std.testing.expect(config.isCanonical(0x0000_7FFF_FFFF_FFFF));
    try std.testing.expect(!config.isCanonical(0x0000_8000_0000_0000));
    try std.testing.expect(config.isCanonical(0xFFFF_8000_0000_0000));
}

test "mode config address limits" {
    var config = ModeConfig.defaultX64();
    try std.testing.expectEqual(@as(u64, 0x0000_FFFF_FFFF_FFFF), config.maxLinearAddress());
    try std.testing.expectEqual(@as(u64, 0x0000_FFFF_FFFF_FFFF), config.maxPhysicalAddress());

    var la57_config = ModeConfig.longMode5Level();
    try std.testing.expectEqual(@as(u64, 0x00FF_FFFF_FFFF_FFFF), la57_config.maxLinearAddress());
}

test "mode config addressing form availability" {
    var config = ModeConfig.defaultX64();
    try std.testing.expect(config.isAddressingFormAvailable(.direct));
    try std.testing.expect(config.isAddressingFormAvailable(.indexed));
    try std.testing.expect(config.isAddressingFormAvailable(.rip_relative));

    var compat_config = ModeConfig.compatibilityMode();
    try std.testing.expect(compat_config.isAddressingFormAvailable(.direct));
    try std.testing.expect(!compat_config.isAddressingFormAvailable(.rip_relative));
}
