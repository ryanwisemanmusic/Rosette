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
    try std.testing.expectEqual(modes.OperatingMode.protected, state.operatingMode());
    try std.testing.expectEqual(modes.MemoryModel.flat, state.memoryModel());

    state.setOperatingMode(.real_address);
    try std.testing.expectEqual(modes.OperatingMode.real_address, state.operatingMode());
    try std.testing.expectEqual(modes.MemoryModel.real_address, state.memoryModel());

    const logical = modes.LogicalAddress.init(0x1000, 0x0200);
    const linear = try state.logicalToLinear(logical);
    try std.testing.expectEqual(@as(u32, 0x10200), linear);
}
