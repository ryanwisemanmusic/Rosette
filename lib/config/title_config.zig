//! Per-title configuration overrides.
//!
//! A title id selects a set of overrides that are layered on top of the global
//! configuration. Halo 3 is `0x4D5307E6`, and a title-specific override is how
//! a workaround stays scoped to the title that needs it instead of becoming a
//! global default nobody remembers enabling.
//!
//! ## Why the layering order is fixed and stated
//!
//! Three sources can set the same key: the schema default, the global config
//! file, and a title override. If the order is ambiguous, the same file
//! produces different behaviour depending on which loader ran first, and the
//! resulting "it works on my machine" is unusually hard to pin down because
//! nothing is wrong with either file.
//!
//! The order is: **default, then global, then title**. Most specific wins. A
//! title override always beats the global file, because the reason it exists is
//! that this title needs something different.
//!
//! ## Absent is not the same as default
//!
//! An override that is not present must leave the lower layer alone. Modelling
//! overrides as a full `Config` and copying it wholesale would silently reset
//! every key the title did not mention back to its default — so an override
//! setting one GPU key would quietly undo the user's audio settings.

const std = @import("std");
const schema = @import("xenia_config_schema");

pub const Config = schema.Config;

/// Halo 3. Named because it is the title this work is aimed at, and a bare
/// hex constant in a table is unreadable.
pub const halo3_title_id: u32 = 0x4D53_07E6;

/// An override set. Every field optional: absent means "leave alone", which is
/// what makes layering non-destructive.
pub const Overrides = struct {
    title_id: u32,

    cpu_backend: ?schema.CpuBackend = null,
    gpu_backend: ?schema.GpuBackend = null,
    resolution_scale: ?u32 = null,
    render_target_path: ?schema.RenderTargetPath = null,
    vsync: ?bool = null,
    audio_driver: ?schema.AudioDriverKind = null,
    audio_latency_ms: ?u32 = null,
    log_level: ?schema.LogLevel = null,
    trace_gpu_commands: ?bool = null,

    /// Whether this set changes anything at all.
    pub fn isEmpty(self: Overrides) bool {
        return self.cpu_backend == null and
            self.gpu_backend == null and
            self.resolution_scale == null and
            self.render_target_path == null and
            self.vsync == null and
            self.audio_driver == null and
            self.audio_latency_ms == null and
            self.log_level == null and
            self.trace_gpu_commands == null;
    }

    /// Apply onto a base configuration.
    ///
    /// Absent fields leave the base untouched. Returns a new value rather than
    /// mutating, so the global config stays available for comparison — which
    /// is what lets a diagnostic say what the override actually changed.
    pub fn applyTo(self: Overrides, base: Config) Config {
        var merged = base;
        if (self.cpu_backend) |value| merged.cpu.backend = value;
        if (self.gpu_backend) |value| merged.gpu.backend = value;
        if (self.resolution_scale) |value| merged.gpu.resolution_scale = value;
        if (self.render_target_path) |value| merged.gpu.render_target_path = value;
        if (self.vsync) |value| merged.gpu.vsync = value;
        if (self.audio_driver) |value| merged.audio.driver = value;
        if (self.audio_latency_ms) |value| merged.audio.latency_ms = value;
        if (self.log_level) |value| merged.debug.log_level = value;
        if (self.trace_gpu_commands) |value| merged.debug.trace_gpu_commands = value;
        return merged;
    }
};

/// The layer a value came from. Reported so a person can tell whether a
/// setting they did not expect came from their file or from a built-in
/// override — the question behind most "why is this on" investigations.
pub const Layer = enum { default, global, title };

pub const Resolution = struct {
    config: Config,
    /// Whether a title override contributed anything.
    title_override_applied: bool,
    title_id: ?u32,
};

/// Resolve the effective configuration for a title.
///
/// Default, then global, then title. Stated in one place so no caller has to
/// reconstruct the precedence.
pub fn resolve(global: Config, overrides: ?Overrides) Resolution {
    if (overrides) |set| {
        return .{
            .config = set.applyTo(global),
            .title_override_applied = !set.isEmpty(),
            .title_id = set.title_id,
        };
    }
    return .{ .config = global, .title_override_applied = false, .title_id = null };
}

/// Find the override set for a title id.
pub fn findOverrides(sets: []const Overrides, title_id: u32) ?Overrides {
    for (sets) |set| {
        if (set.title_id == title_id) return set;
    }
    return null;
}

test "an empty override set changes nothing" {
    const base = schema.defaults;
    const set = Overrides{ .title_id = halo3_title_id };
    try std.testing.expect(set.isEmpty());
    const merged = set.applyTo(base);
    try std.testing.expectEqual(base.gpu.backend, merged.gpu.backend);
    try std.testing.expectEqual(base.audio.latency_ms, merged.audio.latency_ms);
    try std.testing.expectEqual(base.debug.log_level, merged.debug.log_level);
}

test "an absent field leaves the lower layer alone" {
    // The property that makes layering safe. A wholesale copy would reset
    // every unmentioned key to its default, so a GPU override would quietly
    // undo the user's audio settings.
    var global = schema.defaults;
    global.audio.latency_ms = 40;
    global.audio.driver = .sdl;
    global.gpu.vsync = false;

    const set = Overrides{ .title_id = halo3_title_id, .resolution_scale = 2 };
    const merged = set.applyTo(global);

    try std.testing.expectEqual(@as(u32, 2), merged.gpu.resolution_scale);
    // Untouched by the override, and not reset to the schema default.
    try std.testing.expectEqual(@as(u32, 40), merged.audio.latency_ms);
    try std.testing.expectEqual(schema.AudioDriverKind.sdl, merged.audio.driver);
    try std.testing.expectEqual(false, merged.gpu.vsync);
}

test "a title override beats the global file" {
    // Most specific wins: the override exists precisely because this title
    // needs something the global setting does not give it.
    var global = schema.defaults;
    global.gpu.render_target_path = .ts;

    const set = Overrides{ .title_id = halo3_title_id, .render_target_path = .rtl };
    const resolved = resolve(global, set);
    try std.testing.expectEqual(schema.RenderTargetPath.rtl, resolved.config.gpu.render_target_path);
    try std.testing.expect(resolved.title_override_applied);
    try std.testing.expectEqual(halo3_title_id, resolved.title_id.?);
}

test "the global file beats the schema default" {
    var global = schema.defaults;
    global.gpu.backend = .metal;
    const resolved = resolve(global, null);
    try std.testing.expectEqual(schema.GpuBackend.metal, resolved.config.gpu.backend);
    try std.testing.expect(!resolved.title_override_applied);
    try std.testing.expect(resolved.title_id == null);
}

test "an override that sets nothing is reported as not applied" {
    // Distinguishing "no override for this title" from "an override exists
    // and is empty" is what stops a stale, do-nothing entry looking like the
    // cause of a behaviour it cannot produce.
    const set = Overrides{ .title_id = halo3_title_id };
    const resolved = resolve(schema.defaults, set);
    try std.testing.expect(!resolved.title_override_applied);
    // The title id is still reported: an entry was found.
    try std.testing.expectEqual(halo3_title_id, resolved.title_id.?);
}

test "overrides are found by title id and not by position" {
    const sets = [_]Overrides{
        .{ .title_id = 0x1111_1111, .resolution_scale = 3 },
        .{ .title_id = halo3_title_id, .resolution_scale = 2 },
    };
    const found = findOverrides(&sets, halo3_title_id).?;
    try std.testing.expectEqual(@as(u32, 2), found.resolution_scale.?);
    try std.testing.expect(findOverrides(&sets, 0xDEAD_BEEF) == null);
}

test "Halo 3's title id is what the table keys on" {
    try std.testing.expectEqual(@as(u32, 0x4D5307E6), halo3_title_id);
}

test "every override field can be applied" {
    // A field added to Overrides but forgotten in applyTo would silently do
    // nothing, which is indistinguishable from the override not being found.
    const set = Overrides{
        .title_id = halo3_title_id,
        .cpu_backend = .x64,
        .gpu_backend = .metal,
        .resolution_scale = 2,
        .render_target_path = .ts,
        .vsync = false,
        .audio_driver = .nop,
        .audio_latency_ms = 33,
        .log_level = .debug,
        .trace_gpu_commands = true,
    };
    try std.testing.expect(!set.isEmpty());
    const merged = set.applyTo(schema.defaults);
    try std.testing.expectEqual(schema.CpuBackend.x64, merged.cpu.backend);
    try std.testing.expectEqual(schema.GpuBackend.metal, merged.gpu.backend);
    try std.testing.expectEqual(@as(u32, 2), merged.gpu.resolution_scale);
    try std.testing.expectEqual(schema.RenderTargetPath.ts, merged.gpu.render_target_path);
    try std.testing.expectEqual(false, merged.gpu.vsync);
    try std.testing.expectEqual(schema.AudioDriverKind.nop, merged.audio.driver);
    try std.testing.expectEqual(@as(u32, 33), merged.audio.latency_ms);
    try std.testing.expectEqual(schema.LogLevel.debug, merged.debug.log_level);
    try std.testing.expectEqual(true, merged.debug.trace_gpu_commands);
}

test "a merged config still has to pass validation" {
    // An override can produce an invalid config. Layering does not exempt it.
    const set = Overrides{ .title_id = halo3_title_id, .resolution_scale = 99 };
    const merged = set.applyTo(schema.defaults);
    try std.testing.expectEqual(
        schema.ValidationFailure.resolution_scale_out_of_range,
        schema.validate(merged).?,
    );
}

test "applying does not mutate the base" {
    // The global config stays available for comparison, which is what lets a
    // diagnostic report what the override actually changed.
    const base = schema.defaults;
    const set = Overrides{ .title_id = halo3_title_id, .resolution_scale = 2 };
    _ = set.applyTo(base);
    try std.testing.expectEqual(schema.defaults.gpu.resolution_scale, base.gpu.resolution_scale);
}
