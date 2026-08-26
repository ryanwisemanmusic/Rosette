//! Runtime evidence ledger for the complete translated-graphics path.
//!
//! The immutable stage/path vocabulary lives in
//! `pkg/common/xenia/graphics-health-contract`.  This file owns only mutable
//! observations: status, source, step stamps, counts and a bounded note.  It
//! is deliberately separate from the existing graphics and VdSwap ledgers so
//! that a historical milestone in one subsystem cannot silently satisfy a
//! different path.

const std = @import("std");
const schema = @import("xenia_graphics_health_contract");

pub const Stage = schema.Stage;
pub const Path = schema.Path;
pub const Layer = schema.Layer;
pub const schema_version = schema.schema_version;

pub const State = enum(u8) {
    /// The run has not exercised this edge.
    untested,
    /// The edge was observed and is currently healthy.
    satisfied,
    /// The edge is callable or partially present, but its consequence is not
    /// proven. This must never count as a complete path.
    degraded,
    /// The edge was exercised or required and is currently blocking progress.
    blocked,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .untested => "untested",
            .satisfied => "satisfied",
            .degraded => "degraded",
            .blocked => "blocked",
        };
    }

    pub fn complete(self: State) bool {
        return self == .satisfied;
    }
};

pub const Source = enum(u8) {
    process,
    kernel_surface,
    scheduler,
    native_window,
    vulkan_forwarder,
    native_presenter,
    xenos_runtime,
    ring_publication,
    pm4_contract,
    vd_swap_contract,
    causal_trace,
    guest_log,
    deadlock_predictor,
    controller,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .process => "process",
            .kernel_surface => "kernel_surface",
            .scheduler => "scheduler",
            .native_window => "native_window",
            .vulkan_forwarder => "vulkan_forwarder",
            .native_presenter => "native_presenter",
            .xenos_runtime => "xenos_runtime",
            .ring_publication => "ring_publication",
            .pm4_contract => "pm4_contract",
            .vd_swap_contract => "vd_swap_contract",
            .causal_trace => "causal_trace",
            .guest_log => "guest_log",
            .deadlock_predictor => "deadlock_predictor",
            .controller => "controller",
        };
    }
};

pub const source_count: usize = @typeInfo(Source).@"enum".fields.len;
pub const max_note_bytes: usize = 144;

pub const Entry = struct {
    state: State = .untested,
    source_mask: u32 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    count: u64 = 0,
    note_storage: [max_note_bytes]u8 = [_]u8{0} ** max_note_bytes,
    note_length: u8 = 0,

    pub fn note(self: *const Entry) []const u8 {
        return self.note_storage[0..self.note_length];
    }

    pub fn hasSource(self: *const Entry, source: Source) bool {
        return self.source_mask & sourceBit(source) != 0;
    }
};

pub const PathReport = struct {
    path: Path,
    total: usize = 0,
    satisfied: usize = 0,
    degraded: usize = 0,
    blocked: usize = 0,
    untested: usize = 0,
    first_missing: ?Stage = null,

    pub fn complete(self: PathReport) bool {
        return self.total != 0 and self.satisfied == self.total;
    }

    pub fn observed(self: PathReport) usize {
        return self.satisfied + self.degraded + self.blocked;
    }

    pub fn percent(self: PathReport) usize {
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

    pub fn percent(self: LayerReport) usize {
        if (self.total == 0) return 0;
        return self.satisfied * 100 / self.total;
    }
};

pub const Report = struct {
    total: usize = 0,
    satisfied: usize = 0,
    degraded: usize = 0,
    blocked: usize = 0,
    untested: usize = 0,

    pub fn percent(self: Report) usize {
        if (self.total == 0) return 0;
        return self.satisfied * 100 / self.total;
    }
};

fn sourceBit(source: Source) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(source)));
}

/// The live ledger is intentionally fixed-size. A stalled title must remain
/// diagnosable when the allocator, filesystem and guest are all unhealthy.
pub const Ledger = struct {
    entries: [schema.stage_count]Entry = [_]Entry{.{}} ** schema.stage_count,
    updates: u64 = 0,

    /// Record the strongest evidence currently known for a stage. Satisfied
    /// evidence is sticky: a later diagnostic refresh cannot make a completed
    /// native operation disappear. Degraded/blocked evidence may be upgraded
    /// by a later authentic observation.
    pub fn record(
        self: *Ledger,
        stage: Stage,
        state: State,
        step: u64,
        source: Source,
        count: u64,
        note: []const u8,
    ) void {
        if (state == .untested) return;
        const record_entry = &self.entries[@intFromEnum(stage)];
        if (record_entry.state != .satisfied or state == .satisfied) record_entry.state = state;
        record_entry.source_mask |= sourceBit(source);
        if (record_entry.first_step == 0 or (step != 0 and step < record_entry.first_step)) record_entry.first_step = step;
        if (step > record_entry.last_step) record_entry.last_step = step;
        if (count > record_entry.count) record_entry.count = count;
        if (record_entry.count == 0) record_entry.count = 1;
        const length = @min(note.len, record_entry.note_storage.len);
        @memset(&record_entry.note_storage, 0);
        @memcpy(record_entry.note_storage[0..length], note[0..length]);
        record_entry.note_length = @intCast(length);
        self.updates +|= 1;
    }

    pub fn status(self: *const Ledger, stage: Stage) State {
        return self.entries[@intFromEnum(stage)].state;
    }

    pub fn entry(self: *const Ledger, stage: Stage) *const Entry {
        return &self.entries[@intFromEnum(stage)];
    }

    pub fn observedMask(self: *const Ledger) u64 {
        var mask: u64 = 0;
        for (self.entries, 0..) |entry_value, index| {
            if (entry_value.state != .untested) mask |= @as(u64, 1) << @as(u6, @intCast(index));
        }
        return mask;
    }

    pub fn satisfiedMask(self: *const Ledger) u64 {
        var mask: u64 = 0;
        for (self.entries, 0..) |entry_value, index| {
            if (entry_value.state == .satisfied) mask |= @as(u64, 1) << @as(u6, @intCast(index));
        }
        return mask;
    }

    pub fn pathReport(self: *const Ledger, path: Path) PathReport {
        var path_report = PathReport{ .path = path };
        for (schema.stagesFor(path)) |stage| {
            path_report.total += 1;
            const state = self.status(stage);
            switch (state) {
                .satisfied => path_report.satisfied += 1,
                .degraded => path_report.degraded += 1,
                .blocked => path_report.blocked += 1,
                .untested => path_report.untested += 1,
            }
            if (state != .satisfied and path_report.first_missing == null) path_report.first_missing = stage;
        }
        return path_report;
    }

    pub fn layerReport(self: *const Ledger, layer: Layer) LayerReport {
        var layer_report = LayerReport{ .layer = layer };
        for (self.entries, 0..) |entry_value, index| {
            const stage: Stage = @enumFromInt(@as(u8, @intCast(index)));
            if (stage.layer() != layer) continue;
            layer_report.total += 1;
            switch (entry_value.state) {
                .satisfied => layer_report.satisfied += 1,
                .degraded => layer_report.degraded += 1,
                .blocked => layer_report.blocked += 1,
                .untested => layer_report.untested += 1,
            }
        }
        return layer_report;
    }

    pub fn report(self: *const Ledger) Report {
        var result = Report{};
        for (self.entries) |entry_value| {
            result.total += 1;
            switch (entry_value.state) {
                .satisfied => result.satisfied += 1,
                .degraded => result.degraded += 1,
                .blocked => result.blocked += 1,
                .untested => result.untested += 1,
            }
        }
        return result;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 14_695_981_039_346_656_037;
        for (self.entries, 0..) |entry_value, index| {
            hash ^= @as(u64, @intFromEnum(entry_value.state)) + @as(u64, @intCast(index));
            hash *%= 1_099_511_628_211;
            hash ^= entry_value.source_mask;
            hash *%= 1_099_511_628_211;
        }
        return hash;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        const summary = self.report();
        if (summary.satisfied == 0 and summary.degraded == 0 and summary.blocked == 0)
            return "no graphics edge has been exercised yet";
        if (summary.blocked != 0) return "one or more graphics edges are explicitly blocked";
        if (summary.degraded != 0) return "the graphics surface is callable but at least one consequence is unproven";
        return "every observed graphics edge is healthy; untested edges remain unknown";
    }
};

test "a complete host path does not satisfy the Xenos path" {
    var ledger = Ledger{};
    for (schema.stagesFor(.host_presenter)) |stage| {
        ledger.record(stage, .satisfied, 10, .native_presenter, 1, "native evidence");
    }
    const host = ledger.pathReport(.host_presenter);
    const xenos = ledger.pathReport(.xenos_pm4);
    try std.testing.expect(host.complete());
    try std.testing.expect(!xenos.complete());
    try std.testing.expectEqual(State.untested, ledger.status(.render_target_memory_observed));
}

test "degraded and blocked evidence never closes a path" {
    var ledger = Ledger{};
    ledger.record(.application_started, .satisfied, 1, .process, 1, "run identity");
    ledger.record(.native_application_ready, .satisfied, 2, .native_window, 1, "NSApplication");
    ledger.record(.native_window_ready, .degraded, 3, .native_window, 1, "window token only");
    ledger.record(.native_layer_attached, .blocked, 4, .native_window, 1, "layer missing");
    const report = ledger.pathReport(.host_presenter);
    try std.testing.expect(!report.complete());
    try std.testing.expectEqual(@as(usize, 1), report.degraded);
    try std.testing.expectEqual(@as(usize, 1), report.blocked);
    try std.testing.expectEqual(Stage.native_window_ready, report.first_missing.?);
}

test "records retain source, count, first step and latest step" {
    var ledger = Ledger{};
    ledger.record(.pm4_stream_observed, .satisfied, 100, .pm4_contract, 24, "24 packets");
    ledger.record(.pm4_stream_observed, .satisfied, 200, .xenos_runtime, 48, "48 packets");
    const entry = ledger.entry(.pm4_stream_observed);
    try std.testing.expectEqual(@as(u64, 100), entry.first_step);
    try std.testing.expectEqual(@as(u64, 200), entry.last_step);
    try std.testing.expectEqual(@as(u64, 48), entry.count);
    try std.testing.expect(entry.hasSource(.pm4_contract));
    try std.testing.expect(entry.hasSource(.xenos_runtime));
    try std.testing.expectEqualStrings("48 packets", entry.note());
}

test "the ledger explicitly exposes the untested state" {
    const ledger = Ledger{};
    const report = ledger.report();
    try std.testing.expectEqual(schema.stage_count, report.total);
    try std.testing.expectEqual(schema.stage_count, report.untested);
    try std.testing.expectEqual(@as(usize, 0), report.percent());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "has been exercised") != null);
}
