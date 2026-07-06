const std = @import("std");
const reg_map = @import("register_mapping.zig");
const modes = @import("modes/root.zig");

pub const Ia32State = struct {
    regs: reg_map.RegisterFile = .{},
    cr0: u32 = 0,
    cr2: u32 = 0,
    cr3: u32 = 0,
    cr4: u32 = 0,

    /// Memory model configuration for this IA-32 state
    memory_config: modes.MemoryModelConfig = modes.memory.protectedModeFlatDefaults(),

    pub fn instructionPointer(self: *Ia32State) *u32 {
        return &self.regs.eip;
    }

    pub fn stackPointer(self: *Ia32State) *u32 {
        return &self.regs.esp;
    }

    /// Get current operating mode
    pub fn operatingMode(self: *const Ia32State) modes.OperatingMode {
        return self.memory_config.operating_mode;
    }

    /// Get current memory model
    pub fn memoryModel(self: *const Ia32State) modes.MemoryModel {
        return self.memory_config.memory_model;
    }

    /// Translate logical address to linear address
    pub fn logicalToLinear(self: *const Ia32State, logical: modes.LogicalAddress) !modes.LinearAddress {
        return modes.memory.logicalToLinear(&self.memory_config, logical);
    }

    /// Set operating mode (reconfigures memory model appropriately)
    pub fn setOperatingMode(self: *Ia32State, mode: modes.OperatingMode) void {
        self.memory_config = switch (mode) {
            .real_address => modes.memory.realAddressModeDefaults(),
            .protected => modes.memory.protectedModeFlatDefaults(),
            .virtual_8086 => modes.memory.virtual8086Defaults(),
            .system_management => modes.memory.systemManagementDefaults(),
        };
    }

    /// Apply address size override prefix
    pub fn applyAddressSizeOverride(self: *Ia32State) void {
        self.memory_config.applyAddressSizeOverride();
    }

    /// Apply operand size override prefix
    pub fn applyOperandSizeOverride(self: *Ia32State) void {
        self.memory_config.applyOperandSizeOverride();
    }

    /// Clear size overrides
    pub fn clearSizeOverrides(self: *Ia32State) void {
        self.memory_config.clearSizeOverrides();
    }

    /// Get effective address size
    pub fn effectiveAddressSize(self: *const Ia32State) modes.AddressSize {
        return self.memory_config.effectiveAddressSize();
    }

    /// Get effective operand size
    pub fn effectiveOperandSize(self: *const Ia32State) modes.OperandSize {
        return self.memory_config.effectiveOperandSize();
    }

    /// Enable PAE (Physical Address Extension)
    pub fn enablePAE(self: *Ia32State) void {
        self.memory_config.paging_model = modes.memory.PagingModel.pae;
        self.memory_config.physical_addr_size = modes.memory.PhysicalAddressSize.bits36;
        self.memory_config.cr4_pae = true;
    }

    /// Get maximum physical address
    pub fn maxPhysicalAddress(self: *const Ia32State) u64 {
        return self.memory_config.maxPhysicalAddress();
    }
};

test "ia32 state exposes ip and sp" {
    var state: Ia32State = .{};
    state.regs.eip = 0x401000;
    state.regs.esp = 0x7FF0;
    try std.testing.expectEqual(@as(u32, 0x401000), state.instructionPointer().*);
    try std.testing.expectEqual(@as(u32, 0x7FF0), state.stackPointer().*);
}

test "ia32 state memory model integration" {
    var state: Ia32State = .{};
    try std.testing.expectEqual(modes.memory.OperatingMode.protected, state.operatingMode());
    try std.testing.expectEqual(modes.memory.MemoryModel.flat, state.memoryModel());

    state.setOperatingMode(modes.memory.OperatingMode.real_address);
    try std.testing.expectEqual(modes.memory.OperatingMode.real_address, state.operatingMode());
    try std.testing.expectEqual(modes.memory.MemoryModel.real_address, state.memoryModel());

    const logical = modes.memory.LogicalAddress.init(0x1000, 0x0200);
    const linear = try state.logicalToLinear(logical);
    try std.testing.expectEqual(@as(u32, 0x10200), linear);
}

test "ia32 state size overrides" {
    var state: Ia32State = .{};
    try std.testing.expectEqual(modes.memory.AddressSize.bits32, state.effectiveAddressSize());

    state.applyAddressSizeOverride();
    try std.testing.expectEqual(modes.memory.AddressSize.bits16, state.effectiveAddressSize());

    state.applyOperandSizeOverride();
    try std.testing.expectEqual(modes.memory.OperandSize.bits16, state.effectiveOperandSize());

    state.clearSizeOverrides();
    try std.testing.expectEqual(modes.memory.AddressSize.bits32, state.effectiveAddressSize());
    try std.testing.expectEqual(modes.memory.OperandSize.bits32, state.effectiveOperandSize());
}

test "ia32 state PAE enablement" {
    var state: Ia32State = .{};
    try std.testing.expectEqual(modes.memory.PagingModel.standard, state.memory_config.paging_model);

    state.enablePAE();
    try std.testing.expectEqual(modes.memory.PagingModel.pae, state.memory_config.paging_model);
    try std.testing.expectEqual(modes.memory.PhysicalAddressSize.bits36, state.memory_config.physical_addr_size);
    try std.testing.expect(state.memory_config.cr4_pae);
    try std.testing.expectEqual(@as(u64, 0x0000_000F_FFFF_FFFF), state.maxPhysicalAddress());
}
