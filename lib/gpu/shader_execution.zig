//! Whether a shader was translated, whether it can rasterize, and whether the
//! decision to skip a draw came from the shader or from the registers.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run loaded shaders from the pipeline cache and dropped every
//! draw at `no_rasterization_no_memexport`. Loading a shader is not executing
//! one, and "rasterization is not potentially done" is a decision made from
//! register state *and* from what the translated shader turned out to write.
//! With only a draw-exit name, those two are indistinguishable — and they have
//! different owners: registers are the title's, a failed translation is the
//! emulator's.
//!
//! The Vulkan backend also carries unimplemented stages: tessellation, a
//! geometry-type vertex shader, and a vertex-shader memexport fallback when
//! the device lacks `vertexPipelineStoresAndAtomics`. A draw refused for one
//! of those is valid and unimplemented, which is a different thing from a
//! broken one and must not be filed as the title's.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;

pub const Stage = enum(u8) {
    vertex = 0,
    pixel = 1,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .vertex => "vertex",
            .pixel => "pixel",
        };
    }
};

/// The host vertex-shader type a draw asked for. The backend implements two of
/// these and refuses the rest, and the refusal is not a defect in the title.
pub const HostVertexShaderType = enum(u8) {
    vertex = 0,
    point_list_as_triangle_strip = 1,
    rectangle_list_as_triangle_strip = 2,
    tessellation = 3,
    unknown = 255,

    pub fn label(self: HostVertexShaderType) []const u8 {
        return switch (self) {
            .vertex => "vertex",
            .point_list_as_triangle_strip => "point-list-as-triangle-strip",
            .rectangle_list_as_triangle_strip => "rectangle-list-as-triangle-strip",
            .tessellation => "tessellation",
            .unknown => "unknown",
        };
    }

    /// Whether the Vulkan backend implements it today.
    pub fn implemented(self: HostVertexShaderType) bool {
        return self == .vertex or self == .point_list_as_triangle_strip;
    }
};

/// Why a shader could not carry a draw. Separated from the draw-exit name so
/// the owner is unambiguous.
pub const Refusal = enum(u8) {
    /// Nothing refused it.
    none = 0,
    /// No shader was bound for a stage that needs one.
    not_bound = 1,
    /// Translation to the host language failed.
    translation_failed = 2,
    /// The stage exists in the guest and not in this backend.
    stage_unimplemented = 3,
    /// The shader writes to memory and the device cannot do it from this
    /// stage.
    memexport_unsupported = 4,
    /// The host pipeline could not be configured for the state combination.
    pipeline_configuration_failed = 5,

    pub fn label(self: Refusal) []const u8 {
        return switch (self) {
            .none => "none",
            .not_bound => "not-bound",
            .translation_failed => "translation-failed",
            .stage_unimplemented => "stage-unimplemented",
            .memexport_unsupported => "memexport-unsupported",
            .pipeline_configuration_failed => "pipeline-configuration-failed",
        };
    }

    pub fn owner(self: Refusal) []const u8 {
        return switch (self) {
            .none => "-",
            // A missing binding is the title programming a draw without a
            // program, or a binding lost between the register write and the
            // draw. Either way the title named it.
            .not_bound => "guest:title",
            .translation_failed, .pipeline_configuration_failed => "emulator:gpu",
            // Valid and unimplemented. Not a defect in either half, and it has
            // to stay distinguishable from one.
            .stage_unimplemented, .memexport_unsupported => "emulator:gpu-unimplemented",
        };
    }

    pub fn describe(self: Refusal) []const u8 {
        return switch (self) {
            .none => "the shaders were available and translated",
            .not_bound => "a stage that needs a shader had none bound. The title programmed a draw without a program, or the binding was lost between the register write and the draw",
            .translation_failed => "the guest microcode could not be translated to the host language. Nothing downstream of this can render, and the failure is in the translator rather than in anything the title did",
            .stage_unimplemented => "the guest asked for a vertex-shader type this backend does not implement. The draw is valid and unimplemented, which is a different thing from broken and must not be filed against the title",
            .memexport_unsupported => "the shader exports to memory and the device cannot do it from this stage. A fallback exists in principle and is not implemented here",
            .pipeline_configuration_failed => "a host pipeline could not be configured for this state combination. The shaders are fine and the combination is not",
        };
    }

    pub fn isDefect(self: Refusal) bool {
        return self == .translation_failed or self == .pipeline_configuration_failed;
    }
};

pub const refusal_count: usize = @typeInfo(Refusal).@"enum".fields.len;

/// One translated shader.
pub const Shader = struct {
    id: u64 = 0,
    stage: Stage = .vertex,
    /// Hash of the guest microcode, so a cache hit can be checked against the
    /// bytes it claims to be.
    ucode_hash: u64 = 0,
    ucode_bytes: u32 = 0,
    translation_generation: u64 = 0,
    translated: bool = false,
    /// What the translated shader turned out to do. These are what decide
    /// whether a draw can produce output, and they come from the shader rather
    /// than from the registers.
    writes_color: bool = false,
    writes_depth: bool = false,
    memexport_ranges: u32 = 0,
    interpolators_written: u32 = 0,
    /// Guest instructions the translator did not implement.
    unsupported_instructions: u32 = 0,
    refusal: Refusal = .none,
    source: SourceClass = .unknown,

    /// Whether this shader can put anything anywhere.
    pub fn canProduceOutput(self: Shader) bool {
        if (!self.translated) return false;
        if (self.refusal != .none) return false;
        return self.writes_color or self.writes_depth or self.memexport_ranges != 0;
    }

    /// Whether a cache hit's bytes match what it claims to be. A stale entry
    /// executes the wrong program with a plausible id.
    pub fn hashMatches(self: Shader, observed_hash: u64) bool {
        return self.ucode_hash != 0 and self.ucode_hash == observed_hash;
    }
};

pub const max_shaders: usize = 32;

pub const Summary = struct {
    shaders: usize = 0,
    dropped: u64 = 0,
    translated: usize = 0,
    output_capable: usize = 0,
    unsupported_instructions: u64 = 0,
    hash_mismatches: u64 = 0,
    by_refusal: [refusal_count]u64 = [_]u64{0} ** refusal_count,

    pub fn emulatorDefects(self: Summary) u64 {
        return self.by_refusal[@intFromEnum(Refusal.translation_failed)] +|
            self.by_refusal[@intFromEnum(Refusal.pipeline_configuration_failed)];
    }

    pub fn unimplementedRefusals(self: Summary) u64 {
        return self.by_refusal[@intFromEnum(Refusal.stage_unimplemented)] +|
            self.by_refusal[@intFromEnum(Refusal.memexport_unsupported)];
    }
};

pub const Verdict = enum(u8) {
    /// Nothing has been translated.
    unobserved,
    /// Shaders translate and can produce output.
    healthy,
    /// Shaders translate and none of them writes anything. A draw using these
    /// legitimately produces nothing.
    translated_without_output,
    /// A translation or pipeline failure. The emulator's.
    translation_defect,
    /// Refusals are all of the valid-and-unimplemented kind.
    unimplemented_path,
    /// A cache entry's bytes did not match its id.
    cache_mismatch,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .healthy => "healthy",
            .translated_without_output => "translated-without-output",
            .translation_defect => "TRANSLATION-DEFECT",
            .unimplemented_path => "UNIMPLEMENTED-PATH",
            .cache_mismatch => "CACHE-MISMATCH",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "no shader has been translated. A draw refused for a shader reason cannot be attributed until one has",
            .healthy => "shaders translate and at least one can write colour, depth or memory. A draw that produces nothing with these is a register decision rather than a shader one",
            .translated_without_output => "shaders translate and none of them writes colour, depth or memory. A draw using these legitimately has no effect, and that is the title's program rather than a failure to run it",
            .translation_defect => "a shader failed to translate, or no host pipeline could be configured for it. Nothing downstream can render and the failure is the emulator's",
            .unimplemented_path => "the guest asked for a shader stage or a memory-export path this backend does not implement. The draw is valid and unimplemented — a gap in the emulator, and not a defect in either half",
            .cache_mismatch => "a cache entry's microcode hash does not match the bytes it claims to be. Whatever executed was not the program the title asked for, and every conclusion about the draw is unsafe",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .translation_defect or self == .cache_mismatch;
    }
};

pub const Ledger = struct {
    shaders: [max_shaders]Shader = [_]Shader{.{}} ** max_shaders,
    count: usize = 0,
    dropped: u64 = 0,
    hash_mismatches: u64 = 0,
    by_refusal: [refusal_count]u64 = [_]u64{0} ** refusal_count,

    pub fn record(self: *Ledger, shader: Shader) ?*Shader {
        self.by_refusal[@intFromEnum(shader.refusal)] +|= 1;
        if (self.count >= max_shaders) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.shaders[self.count];
        self.count += 1;
        slot.* = shader;
        return slot;
    }

    /// Check a cache hit against the bytes it claims. A mismatch is recorded
    /// rather than corrected: correcting it would hide the defect.
    pub fn verifyCacheHit(self: *Ledger, id: u64, observed_hash: u64) bool {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.shaders[index].id != id) continue;
            if (self.shaders[index].hashMatches(observed_hash)) return true;
            self.hash_mismatches +|= 1;
            return false;
        }
        return false;
    }

    pub fn retained(self: *const Ledger) []const Shader {
        return self.shaders[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{
            .shaders = self.count,
            .dropped = self.dropped,
            .hash_mismatches = self.hash_mismatches,
            .by_refusal = self.by_refusal,
        };
        for (self.retained()) |shader| {
            if (shader.translated) out.translated += 1;
            if (shader.canProduceOutput()) out.output_capable += 1;
            out.unsupported_instructions +|= shader.unsupported_instructions;
        }
        return out;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        if (self.count == 0) return .unobserved;
        const totals = self.summary();
        if (totals.hash_mismatches != 0) return .cache_mismatch;
        if (totals.emulatorDefects() != 0) return .translation_defect;
        if (totals.unimplementedRefusals() != 0) return .unimplemented_path;
        if (totals.output_capable != 0) return .healthy;
        return .translated_without_output;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.shaders;
        hash = hash *% 31 +% totals.output_capable;
        hash = hash *% 31 +% totals.hash_mismatches;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

fn plainShader(id: u64, stage: Stage) Shader {
    return .{
        .id = id,
        .stage = stage,
        .ucode_hash = 0x1000 + id,
        .ucode_bytes = 256,
        .translated = true,
        .source = .guest_authentic,
    };
}

// The 2026-08-31 shape: shaders loaded, draws dropped, and no way to tell
// whether the shader or the registers made the decision.
test "shaders that write nothing make a no-output draw the title's program" {
    var ledger = Ledger{};
    _ = ledger.record(plainShader(1, .vertex));
    _ = ledger.record(plainShader(2, .pixel));
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.translated_without_output, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expectEqual(@as(usize, 2), ledger.summary().translated);
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().output_capable);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "title's program") != null);
}

test "a shader that writes colour makes a no-output draw a register decision" {
    var ledger = Ledger{};
    var shader = plainShader(1, .pixel);
    shader.writes_color = true;
    _ = ledger.record(shader);
    try std.testing.expectEqual(Verdict.healthy, ledger.verdict());
    try std.testing.expect(std.mem.indexOf(u8, Verdict.healthy.describe(), "register decision") != null);
}

test "a failed translation is the emulator's and outranks the output question" {
    var ledger = Ledger{};
    var broken = plainShader(1, .vertex);
    broken.translated = false;
    broken.refusal = .translation_failed;
    _ = ledger.record(broken);
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.translation_defect, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expectEqualStrings("emulator:gpu", Refusal.translation_failed.owner());
    try std.testing.expect(!broken.canProduceOutput());
}

test "an unimplemented stage is neither half's defect and stays distinguishable" {
    var ledger = Ledger{};
    var tess = plainShader(1, .vertex);
    tess.refusal = .stage_unimplemented;
    _ = ledger.record(tess);
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.unimplemented_path, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expectEqualStrings("emulator:gpu-unimplemented", Refusal.stage_unimplemented.owner());
    try std.testing.expect(!Refusal.stage_unimplemented.isDefect());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().unimplementedRefusals());
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().emulatorDefects());

    try std.testing.expect(HostVertexShaderType.vertex.implemented());
    try std.testing.expect(!HostVertexShaderType.tessellation.implemented());
}

test "a cache entry whose bytes do not match outranks every other verdict" {
    var ledger = Ledger{};
    var shader = plainShader(1, .vertex);
    shader.writes_color = true;
    _ = ledger.record(shader);
    try std.testing.expectEqual(Verdict.healthy, ledger.verdict());

    try std.testing.expect(ledger.verifyCacheHit(1, 0x1001));
    try std.testing.expect(!ledger.verifyCacheHit(1, 0xDEAD));
    try std.testing.expectEqual(@as(u64, 1), ledger.hash_mismatches);
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.cache_mismatch, verdict);
    try std.testing.expect(verdict.isDefect());
}

test "an unbound shader is the title's and a missing hash never matches" {
    var ledger = Ledger{};
    var unbound = Shader{ .id = 1, .stage = .vertex, .refusal = .not_bound };
    _ = ledger.record(unbound);
    try std.testing.expectEqualStrings("guest:title", Refusal.not_bound.owner());
    try std.testing.expect(!unbound.canProduceOutput());
    // A shader with no recorded hash cannot be verified into a match.
    try std.testing.expect(!unbound.hashMatches(0));
    try std.testing.expect(!ledger.verifyCacheHit(1, 0));
}

test "nothing translated is unobserved rather than a shader failure" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict());
    try std.testing.expect(!ledger.verdict().isDefect());
}

test "the shader table is bounded and refusal counts survive the bound" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_shaders + 4) : (index += 1) {
        _ = ledger.record(plainShader(index + 1, .vertex));
    }
    try std.testing.expectEqual(max_shaders, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 4), ledger.dropped);
    try std.testing.expectEqual(@as(u64, max_shaders + 4), ledger.summary().by_refusal[@intFromEnum(Refusal.none)]);
}

test "every refusal and vertex shader type states its own vocabulary" {
    inline for (@typeInfo(Refusal).@"enum".fields) |field| {
        const which: Refusal = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.owner().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
    inline for (@typeInfo(HostVertexShaderType).@"enum".fields) |field| {
        const which: HostVertexShaderType = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
}
