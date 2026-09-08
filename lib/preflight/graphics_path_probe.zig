//! Executable readiness checks for the translated graphics paths.
//!
//! `graphics_readiness.zig` answers questions that can be answered from the
//! image before a guest starts.  This module answers the next question: which
//! parts of the frame paths were actually tested at the admission boundary.
//! It intentionally has a different vocabulary from the runtime ledger.  A
//! stage can be untested, not reached because its owner is downstream, or
//! unknown because a probe could not establish an answer.  None of those
//! states is a pass.

const std = @import("std");
const schema = @import("xenia_graphics_health_contract");

pub const Stage = schema.Stage;
pub const Path = schema.Path;
pub const Layer = schema.Layer;
pub const Owner = schema.Owner;
pub const Phase = schema.PreflightPhase;
pub const stage_count = schema.stage_count;
pub const path_count: usize = @typeInfo(Path).@"enum".fields.len;
pub const layer_count: usize = @typeInfo(Layer).@"enum".fields.len;
pub const schema_version: u16 = 2;

pub const State = enum(u8) {
    satisfied,
    degraded,
    blocked,
    untested,
    not_reached,
    unknown,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .satisfied => "satisfied",
            .degraded => "degraded",
            .blocked => "blocked",
            .untested => "untested",
            .not_reached => "not-reached",
            .unknown => "unknown",
        };
    }

    pub fn complete(self: State) bool {
        return self == .satisfied;
    }

    /// Unknown means the probe ran but could not establish a fact.  Untested
    /// and not-reached mean no such probe result exists yet.
    pub fn wasTested(self: State) bool {
        return self != .untested and self != .not_reached;
    }
};

pub const Evidence = struct {
    state: State = .untested,
    detail: []const u8 = "",
    blocked_by: []const u8 = "",
};

fn defaultEvidence() [stage_count]Evidence {
    return [_]Evidence{.{}} ** stage_count;
}

pub const Facts = struct {
    stages: [stage_count]Evidence = defaultEvidence(),

    pub fn set(
        self: *Facts,
        stage: Stage,
        state: State,
        detail: []const u8,
        blocked_by: []const u8,
    ) void {
        self.stages[@intFromEnum(stage)] = .{
            .state = state,
            .detail = detail,
            .blocked_by = blocked_by,
        };
    }

    pub fn evidence(self: *const Facts, stage: Stage) Evidence {
        return self.stages[@intFromEnum(stage)];
    }
};

pub const StageReport = struct {
    stage: Stage,
    state: State,
    owner: Owner,
    layer: Layer,
    phase: Phase,
    probe: []const u8,
    detail: []const u8,
    blocked_by: []const u8,
    next_action: []const u8,
};

pub const PathReport = struct {
    path: Path,
    total: usize = 0,
    satisfied: usize = 0,
    degraded: usize = 0,
    blocked: usize = 0,
    untested: usize = 0,
    not_reached: usize = 0,
    unknown: usize = 0,
    first_missing: ?Stage = null,
    first_actionable: ?Stage = null,
    first_deferred: ?Stage = null,

    pub fn complete(self: PathReport) bool {
        return self.total != 0 and self.satisfied == self.total;
    }

    pub fn tested(self: PathReport) usize {
        return self.total -| self.untested -| self.not_reached;
    }

    pub fn progress(self: PathReport) usize {
        return self.satisfied;
    }

    /// A stage in one of these states needs a concrete next action. A
    /// not-reached stage is different: the probe is intentionally deferred
    /// until its producer exists, so it must not be reported as a failed test.
    pub fn actionable(self: PathReport) usize {
        return self.blocked + self.untested + self.unknown;
    }

    pub fn deferred(self: PathReport) usize {
        return self.not_reached;
    }

    pub fn testedPercent(self: PathReport) usize {
        if (self.total == 0) return 0;
        return self.tested() * 100 / self.total;
    }

    pub fn coveragePercent(self: PathReport) usize {
        if (self.total == 0) return 0;
        return self.satisfied * 100 / self.total;
    }
};

pub const LayerReport = struct {
    layer: Layer,
    total: usize = 0,
    satisfied: usize = 0,
    degraded: usize = 0,
    blocked: usize = 0,
    untested: usize = 0,
    not_reached: usize = 0,
    unknown: usize = 0,
    first_actionable: ?Stage = null,
    first_deferred: ?Stage = null,

    pub fn actionable(self: LayerReport) usize {
        return self.blocked + self.untested + self.unknown;
    }

    pub fn deferred(self: LayerReport) usize {
        return self.not_reached;
    }

    pub fn tested(self: LayerReport) usize {
        return self.total -| self.untested -| self.not_reached;
    }
};

fn defaultLayerReports() [layer_count]LayerReport {
    var result: [layer_count]LayerReport = undefined;
    for (&result, 0..) |*slot, index| slot.* = .{ .layer = @enumFromInt(index) };
    return result;
}

pub const Verdict = enum(u8) {
    ready,
    incomplete,
    blocked,
    unknown,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .ready => "ready",
            .incomplete => "incomplete",
            .blocked => "blocked",
            .unknown => "unknown",
        };
    }
};

fn defaultStageReports() [stage_count]StageReport {
    var result: [stage_count]StageReport = undefined;
    for (&result, 0..) |*slot, index| {
        const stage: Stage = @enumFromInt(index);
        slot.* = .{
            .stage = stage,
            .state = .untested,
            .owner = stage.owner(),
            .layer = stage.layer(),
            .phase = stage.preflightPhase(),
            .probe = stage.preflightProbe(),
            .detail = "",
            .blocked_by = "",
            .next_action = stage.guidance(),
        };
    }
    return result;
}

fn defaultPathReports() [path_count]PathReport {
    var result: [path_count]PathReport = undefined;
    for (&result, 0..) |*slot, index| slot.* = .{ .path = @enumFromInt(index) };
    return result;
}

pub const Report = struct {
    stages: [stage_count]StageReport = defaultStageReports(),
    paths: [path_count]PathReport = defaultPathReports(),
    layers: [layer_count]LayerReport = defaultLayerReports(),
    verdict: Verdict = .incomplete,
    plan_complete: bool = false,
    planned_stages: usize = 0,
    window_gate: bool = false,
    window_gate_first_missing: ?Stage = null,
    window_gate_satisfied: usize = 0,
    window_gate_total: usize = 0,
    total: usize = 0,
    satisfied: usize = 0,
    degraded: usize = 0,
    blocked: usize = 0,
    untested: usize = 0,
    not_reached: usize = 0,
    unknown: usize = 0,
    actionable: usize = 0,
    deferred: usize = 0,
    first_actionable: ?Stage = null,
    first_deferred: ?Stage = null,

    pub fn windowGateAllows(self: *const Report) bool {
        return self.window_gate;
    }

    pub fn stage(self: *const Report, value: Stage) StageReport {
        return self.stages[@intFromEnum(value)];
    }

    pub fn path(self: *const Report, value: Path) PathReport {
        return self.paths[@intFromEnum(value)];
    }

    pub fn tested(self: *const Report) usize {
        return self.total -| self.untested -| self.not_reached;
    }

    pub fn complete(self: *const Report) bool {
        return self.verdict == .ready;
    }

    pub fn testedPercent(self: *const Report) usize {
        if (self.total == 0) return 0;
        return self.tested() * 100 / self.total;
    }

    pub fn coveragePercent(self: *const Report) usize {
        if (self.total == 0) return 0;
        return self.satisfied * 100 / self.total;
    }

    pub fn admissionReason(self: *const Report) []const u8 {
        if (!self.window_gate) {
            if (self.window_gate_first_missing) |missing_stage| return missing_stage.guidance();
            return "the hidden host admission probe did not complete";
        }
        if (self.first_actionable) |actionable_stage| {
            return actionable_stage.guidance();
        }
        if (self.first_deferred != null) {
            return "the host gate is complete; guest-owned stages are deferred until guest start";
        }
        return "all declared preflight stages are satisfied";
    }
};

/// The last host stage is intentionally absent from this gate.  A native
/// presenter can be completely alive before a guest has produced a source
/// image, but claiming `native_present_completed` at that point would turn a
/// host clear or an empty swap into guest output.
pub fn hostWindowGateStages() []const Stage {
    return schema.host_presenter_path[0 .. schema.host_presenter_path.len - 1];
}

fn recordState(report: *Report, state: State) void {
    report.total += 1;
    switch (state) {
        .satisfied => report.satisfied += 1,
        .degraded => report.degraded += 1,
        .blocked => report.blocked += 1,
        .untested => report.untested += 1,
        .not_reached => report.not_reached += 1,
        .unknown => report.unknown += 1,
    }
}

fn recordLayer(report: *LayerReport, stage: Stage, state: State) void {
    report.total += 1;
    switch (state) {
        .satisfied => report.satisfied += 1,
        .degraded => report.degraded += 1,
        .blocked => report.blocked += 1,
        .untested => report.untested += 1,
        .not_reached => {
            report.not_reached += 1;
            if (report.first_deferred == null) report.first_deferred = stage;
        },
        .unknown => report.unknown += 1,
    }
    if ((state == .blocked or state == .untested or state == .unknown) and report.first_actionable == null) {
        report.first_actionable = stage;
    }
}

pub fn evaluate(facts: Facts) Report {
    var report = Report{};
    report.plan_complete = schema.contractIsWellFormed();
    report.planned_stages = stage_count;

    for (facts.stages, 0..) |evidence, index| {
        const stage: Stage = @enumFromInt(index);
        report.stages[index] = .{
            .stage = stage,
            .state = evidence.state,
            .owner = stage.owner(),
            .layer = stage.layer(),
            .phase = stage.preflightPhase(),
            .probe = stage.preflightProbe(),
            .detail = evidence.detail,
            .blocked_by = evidence.blocked_by,
            .next_action = stage.guidance(),
        };
        recordState(&report, evidence.state);
        recordLayer(&report.layers[@intFromEnum(stage.layer())], stage, evidence.state);
        if ((evidence.state == .blocked or evidence.state == .untested or evidence.state == .unknown) and report.first_actionable == null) {
            report.first_actionable = stage;
        }
        if (evidence.state == .not_reached and report.first_deferred == null) {
            report.first_deferred = stage;
        }
    }

    for (0..path_count) |path_index| {
        const path: Path = @enumFromInt(path_index);
        var path_report = PathReport{ .path = path };
        for (schema.stagesFor(path)) |stage| {
            path_report.total += 1;
            const state = report.stages[@intFromEnum(stage)].state;
            switch (state) {
                .satisfied => path_report.satisfied += 1,
                .degraded => path_report.degraded += 1,
                .blocked => path_report.blocked += 1,
                .untested => path_report.untested += 1,
                .not_reached => path_report.not_reached += 1,
                .unknown => path_report.unknown += 1,
            }
            if (!state.complete() and path_report.first_missing == null) {
                path_report.first_missing = stage;
            }
            if ((state == .blocked or state == .untested or state == .unknown) and path_report.first_actionable == null) {
                path_report.first_actionable = stage;
            }
            if (state == .not_reached and path_report.first_deferred == null) {
                path_report.first_deferred = stage;
            }
        }
        report.paths[path_index] = path_report;
    }

    // The global counts are over the unique stage plan; path counts above are
    // intentionally not added to the report counters because paths overlap.
    report.actionable = 0;
    report.deferred = 0;
    for (report.stages) |stage_report| {
        if (stage_report.state == .blocked or stage_report.state == .untested or stage_report.state == .unknown) report.actionable += 1;
        if (stage_report.state == .not_reached) report.deferred += 1;
    }

    report.window_gate = true;
    report.window_gate_total = hostWindowGateStages().len;
    for (hostWindowGateStages()) |stage| {
        if (report.stages[@intFromEnum(stage)].state.complete()) {
            report.window_gate_satisfied += 1;
        } else {
            report.window_gate = false;
            if (report.window_gate_first_missing == null) {
                report.window_gate_first_missing = stage;
            }
        }
    }

    report.verdict = if (!report.plan_complete)
        .blocked
    else if (report.blocked != 0)
        .blocked
    else if (report.unknown != 0)
        .unknown
    else if (report.degraded != 0 or report.untested != 0 or report.not_reached != 0)
        .incomplete
    else
        .ready;
    return report;
}

test "path reports distinguish untested from downstream not-reached" {
    var facts = Facts{};
    facts.set(.guest_image_mapped, .satisfied, "mapped", "");
    facts.set(.guest_vulkan_activity_observed, .not_reached, "guest has not started", "guest start");
    facts.set(.native_application_ready, .unknown, "probe returned no status", "host probe");

    const report = evaluate(facts);
    const guest = report.path(.guest_vulkan);
    try std.testing.expectEqual(@as(usize, 1), guest.satisfied);
    try std.testing.expectEqual(@as(usize, 1), guest.not_reached);
    try std.testing.expectEqual(@as(usize, 2), guest.untested);
    try std.testing.expectEqual(State.not_reached, report.stage(.guest_vulkan_activity_observed).state);
    try std.testing.expectEqual(State.unknown, report.stage(.native_application_ready).state);
    try std.testing.expect(!report.windowGateAllows());
}

test "host window gate requires every tested host stage" {
    var facts = Facts{};
    for (hostWindowGateStages()) |stage| {
        facts.set(stage, .satisfied, "host smoke passed", "");
    }
    facts.set(.native_present_completed, .not_reached, "requires guest-produced pixels", "guest frame source");

    const report = evaluate(facts);
    try std.testing.expect(report.windowGateAllows());
    try std.testing.expect(!report.path(.host_presenter).complete());
    try std.testing.expectEqual(State.not_reached, report.stage(.native_present_completed).state);
    try std.testing.expectEqual(@as(usize, 1), report.path(.host_presenter).not_reached);
}

test "all stages satisfied is the only complete report" {
    var facts = Facts{};
    for (0..stage_count) |index| {
        facts.set(@enumFromInt(index), .satisfied, "verified", "");
    }
    const report = evaluate(facts);
    try std.testing.expect(report.complete());
    try std.testing.expect(report.windowGateAllows());
    try std.testing.expectEqual(Verdict.ready, report.verdict);
    try std.testing.expectEqual(stage_count, report.satisfied);
}

test "the report exposes unique-stage actionability and deferred coverage" {
    var facts = Facts{};
    for (0..stage_count) |index| {
        facts.set(@enumFromInt(index), .not_reached, "guest has not started", "guest start");
    }
    facts.set(.application_started, .satisfied, "identity", "");
    facts.set(.guest_image_mapped, .satisfied, "mapped", "");
    for (hostWindowGateStages()) |stage| {
        facts.set(stage, .satisfied, "host smoke passed", "");
    }
    facts.set(.guest_scheduler_running, .not_reached, "guest has not started", "guest start");
    const report = evaluate(facts);

    try std.testing.expect(report.plan_complete);
    try std.testing.expectEqual(stage_count, report.planned_stages);
    try std.testing.expectEqual(@as(usize, 0), report.actionable);
    try std.testing.expect(report.deferred != 0);
    try std.testing.expectEqual(Stage.guest_scheduler_running, report.first_deferred.?);
    try std.testing.expect(report.windowGateAllows());
    try std.testing.expectEqual(hostWindowGateStages().len, report.window_gate_satisfied);
    try std.testing.expectEqual(hostWindowGateStages().len, report.window_gate_total);
    try std.testing.expectEqual(Phase.host_smoke, report.stage(.native_window_ready).phase);
    try std.testing.expectEqual(Phase.guest_runtime, report.stage(.guest_scheduler_running).phase);
    try std.testing.expect(report.stage(.guest_scheduler_running).probe.len != 0);
    try std.testing.expect(report.stage(.guest_scheduler_running).next_action.len != 0);

    var covered: usize = 0;
    for (report.layers) |layer| covered += layer.total;
    try std.testing.expectEqual(stage_count, covered);
}

test "a host preflight gap is actionable and remains a hard window refusal" {
    var facts = Facts{};
    for (0..stage_count) |index| {
        facts.set(@enumFromInt(index), .not_reached, "guest has not started", "guest start");
    }
    facts.set(.application_started, .satisfied, "identity", "");
    facts.set(.guest_image_mapped, .satisfied, "mapped", "");
    facts.set(.native_application_ready, .blocked, "NSApplication failed", "native application");
    const report = evaluate(facts);

    try std.testing.expectEqual(Verdict.blocked, report.verdict);
    try std.testing.expect(!report.windowGateAllows());
    try std.testing.expectEqual(Stage.native_application_ready, report.first_actionable.?);
    try std.testing.expectEqual(Stage.native_application_ready, report.window_gate_first_missing.?);
    try std.testing.expect(report.stage(.native_application_ready).phase.canRunBeforeGuest());
    try std.testing.expect(std.mem.indexOf(u8, report.admissionReason(), "Cocoa") != null);
}
