//! Bounded SPIR-V stage and fragment-interlock inspection for Vulkan diagnostics.
//!
//! Shader modules do not carry a stage field in VkShaderModuleCreateInfo.
//! Reading OpEntryPoint is the narrowest reliable way for the Vulkan bridge to
//! tell whether a tessellation module reached the host create call. Interlock
//! capabilities and begin/end opcodes separately show when Xenia generated an
//! FSI shader.

const std = @import("std");

pub const ModuleStages = struct {
    valid: bool = false,
    has_entry_point: bool = false,
    /// SPIR-V execution-model bits: vertex=0, tess-control=1,
    /// tess-evaluation=2, geometry=3, fragment=4, compute=5.
    execution_model_mask: u8 = 0,
    tessellation_control: bool = false,
    tessellation_evaluation: bool = false,
    fragment_interlock_capabilities: u8 = 0,
    begin_interlock_ops: u32 = 0,
    end_interlock_ops: u32 = 0,

    pub fn tessellationMask(self: ModuleStages) u8 {
        return @as(u8, @intFromBool(self.tessellation_control)) |
            (@as(u8, @intFromBool(self.tessellation_evaluation)) << 1);
    }

    pub fn usesFragmentShaderInterlock(self: ModuleStages) bool {
        return self.fragment_interlock_capabilities != 0 or
            self.begin_interlock_ops != 0 or self.end_interlock_ops != 0;
    }
};

const SPIRV_MAGIC: u32 = 0x0723_0203;
const OP_ENTRY_POINT: u16 = 15;
const OP_CAPABILITY: u16 = 17;
const OP_BEGIN_INVOCATION_INTERLOCK_EXT: u16 = 5364;
const OP_END_INVOCATION_INTERLOCK_EXT: u16 = 5365;
const EXECUTION_MODEL_TESSELLATION_CONTROL: u32 = 1;
const EXECUTION_MODEL_TESSELLATION_EVALUATION: u32 = 2;
const CAPABILITY_FRAGMENT_SHADER_SAMPLE_INTERLOCK_EXT: u32 = 5363;
const CAPABILITY_FRAGMENT_SHADER_SHADING_RATE_INTERLOCK_EXT: u32 = 5372;
const CAPABILITY_FRAGMENT_SHADER_PIXEL_INTERLOCK_EXT: u32 = 5378;

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
            const model = words[cursor + 1];
            if (model < 6) result.execution_model_mask |= @as(u8, 1) << @as(u3, @intCast(model));
            switch (model) {
                EXECUTION_MODEL_TESSELLATION_CONTROL => result.tessellation_control = true,
                EXECUTION_MODEL_TESSELLATION_EVALUATION => result.tessellation_evaluation = true,
                else => {},
            }
        }
        if (opcode == OP_CAPABILITY) {
            if (word_count < 2) return .{};
            result.fragment_interlock_capabilities |= switch (words[cursor + 1]) {
                CAPABILITY_FRAGMENT_SHADER_SAMPLE_INTERLOCK_EXT => 1,
                CAPABILITY_FRAGMENT_SHADER_PIXEL_INTERLOCK_EXT => 2,
                CAPABILITY_FRAGMENT_SHADER_SHADING_RATE_INTERLOCK_EXT => 4,
                else => 0,
            };
        }
        if (opcode == OP_BEGIN_INVOCATION_INTERLOCK_EXT) result.begin_interlock_ops +|= 1;
        if (opcode == OP_END_INVOCATION_INTERLOCK_EXT) result.end_interlock_ops +|= 1;
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
    try std.testing.expectEqual(@as(u8, 0x06), stages.execution_model_mask);
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
    try std.testing.expectEqual(@as(u8, 1), stages.execution_model_mask);
}

test "SPIR-V inspection detects FSI capability and balanced interlock operations" {
    const words = [_]u32{
        SPIRV_MAGIC,                         0x0001_0000,                                    0,                                                       8,                                                     0,
        (@as(u32, 2) << 16) | OP_CAPABILITY, CAPABILITY_FRAGMENT_SHADER_PIXEL_INTERLOCK_EXT, (@as(u32, 5) << 16) | OP_ENTRY_POINT,                    4,                                                     1,
        0x6e69_616d,                         0,                                              (@as(u32, 1) << 16) | OP_BEGIN_INVOCATION_INTERLOCK_EXT, (@as(u32, 1) << 16) | OP_END_INVOCATION_INTERLOCK_EXT,
    };
    const stages = inspect(&words);
    try std.testing.expect(stages.valid);
    try std.testing.expect(stages.usesFragmentShaderInterlock());
    try std.testing.expectEqual(@as(u8, 2), stages.fragment_interlock_capabilities);
    try std.testing.expectEqual(@as(u32, 1), stages.begin_interlock_ops);
    try std.testing.expectEqual(@as(u32, 1), stages.end_interlock_ops);
}
