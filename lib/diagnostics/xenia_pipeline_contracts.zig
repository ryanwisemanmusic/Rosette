//! Static contract for the Xenia startup, title-launch and first-frame path.
//!
//! The order comes from Emulator::Setup, Emulator::LaunchPath /
//! CompleteLaunch, GraphicsSystem::Setup, CommandProcessor and
//! VulkanPresenter.  Rosette uses this as an observability contract only; it
//! never manufactures a missing Xenia transition.

const std = @import("std");

pub const Subsystem = enum {
    process,
    memory,
    cpu_backend,
    patch_database,
    kernel,
    graphics,
    command_processor,
    virtual_filesystem,
    xex_loader,
    shader_storage,
    guest_thread,
    ring_buffer,
    window_surface,
    guest_output,
    presentation,
};

pub const Stage = enum(u8) {
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
    surface_ready,
    ring_buffer_ready,
    guest_output_ready,
    first_present,
};

pub const stage_count = std.meta.fields(Stage).len;

fn bit(stage: Stage) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(stage)));
}

/// The startup path is mostly linear. After shader storage is ready,
/// LaunchModule's guest-thread observation and CompleteLaunch's host-return
/// observation are concurrent edges and may arrive in either order. The guest
/// then owns two independent bring-up edges: it may create the host surface
/// before programming the command ring, or program the ring first. Keeping
/// both pairs as dependency sets prevents the observer from turning a valid
/// partial order into a false ordering failure.
pub fn prerequisites(stage: Stage) u32 {
    return switch (stage) {
        .emulator_setup_started => 0,
        .memory_ready => bit(.emulator_setup_started),
        .processor_ready => bit(.memory_ready),
        .patch_database_ready => bit(.processor_ready),
        .kernel_globals_started => bit(.patch_database_ready),
        .kernel_globals_ready => bit(.kernel_globals_started),
        .kernel_modules_ready => bit(.kernel_globals_ready),
        .graphics_setup_started => bit(.kernel_modules_ready),
        .command_processor_ready => bit(.graphics_setup_started),
        .graphics_ready => bit(.command_processor_ready),
        .emulator_setup_ready => bit(.graphics_ready),
        .launch_path_started => bit(.emulator_setup_ready),
        .disc_mounted => bit(.launch_path_started),
        .complete_launch_started => bit(.disc_mounted),
        .user_module_loaded => bit(.complete_launch_started),
        .precompile_requested => bit(.user_module_loaded),
        .precompile_completed => bit(.precompile_requested),
        .user_module_ready => bit(.precompile_completed),
        .shader_storage_requested => bit(.user_module_ready),
        .shader_storage_ready => bit(.shader_storage_requested),
        // LaunchModule resumes the guest main thread before CompleteLaunch
        // returns, but the two observations are made by different contexts
        // and can be reported in either order. Both require shader storage;
        // neither is a prerequisite of the other.
        .guest_main_ready => bit(.shader_storage_ready),
        .complete_launch_ready => bit(.shader_storage_ready),
        .surface_ready, .ring_buffer_ready => bit(.guest_main_ready),
        .guest_output_ready => bit(.surface_ready) | bit(.ring_buffer_ready),
        .first_present => bit(.guest_output_ready),
    };
}

pub const StageSpec = struct {
    stage: Stage,
    subsystem: Subsystem,
    required: bool = true,
    description: []const u8,
};

pub const specs = [_]StageSpec{
    .{ .stage = .emulator_setup_started, .subsystem = .process, .description = "Emulator::Setup entered" },
    .{ .stage = .memory_ready, .subsystem = .memory, .description = "guest memory initialized and exports may be created" },
    .{ .stage = .processor_ready, .subsystem = .cpu_backend, .description = "CPU frontend, backend and code cache initialized" },
    .{ .stage = .patch_database_ready, .subsystem = .patch_database, .description = "patch database object constructed" },
    .{ .stage = .kernel_globals_started, .subsystem = .kernel, .description = "kernel guest-global allocation and initialization entered" },
    .{ .stage = .kernel_globals_ready, .subsystem = .kernel, .description = "kernel guest-global object and trampoline table initialized" },
    .{ .stage = .kernel_modules_ready, .subsystem = .kernel, .description = "xboxkrnl, xam and xbdm modules loaded" },
    .{ .stage = .graphics_setup_started, .subsystem = .graphics, .description = "GraphicsSystem::Setup entered" },
    .{ .stage = .command_processor_ready, .subsystem = .command_processor, .description = "GPU command processor worker initialized" },
    .{ .stage = .graphics_ready, .subsystem = .graphics, .description = "graphics system setup returned success" },
    .{ .stage = .emulator_setup_ready, .subsystem = .process, .description = "Emulator::Setup completed" },
    .{ .stage = .launch_path_started, .subsystem = .virtual_filesystem, .description = "target path classification entered" },
    .{ .stage = .disc_mounted, .subsystem = .virtual_filesystem, .description = "XISO device mounted and default.xex route selected" },
    .{ .stage = .complete_launch_started, .subsystem = .xex_loader, .description = "CompleteLaunch entered" },
    .{ .stage = .user_module_loaded, .subsystem = .xex_loader, .description = "default.xex loaded into a UserModule" },
    .{ .stage = .precompile_requested, .subsystem = .xex_loader, .description = "FinishLoadingUserModule entered XexModule::Precompile" },
    .{ .stage = .precompile_completed, .subsystem = .xex_loader, .description = "XexModule::Precompile returned after its discovered-function pass" },
    .{ .stage = .user_module_ready, .subsystem = .xex_loader, .description = "imports, protections and executable-module wiring completed" },
    .{ .stage = .shader_storage_requested, .subsystem = .shader_storage, .description = "CompleteLaunch entered the title shader-storage request" },
    .{ .stage = .shader_storage_ready, .subsystem = .shader_storage, .description = "per-title shader storage initialization request completed" },
    .{ .stage = .guest_main_ready, .subsystem = .guest_thread, .description = "guest main thread retired its first guest instruction" },
    .{ .stage = .complete_launch_ready, .subsystem = .xex_loader, .description = "CompleteLaunch returned success" },
    .{ .stage = .surface_ready, .subsystem = .window_surface, .description = "presenter obtained a surface and swapchain (not proof of native image backing)" },
    .{ .stage = .ring_buffer_ready, .subsystem = .ring_buffer, .description = "guest command ring buffer initialized" },
    .{ .stage = .guest_output_ready, .subsystem = .guest_output, .description = "first guest output image reached the presenter" },
    .{ .stage = .first_present, .subsystem = .presentation, .description = "first presentation API call returned success (not proof of visible drawable pixels)" },
};

pub fn spec(stage: Stage) *const StageSpec {
    return &specs[@intFromEnum(stage)];
}

pub fn nextRequiredAfter(stage: ?Stage) ?Stage {
    var index: usize = if (stage) |value| @intFromEnum(value) + 1 else 0;
    while (index < specs.len) : (index += 1) {
        if (specs[index].required) return specs[index].stage;
    }
    return null;
}

test "pipeline contract is dense and ordered" {
    try std.testing.expectEqual(stage_count, specs.len);
    for (specs, 0..) |entry, index| {
        try std.testing.expectEqual(index, @intFromEnum(entry.stage));
        try std.testing.expect(entry.description.len != 0);
    }
}

test "guest main and CompleteLaunch are independent post-storage edges" {
    try std.testing.expectEqual(
        bit(.shader_storage_ready),
        prerequisites(.guest_main_ready),
    );
    try std.testing.expectEqual(
        bit(.shader_storage_ready),
        prerequisites(.complete_launch_ready),
    );
    try std.testing.expectEqual(@as(u32, 0), prerequisites(.guest_main_ready) & bit(.complete_launch_ready));
    try std.testing.expectEqual(@as(u32, 0), prerequisites(.complete_launch_ready) & bit(.guest_main_ready));
    try std.testing.expectEqual(bit(.guest_main_ready), prerequisites(.surface_ready));
    try std.testing.expectEqual(bit(.guest_main_ready), prerequisites(.ring_buffer_ready));
}

test "surface and ring are independent guest bring-up edges" {
    try std.testing.expectEqual(bit(.guest_main_ready), prerequisites(.surface_ready));
    try std.testing.expectEqual(bit(.guest_main_ready), prerequisites(.ring_buffer_ready));
    try std.testing.expectEqual(
        bit(.surface_ready) | bit(.ring_buffer_ready),
        prerequisites(.guest_output_ready),
    );
}
