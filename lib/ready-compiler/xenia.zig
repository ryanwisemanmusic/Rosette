//! The Halo/Xenia activation contract consumed by the generic ready compiler.
//!
//! The first three stages are Rosette-owned. The next group mirrors the
//! existing Xenia pipeline observer's ordered stages. The final group comes
//! from the authentic GPU handoff ledger and is deliberately stronger than a
//! successful host diagnostic present.

const builtin = @import("builtin");
const std = @import("std");
const types = @import("types.zig");
const graphics_contract = @import("xenia_graphics_contract");
const surface_path_contract = @import("xenia_surface_path_contract");
const shader_storage_contract = @import("xenia_shader_storage_contract");
const launch_phase_map = @import("xenia_launch_phase_map");
const abi_bridge = @import("xenia_abi_bridge");
const guest_bridge = @import("xenia_guest_bridge");
const codegen_activation = @import("xenia_codegen_activation");
const wait_contract = @import("xenia_wait_contract");
const startup_evidence = @import("xenia_startup_evidence");

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

const shader_storage_stage_names = [_][]const u8{
    "user_module_ready",
    "shader_storage_requested",
    "shader_storage_ready",
    "guest_main_ready",
};

const surface_path_stage_names = [_][]const u8{
    "surface_ready",
    "guest_output_ready",
    "authentic_native_presented",
};

comptime {
    if (!graphics_contract.contractIsWellFormed()) {
        @compileError("xenia graphics handoff package is internally inconsistent");
    }
    if (!graphics_contract.matchesReadyCompilerNames(graphics_handoff_stage_names[0..])) {
        @compileError("xenia graphics handoff package drifted from the Ready Compiler contract");
    }
    if (!surface_path_contract.contractIsWellFormed()) {
        @compileError("xenia Vulkan-to-Metal surface-path package is internally inconsistent");
    }
    if (!surface_path_contract.matchesReadyCompilerNames(surface_path_stage_names[0..])) {
        @compileError("xenia surface-path package drifted from the Ready Compiler contract");
    }
    if (!shader_storage_contract.contractIsWellFormed()) {
        @compileError("xenia shader-storage package is internally inconsistent");
    }
    if (!shader_storage_contract.matchesReadyCompilerNames(shader_storage_stage_names[0..])) {
        @compileError("xenia shader-storage package drifted from the Ready Compiler contract");
    }
    if (!launch_phase_map.contractIsWellFormed()) {
        @compileError("xenia launch phase map is internally inconsistent");
    }
    // Two cross-checks below walk 36 stages once per phase and once per
    // referenced stage name. That is a few thousand comptime branches against
    // a default quota of one thousand, and the alternative to raising it is to
    // stop checking — which is how a package and the contract it mirrors drift
    // apart without a single build failing.
    @setEvalBranchQuota(20_000);
    // Every stage the phase map refuses to precede has to be a stage this
    // contract actually declares. Without the check, renaming a stage here
    // leaves a rule in the package that can never fire and a report that
    // quietly loses its owner attribution — the failure mode that is hardest
    // to notice, because nothing breaks.
    // Two names per phase now: its own prerequisite and a proxy's. Sizing this
    // at `phase_count` would silently truncate the list the check walks, and a
    // cross-check that stops early is a cross-check that passes for the wrong
    // reason.
    var stage_name_buffer: [launch_phase_map.phase_count * 2][]const u8 = undefined;
    for (launch_phase_map.referencedStageNames(stage_name_buffer[0..])) |referenced| {
        var declared = false;
        for (specs) |spec| {
            if (std.mem.eql(u8, spec.name, referenced)) declared = true;
        }
        if (!declared) {
            @compileError("xenia launch phase map names a stage the contract does not declare: " ++ referenced);
        }
    }
    // The owners the phase map attributes work to must be owners this file
    // recognises, so a blocked report cannot name two different vocabularies
    // for the same subsystem. An owner that no stage declares is allowed only
    // if it is listed below as deliberately unmodelled.
    var owner_name_buffer: [launch_phase_map.phase_count * 2][]const u8 = undefined;
    for (launch_phase_map.referencedOwnerNames(owner_name_buffer[0..])) |phase_owner| {
        if (phase_owner.len == 0) continue;
        var known = false;
        for (specs) |spec| {
            if (std.mem.eql(u8, spec.owner, phase_owner)) known = true;
        }
        for (unstaged_owners) |unstaged| {
            if (std.mem.eql(u8, unstaged, phase_owner)) known = true;
        }
        if (!known) {
            @compileError("xenia launch phase map attributes work to an owner no stage declares: " ++ phase_owner);
        }
    }
    // The escape hatch above is only honest while it stays an admission. An
    // entry that has since acquired a stage would let a real owner keep
    // reading as unmodelled, so the list has to stay empty of those.
    for (unstaged_owners) |unstaged| {
        for (specs) |spec| {
            if (std.mem.eql(u8, spec.owner, unstaged)) {
                @compileError("owner is listed as unmodelled but a stage now declares it: " ++ unstaged);
            }
        }
    }
}

/// The route identity this build is actually compiling for, in the vocabulary
/// the route packages use. Empty means a host with no route package, in which
/// case the selection check below has nothing to compare against and says so
/// by staying silent rather than by guessing.
const route_host_architecture = switch (builtin.target.cpu.arch) {
    .x86_64 => "x86_64",
    .aarch64 => "arm64",
    .powerpc64 => "ppc64",
    else => "",
};

/// Fails the build when a route package that is not this host's was selected.
///
/// This is the check the package tree did not have. `pkg/x86` and `pkg/ARM64`
/// are chosen by the architecture Rosette is *compiled for*, so on an Apple
/// Silicon host the x86 copy can be edited, tested, and reported green while
/// the binary keeps shipping the ARM64 one. Every symptom of that is a silence.
fn assertRouteSelected(comptime package: []const u8, comptime declared: []const u8) void {
    if (route_host_architecture.len == 0) return;
    if (!std.mem.eql(u8, declared, route_host_architecture)) {
        @compileError("the " ++ package ++ " route package declares host_architecture=\"" ++
            declared ++ "\" but this build compiles for " ++ route_host_architecture ++
            ": the selected package is not the one that ships");
    }
}

/// `Frontier` tags that name a milestone rather than a contract stage. The
/// package uses `authentic_present` as shorthand for the terminal edge; every
/// other tag has to be a stage this file declares, or the classifier is
/// deciding about something the contract cannot report.
const codegen_frontier_aliases = [_][]const u8{"authentic_present"};

comptime {
    // Each of these two cross-checks walks the 36-stage table once per name it
    // is checking. The default quota is a thousand branches, and the only
    // alternative to raising it is to stop checking — which is the failure this
    // whole block exists to make impossible.
    @setEvalBranchQuota(50_000);

    assertRouteSelected("graphics", graphics_contract.host_architecture);
    assertRouteSelected("surface-path", surface_path_contract.host_architecture);
    assertRouteSelected("shader-storage", shader_storage_contract.host_architecture);
    assertRouteSelected("launch-phase-map", launch_phase_map.host_architecture);
    assertRouteSelected("ABI bridge", abi_bridge.host_architecture);
    assertRouteSelected("guest bridge", guest_bridge.host_architecture);
    assertRouteSelected("codegen-activation", codegen_activation.host_architecture);
    assertRouteSelected("wait contract", wait_contract.host_architecture);
    assertRouteSelected("startup evidence", startup_evidence.host_architecture);

    // ---- Startup evidence: one stage vocabulary, checked both ways.
    //
    // The package parses the log this contract emits. A stage renamed on one
    // side is not a compile error anywhere else: the parser simply stops
    // recognising the line and reports a frontier that is earlier than the run
    // reached, which reads as a regression in the guest.
    for (@typeInfo(Stage).@"enum".fields) |field| {
        if (startup_evidence.stageFromName(field.name) == null) {
            @compileError("the startup-evidence package cannot parse a stage this contract declares: " ++ field.name);
        }
    }
    for (@typeInfo(startup_evidence.Stage).@"enum".fields) |field| {
        var declared = false;
        for (specs) |spec| {
            if (std.mem.eql(u8, spec.name, field.name)) declared = true;
        }
        if (!declared) {
            @compileError("the startup-evidence package parses a stage this contract does not declare: " ++ field.name);
        }
    }
    // The package reports `blocks=n/total`. That total is the number of stages
    // this contract requires, so an optional stage added here without the
    // package noticing would silently move every reported denominator.
    var required_stages: usize = 0;
    for (specs) |spec| {
        if (spec.required) required_stages += 1;
    }
    if (required_stages != startup_evidence.required_stage_count) {
        @compileError("the startup-evidence package counts a different number of required stages than this contract declares");
    }

    // ---- Codegen activation: the classifier decides about stages, so the
    // stages it names have to be ones a report can actually carry.
    for (@typeInfo(codegen_activation.Frontier).@"enum".fields) |field| {
        var known = false;
        for (specs) |spec| {
            if (std.mem.eql(u8, spec.name, field.name)) known = true;
        }
        for (codegen_frontier_aliases) |alias| {
            if (std.mem.eql(u8, alias, field.name)) known = true;
        }
        if (!known) {
            @compileError("the codegen-activation package classifies a frontier this contract does not declare: " ++ field.name);
        }
    }
    // A run whose compile plan is not green is never an activation verdict, no
    // matter what the rest of the sample says. That precedence is the whole
    // reason the ready compiler keeps compilation evidence and activation
    // evidence apart, so it is asserted rather than assumed.
    const not_green = codegen_activation.ActivationSample{
        .compile_green = false,
        .frontier = .authentic_present,
        .current_step = 1,
        .last_milestone_step = 0,
        .precompile_cost_steps = 0,
        .runnable_threads = 1,
        .parked_threads = 0,
        .wait_notifications = 1,
        .gpu_aperture_writes = 1,
        .ring_writes = 1,
    };
    if (codegen_activation.classifyActivation(not_green) != .compile_not_green) {
        @compileError("the codegen-activation package lets a non-green compile plan reach an activation verdict");
    }

    // ---- Wait contract: the invariant the graphics frontier depends on.
    //
    // If a successful wait leaves its signal available the waiter never blocks,
    // a producer/consumer pair free-runs, and the report blames whichever
    // subsystem the loop belongs to for a stall that is not there.
    var probe = wait_contract.WaitEvent.init(.consume_one);
    if (probe.wait() != .blocked) {
        @compileError("the wait contract lets an unsignalled consuming wait succeed");
    }
    probe.signal();
    if (probe.wait() != .signaled) {
        @compileError("the wait contract blocks a consuming wait that has a pending signal");
    }
    if (probe.wait() != .blocked) {
        @compileError("the wait contract lets a successful consuming wait leave its signal available");
    }
    if (!probe.invariantHolds()) {
        @compileError("the wait contract's own success/consumption ledger does not balance");
    }

    // ---- ABI bridge and guest bridge: one route, one set of host encodings.
    //
    // The two packages are selected independently by the build, so nothing but
    // this stops a build from pairing one route's ABI facts with the other
    // route's branch reach and NOP width.
    if (abi_bridge.contract.currentArchitecture() != abi_bridge.host_route) {
        @compileError("the ABI bridge package's declared route is not the architecture it is being compiled for");
    }
    const route_profile = abi_bridge.contract.profile(abi_bridge.host_route);
    if (!std.mem.eql(u8, route_profile.host_nop_bytes, guest_bridge.host_nop_bytes[0..])) {
        @compileError("the guest-bridge and ABI-bridge packages disagree about this route's host NOP encoding");
    }
    // The guest stays 32-bit big-endian Xenon on every route. A host that read
    // guest words in its own order would produce the right value in the wrong
    // byte order, which is the one corruption that looks like a plausible
    // address.
    if (route_profile.guest_endian != .big) {
        @compileError("a route package claims the Xenon guest is little-endian");
    }
    if (guest_bridge.decodeGuestWord(&guest_bridge.ppc_guest_nop_bytes) != 0x6000_0000) {
        @compileError("the guest-bridge package does not decode PPC guest words big-endian");
    }
    if (abi_bridge.contract.bridge_record_size != 16) {
        @compileError("the ABI bridge record changed width; the package ABI epoch has to change with it");
    }
}

/// Subsystems that run during startup and own no contract edge.
///
/// This is a statement about the contract, not about Xenia. `CompleteLaunch`
/// loads the per-title config, builds the game-info database from the XDBF
/// resource, updates the profile's played-title list, and hands an icon to the
/// window — hundreds of millions of instructions with no stage between
/// `user_module_ready` and `shader_storage_requested` to describe any of it.
///
/// The gap is why the failing run named `xenia:graphics` as the silent owner
/// of work that belonged to `xenia:xam`. Naming these subsystems does not fix
/// the contract; it stops the report from attributing their work to whichever
/// stage happened to be next, which is a worse answer than "unmodelled".
///
/// Adding a stage for one of these is a contract change with its own evidence
/// requirements — Xenia emits no log line for any of them, so a stage here
/// could only ever be reached by symbol attribution, and a stage that can only
/// be reached by a heuristic is not the same kind of thing as the rest of this
/// table. That decision is deliberately not being made here.
pub const unstaged_owners = [_][]const u8{
    "xenia:xam",
    "xenia:config",
    "xenia:ui",
};

pub const LaunchPhase = launch_phase_map.Phase;
pub const LaunchAttribution = launch_phase_map.Attribution;

/// Which startup region a resolved Mach-O symbol belongs to.
///
/// The answer is fixed when Xenia is compiled, so it is a package lookup
/// rather than runtime analysis. A null result is the common case and leaves
/// the gate exactly as blind as it was; see the package README for why that is
/// the right default.
pub fn launchPhaseFor(symbol_name: []const u8) ?LaunchAttribution {
    return launch_phase_map.classify(symbol_name);
}

/// Recover the known silent `CompleteLaunch` owner when nearest-symbol
/// resolution stops at an inlined libc++/UTF-8 helper. The package itself
/// supplies the frontier-scoped rule; this wrapper keeps Mach-O independent of
/// the selected ISA package's module name.
pub fn launchPhaseFallback(frontier_stage: []const u8, symbol_name: []const u8) ?LaunchAttribution {
    return launch_phase_map.frontierFallback(frontier_stage, symbol_name);
}

/// The subsystem whose progress this phase demonstrates once
/// `launchPhaseProxyAfterStage` has been reached, or empty.
///
/// Xenia translates guest PowerPC lazily, so after guest main starts, the
/// translator only runs because the title reached code it had not reached
/// before. The symbols belong to `xenia:cpu` and the progress belongs to
/// `guest:title`; the package states which phases carry that link.
pub fn launchPhaseProxyOwner(phase: LaunchPhase) []const u8 {
    return launch_phase_map.proxyOwner(phase);
}

/// The stage after which `launchPhaseProxyOwner` applies, or empty.
pub fn launchPhaseProxyAfterStage(phase: LaunchPhase) []const u8 {
    return launch_phase_map.proxyAfterStage(phase);
}

/// A loop that retires instructions without advancing anything.
pub fn idleLoopFor(symbol_name: []const u8) ?launch_phase_map.IdleLoop {
    return launch_phase_map.idleLoop(symbol_name);
}

/// The contract stage a phase cannot precede, spelled as this contract spells
/// it. The comptime block above proves every returned name is declared here.
pub fn launchPhaseAfterStage(phase: LaunchPhase) []const u8 {
    return launch_phase_map.afterStage(phase);
}

/// Whether Xenia narrates this phase itself. A phase Xenia logs does not need
/// symbol attribution to be visible; a silent one has no other witness.
pub fn launchPhaseIsSilent(phase: LaunchPhase) bool {
    return launch_phase_map.isSilentInXenia(phase);
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
    .surface_ready,
    .ring_buffer_ready,
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
    // LaunchModule resumes the guest main thread before CompleteLaunch
    // returns. These observations run on different cooperative contexts, so
    // either can be recorded first. They share the shader-storage barrier but
    // must not be made prerequisites of one another.
    .{ .id = @intFromEnum(Stage.guest_main_ready), .name = "guest_main_ready", .prerequisites = bit(.shader_storage_ready), .owner = "xenia:kernel_state", .description = "guest main thread is running" },
    .{ .id = @intFromEnum(Stage.complete_launch_ready), .name = "complete_launch_ready", .prerequisites = bit(.shader_storage_ready), .owner = "xenia:launcher", .description = "CompleteLaunch returned success" },
    // The title can request the host surface from its first guest instruction
    // before it programs the Xenos ring. These are independent guest-owned
    // edges after guest_main_ready, not a surface-before-ring or
    // ring-before-surface sequence.
    .{ .id = @intFromEnum(Stage.surface_ready), .name = "surface_ready", .prerequisites = bit(.guest_main_ready), .owner = "xenia:presenter", .description = "presenter surface and swapchain acquired" },
    .{ .id = @intFromEnum(Stage.ring_buffer_ready), .name = "ring_buffer_ready", .prerequisites = bit(.guest_main_ready), .owner = "guest:title", .description = "guest command ring initialized" },
    .{ .id = @intFromEnum(Stage.guest_output_ready), .name = "guest_output_ready", .prerequisites = bit(.surface_ready) | bit(.ring_buffer_ready), .owner = "xenia:presenter", .description = "guest output reached the presenter after surface and ring readiness" },
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
    try std.testing.expectEqual(@as(u32, 5_000), shader_storage_contract.blocking_timeout_ms);
    try std.testing.expectEqual(
        shader_storage_contract.Verdict.explicit_timeout_continuation,
        shader_storage_contract.classify(
            shader_storage_contract.stageBit(.user_module_ready) |
                shader_storage_contract.stageBit(.shader_storage_requested),
            .blocking,
            true,
        ),
    );
    try std.testing.expectEqualStrings("vulkan", surface_path_contract.backend);
    try std.testing.expectEqualStrings("fbo", surface_path_contract.render_target_path);
    try std.testing.expectEqualStrings("VK_EXT_metal_surface", surface_path_contract.native_surface_api);
    try std.testing.expect(surface_path_contract.requires_guest_surface_call);
}

test "the route packages this build selected are this host's" {
    // The comptime block above already refuses a mismatch. This is the same
    // fact stated where a reader can see it fail by name rather than as a
    // compile error inside a package they did not know was selected.
    try std.testing.expectEqualStrings(route_host_architecture, graphics_contract.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, surface_path_contract.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, shader_storage_contract.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, launch_phase_map.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, abi_bridge.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, guest_bridge.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, codegen_activation.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, wait_contract.host_architecture);
    try std.testing.expectEqualStrings(route_host_architecture, startup_evidence.host_architecture);
}

test "the startup-evidence parser reads this contract's own report" {
    // A round trip through the two formats the ready compiler actually emits.
    // If either the stage line or the blocked line changes shape, the parser
    // reports an earlier frontier than the run reached — a regression that
    // looks like the guest lost ground.
    var report = startup_evidence.Report{};
    report.ingest(
        "READY COMPILER: compile plan GREEN units=39/42 ok=39 failed=0 unknown=3 skipped=0\n" ++
            "READY COMPILER: report stage id=0 name=image_ready reached=true\n" ++
            "READY COMPILER: stage name=user_module_loaded id=17 accepted=true\n" ++
            "READY COMPILER: stage name=user_module_ready id=20 accepted=true\n" ++
            "READY COMPILER: BLOCKED kind=ACTIVATION_BUDGET_EXHAUSTED stage=shader_storage_requested step=500000000\n",
    );
    try std.testing.expect(report.compile_green);
    try std.testing.expect(report.reached(startup_evidence.stageFromName("user_module_ready").?));
    try std.testing.expectEqual(startup_evidence.Verdict.graphics_owner_silent, report.verdict());
    try std.testing.expectEqual(
        @as(usize, 35),
        @as(usize, startup_evidence.required_stage_count),
    );
}

test "the activation classifier separates a silent owner from a wait gap" {
    // The x86 evidence: compile green, the launch past user_module_ready, no
    // GPU aperture or ring traffic, and a parked waiter that was never
    // notified. Those are two different findings and the package keeps them
    // apart — one sends a reader to the graphics owner, the other to Rosette's
    // own wait primitives.
    const silent_owner = codegen_activation.ActivationSample{
        .compile_green = true,
        .frontier = .shader_storage_requested,
        .current_step = 500_000_000,
        .last_milestone_step = 368_560_915,
        .precompile_cost_steps = 227_509_982,
        .runnable_threads = 1,
        .parked_threads = 7,
        .wait_notifications = 12,
        .gpu_aperture_writes = 0,
        .ring_writes = 0,
    };
    try std.testing.expectEqual(
        codegen_activation.ActivationVerdict.graphics_owner_silent,
        codegen_activation.classifyActivation(silent_owner),
    );

    var wait_gap = silent_owner;
    wait_gap.wait_notifications = 0;
    try std.testing.expectEqual(
        codegen_activation.ActivationVerdict.wait_notification_gap,
        codegen_activation.classifyActivation(wait_gap),
    );

    // An unbound label is not a code buffer that is nearly ready.
    var ledger = codegen_activation.LabelLedger{};
    try std.testing.expect(ledger.reference(11));
    try std.testing.expectEqual(codegen_activation.CodegenStatus.undefined_label, ledger.validate());
}

test "a successful consuming wait consumes exactly one signal" {
    var event = wait_contract.WaitEvent.init(.consume_one);
    event.broadcast(2);
    try std.testing.expectEqual(wait_contract.WaitResult.signaled, event.wait());
    try std.testing.expectEqual(wait_contract.WaitResult.signaled, event.wait());
    try std.testing.expectEqual(wait_contract.WaitResult.blocked, event.wait());
    try std.testing.expectEqual(@as(u64, 2), event.consumed_signal_count);
    try std.testing.expect(event.invariantHolds());

    // The audit half: a runtime that reports a successful consuming wait
    // without consuming anything is the failure this contract exists to name,
    // and it is recorded rather than silently tolerated.
    var audited = wait_contract.WaitEvent.init(.consume_one);
    audited.observeExternalSuccess(false);
    try std.testing.expect(!audited.invariantHolds());
}

test "a guest pointer is never a host pointer that fits" {
    const window = abi_bridge.contract.GuestWindow{};
    try std.testing.expectEqual(
        abi_bridge.contract.PointerClass.guest_pointer,
        abi_bridge.contract.classifyPointer(0x8258_2cc8, window).class,
    );
    // The same value with a 33rd bit set is a host value, not a guest address
    // that happens to be large. Truncating it would produce a plausible guest
    // pointer, which is exactly why the classifier refuses.
    try std.testing.expectEqual(
        abi_bridge.contract.PointerClass.host_width_value,
        abi_bridge.contract.classifyPointer(0x0000_0001_8258_2cc8, window).class,
    );
    // Byte-reversal is self-announcing: reverse it and a guest address appears.
    const reversed = abi_bridge.contract.classifyPointer(0xc82c_5882, window);
    try std.testing.expectEqual(abi_bridge.contract.PointerClass.byte_reversed_guest_pointer, reversed.class);
    try std.testing.expectEqual(@as(u32, 0x8258_2cc8), reversed.canonical_guest.?);

    // The guest bridge reads the same guest in the same order on either route.
    try std.testing.expectEqual(
        @as(u32, 0x6000_0000),
        guest_bridge.decodeGuestWord(&guest_bridge.ppc_guest_nop_bytes),
    );
    try std.testing.expect(guest_bridge.guestInstructionAligned(0x8258_2cc8));
    try std.testing.expect(!guest_bridge.guestInstructionAligned(0x8258_2cc9));
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

test "the silent window between user_module_ready and shader_storage_requested has an owner" {
    // The exact stall sites of the x86 run this attribution was built for.
    // They are libc++ container helpers, so each one is a carrier: it names
    // the phase it was called from rather than a phase of its own.
    const observed_carriers = [_][]const u8{
        "__ZNSt3__130__uninitialized_allocator_copyB7v160006INS_9allocatorIhEEPhS3_S3_EET2_RT_T0_T1_S4_",
        "__ZNSt3__112__to_addressB7v160006IhEEPT_S2_",
        "__ZNSt3__16vectorIhNS_9allocatorIhEEE22__base_destruct_at_endB7v160006EPh",
    };
    for (observed_carriers) |symbol| {
        const attribution = launchPhaseFor(symbol) orelse return error.TestUnexpectedResult;
        try std.testing.expect(attribution.carrier);
    }

    // The Xenia code those helpers are called from. `CompleteLaunch` runs it
    // between `user_module_ready` and `shader_storage_requested` and logs
    // nothing, which is why the gate had no owner to name.
    const database = launchPhaseFor("__ZN2xe6kernel4util16GameInfoDatabase7GetIconEv") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(LaunchPhase.title_metadata, database.phase);
    try std.testing.expectEqualStrings("xenia:xam", database.owner);
    try std.testing.expect(launchPhaseIsSilent(database.phase));

    // That owner is not the one the blocked report names, and the difference
    // is the finding: `shader_storage_requested` is owed by xenia:graphics,
    // which the launch had not reached yet.
    try std.testing.expectEqualStrings(
        "xenia:graphics",
        contract().stages[@intFromEnum(Stage.shader_storage_requested)].owner,
    );
}

test "workers that spin for the whole run are never attributed" {
    // Both of these executed continuously through the failing window. The
    // first was its hottest site.
    try std.testing.expect(launchPhaseFor("__ZN13disruptorplus9spin_wait15yield_processorEv") == null);
    try std.testing.expect(idleLoopFor("__ZN13disruptorplus9spin_wait15yield_processorEv") != null);
    try std.testing.expect(launchPhaseFor("__ZN2xe3gpu14GraphicsSystem28GetInternalDisplayResolutionEv") == null);
    try std.testing.expect(idleLoopFor("__ZN2xe3gpu14GraphicsSystem28GetInternalDisplayResolutionEv") != null);
}

test "an attributed owner is either staged or admitted as unmodelled" {
    // The compile-time checks in this file prove it for the whole table; this
    // asserts the spellings a reader is most likely to change by hand.
    try std.testing.expectEqualStrings("xenia:graphics", launch_phase_map.owner(.shader_storage));
    try std.testing.expectEqualStrings("xenia:cpu", launch_phase_map.owner(.guest_translation));
    var declared_graphics = false;
    for (contract().stages) |spec| {
        if (std.mem.eql(u8, spec.owner, "xenia:graphics")) declared_graphics = true;
    }
    try std.testing.expect(declared_graphics);

    // The unmodelled list has to stay an admission of a gap. An entry that has
    // quietly acquired a stage would let a real owner keep reading as
    // unmodelled, so nothing on it may appear in the stage table.
    try std.testing.expect(unstaged_owners.len != 0);
    for (unstaged_owners) |unstaged| {
        try std.testing.expect(unstaged.len != 0);
        for (contract().stages) |spec| {
            std.testing.expect(!std.mem.eql(u8, spec.owner, unstaged)) catch |err| {
                std.debug.print("'{s}' is listed as unmodelled but stage '{s}' declares it\n", .{ unstaged, spec.name });
                return err;
            };
        }
    }

    // The window this whole mechanism exists for is owned by one of them, and
    // by none of the stages the gate can point at.
    const database = launchPhaseFor("__ZN2xe6kernel4util16GameInfoDatabase7GetIconEv") orelse
        return error.TestUnexpectedResult;
    var admitted = false;
    for (unstaged_owners) |unstaged| {
        if (std.mem.eql(u8, unstaged, database.owner)) admitted = true;
    }
    try std.testing.expect(admitted);
}
