//! The Halo/Xenia activation contract consumed by the generic ready compiler.
//!
//! The first three stages are Rosette-owned. The next group mirrors the
//! existing Xenia pipeline observer's ordered stages. The final group comes
//! from the authentic GPU handoff ledger and is deliberately stronger than a
//! successful host diagnostic present.

const std = @import("std");
const types = @import("types.zig");
const graphics_contract = @import("xenia_graphics_contract");

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
};

const graphics_handoff_stage_names = [_][]const u8{
    "guest_vdswap_entered",
    "guest_swap_packet_encoded",
    "guest_vdswap_completed",
    "guest_swap_published",
    "authentic_swap_consumed",
    "authentic_refresh_succeeded",
    "authentic_native_presented",
};

comptime {
    if (!graphics_contract.contractIsWellFormed()) {
        @compileError("xenia graphics handoff package is internally inconsistent");
    }
    if (!graphics_contract.matchesReadyCompilerNames(graphics_handoff_stage_names[0..])) {
        @compileError("xenia graphics handoff package drifted from the Ready Compiler contract");
    }
}

/// The diagnostics pipeline has its own enum and now includes the three
/// boundaries that used to be hidden inside `user_module_ready`. Keep this
/// mapping explicit: arithmetic over the Ready Compiler enum would silently
/// map a diagnostics stage to the wrong edge whenever an internal boundary is
/// inserted into the activation contract.
pub const pipeline_stages = [_]Stage{
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
    .first_present,
};

pub const pipeline_stage_count: u8 = @intCast(pipeline_stages.len);

fn bit(stage: Stage) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
}

const specs = [_]types.StageSpec{
    .{ .id = @intFromEnum(Stage.image_ready), .name = "image_ready", .owner = "rosette:loader", .description = "the Mach-O image is mapped and has an entry point" },
    .{ .id = @intFromEnum(Stage.compile_ready), .name = "compile_ready", .prerequisites = bit(.image_ready), .owner = "rosette:loader", .description = "Rosette's compile/readiness checks passed" },
    .{ .id = @intFromEnum(Stage.static_initializers_complete), .name = "static_initializers_complete", .prerequisites = bit(.compile_ready), .owner = "rosette:initializers", .description = "all pre-main initializers completed" },

    .{ .id = @intFromEnum(Stage.emulator_setup_started), .name = "emulator_setup_started", .prerequisites = bit(.static_initializers_complete), .owner = "xenia:emulator", .description = "Emulator::Setup entered" },
    .{ .id = @intFromEnum(Stage.memory_ready), .name = "memory_ready", .prerequisites = bit(.emulator_setup_started), .owner = "xenia:memory", .description = "guest memory initialized" },
    .{ .id = @intFromEnum(Stage.processor_ready), .name = "processor_ready", .prerequisites = bit(.memory_ready), .owner = "xenia:cpu", .description = "CPU frontend, backend and code cache initialized" },
    .{ .id = @intFromEnum(Stage.patch_database_ready), .name = "patch_database_ready", .prerequisites = bit(.processor_ready), .owner = "xenia:patcher", .description = "patch database constructed" },
    .{ .id = @intFromEnum(Stage.kernel_globals_started), .name = "kernel_globals_started", .prerequisites = bit(.patch_database_ready), .owner = "xenia:kernel", .description = "kernel guest globals initialization entered" },
    .{ .id = @intFromEnum(Stage.kernel_globals_ready), .name = "kernel_globals_ready", .prerequisites = bit(.kernel_globals_started), .owner = "xenia:kernel", .description = "kernel guest globals initialized" },
    .{ .id = @intFromEnum(Stage.kernel_modules_ready), .name = "kernel_modules_ready", .prerequisites = bit(.kernel_globals_ready), .owner = "xenia:kernel", .description = "kernel modules loaded" },
    .{ .id = @intFromEnum(Stage.graphics_setup_started), .name = "graphics_setup_started", .prerequisites = bit(.kernel_modules_ready), .owner = "xenia:graphics", .description = "GraphicsSystem::Setup entered" },
    .{ .id = @intFromEnum(Stage.command_processor_ready), .name = "command_processor_ready", .prerequisites = bit(.graphics_setup_started), .owner = "xenia:command_processor", .description = "GPU command processor initialized" },
    .{ .id = @intFromEnum(Stage.graphics_ready), .name = "graphics_ready", .prerequisites = bit(.command_processor_ready), .owner = "xenia:graphics", .description = "graphics setup completed" },
    .{ .id = @intFromEnum(Stage.emulator_setup_ready), .name = "emulator_setup_ready", .prerequisites = bit(.graphics_ready), .owner = "xenia:emulator", .description = "Emulator::Setup completed" },
    .{ .id = @intFromEnum(Stage.launch_path_started), .name = "launch_path_started", .prerequisites = bit(.emulator_setup_ready), .owner = "xenia:launcher", .description = "target path classification entered" },
    .{ .id = @intFromEnum(Stage.disc_mounted), .name = "disc_mounted", .prerequisites = bit(.launch_path_started), .owner = "xenia:vfs", .description = "XISO route selected" },
    .{ .id = @intFromEnum(Stage.complete_launch_started), .name = "complete_launch_started", .prerequisites = bit(.disc_mounted), .owner = "xenia:launcher", .description = "CompleteLaunch entered" },
    .{ .id = @intFromEnum(Stage.user_module_loaded), .name = "user_module_loaded", .prerequisites = bit(.complete_launch_started), .owner = "xenia:xex_loader", .description = "default.xex loaded" },
    .{ .id = @intFromEnum(Stage.precompile_requested), .name = "precompile_requested", .prerequisites = bit(.user_module_loaded), .owner = "xenia:kernel_state", .description = "FinishLoadingUserModule entered the XexModule precompile boundary" },
    .{ .id = @intFromEnum(Stage.precompile_completed), .name = "precompile_completed", .prerequisites = bit(.precompile_requested), .owner = "xenia:xex_loader", .description = "XexModule precompile and discovered-function pass returned" },
    .{ .id = @intFromEnum(Stage.user_module_ready), .name = "user_module_ready", .prerequisites = bit(.precompile_completed), .owner = "xenia:kernel_state", .description = "user module wiring and precompile completion were reported" },
    .{ .id = @intFromEnum(Stage.shader_storage_requested), .name = "shader_storage_requested", .prerequisites = bit(.user_module_ready), .owner = "xenia:graphics", .description = "CompleteLaunch entered the title shader-storage request" },
    .{ .id = @intFromEnum(Stage.shader_storage_ready), .name = "shader_storage_ready", .prerequisites = bit(.shader_storage_requested), .owner = "xenia:graphics", .description = "title shader storage initialization request completed" },
    .{ .id = @intFromEnum(Stage.guest_main_ready), .name = "guest_main_ready", .prerequisites = bit(.shader_storage_ready), .owner = "xenia:kernel_state", .description = "guest main thread is running" },
    .{ .id = @intFromEnum(Stage.complete_launch_ready), .name = "complete_launch_ready", .prerequisites = bit(.guest_main_ready), .owner = "xenia:launcher", .description = "CompleteLaunch returned success" },
    .{ .id = @intFromEnum(Stage.ring_buffer_ready), .name = "ring_buffer_ready", .prerequisites = bit(.complete_launch_ready), .owner = "guest:title", .description = "guest command ring initialized" },
    .{ .id = @intFromEnum(Stage.surface_ready), .name = "surface_ready", .prerequisites = bit(.ring_buffer_ready), .owner = "xenia:presenter", .description = "presenter surface and swapchain acquired" },
    .{ .id = @intFromEnum(Stage.guest_output_ready), .name = "guest_output_ready", .prerequisites = bit(.surface_ready), .owner = "xenia:presenter", .description = "guest output reached the presenter" },
    // Host API success is useful evidence but is not the final application
    // contract. Authentic native presentation below is the required terminal
    // stage, so this textual/API breadcrumb remains advisory.
    .{ .id = @intFromEnum(Stage.first_present), .name = "first_present", .required = false, .prerequisites = bit(.guest_output_ready), .owner = "rosette:presenter", .description = "presentation API returned success" },

    .{ .id = @intFromEnum(Stage.guest_vdswap_entered), .name = "guest_vdswap_entered", .prerequisites = bit(.ring_buffer_ready), .owner = "guest:title", .description = "guest VdSwap export was entered" },
    .{ .id = @intFromEnum(Stage.guest_swap_packet_encoded), .name = "guest_swap_packet_encoded", .prerequisites = bit(.guest_vdswap_entered), .owner = "guest:title", .description = "guest XE_SWAP packet was encoded" },
    .{ .id = @intFromEnum(Stage.guest_vdswap_completed), .name = "guest_vdswap_completed", .prerequisites = bit(.guest_swap_packet_encoded), .owner = "guest:title", .description = "guest VdSwap returned after encoding" },
    .{ .id = @intFromEnum(Stage.guest_swap_published), .name = "guest_swap_published", .prerequisites = bit(.guest_vdswap_completed), .owner = "guest:title", .description = "guest published the swap packet" },
    .{ .id = @intFromEnum(Stage.authentic_swap_consumed), .name = "authentic_swap_consumed", .prerequisites = bit(.guest_swap_published), .owner = "xenia:command_processor", .description = "the command processor consumed an authentic guest XE_SWAP" },
    .{ .id = @intFromEnum(Stage.authentic_refresh_succeeded), .name = "authentic_refresh_succeeded", .prerequisites = bit(.authentic_swap_consumed), .owner = "xenia:presenter", .description = "authentic guest output refreshed successfully" },
    .{ .id = @intFromEnum(Stage.authentic_native_presented), .name = "authentic_native_presented", .prerequisites = bit(.authentic_refresh_succeeded), .owner = "rosette:presenter", .description = "an authentic guest-derived frame reached native presentation" },
};

pub fn contract() types.Contract {
    return .{
        .name = "xenia-halo3-runtime",
        .stages = &specs,
        // The title owns the duration of guest startup. A total instruction
        // cap made a healthy-but-slow Xenia route fail before it could reach
        // VdSwap. Zero means unlimited activation; the contract still ends
        // at authentic_native_presented and quiet/compile/order failures stay
        // active.
        .activation_budget_steps = 0,
        .quiet_budget_steps = 150_000_000,
    };
}

pub fn pipelineStage(raw_stage: u8) ?Stage {
    if (raw_stage >= pipeline_stage_count) return null;
    return pipeline_stages[raw_stage];
}

/// Work-unit boundaries are emitted by the Xenia macOS launch path before the
/// coarser pipeline observer sees its next stage. They are deliberately parsed
/// here, beside the contract, so the Ready Compiler can distinguish "the
/// graphics request was never entered" from "the request entered and never
/// completed".
pub fn workUnitStage(line: []const u8) ?Stage {
    if (std.mem.indexOf(u8, line, "FinishLoadingUserModule stage=Precompile.begin") != null) {
        return .precompile_requested;
    }
    if (std.mem.indexOf(u8, line, "FinishLoadingUserModule stage=Precompile.end") != null or
        std.mem.indexOf(u8, line, "XexModule::Precompile END") != null)
    {
        return .precompile_completed;
    }
    if (std.mem.indexOf(u8, line, "Initializing shader storage") != null) {
        return .shader_storage_requested;
    }
    return null;
}

/// The numeric values mirror diagnostics.xenia_gpu_handoff.Phase without
/// importing the diagnostics module into this generic library.
pub fn handoffPhase(raw_phase: u8) ?Stage {
    return switch (raw_phase) {
        9 => .guest_vdswap_entered,
        10 => .guest_swap_packet_encoded,
        11 => .guest_vdswap_completed,
        12 => .guest_swap_published,
        13 => .authentic_swap_consumed,
        14 => .authentic_refresh_succeeded,
        15 => .authentic_native_presented,
        else => null,
    };
}

test "Xenia contract ends at authentic native presentation" {
    const active = contract();
    try std.testing.expectEqual(@as(usize, 36), active.stages.len);
    try std.testing.expectEqual(Stage.authentic_native_presented, @as(Stage, @enumFromInt(active.stages[active.stages.len - 1].id)));
    try std.testing.expect(active.stages[@intFromEnum(Stage.first_present)].required == false);
    try std.testing.expectEqual(Stage.first_present, pipelineStage(25) orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(Stage.authentic_native_presented, handoffPhase(15) orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(Stage.precompile_requested, workUnitStage("FinishLoadingUserModule stage=Precompile.begin") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(Stage.precompile_completed, workUnitStage("FinishLoadingUserModule stage=Precompile.end") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(Stage.shader_storage_requested, workUnitStage("DEBUG: Initializing shader storage...") orelse return error.TestUnexpectedResult);
    try std.testing.expect(graphics_contract.requiredArgumentsPresent(graphics_contract.required_argument_mask));
    try std.testing.expectEqual(graphics_contract.HandoffVerdict.authentic_native_presented, graphics_contract.classifyHandoff(graphics_contract.all_handoff_stages_mask));
}

test "Xenia activation has no aggregate budget but has a terminal edge" {
    try std.testing.expectEqual(@as(u64, 0), contract().activation_budget_steps);
    try std.testing.expectEqual(graphics_contract.HandoffStage.authentic_native_presented, graphics_contract.terminal_stage);
}

test "every stage names the subsystem that owes it" {
    // An unattributed edge produces a blocked report that cannot say whether
    // the missing evidence is Rosette's to produce or the guest's, which is
    // the first question a reader asks.
    for (contract().stages) |spec| {
        std.testing.expect(spec.owner.len != 0) catch |err| {
            std.debug.print("stage '{s}' has no owner\n", .{spec.name});
            return err;
        };
    }
    try std.testing.expectEqualStrings(
        "xenia:kernel_state",
        contract().stages[@intFromEnum(Stage.user_module_ready)].owner,
    );
    // The terminal edge is Rosette's: only Rosette can witness that a
    // guest-derived frame actually reached native presentation.
    try std.testing.expectEqualStrings(
        "rosette:presenter",
        contract().stages[@intFromEnum(Stage.authentic_native_presented)].owner,
    );
}
