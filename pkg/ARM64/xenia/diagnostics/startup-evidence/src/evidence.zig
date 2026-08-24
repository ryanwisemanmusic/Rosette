//! Static Xenia Ready Compiler and graphics evidence vocabulary.
//!
//! This package contains immutable stage names and verdict vocabulary. It does
//! not parse logs or retain observations; the live evidence observer is
//! implemented in lib/diagnostics.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";

pub const Stage = enum(u8) {
    image_ready,
    compile_ready,
    static_initializers_complete,
    emulator_setup_started,
    memory_ready,
    processor_ready,
    patch_database_ready,
    kernel_globals_started,
    kernel_globals_ready,
    kernel_modules_ready,
    graphics_setup_started,
    command_processor_ready,
    graphics_ready,
    emulator_setup_ready,
    launch_path_started,
    disc_mounted,
    complete_launch_started,
    user_module_loaded,
    precompile_requested,
    precompile_completed,
    user_module_ready,
    shader_storage_requested,
    shader_storage_ready,
    guest_main_ready,
    complete_launch_ready,
    ring_buffer_ready,
    surface_ready,
    guest_output_ready,
    first_present,
    guest_vdswap_entered,
    guest_swap_packet_encoded,
    guest_vdswap_completed,
    guest_swap_published,
    authentic_swap_consumed,
    authentic_refresh_succeeded,
    authentic_native_presented,

    pub fn label(self: Stage) []const u8 {
        return @tagName(self);
    }
};

pub const ordered_stages = [_]Stage{
    .image_ready,
    .compile_ready,
    .static_initializers_complete,
    .emulator_setup_started,
    .memory_ready,
    .processor_ready,
    .patch_database_ready,
    .kernel_globals_started,
    .kernel_globals_ready,
    .kernel_modules_ready,
    .graphics_setup_started,
    .command_processor_ready,
    .graphics_ready,
    .emulator_setup_ready,
    .launch_path_started,
    .disc_mounted,
    .complete_launch_started,
    .user_module_loaded,
    .precompile_requested,
    .precompile_completed,
    .user_module_ready,
    .shader_storage_requested,
    .shader_storage_ready,
    .guest_main_ready,
    .complete_launch_ready,
    .ring_buffer_ready,
    .surface_ready,
    .guest_output_ready,
    .guest_vdswap_entered,
    .guest_swap_packet_encoded,
    .guest_vdswap_completed,
    .guest_swap_published,
    .authentic_swap_consumed,
    .authentic_refresh_succeeded,
    .authentic_native_presented,
};

pub const required_stage_count: u8 = 34;

pub fn stageBit(stage: Stage) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
}

pub fn stageFromName(name: []const u8) ?Stage {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub const Verdict = enum {
    compile_not_green,
    before_user_module,
    graphics_owner_silent,
    no_guest_swap,
    not_presented,
    authentic_frame,

    pub fn label(self: Verdict) []const u8 {
        return @tagName(self);
    }
};

test "package identity is the selected route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
}

test "stage vocabulary is ordered and name-stable" {
    try std.testing.expectEqual(@as(usize, 35), ordered_stages.len);
    try std.testing.expectEqual(@as(u8, 34), required_stage_count);
    try std.testing.expectEqual(Stage.image_ready, ordered_stages[0]);
    try std.testing.expectEqual(Stage.authentic_native_presented, ordered_stages[ordered_stages.len - 1]);
    try std.testing.expectEqual(Stage.shader_storage_requested, stageFromName("shader_storage_requested").?);
    try std.testing.expectEqual(@as(u64, 1) << 21, stageBit(.shader_storage_requested));
    try std.testing.expect(stageFromName("not_a_ready_stage") == null);
}

test "verdict vocabulary is static and presentation-aware" {
    try std.testing.expectEqualStrings("graphics_owner_silent", Verdict.graphics_owner_silent.label());
    try std.testing.expectEqualStrings("authentic_frame", Verdict.authentic_frame.label());
}
