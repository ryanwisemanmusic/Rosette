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
    user_module_ready,
    shader_storage_ready,
    guest_main_ready,
    complete_launch_ready,
    ring_buffer_ready,
    surface_ready,
    guest_output_ready,
    first_present,
};

pub const stage_count = std.meta.fields(Stage).len;

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
    .{ .stage = .user_module_ready, .subsystem = .xex_loader, .description = "imports, protections and executable-module wiring completed" },
    .{ .stage = .shader_storage_ready, .subsystem = .shader_storage, .description = "per-title shader storage initialization request completed" },
    .{ .stage = .guest_main_ready, .subsystem = .guest_thread, .description = "LaunchModule returned a running guest main thread" },
    .{ .stage = .complete_launch_ready, .subsystem = .xex_loader, .description = "CompleteLaunch returned success" },
    .{ .stage = .ring_buffer_ready, .subsystem = .ring_buffer, .description = "guest command ring buffer initialized" },
    .{ .stage = .surface_ready, .subsystem = .window_surface, .description = "presenter obtained a surface and swapchain (not proof of native image backing)" },
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
