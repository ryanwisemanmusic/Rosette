//! Runtime observer for Xenia's startup-to-first-present execution path.
//!
//! Classification is deliberately based on stable subsystem and method names
//! already emitted by Xenia's macOS port.  A stage is evidence, not a repair:
//! Rosette records what Xenia proved and identifies the next missing contract.

const std = @import("std");
const event_log = @import("event_log");
const contracts = @import("xenia_pipeline_contracts.zig");
const shader_storage_contract = @import("xenia_shader_storage_contract");
/// Which phrase witnesses which stage is fixed when Xenia is compiled, so the
/// table and its rare-character filter are resolved at build time rather than
/// re-walked per log line. What stays here is the part that needs the run:
/// ordering, prerequisites, and whether an observation is accepted.
const phrase_map = @import("xenia_log_phrase_map");

const machoCapturePrint = event_log.machoCapturePrint;

pub const Stage = contracts.Stage;

comptime {
    // The package and the contract each declare the stage vocabulary, and a
    // rename on either side would otherwise leave rules that can never fire
    // and a frontier that silently reports an earlier stage than the run
    // reached. Matching by name and position makes that a build error.
    const package_fields = std.meta.fields(phrase_map.Stage);
    const contract_fields = std.meta.fields(contracts.Stage);
    if (package_fields.len != contract_fields.len) {
        @compileError("xenia log-phrase package and pipeline contract disagree on the stage count");
    }
    for (package_fields, contract_fields) |package_field, contract_field| {
        if (!std.mem.eql(u8, package_field.name, contract_field.name)) {
            @compileError(
                "xenia log-phrase package stage '" ++ package_field.name ++
                    "' does not match contract stage '" ++ contract_field.name ++ "'",
            );
        }
        if (package_field.value != contract_field.value) {
            @compileError("xenia log-phrase package stage '" ++ package_field.name ++ "' has a different ordinal");
        }
    }
}
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
    title_launch_failed: bool = false,
    title_path_empty: bool = false,
    gpu_callback_import_ready: bool = false,
    gpu_callback_registration_pending: bool = false,
    gpu_callback_registered: bool = false,
    gpu_callback_pending_events: u64 = 0,
    gpu_callback_first_pending_step: u64 = 0,
    gpu_callback_registered_step: u64 = 0,
    shader_storage_timeout_continuation: bool = false,

    pub fn observeLine(self: *Engine, line: []const u8, step: u64) ?Observation {
        self.observeGpuCallbackContract(line, step);
        if (contains(line, "Shader storage blocking wait timed out")) {
            self.shader_storage_timeout_continuation = true;
        }
        if (contains(line, "Failed to launch title path is empty") or
            contains(line, "DEBUG: TARGET PATH: ''"))
        {
            self.title_launch_failed = true;
            self.title_path_empty = true;
        } else if ((contains(line, "RunTitle returned:") or
            contains(line, "RunTitle returned result:")) and
            contains(line, "not X_STATUS_SUCCESS"))
        {
            self.title_launch_failed = true;
        } else if (contains(line, "CompleteLaunch SUCCEEDED")) {
            self.title_launch_failed = false;
            self.title_path_empty = false;
        }

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

        const prerequisite_missing = !self.prerequisitesSatisfied(stage);
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

    /// A request-return log is not enough to prove shader storage. Xenia's
    /// macOS path can return after its blocking wait times out, then let the
    /// launch path continue. Only the GPU-thread completion line is a real
    /// ready edge; the package keeps the timeout as a separate verdict.
    pub fn shaderStorageVerdict(self: *const Engine) shader_storage_contract.Verdict {
        var observed: u8 = 0;
        if (self.hasReached(.user_module_ready)) observed |= shader_storage_contract.stageBit(.user_module_ready);
        if (self.hasReached(.shader_storage_requested)) observed |= shader_storage_contract.stageBit(.shader_storage_requested);
        if (self.hasReached(.shader_storage_ready)) observed |= shader_storage_contract.stageBit(.shader_storage_ready);
        if (self.hasReached(.guest_main_ready)) observed |= shader_storage_contract.stageBit(.guest_main_ready);
        return shader_storage_contract.classify(observed, .blocking, self.shader_storage_timeout_continuation);
    }

    pub fn stepsSinceProgress(self: *const Engine, current_step: u64) u64 {
        return current_step -| self.lastEventForFrontier();
    }

    pub fn verdict(self: *const Engine) []const u8 {
        if (self.hasReached(.first_present)) {
            return "presentation API returned success; visible drawable pixels are not independently proven";
        }
        if (self.title_path_empty and !self.hasReached(.user_module_ready)) {
            return "title launch failed because the target path became empty; prelaunch graphics readiness cannot produce a frame";
        }
        if (self.title_launch_failed and !self.hasReached(.user_module_ready)) {
            return "title launch failed; no guest frame can be produced";
        }
        if (self.hasReached(.guest_output_ready)) return "guest output reached presenter; first present not yet proven";
        if (self.hasReached(.guest_main_ready) and
            self.gpu_callback_registration_pending and
            !self.gpu_callback_registered)
        {
            return if (self.gpu_callback_import_ready)
                "guest main thread running; GPU callback import is ready and guest callback registration is pending"
            else
                "guest main thread running; guest GPU callback registration is pending and import readiness is unproven";
        }
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
            "macho-processor: Xenia pipeline summary: frontier={s} reached={d}/{d} observations={d} duplicates={d} out_of_order={d} title_launch_failed={} title_path_empty={} last_progress_step={d} idle_steps={d} next={s} next_subsystem={s} verdict={s}\n",
            .{
                if (self.frontier) |stage| @tagName(stage) else "none",
                self.unique_stages,
                contracts.stage_count,
                self.observations,
                self.duplicate_events,
                self.out_of_order_events,
                self.title_launch_failed,
                self.title_path_empty,
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
        machoCapturePrint(
            "macho-processor: Xenia GPU callback contract: import_ready={} registration_pending={} registered={} pending_events={d} first_pending_step={d} registered_step={d}\n",
            .{
                self.gpu_callback_import_ready,
                self.gpu_callback_registration_pending,
                self.gpu_callback_registered,
                self.gpu_callback_pending_events,
                self.gpu_callback_first_pending_step,
                self.gpu_callback_registered_step,
            },
        );
    }

    fn observeGpuCallbackContract(self: *Engine, line: []const u8, step: u64) void {
        const import_probe_ready =
            contains(line, "callback-missing import probe ordinal=0x1D5") and
            contains(line, "thunk_sc2_stub=YES");
        const import_gate_ready =
            contains(line, "critical GPU static import probes are valid") and
            contains(line, "probe_01D5=READY");
        const export_implementation_ready =
            contains(line, "export verify critical ordinal=0x1D5") and
            contains(line, "VdSetGraphicsInterruptCallback") and
            contains(line, "implemented=YES");
        const preinitialized_import_ready =
            contains(line, "VdSetGraphicsInterruptCallback import is preinitialized");
        if (import_probe_ready or import_gate_ready or
            export_implementation_ready or preinitialized_import_ready)
        {
            self.gpu_callback_import_ready = true;
        }

        const registration_pending =
            contains(line, "GPU interrupt callback not set") or
            contains(line, "GPU interrupt callback registration pending");
        if (registration_pending and !self.gpu_callback_registered) {
            self.gpu_callback_registration_pending = true;
            self.gpu_callback_pending_events +|= 1;
            if (self.gpu_callback_first_pending_step == 0) {
                self.gpu_callback_first_pending_step = step;
            }
        }

        const registration_executed =
            contains(line, "VdSetGraphicsInterruptCallback EXECUTED:") or
            contains(line, "GPU interrupt callback set #");
        if (registration_executed) {
            self.gpu_callback_registered = true;
            self.gpu_callback_registration_pending = false;
            if (self.gpu_callback_registered_step == 0) {
                self.gpu_callback_registered_step = step;
            }
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

    fn prerequisitesSatisfied(self: *const Engine, stage: Stage) bool {
        var required = contracts.prerequisites(stage);
        var index: usize = 0;
        while (required != 0) : (index += 1) {
            if ((required & 1) != 0 and !self.reached[index]) return false;
            required >>= 1;
        }
        return true;
    }

    fn lastEventForFrontier(self: *const Engine) u64 {
        const stage = self.frontier orelse return 0;
        return self.first_step[@intFromEnum(stage)];
    }
};

/// The stage a Xenia log line witnesses, or null.
///
/// The 33 sequential substring searches this used to run moved into
/// `pkg/common/xenia/log-phrase-map`, which rejects a phrase with a single bit
/// test when the line cannot contain it. Null stays the overwhelmingly common
/// answer and is now much cheaper to reach, which matters because this runs on
/// every guest log line.
pub fn classifyLine(line: []const u8) ?Stage {
    const stage = phrase_map.classify(line) orelse return null;
    // Same vocabulary, proven identical by the comptime block above.
    return @enumFromInt(@intFromEnum(stage));
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
        "[DEBUG] KernelState::FinishLoadingUserModule stage=Precompile.begin",
        "[DEBUG] KernelState::FinishLoadingUserModule stage=Precompile.end",
        "DEBUG: User module finished loading successfully",
        "DEBUG: Initializing shader storage...",
        "DEBUG: GPU THREAD: Shader storage initialization completed!",
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
    try std.testing.expectEqualStrings(
        "presentation API returned success; visible drawable pixels are not independently proven",
        engine.verdict(),
    );
}

test "first guest execution proves the main thread even without a breadcrumb" {
    var engine = Engine{};
    const observation = engine.observeLine(
        "[xenia] i> GUEST EXECUTE: fid=0 address=82582A98 thread_id=5",
        624_000_000,
    ) orelse return error.TestExpectedEqual;

    try std.testing.expectEqual(Stage.guest_main_ready, observation.stage);
    try std.testing.expect(engine.hasReached(.guest_main_ready));
}

test "shader storage request return is not completion after a timeout" {
    var engine = Engine{};
    _ = engine.observeLine("DEBUG: User module finished loading successfully", 10).?;
    _ = engine.observeLine("DEBUG: Initializing shader storage...", 20).?;
    try std.testing.expect(engine.observeLine(
        "DEBUG: Shader storage blocking wait timed out; continuing launch",
        30,
    ) == null);
    try std.testing.expect(engine.observeLine(
        "DEBUG: Shader storage init request completed in 5001 ms (blocking=YES)",
        31,
    ) == null);
    try std.testing.expectEqual(
        shader_storage_contract.Verdict.explicit_timeout_continuation,
        engine.shaderStorageVerdict(),
    );
    try std.testing.expect(engine.frontier == null);
    try std.testing.expectEqual(
        Stage.shader_storage_ready,
        classifyLine("DEBUG: GPU THREAD: Shader storage initialization completed!").?,
    );
}

test "pipeline recognizes the Xenia ring-buffer completion breadcrumb" {
    try std.testing.expectEqual(
        Stage.ring_buffer_ready,
        classifyLine(
            "RING BUFFER: InitializeRingBuffer COMPLETE rb_base=FFAA9000 rb_size=00200000 read_ptr=00000000 write_ptr=00000000 init=YES",
        ).?,
    );
}

test "pipeline distinguishes callback import readiness from guest registration" {
    var engine = Engine{};
    const setup_lines = [_][]const u8{
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
        "[DEBUG] KernelState::FinishLoadingUserModule stage=Precompile.begin",
        "[DEBUG] KernelState::FinishLoadingUserModule stage=Precompile.end",
        "DEBUG: User module finished loading successfully",
        "DEBUG: Initializing shader storage...",
        "DEBUG: GPU THREAD: Shader storage initialization completed!",
        "DEBUG: Guest main thread ready",
        "DEBUG: CompleteLaunch SUCCEEDED",
    };
    for (setup_lines, 0..) |line, index| {
        _ = engine.observeLine(line, index + 1).?;
    }
    try std.testing.expect(engine.observeLine(
        "RING BUFFER: callback-missing import probe ordinal=0x1D5 name=VdSetGraphicsInterruptCallback thunk_sc2_stub=YES",
        30,
    ) == null);
    try std.testing.expect(engine.observeLine(
        "RING BUFFER: GPU interrupt callback registration pending during guest bootstrap grace",
        31,
    ) == null);
    try std.testing.expect(engine.gpu_callback_import_ready);
    try std.testing.expect(engine.gpu_callback_registration_pending);
    try std.testing.expect(!engine.gpu_callback_registered);
    try std.testing.expectEqual(@as(u64, 31), engine.gpu_callback_first_pending_step);
    try std.testing.expectEqualStrings(
        "guest main thread running; GPU callback import is ready and guest callback registration is pending",
        engine.verdict(),
    );

    try std.testing.expect(engine.observeLine(
        "VdSetGraphicsInterruptCallback EXECUTED: cb=82590000 arg=00000000",
        40,
    ) == null);
    try std.testing.expect(engine.gpu_callback_registered);
    try std.testing.expect(!engine.gpu_callback_registration_pending);
    try std.testing.expectEqual(@as(u64, 40), engine.gpu_callback_registered_step);
}

test "pipeline recognizes implemented callback export before registration" {
    var engine = Engine{};
    try std.testing.expect(engine.observeLine(
        "RING BUFFER: export verify critical ordinal=0x1D5 required_name=VdSetGraphicsInterruptCallback export_name=VdSetGraphicsInterruptCallback state=ordinal-match type=function implemented=YES",
        10,
    ) == null);
    try std.testing.expect(engine.gpu_callback_import_ready);

    try std.testing.expect(engine.observeLine(
        "RING BUFFER: GPU interrupt callback registration pending during guest bootstrap grace (vblank_id=1 age=0ms grace=500ms); VdSetGraphicsInterruptCallback import is preinitialized",
        20,
    ) == null);
    try std.testing.expect(engine.gpu_callback_registration_pending);
    try std.testing.expect(engine.gpu_callback_import_ready);
}

test "pipeline reports an empty RunTitle path as the frame blocker" {
    var engine = Engine{};
    _ = engine.observeLine("Setup: Initializing Memory...", 10).?;
    _ = engine.observeLine("Setup: Initializing Exports...", 20).?;
    _ = engine.observeLine("Setup: Processor setup completed successfully", 30).?;
    try std.testing.expect(engine.observeLine(
        "Failed to launch title path is empty.",
        40,
    ) == null);
    try std.testing.expect(engine.title_launch_failed);
    try std.testing.expect(engine.title_path_empty);
    try std.testing.expectEqualStrings(
        "title launch failed because the target path became empty; prelaunch graphics readiness cannot produce a frame",
        engine.verdict(),
    );
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
