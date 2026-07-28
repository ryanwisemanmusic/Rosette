//! Runtime observer for Xenia's startup-to-first-present execution path.
//!
//! Classification is deliberately based on stable subsystem and method names
//! already emitted by Xenia's macOS port.  A stage is evidence, not a repair:
//! Rosette records what Xenia proved and identifies the next missing contract.

const std = @import("std");
const event_log = @import("event_log");
const contracts = @import("xenia_pipeline_contracts.zig");

const machoCapturePrint = event_log.machoCapturePrint;

pub const Stage = contracts.Stage;
pub const Subsystem = contracts.Subsystem;

pub const Observation = struct {
    stage: Stage,
    step: u64,
    first_observation: bool,
    prerequisite_missing: bool,
    previous_frontier: ?Stage,
    frontier: ?Stage,
};

pub const Engine = struct {
    reached: [contracts.stage_count]bool = [_]bool{false} ** contracts.stage_count,
    first_step: [contracts.stage_count]u64 = [_]u64{0} ** contracts.stage_count,
    observations: u64 = 0,
    unique_stages: u64 = 0,
    duplicate_events: u64 = 0,
    out_of_order_events: u64 = 0,
    last_event_step: u64 = 0,
    frontier: ?Stage = null,

    pub fn observeLine(self: *Engine, line: []const u8, step: u64) ?Observation {
        const stage = classifyLine(line) orelse return null;
        self.observations +|= 1;
        self.last_event_step = step;
        const index: usize = @intFromEnum(stage);
        const previous_frontier = self.frontier;
        if (self.reached[index]) {
            self.duplicate_events +|= 1;
            return .{
                .stage = stage,
                .step = step,
                .first_observation = false,
                .prerequisite_missing = false,
                .previous_frontier = previous_frontier,
                .frontier = self.frontier,
            };
        }

        const prerequisite_missing = if (index == 0)
            false
        else
            !self.reached[index - 1];
        if (prerequisite_missing) self.out_of_order_events +|= 1;
        self.reached[index] = true;
        self.first_step[index] = step;
        self.unique_stages +|= 1;
        self.advanceFrontier();
        return .{
            .stage = stage,
            .step = step,
            .first_observation = true,
            .prerequisite_missing = prerequisite_missing,
            .previous_frontier = previous_frontier,
            .frontier = self.frontier,
        };
    }

    pub fn hasReached(self: *const Engine, stage: Stage) bool {
        return self.reached[@intFromEnum(stage)];
    }

    pub fn nextRequired(self: *const Engine) ?Stage {
        return contracts.nextRequiredAfter(self.frontier);
    }

    pub fn nextSubsystem(self: *const Engine) ?Subsystem {
        const next = self.nextRequired() orelse return null;
        return contracts.spec(next).subsystem;
    }

    pub fn stepsSinceProgress(self: *const Engine, current_step: u64) u64 {
        return current_step -| self.lastEventForFrontier();
    }

    pub fn verdict(self: *const Engine) []const u8 {
        if (self.hasReached(.first_present)) return "first frame presented";
        if (self.hasReached(.guest_output_ready)) return "guest output reached presenter; first present not yet proven";
        if (self.hasReached(.guest_main_ready)) return "guest main thread running; GPU ring/output milestones remain";
        if (self.hasReached(.user_module_ready)) return "title image ready; guest main thread not yet proven";
        if (self.hasReached(.emulator_setup_ready)) return "emulator setup ready; title launch not yet proven";
        if (self.hasReached(.kernel_globals_started) and !self.hasReached(.kernel_globals_ready)) {
            return "kernel guest-global initialization entered but did not complete";
        }
        if (self.hasReached(.processor_ready)) return "CPU ready; later emulator setup not yet proven";
        return "early Xenia setup incomplete";
    }

    pub fn logSummary(self: *const Engine, current_step: u64) void {
        if (self.observations == 0) return;
        const next = self.nextRequired();
        machoCapturePrint(
            "macho-processor: Xenia pipeline summary: frontier={s} reached={d}/{d} observations={d} duplicates={d} out_of_order={d} last_progress_step={d} idle_steps={d} next={s} next_subsystem={s} verdict={s}\n",
            .{
                if (self.frontier) |stage| @tagName(stage) else "none",
                self.unique_stages,
                contracts.stage_count,
                self.observations,
                self.duplicate_events,
                self.out_of_order_events,
                self.lastEventForFrontier(),
                self.stepsSinceProgress(current_step),
                if (next) |stage| @tagName(stage) else "none",
                if (next) |stage| @tagName(contracts.spec(stage).subsystem) else "none",
                self.verdict(),
            },
        );
        if (next) |stage| {
            machoCapturePrint(
                "macho-processor: Xenia pipeline next contract: stage={s} subsystem={s} evidence={s}\n",
                .{ @tagName(stage), @tagName(contracts.spec(stage).subsystem), contracts.spec(stage).description },
            );
        }
    }

    fn advanceFrontier(self: *Engine) void {
        var index: usize = 0;
        var contiguous: ?Stage = null;
        while (index < self.reached.len and self.reached[index]) : (index += 1) {
            contiguous = @enumFromInt(index);
        }
        self.frontier = contiguous;
    }

    fn lastEventForFrontier(self: *const Engine) u64 {
        const stage = self.frontier orelse return 0;
        return self.first_step[@intFromEnum(stage)];
    }
};

pub fn classifyLine(line: []const u8) ?Stage {
    if (contains(line, "Initializing Memory")) return .emulator_setup_started;
    if (contains(line, "Initializing Exports")) return .memory_ready;
    if (contains(line, "Processor setup completed successfully") or
        contains(line, "Processor::Setup() completed successfully"))
        return .processor_ready;
    if (contains(line, "Creating patcher")) return .patch_database_ready;
    if (contains(line, "PIPELINE: Kernel guest globals begin")) return .kernel_globals_started;
    if (contains(line, "PIPELINE: Kernel guest globals ready")) return .kernel_globals_ready;
    if (contains(line, "Kernel initialization completed successfully")) return .kernel_modules_ready;
    if (contains(line, "Setting up graphics system")) return .graphics_setup_started;
    if (contains(line, "CommandProcessor::Initialize() SUCCEEDED")) return .command_processor_ready;
    if (contains(line, "Graphics system setup completed successfully")) return .graphics_ready;
    if (contains(line, "Emulator setup completed successfully")) return .emulator_setup_ready;
    if (contains(line, "Emulator::LaunchPath ENTRY")) return .launch_path_started;
    if (contains(line, "LaunchPath: Detected XISO") or
        contains(line, "XISO case detected"))
        return .disc_mounted;
    if (contains(line, "Emulator::CompleteLaunch ENTRY")) return .complete_launch_started;
    if (contains(line, "Module loaded successfully")) return .user_module_loaded;
    if (contains(line, "User module finished loading successfully") or
        contains(line, "module fully ready"))
        return .user_module_ready;
    if (contains(line, "Shader storage init request completed")) return .shader_storage_ready;
    if (contains(line, "Guest main thread ready")) return .guest_main_ready;
    if (contains(line, "CompleteLaunch SUCCEEDED")) return .complete_launch_ready;
    if (contains(line, "RING BUFFER INITIALIZED") or
        contains(line, "InitializeRingBuffer completed"))
        return .ring_buffer_ready;
    if (contains(line, "Created") and contains(line, "swapchain") or
        contains(line, "surface binding validated"))
        return .surface_ready;
    if (contains(line, "first guest output image available")) return .guest_output_ready;
    if (contains(line, "first present SUCCESS")) return .first_present;
    return null;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "pipeline records the setup launch and first-frame frontier" {
    var engine = Engine{};
    const lines = [_][]const u8{
        "Setup: Initializing Memory...",
        "Setup: Initializing Exports...",
        "Setup: Processor setup completed successfully",
        "Setup: Creating patcher...",
        "PIPELINE: Kernel guest globals begin",
        "PIPELINE: Kernel guest globals ready",
        "Setup: Kernel initialization completed successfully",
        "Setup: Setting up graphics system...",
        "DEBUG: CommandProcessor::Initialize() SUCCEEDED!",
        "Setup: Graphics system setup completed successfully",
        "Setup: DEBUG: Emulator setup completed successfully!",
        "DEBUG: Emulator::LaunchPath ENTRY",
        "LaunchPath: Detected XISO",
        "DEBUG: Emulator::CompleteLaunch ENTRY",
        "DEBUG: Module loaded successfully",
        "DEBUG: User module finished loading successfully",
        "DEBUG: Shader storage init request completed",
        "DEBUG: Guest main thread ready",
        "DEBUG: CompleteLaunch SUCCEEDED",
        "RING BUFFER INITIALIZED",
        "VulkanPresenter: Created 1280x720 swapchain",
        "DEBUG: VulkanPresenter: first guest output image available",
        "DEBUG: VulkanPresenter: first present SUCCESS",
    };
    for (lines, 0..) |line, index| {
        const observation = engine.observeLine(line, index + 1) orelse
            return error.TestUnexpectedResult;
        try std.testing.expect(observation.first_observation);
        try std.testing.expect(!observation.prerequisite_missing);
    }
    try std.testing.expectEqual(Stage.first_present, engine.frontier.?);
    try std.testing.expect(engine.nextRequired() == null);
    try std.testing.expectEqualStrings("first frame presented", engine.verdict());
}

test "pipeline keeps a missing kernel-global completion visible" {
    var engine = Engine{};
    _ = engine.observeLine("Setup: Initializing Memory...", 10).?;
    _ = engine.observeLine("Setup: Initializing Exports...", 20).?;
    _ = engine.observeLine("Setup: Processor setup completed successfully", 30).?;
    _ = engine.observeLine("Setup: Creating patcher...", 40).?;
    _ = engine.observeLine("PIPELINE: Kernel guest globals begin", 50).?;
    try std.testing.expectEqual(Stage.kernel_globals_started, engine.frontier.?);
    try std.testing.expectEqual(Stage.kernel_globals_ready, engine.nextRequired().?);
    try std.testing.expectEqual(Subsystem.kernel, engine.nextSubsystem().?);
}
