const std = @import("std");
const core = @import("../x86-ASM/family_core.zig");
const ia32 = @import("../x86-ASM/ia32_state.zig");
const x64 = @import("x64_state.zig");
const ia32_modes = @import("../x86-ASM/modes/root.zig");
const x64_modes = @import("modes/root.zig");

pub const FamilyCpuState = union(core.ExecutionMode) {
    ia32: ia32.Ia32State,
    x64: x64.X64State,

    pub fn mode(self: FamilyCpuState) core.ExecutionMode {
        return switch (self) {
            .ia32 => .ia32,
            .x64 => .x64,
        };
    }

    /// Get operating mode for the current state
    pub fn operatingMode(self: *const FamilyCpuState) union(enum) {
        ia32: ia32_modes.OperatingMode,
        x64: x64_modes.OperatingMode,
    } {
        return switch (self) {
            .ia32 => |state| .{ .ia32 = state.operatingMode() },
            .x64 => |state| .{ .x64 = state.operatingMode() },
        };
    }

    /// Get memory model for the current state
    pub fn memoryModel(self: *const FamilyCpuState) union(enum) {
        ia32: ia32_modes.MemoryModel,
        x64: x64_modes.MemoryModel,
    } {
        return switch (self) {
            .ia32 => |state| .{ .ia32 = state.memoryModel() },
            .x64 => |state| .{ .x64 = state.memoryModel() },
        };
    }

    /// Check if address is valid for current mode
    pub fn isValidAddress(self: *const FamilyCpuState, addr: u64) bool {
        return switch (self) {
            .ia32 => {
                // IA-32: check if address fits in 32-bit space
                return addr <= 0xFFFF_FFFF;
            },
            .x64 => |state| {
                // x64: check canonicality
                return state.isCanonical(addr);
            },
        };
    }

    /// Set operating mode for the current state
    pub fn setOperatingMode(self: *FamilyCpuState, new_mode: anytype) void {
        switch (self) {
            .ia32 => |*state| state.setOperatingMode(new_mode),
            .x64 => |*state| state.setOperatingMode(new_mode),
        }
    }
};

test "bridge exposes both execution modes under one family state" {
    const state = FamilyCpuState{ .x64 = .{} };
    try std.testing.expectEqual(core.ExecutionMode.x64, state.mode());
}

test "bridge exposes operating mode information" {
    var ia32_state = FamilyCpuState{ .ia32 = .{} };
    const op_mode = ia32_state.operatingMode();
    try std.testing.expectEqual(@as(ia32_modes.OperatingMode, .protected), op_mode.ia32);

    var x64_state = FamilyCpuState{ .x64 = .{} };
    const x64_op_mode = x64_state.operatingMode();
    try std.testing.expectEqual(@as(x64_modes.OperatingMode, .long_mode), x64_op_mode.x64);
}

test "bridge exposes memory model information" {
    var ia32_state = FamilyCpuState{ .ia32 = .{} };
    const mem_model = ia32_state.memoryModel();
    try std.testing.expectEqual(@as(ia32_modes.MemoryModel, .flat), mem_model.ia32);

    var x64_state = FamilyCpuState{ .x64 = .{} };
    const x64_mem_model = x64_state.memoryModel();
    try std.testing.expectEqual(@as(x64_modes.MemoryModel, .flat_64), x64_mem_model.x64);
}

test "bridge validates addresses per mode" {
    var ia32_state = FamilyCpuState{ .ia32 = .{} };
    try std.testing.expect(ia32_state.isValidAddress(0x0000_0000));
    try std.testing.expect(ia32_state.isValidAddress(0xFFFF_FFFF));
    try std.testing.expect(!ia32_state.isValidAddress(0x1_0000_0000));

    var x64_state = FamilyCpuState{ .x64 = .{} };
    try std.testing.expect(x64_state.isValidAddress(0x0000_0000_0000_0000));
    try std.testing.expect(x64_state.isValidAddress(0x0000_7FFF_FFFF_FFFF));
    try std.testing.expect(!x64_state.isValidAddress(0x0000_8000_0000_0000));
}

test "bridge allows setting operating mode" {
    var ia32_state = FamilyCpuState{ .ia32 = .{} };
    ia32_state.setOperatingMode(ia32_modes.OperatingMode.real_address);
    try std.testing.expectEqual(@as(ia32_modes.OperatingMode, .real_address), ia32_state.operatingMode().ia32);

    var x64_state = FamilyCpuState{ .x64 = .{} };
    x64_state.setOperatingMode(x64_modes.OperatingMode.compatibility);
    try std.testing.expectEqual(@as(x64_modes.OperatingMode, .compatibility), x64_state.operatingMode().x64);
}
