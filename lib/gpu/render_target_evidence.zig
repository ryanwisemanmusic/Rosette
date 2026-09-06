//! Whether a draw actually landed somewhere, tracked independently of the
//! draw counter.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run entered `IssueDraw` twenty-four times, and:
//!
//! * all twenty-four exited at `no_rasterization_no_memexport`;
//! * the render-target cache was entered zero times;
//! * target registers `0x2000`, `0x2001` and `0x2002` were never written;
//! * no EDRAM write and no resolve was observed;
//! * twenty-four draw completions were nevertheless counted.
//!
//! A draw count is not a pixel count, and a completion from a modelled draw
//! path is not evidence that a hardware-equivalent completion reached the
//! guest. Both of those numbers looked healthy while nothing rendered.
//!
//! So the verdicts here are separate on purpose. `state_programmed` and
//! `rasterization_executed` are different questions with different owners, and
//! a run that can answer the first and not the second is in a completely
//! different place from one that can answer neither. The audit's acceptance
//! criterion — a controlled clear or triangle that programs state, updates the
//! cache, changes EDRAM, resolves to guest memory, changes a checksum there,
//! and reaches frame custody without a synthetic swap — is six of these
//! verdicts in a row, and nothing here lets one of them imply another.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;
pub const Address = bridge.contract.Address;

/// The independent questions about one draw or resolve. Each is proven on its
/// own evidence; reaching one never implies the one before it.
pub const Verdict = enum(u8) {
    /// Valid colour/depth/surface registers were decoded.
    state_programmed = 0,
    /// A target with a readable destination was bound.
    target_memory_bound = 1,
    /// Rasterization actually ran, as opposed to being possible.
    rasterization_executed = 2,
    /// EDRAM or the modelled target changed.
    edram_modified = 3,
    /// A resolve wrote into a guest-visible range.
    resolved_to_guest_memory = 4,
    /// The resolved range was published as a frame candidate.
    frame_candidate_published = 5,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .state_programmed => "state programmed",
            .target_memory_bound => "target memory bound",
            .rasterization_executed => "rasterization executed",
            .edram_modified => "EDRAM modified",
            .resolved_to_guest_memory => "resolved to guest memory",
            .frame_candidate_published => "frame candidate published",
        };
    }

    pub fn owner(self: Verdict) []const u8 {
        return switch (self) {
            .state_programmed => "guest:title",
            .target_memory_bound, .rasterization_executed, .edram_modified => "emulator:gpu",
            .resolved_to_guest_memory => "emulator:gpu",
            .frame_candidate_published => "emulator:gpu",
        };
    }

    pub fn gapMeans(self: Verdict) []const u8 {
        return switch (self) {
            .state_programmed => "no draw has programmed a valid colour, depth or surface register. The title has not named a destination, and every verdict below this is unreachable rather than failing",
            .target_memory_bound => "target state was programmed and no target with a readable destination was bound. The registers name somewhere the cache could not turn into memory",
            .rasterization_executed => "a target is bound and nothing rasterized into it. Either the draws were configured not to rasterize — which is a title decision and normal for a state batch — or the pipeline refused them",
            .edram_modified => "rasterization ran and the target's contents did not change. A draw that writes nothing is a real thing; a draw that should have written and did not is the emulator's",
            .resolved_to_guest_memory => "the target changed and nothing copied it into guest-visible memory. The picture exists where the title cannot reach it",
            .frame_candidate_published => "guest memory holds resolved content and nothing offered it as a frame. The image exists and the custody chain never started",
        };
    }
};

pub const verdict_count: usize = @typeInfo(Verdict).@"enum".fields.len;

/// Why a draw did not produce output. Named rather than counted, because
/// "twenty-four draws, nothing rendered" and "twenty-four draws that the title
/// configured to render nothing" are opposite findings with the same counter.
pub const Classification = enum(u8) {
    /// Rasterized into a bound target.
    target_backed = 0,
    /// Wrote to memory through shader export rather than a target.
    memory_export = 1,
    /// Copied or resolved without rasterizing.
    resolve_only = 2,
    /// Configured by the title to have no output. Normal, and it may not
    /// satisfy a frame or completion gate.
    intentional_no_output = 3,
    /// The emulator dropped it. This is a defect and it is the emulator's.
    emulator_dropped = 4,
    /// Nobody said.
    unclassified = 255,

    pub fn label(self: Classification) []const u8 {
        return switch (self) {
            .target_backed => "target-backed",
            .memory_export => "memory-export",
            .resolve_only => "resolve-only",
            .intentional_no_output => "intentional-no-output",
            .emulator_dropped => "EMULATOR-DROPPED",
            .unclassified => "UNCLASSIFIED",
        };
    }

    /// Whether a draw of this kind may satisfy a frame or draw-completion gate.
    /// No-output work is normal and must not close the render path.
    pub fn satisfiesOutputGate(self: Classification) bool {
        return self == .target_backed or self == .memory_export or self == .resolve_only;
    }

    pub fn isDefect(self: Classification) bool {
        return self == .emulator_dropped or self == .unclassified;
    }
};

/// The decoded destination one draw named.
pub const TargetState = struct {
    color_info: u32 = 0,
    depth_info: u32 = 0,
    surface_info: u32 = 0,
    color_valid: bool = false,
    depth_valid: bool = false,
    surface_valid: bool = false,
    edram_base: u32 = 0,
    format: u32 = 0,
    pitch: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    /// Xenos MSAA mode as programmed.
    msaa: u8 = 0,
    tiled: bool = false,
    slice: u32 = 0,
    guest_destination: Address = .{},

    /// Whether the registers describe somewhere real. A target with a valid
    /// register and a zero extent is a decoded value, not a destination.
    pub fn programmed(self: TargetState) bool {
        return (self.color_valid or self.depth_valid) and
            self.surface_valid and
            self.width != 0 and
            self.height != 0;
    }
};

/// Rasterization inputs, which decide whether a draw could produce anything.
pub const RasterState = struct {
    viewport_width: u32 = 0,
    viewport_height: u32 = 0,
    scissor_width: u32 = 0,
    scissor_height: u32 = 0,
    primitive_type: u32 = 0,
    rasterization_enabled: bool = false,
    memexport_ranges: u32 = 0,
    memexport_bytes_written: u64 = 0,
    vertex_shader_id: u64 = 0,
    pixel_shader_id: u64 = 0,
    vertex_shader_translated: bool = false,
    pixel_shader_translated: bool = false,

    /// Whether anything could have been produced. Deliberately not "did":
    /// this is the question `IssueDraw` answers before it consults the cache,
    /// and the audit's whole point is that the two are different.
    pub fn couldProduceOutput(self: RasterState) bool {
        if (self.memexport_ranges != 0) return true;
        if (!self.rasterization_enabled) return false;
        if (self.scissor_width == 0 or self.scissor_height == 0) return false;
        return self.viewport_width != 0 and self.viewport_height != 0;
    }
};

/// One draw or resolve, tracked across every verdict.
pub const Candidate = struct {
    id: u64 = 0,
    guest_step: u64 = 0,
    source: SourceClass = .unknown,
    target: TargetState = .{},
    raster: RasterState = .{},
    classification: Classification = .unclassified,
    reached: [verdict_count]bool = [_]bool{false} ** verdict_count,
    /// Content generation and checksum before and after, which is the only
    /// evidence that something changed rather than being written with what it
    /// already held.
    content_before: u64 = 0,
    content_after: u64 = 0,
    content_sampled: bool = false,
    resolve_destination: Address = .{},
    resolve_bytes: u64 = 0,

    pub fn note(self: *Candidate, verdict: Verdict) void {
        self.reached[@intFromEnum(verdict)] = true;
    }

    pub fn has(self: Candidate, verdict: Verdict) bool {
        return self.reached[@intFromEnum(verdict)];
    }

    /// Whether the content actually changed. An unsampled candidate has not
    /// answered the question, which is not the same as answering "no".
    pub fn contentChanged(self: Candidate) bool {
        return self.content_sampled and self.content_before != self.content_after;
    }

    pub fn firstGap(self: Candidate) ?Verdict {
        var index: usize = 0;
        while (index < verdict_count) : (index += 1) {
            if (!self.reached[index]) return @enumFromInt(index);
        }
        return null;
    }

    /// The audit's controlled-vector criterion: six verdicts in a row, with a
    /// content change proven and no synthetic source anywhere.
    pub fn provesFirstPixel(self: Candidate) bool {
        return self.firstGap() == null and
            self.contentChanged() and
            self.source == .guest_authentic;
    }
};

pub const max_candidates: usize = 48;

pub const Summary = struct {
    candidates: u64 = 0,
    retained: usize = 0,
    dropped: u64 = 0,
    target_backed: u64 = 0,
    memory_export: u64 = 0,
    resolve_only: u64 = 0,
    intentional_no_output: u64 = 0,
    emulator_dropped: u64 = 0,
    unclassified: u64 = 0,
    proven: [verdict_count]u64 = [_]u64{0} ** verdict_count,
    content_changes: u64 = 0,
    first_pixel_candidates: u64 = 0,

    /// Draws that may close an output gate.
    pub fn outputBearing(self: Summary) u64 {
        return self.target_backed +| self.memory_export +| self.resolve_only;
    }

    pub fn anyDefect(self: Summary) bool {
        return self.emulator_dropped != 0 or self.unclassified != 0;
    }

    /// Whether the first-pixel gate has an output-bearing candidate or a
    /// concrete defect to judge. Intentional no-output draws are title state,
    /// not a failed rendering attempt.
    pub fn outputGateJudgeable(self: Summary) bool {
        return self.candidates != 0 and (self.outputBearing() != 0 or self.anyDefect());
    }
};

pub const Ledger = struct {
    candidates: [max_candidates]Candidate = [_]Candidate{.{}} ** max_candidates,
    count: usize = 0,
    dropped: u64 = 0,
    total: u64 = 0,
    next_id: u64 = 1,

    pub fn begin(self: *Ledger, guest_step: u64, source: SourceClass) ?*Candidate {
        self.total +|= 1;
        if (self.count >= max_candidates) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.candidates[self.count];
        self.count += 1;
        slot.* = .{ .id = self.next_id, .guest_step = guest_step, .source = source };
        self.next_id += 1;
        return slot;
    }

    pub fn retained(self: *const Ledger) []const Candidate {
        return self.candidates[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .candidates = self.total, .retained = self.count, .dropped = self.dropped };
        for (self.retained()) |candidate| {
            switch (candidate.classification) {
                .target_backed => out.target_backed +|= 1,
                .memory_export => out.memory_export +|= 1,
                .resolve_only => out.resolve_only +|= 1,
                .intentional_no_output => out.intentional_no_output +|= 1,
                .emulator_dropped => out.emulator_dropped +|= 1,
                .unclassified => out.unclassified +|= 1,
            }
            var index: usize = 0;
            while (index < verdict_count) : (index += 1) {
                if (candidate.reached[index]) out.proven[index] +|= 1;
            }
            if (candidate.contentChanged()) out.content_changes +|= 1;
            if (candidate.provesFirstPixel()) out.first_pixel_candidates +|= 1;
        }
        return out;
    }

    /// The first verdict no candidate has ever proven. This is the frontier,
    /// and it is what a reader should be sent to.
    pub fn frontier(self: *const Ledger) ?Verdict {
        const totals = self.summary();
        var index: usize = 0;
        while (index < verdict_count) : (index += 1) {
            if (totals.proven[index] == 0) return @enumFromInt(index);
        }
        return null;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.candidates;
        var index: usize = 0;
        while (index < verdict_count) : (index += 1) {
            hash = hash *% 31 +% totals.proven[index];
        }
        return hash *% 31 +% totals.outputBearing();
    }
};

test "a draw the title configured to produce nothing does not close the output gate" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 24) : (index += 1) {
        const candidate = ledger.begin(3_259_735_760 + index, .guest_authentic).?;
        candidate.raster = .{ .rasterization_enabled = false, .memexport_ranges = 0 };
        candidate.classification = .intentional_no_output;
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 24), totals.candidates);
    try std.testing.expectEqual(@as(u64, 24), totals.intentional_no_output);
    try std.testing.expectEqual(@as(u64, 0), totals.outputBearing());
    try std.testing.expect(!totals.anyDefect());
    try std.testing.expect(!totals.outputGateJudgeable());
    try std.testing.expect(!Classification.intentional_no_output.satisfiesOutputGate());
    // The frontier is the very first verdict: nothing ever programmed state.
    try std.testing.expectEqual(Verdict.state_programmed, ledger.frontier().?);
}

test "reaching one verdict never implies the one before it" {
    var candidate = Candidate{ .source = .guest_authentic };
    candidate.note(.rasterization_executed);
    try std.testing.expect(candidate.has(.rasterization_executed));
    try std.testing.expect(!candidate.has(.state_programmed));
    try std.testing.expectEqual(Verdict.state_programmed, candidate.firstGap().?);
    try std.testing.expect(!candidate.provesFirstPixel());
}

// The audit's acceptance criterion for the first pixel.
test "a controlled vector proves six verdicts, a content change and an authentic source" {
    var ledger = Ledger{};
    const candidate = ledger.begin(1000, .guest_authentic).?;
    candidate.target = .{
        .color_info = 0x1234,
        .surface_info = 0x5678,
        .color_valid = true,
        .surface_valid = true,
        .width = 1280,
        .height = 720,
        .guest_destination = .{ .guest_physical = 0x1FC0_0000 },
    };
    candidate.raster = .{
        .rasterization_enabled = true,
        .viewport_width = 1280,
        .viewport_height = 720,
        .scissor_width = 1280,
        .scissor_height = 720,
        .vertex_shader_translated = true,
    };
    candidate.classification = .target_backed;
    candidate.content_sampled = true;
    candidate.content_before = 0;
    candidate.content_after = 0xDEAD_BEEF;
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        candidate.note(@enumFromInt(field.value));
    }

    try std.testing.expect(candidate.target.programmed());
    try std.testing.expect(candidate.raster.couldProduceOutput());
    try std.testing.expect(candidate.contentChanged());
    try std.testing.expect(candidate.provesFirstPixel());
    try std.testing.expect(ledger.frontier() == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().first_pixel_candidates);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().outputBearing());
}

test "a synthetic source can cross every verdict and still prove nothing" {
    var ledger = Ledger{};
    const candidate = ledger.begin(1000, .synthetic).?;
    candidate.classification = .target_backed;
    candidate.content_sampled = true;
    candidate.content_after = 1;
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        candidate.note(@enumFromInt(field.value));
    }
    try std.testing.expect(!candidate.provesFirstPixel());
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().first_pixel_candidates);
}

test "an unsampled content has not answered whether anything changed" {
    var candidate = Candidate{ .source = .guest_authentic };
    candidate.content_before = 5;
    candidate.content_after = 9;
    try std.testing.expect(!candidate.contentChanged());
    candidate.content_sampled = true;
    try std.testing.expect(candidate.contentChanged());
    candidate.content_after = 5;
    try std.testing.expect(!candidate.contentChanged());
}

test "a target with valid registers and no extent is not programmed" {
    var target = TargetState{ .color_valid = true, .surface_valid = true };
    try std.testing.expect(!target.programmed());
    target.width = 1280;
    try std.testing.expect(!target.programmed());
    target.height = 720;
    try std.testing.expect(target.programmed());
}

test "an empty scissor stops output however enabled rasterization is" {
    var raster = RasterState{
        .rasterization_enabled = true,
        .viewport_width = 1280,
        .viewport_height = 720,
        .scissor_width = 0,
        .scissor_height = 720,
    };
    try std.testing.expect(!raster.couldProduceOutput());
    raster.scissor_width = 1280;
    try std.testing.expect(raster.couldProduceOutput());
    // Memory export produces output with rasterization off entirely.
    raster.rasterization_enabled = false;
    try std.testing.expect(!raster.couldProduceOutput());
    raster.memexport_ranges = 1;
    try std.testing.expect(raster.couldProduceOutput());
}

test "an unclassified draw is a defect rather than a silent pass" {
    var ledger = Ledger{};
    _ = ledger.begin(100, .guest_authentic).?;
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.unclassified);
    try std.testing.expect(totals.anyDefect());
    try std.testing.expect(Classification.unclassified.isDefect());
    try std.testing.expect(!Classification.unclassified.satisfiesOutputGate());
}

test "the candidate list is bounded and counts what it shed" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_candidates + 5) : (index += 1) {
        _ = ledger.begin(index, .guest_authentic);
    }
    try std.testing.expectEqual(max_candidates, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 5), ledger.dropped);
    try std.testing.expectEqual(@as(u64, max_candidates + 5), ledger.summary().candidates);
}

test "every verdict and classification states its own vocabulary" {
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const verdict: Verdict = @enumFromInt(field.value);
        try std.testing.expect(verdict.label().len != 0);
        try std.testing.expect(verdict.owner().len != 0);
        try std.testing.expect(verdict.gapMeans().len != 0);
    }
    inline for (@typeInfo(Classification).@"enum".fields) |field| {
        const class: Classification = @enumFromInt(field.value);
        try std.testing.expect(class.label().len != 0);
    }
}
