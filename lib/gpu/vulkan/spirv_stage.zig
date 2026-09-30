//! Bounded SPIR-V entry-point stage inspection for Vulkan diagnostics.
//!
//! Shader modules do not carry a stage field in VkShaderModuleCreateInfo.
//! Reading OpEntryPoint is the narrowest reliable way for the Vulkan bridge to
//! tell whether a tessellation module reached the host create call.

const std = @import("std");

pub const ModuleStages = struct {
    valid: bool = false,
    has_entry_point: bool = false,
    tessellation_control: bool = false,
    tessellation_evaluation: bool = false,

    pub fn tessellationMask(self: ModuleStages) u8 {
        return @as(u8, @intFromBool(self.tessellation_control)) |
            (@as(u8, @intFromBool(self.tessellation_evaluation)) << 1);
    }
};

const SPIRV_MAGIC: u32 = 0x0723_0203;
const OP_ENTRY_POINT: u16 = 15;
const EXECUTION_MODEL_TESSELLATION_CONTROL: u32 = 1;
const EXECUTION_MODEL_TESSELLATION_EVALUATION: u32 = 2;

/// Inspect instruction framing and OpEntryPoint execution models only.
/// Malformed input returns `valid=false`; callers continue through the normal
/// Vulkan path without rewriting or rejecting the guest's module.
pub fn inspect(words: []const u32) ModuleStages {
    if (words.len < 5 or words[0] != SPIRV_MAGIC) return .{};

    var result: ModuleStages = .{ .valid = true };
    var cursor: usize = 5;
    while (cursor < words.len) {
        const instruction = words[cursor];
        const word_count: usize = instruction >> 16;
        const opcode: u16 = @truncate(instruction);
        if (word_count == 0 or word_count > words.len - cursor) return .{};

        if (opcode == OP_ENTRY_POINT) {
            if (word_count < 4) return .{};
            result.has_entry_point = true;
            switch (words[cursor + 1]) {
                EXECUTION_MODEL_TESSELLATION_CONTROL => result.tessellation_control = true,
                EXECUTION_MODEL_TESSELLATION_EVALUATION => result.tessellation_evaluation = true,
                else => {},
            }
        }
        cursor += word_count;
    }
    return result;
}

test "SPIR-V inspection identifies tessellation entry points" {
    const words = [_]u32{
        SPIRV_MAGIC,                          0x0001_0000,                             0, 8,           0,
        (@as(u32, 5) << 16) | OP_ENTRY_POINT, EXECUTION_MODEL_TESSELLATION_CONTROL,    1, 0x6e69_616d, 0,
        (@as(u32, 5) << 16) | OP_ENTRY_POINT, EXECUTION_MODEL_TESSELLATION_EVALUATION, 2, 0x6e69_616d, 0,
    };
    const stages = inspect(&words);
    try std.testing.expect(stages.valid);
    try std.testing.expect(stages.has_entry_point);
    try std.testing.expect(stages.tessellation_control);
    try std.testing.expect(stages.tessellation_evaluation);
    try std.testing.expectEqual(@as(u8, 3), stages.tessellationMask());
}

test "SPIR-V inspection rejects malformed framing and accepts a vertex module" {
    const malformed = [_]u32{ SPIRV_MAGIC, 0x0001_0000, 0, 8, 0, 0 };
    try std.testing.expect(!inspect(&malformed).valid);

    const vertex = [_]u32{
        SPIRV_MAGIC,                          0x0001_0000, 0, 8,           0,
        (@as(u32, 5) << 16) | OP_ENTRY_POINT, 0,           1, 0x6e69_616d, 0,
    };
    const stages = inspect(&vertex);
    try std.testing.expect(stages.valid);
    try std.testing.expect(stages.has_entry_point);
    try std.testing.expectEqual(@as(u8, 0), stages.tessellationMask());
}
