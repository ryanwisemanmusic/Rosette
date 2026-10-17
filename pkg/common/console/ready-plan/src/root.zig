//! Static Xenia startup facts shared by the Ready Compiler and host adapters.
//!
//! This package is intentionally free of process state. It describes the
//! contract, symbol fragments, host capability vocabulary, and pure routing
//! decisions that are fixed before a Rosette run begins. Runtime observers
//! and mutable plan records remain in lib.

const std = @import("std");

pub const guest_architecture = "x86-64";
pub const host_architecture = "any";
pub const symbol_prefix = "__ZN2xe";

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

pub const StageSpec = struct {
    id: u8,
    name: []const u8,
    required: bool = true,
    prerequisites: u64 = 0,
    description: []const u8 = "",
    owner: []const u8 = "",
};

pub const Contract = struct {
    name: []const u8,
    stages: []const StageSpec,
    activation_budget_steps: u64 = 0,
    quiet_budget_steps: u64 = 0,
};

fn bit(stage: Stage) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
}

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
    .surface_ready,
    .ring_buffer_ready,
    .guest_output_ready,
    .first_present,
};

pub const pipeline_stage_count: u8 = @intCast(pipeline_stages.len);
pub const required_stage_count: u8 = 34;

pub const graphics_handoff_stage_names = [_][]const u8{
    "guest_vdswap_entered",
    "guest_swap_packet_encoded",
    "guest_vdswap_completed",
    "guest_swap_published",
    "authentic_swap_consumed",
    "authentic_refresh_succeeded",
    "authentic_native_presented",
};

pub const shader_storage_stage_names = [_][]const u8{
    "user_module_ready",
    "shader_storage_requested",
    "shader_storage_ready",
    "guest_main_ready",
};

pub const surface_path_stage_names = [_][]const u8{
    "surface_ready",
    "guest_output_ready",
    "authentic_native_presented",
};

pub const codegen_frontier_aliases = [_][]const u8{"authentic_present"};

pub const unstaged_owners = [_][]const u8{
    "xenia:xam",
    "xenia:config",
    "xenia:ui",
};

pub const specs = [_]StageSpec{
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
    .{ .id = @intFromEnum(Stage.complete_launch_ready), .name = "complete_launch_ready", .prerequisites = bit(.shader_storage_ready), .owner = "xenia:launcher", .description = "CompleteLaunch returned success" },
    .{ .id = @intFromEnum(Stage.ring_buffer_ready), .name = "ring_buffer_ready", .prerequisites = bit(.shader_storage_ready), .owner = "guest:title", .description = "guest command ring initialized" },
    .{ .id = @intFromEnum(Stage.surface_ready), .name = "surface_ready", .prerequisites = bit(.shader_storage_ready), .owner = "xenia:presenter", .description = "presenter surface and swapchain acquired" },
    .{ .id = @intFromEnum(Stage.guest_output_ready), .name = "guest_output_ready", .required = false, .prerequisites = bit(.surface_ready) | bit(.ring_buffer_ready), .owner = "xenia:presenter", .description = "guest output reached the presenter after surface and ring readiness" },
    .{ .id = @intFromEnum(Stage.first_present), .name = "first_present", .required = false, .prerequisites = bit(.guest_output_ready), .owner = "rosette:presenter", .description = "presentation API returned success" },

    .{ .id = @intFromEnum(Stage.guest_vdswap_entered), .name = "guest_vdswap_entered", .prerequisites = bit(.ring_buffer_ready), .owner = "guest:title", .description = "guest VdSwap export was entered" },
    .{ .id = @intFromEnum(Stage.guest_swap_packet_encoded), .name = "guest_swap_packet_encoded", .prerequisites = bit(.guest_vdswap_entered), .owner = "guest:title", .description = "guest XE_SWAP packet was encoded" },
    .{ .id = @intFromEnum(Stage.guest_vdswap_completed), .name = "guest_vdswap_completed", .prerequisites = bit(.guest_swap_packet_encoded), .owner = "guest:title", .description = "guest VdSwap returned after encoding" },
    .{ .id = @intFromEnum(Stage.guest_swap_published), .name = "guest_swap_published", .prerequisites = bit(.guest_vdswap_completed), .owner = "guest:title", .description = "guest published the swap packet" },
    .{ .id = @intFromEnum(Stage.authentic_swap_consumed), .name = "authentic_swap_consumed", .prerequisites = bit(.guest_swap_published), .owner = "xenia:command_processor", .description = "the command processor consumed an authentic guest XE_SWAP" },
    .{ .id = @intFromEnum(Stage.authentic_refresh_succeeded), .name = "authentic_refresh_succeeded", .prerequisites = bit(.authentic_swap_consumed), .owner = "xenia:presenter", .description = "authentic guest output refreshed successfully" },
    .{ .id = @intFromEnum(Stage.authentic_native_presented), .name = "authentic_native_presented", .prerequisites = bit(.authentic_refresh_succeeded), .owner = "rosette:presenter", .description = "an authentic guest-derived frame reached native presentation" },
};

pub fn contract() Contract {
    return .{
        .name = "xenia-halo3-runtime",
        .stages = &specs,
        .activation_budget_steps = 0,
        .quiet_budget_steps = 150_000_000,
    };
}

pub fn pipelineStage(raw_stage: u8) ?Stage {
    if (raw_stage >= pipeline_stage_count) return null;
    return pipeline_stages[raw_stage];
}

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
    if (std.mem.indexOf(u8, line, "GUEST MAIN THREAD: Successfully launched a main thread under guest") != null and
        std.mem.indexOf(u8, line, "running=YES") != null)
    {
        return .guest_main_ready;
    }
    if (std.mem.indexOf(u8, line, "GUEST MAIN THREAD: Heartbeat") != null and
        std.mem.indexOf(u8, line, "running=YES") != null)
    {
        return .guest_main_ready;
    }
    return null;
}

pub fn handoffPhase(raw_phase: u8) ?Stage {
    return switch (raw_phase) {
        1...8 => .ring_buffer_ready,
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

pub const ContractUnit = struct {
    stage: Stage,
    fragment: []const u8,
    purpose: []const u8,
    reachability_required: bool = false,
};

pub const contract_units = [_]ContractUnit{
    .{ .stage = .emulator_setup_started, .fragment = "8Emulator5SetupE", .purpose = "Emulator::Setup must exist to begin bring-up" },
    .{ .stage = .memory_ready, .fragment = "6Memory10InitializeE", .purpose = "guest memory initialization" },
    .{ .stage = .processor_ready, .fragment = "3cpu9Processor5SetupE", .purpose = "CPU frontend and backend bring-up" },
    .{ .stage = .kernel_globals_started, .fragment = "11KernelState28InitializeKernelGuestGlobalsE", .purpose = "kernel guest globals" },
    .{ .stage = .graphics_setup_started, .fragment = "14GraphicsSystem5SetupE", .purpose = "GraphicsSystem::Setup" },
    .{ .stage = .command_processor_ready, .fragment = "16CommandProcessor10InitializeE", .purpose = "GPU command processor bring-up" },
    .{ .stage = .complete_launch_started, .fragment = "8Emulator14CompleteLaunchE", .purpose = "the launch path that loads the title" },
    .{ .stage = .user_module_loaded, .fragment = "11KernelState19SetExecutableModuleE", .purpose = "wiring default.xex as the executable module" },
    .{ .stage = .precompile_requested, .fragment = "9XexModule10PrecompileE", .purpose = "entering the title's discovered-function precompile pass" },
    .{ .stage = .precompile_completed, .fragment = "9XexModule10PrecompileE", .purpose = "returning from the title's discovered-function precompile pass" },
    .{ .stage = .user_module_ready, .fragment = "11KernelState23FinishLoadingUserModuleE", .purpose = "completing user module load" },
    .{ .stage = .shader_storage_requested, .fragment = "14GraphicsSystem23InitializeShaderStorageE", .purpose = "entering per-title shader storage initialization" },
    .{ .stage = .shader_storage_ready, .fragment = "14GraphicsSystem23InitializeShaderStorageE", .purpose = "per-title shader storage initialization" },
    .{ .stage = .guest_main_ready, .fragment = "11KernelState12LaunchModuleE", .purpose = "starting the guest main thread" },
};

pub const SymbolUnit = struct {
    fragment: []const u8,
    purpose: []const u8,
    required: bool = true,
};

pub const symbol_units = [_]SymbolUnit{
    .{ .fragment = "9XexModule10PrecompileE", .purpose = "ahead-of-time translation of discovered guest functions" },
    .{ .fragment = "9XexModule12LoadContinueE", .purpose = "XEX image load" },
    .{ .fragment = "3gpu16CommandProcessor13ExecutePacketE", .purpose = "guest command ring execution", .required = false },
    .{ .fragment = "2ui9Presenter", .purpose = "host presentation", .required = false },
};

pub const HostUnit = struct {
    name: []const u8,
    purpose: []const u8,
    required: bool = true,
};

pub const host_units = [_]HostUnit{
    .{ .name = "decoder-audit", .purpose = "the x86-64 decoder handles the encodings this image contains" },
    .{ .name = "vex-safety", .purpose = "VEX encodings are decodable or provably absent", .required = false },
    .{ .name = "vulkan-loader", .purpose = "a Vulkan loader is present for the graphics path", .required = false },
    .{ .name = "window-system", .purpose = "a native window can be created for presentation", .required = false },
};

pub const ImageUnit = struct {
    name: []const u8,
    purpose: []const u8,
    required: bool = true,
};

pub const image_units = [_]ImageUnit{
    .{ .name = "mach-o-header", .purpose = "the file is a mapped 64-bit Mach-O image" },
    .{ .name = "entry-point", .purpose = "the image declares an entry point" },
    .{ .name = "text-segment", .purpose = "an executable text segment is mapped" },
    .{ .name = "symbol-table", .purpose = "a symbol table is present for contract resolution" },
    .{ .name = "bundle-executable", .purpose = "the image is the app bundle's executable", .required = false },
};

pub fn fragmentIsWellFormed(fragment: []const u8) bool {
    var index: usize = 0;
    var components: usize = 0;
    while (index < fragment.len) {
        if (fragment[index] == 'E') {
            index += 1;
            continue;
        }
        if (fragment[index] < '0' or fragment[index] > '9') return false;
        var length: usize = 0;
        while (index < fragment.len and fragment[index] >= '0' and fragment[index] <= '9') {
            length = length * 10 + (fragment[index] - '0');
            index += 1;
        }
        if (length == 0 or index + length > fragment.len) return false;
        index += length;
        components += 1;
    }
    return components != 0;
}

pub fn fingerprint() u64 {
    var result = std.hash.Wyhash.hash(0, symbol_prefix);
    for (specs) |spec| {
        result = std.hash.Wyhash.hash(result, spec.name);
        result = std.hash.Wyhash.hash(result, spec.description);
        result = std.hash.Wyhash.hash(result, spec.owner);
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&spec.id));
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&spec.prerequisites));
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&spec.required));
    }
    for (contract_units) |unit| {
        result = std.hash.Wyhash.hash(result, unit.fragment);
        result = std.hash.Wyhash.hash(result, unit.purpose);
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&unit.stage));
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&unit.reachability_required));
    }
    for (symbol_units) |unit| {
        result = std.hash.Wyhash.hash(result, unit.fragment);
        result = std.hash.Wyhash.hash(result, unit.purpose);
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&unit.required));
    }
    for (host_units) |unit| {
        result = std.hash.Wyhash.hash(result, unit.name);
        result = std.hash.Wyhash.hash(result, unit.purpose);
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&unit.required));
    }
    return result;
}

test "the static contract has the authentic native presentation terminal" {
    try std.testing.expectEqual(@as(usize, 36), specs.len);
    try std.testing.expectEqual(Stage.authentic_native_presented, @as(Stage, @enumFromInt(specs[35].id)));
    try std.testing.expectEqual(@as(u8, 34), required_stage_count);
    try std.testing.expectEqual(Stage.first_present, pipelineStage(25).?);
    try std.testing.expectEqual(Stage.ring_buffer_ready, handoffPhase(1).?);
    try std.testing.expectEqual(Stage.authentic_native_presented, handoffPhase(15).?);
    try std.testing.expect(handoffPhase(0) == null);
    try std.testing.expect(handoffPhase(16) == null);
}

test "the static contract preserves independent guest and surface barriers" {
    try std.testing.expectEqual(bit(.shader_storage_ready), specs[@intFromEnum(Stage.guest_main_ready)].prerequisites);
    try std.testing.expectEqual(bit(.shader_storage_ready), specs[@intFromEnum(Stage.complete_launch_ready)].prerequisites);
    try std.testing.expectEqual(bit(.shader_storage_ready), specs[@intFromEnum(Stage.ring_buffer_ready)].prerequisites);
    try std.testing.expectEqual(bit(.shader_storage_ready), specs[@intFromEnum(Stage.surface_ready)].prerequisites);
    try std.testing.expect(!specs[@intFromEnum(Stage.guest_output_ready)].required);
}

test "work-unit routing is pure and does not require live state" {
    try std.testing.expectEqual(Stage.precompile_requested, workUnitStage("FinishLoadingUserModule stage=Precompile.begin").?);
    try std.testing.expectEqual(Stage.precompile_completed, workUnitStage("XexModule::Precompile END").?);
    try std.testing.expectEqual(Stage.shader_storage_requested, workUnitStage("DEBUG: Initializing shader storage...").?);
    try std.testing.expectEqual(Stage.guest_main_ready, workUnitStage("GUEST MAIN THREAD: Heartbeat (running=YES)").?);
    try std.testing.expect(workUnitStage("unrelated line") == null);
}

test "static symbol fragments are length-prefixed and fingerprinted" {
    for (contract_units) |unit| try std.testing.expect(fragmentIsWellFormed(unit.fragment));
    for (symbol_units) |unit| try std.testing.expect(fragmentIsWellFormed(unit.fragment));
    try std.testing.expect(!fragmentIsWellFormed("LaunchModule"));
    try std.testing.expect(fingerprint() != 0);
}
