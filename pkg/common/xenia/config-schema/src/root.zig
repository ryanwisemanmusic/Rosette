//! Route-independent: the emulator configuration schema, as Zig types.
//!
//! Every key Rosette honours, its type, and its default. The schema is a
//! compile-time fact; the TOML text that fills it is runtime input, and
//! `lib/config/` owns reading that text. Nothing here touches a file.
//!
//! ## Why the schema is a package and not just a struct in the loader
//!
//! Configuration is the layer where a typo costs the most time per character.
//! A misspelled key in a hand-written TOML file silently keeps the default,
//! and the run that follows is then debugged as if the setting had applied —
//! the GPU backend that "didn't change anything", the log level that "doesn't
//! work". Because the key set lives here as data, the loader can do the one
//! thing that ends that class of bug: report an unknown key instead of
//! ignoring it. `isKnownKey` is the whole point of the package.
//!
//! It also means a default is stated once. A default duplicated between a
//! struct field and a parser's fallback branch is a default that will
//! eventually disagree with itself.
//!
//! ## What this package is not
//!
//! * It is not a parser. It cannot read TOML, and it holds no parsed state.
//! * It is not a config object in use. A `Config` value here is a default
//!   template; the live one the runtime consults belongs to `lib/config/`.
//! * It does not decide anything. `.vulkan` being the default backend is a
//!   recorded default, not a backend selection — selection happens in lib,
//!   against what the host actually offers.

const std = @import("std");

// ---------------------------------------------------------------------------
// Value-domain enums
//
// Spelled exactly as they appear in the TOML file. `@"error"` and `@"null"`
// are quoted because they collide with Zig keywords; the field *name* is what
// a string-to-enum lookup matches, so the quoting keeps the config text
// readable rather than forcing a rename on the user's file.
// ---------------------------------------------------------------------------

pub const CpuBackend = enum { any, x64, ppc };

pub const GpuBackend = enum { vulkan, d3d12, metal, @"null" };

pub const RenderTargetPath = enum {
    /// Render-target-local: the EDRAM-faithful path.
    rtl,
    /// Texture-swap: cheaper, less faithful.
    ts,
};

pub const AudioDriverKind = enum { sdl, coreaudio, nop };

pub const LogLevel = enum(u8) {
    @"error" = 0,
    warning = 1,
    info = 2,
    debug = 3,

    /// Whether a message at `message` should be emitted when the configured
    /// level is `self`. Ordering is by severity, so this is a comparison and
    /// not a table; getting the direction backwards is the classic version of
    /// this bug and the test below pins it.
    pub fn admits(self: LogLevel, message: LogLevel) bool {
        return @intFromEnum(message) <= @intFromEnum(self);
    }
};

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

pub const CpuConfig = struct {
    backend: CpuBackend = .any,
    debug_symbol_loader: bool = false,
    /// 0 means "decide at runtime from the host". A fixed non-zero value here
    /// is a request, and lib is free to refuse it.
    translation_thread_count: u32 = 0,
};

pub const GpuConfig = struct {
    backend: GpuBackend = .vulkan,
    /// Null means "let the runtime pick". An empty string is a different
    /// thing — a user who wrote `vulkan_adapter = ""` asked for a nameless
    /// adapter and should be told that is not one.
    vulkan_adapter: ?[]const u8 = null,
    resolution_scale: u32 = 1,
    render_target_path: RenderTargetPath = .rtl,
    vsync: bool = true,
};

pub const AudioConfig = struct {
    driver: AudioDriverKind = .coreaudio,
    latency_ms: u32 = 20,
    /// Master volume in hundredths, so the schema stays integer-typed and a
    /// TOML float cannot silently truncate to 0.
    master_volume_percent: u32 = 100,
};

pub const DebugConfig = struct {
    trace_gpu_commands: bool = false,
    log_level: LogLevel = .warning,
    break_on_unimplemented: bool = false,
};

pub const PatchEntry = struct {
    title_id: u32,
    address: u32,
    value: u32,
};

pub const Config = struct {
    cpu: CpuConfig = .{},
    gpu: GpuConfig = .{},
    audio: AudioConfig = .{},
    debug: DebugConfig = .{},
    patches: []const PatchEntry = &.{},
};

/// The defaults, as one value. A loader starts here and overlays the file.
pub const defaults: Config = .{};

// ---------------------------------------------------------------------------
// Key registry
// ---------------------------------------------------------------------------

pub const ValueKind = enum { boolean, integer, text, enumeration };

pub const KeySpec = struct {
    /// Dotted path as written in the TOML file: `section.key`.
    path: []const u8,
    kind: ValueKind,
};

/// Every key the runtime honours.
///
/// Derived from the section structs at comptime rather than typed out, so a
/// field added above cannot be forgotten here. A hand-maintained second list
/// is exactly the duplication this package exists to remove.
pub const keys: []const KeySpec = blk: {
    const sections = .{
        .{ "cpu", CpuConfig },
        .{ "gpu", GpuConfig },
        .{ "audio", AudioConfig },
        .{ "debug", DebugConfig },
    };
    var count: usize = 0;
    for (sections) |section| count += @typeInfo(section[1]).@"struct".fields.len;

    var list: [count]KeySpec = undefined;
    var index: usize = 0;
    for (sections) |section| {
        const prefix = section[0];
        for (@typeInfo(section[1]).@"struct".fields) |field| {
            list[index] = .{
                .path = prefix ++ "." ++ field.name,
                .kind = kindOf(field.type),
            };
            index += 1;
        }
    }
    const frozen = list;
    break :blk &frozen;
};

fn kindOf(comptime T: type) ValueKind {
    return switch (@typeInfo(T)) {
        .bool => .boolean,
        .int => .integer,
        .@"enum" => .enumeration,
        .optional => |optional| kindOf(optional.child),
        .pointer => .text,
        else => @compileError("config schema: unsupported field type " ++ @typeName(T)),
    };
}

/// Whether a dotted key is one the runtime honours.
///
/// The function the loader needs to reject a typo instead of ignoring it.
pub fn isKnownKey(path: []const u8) bool {
    return specFor(path) != null;
}

pub fn specFor(path: []const u8) ?KeySpec {
    for (keys) |key| {
        if (std.mem.eql(u8, key.path, path)) return key;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Bounds
// ---------------------------------------------------------------------------

/// The largest resolution scale the render target path can back.
pub const max_resolution_scale: u32 = 3;
/// Latency below this cannot be serviced by a 256-sample callback at 48 kHz.
pub const min_audio_latency_ms: u32 = 5;
pub const max_audio_latency_ms: u32 = 500;

pub const ValidationFailure = enum {
    resolution_scale_out_of_range,
    audio_latency_out_of_range,
    master_volume_out_of_range,
    empty_vulkan_adapter,
};

/// Whether a config is inside the bounds the runtime can honour.
///
/// Returns the first failure rather than a bool, because "invalid config" with
/// no field named is a message that sends someone re-reading their whole file.
/// Pure: it inspects the value it is handed and nothing else.
pub fn validate(config: Config) ?ValidationFailure {
    if (config.gpu.resolution_scale == 0 or config.gpu.resolution_scale > max_resolution_scale) {
        return .resolution_scale_out_of_range;
    }
    if (config.audio.latency_ms < min_audio_latency_ms or
        config.audio.latency_ms > max_audio_latency_ms)
    {
        return .audio_latency_out_of_range;
    }
    if (config.audio.master_volume_percent > 100) return .master_volume_out_of_range;
    if (config.gpu.vulkan_adapter) |adapter| {
        if (adapter.len == 0) return .empty_vulkan_adapter;
    }
    return null;
}

test "the defaults are valid" {
    // A default set that does not pass its own validator is a build that
    // cannot start with an empty config file.
    try std.testing.expect(validate(defaults) == null);
}

test "the key registry is derived from the section structs" {
    // 3 cpu + 5 gpu + 3 audio + 3 debug.
    try std.testing.expectEqual(@as(usize, 14), keys.len);
    try std.testing.expect(isKnownKey("gpu.backend"));
    try std.testing.expect(isKnownKey("cpu.debug_symbol_loader"));
    try std.testing.expect(isKnownKey("audio.latency_ms"));
    try std.testing.expect(isKnownKey("debug.log_level"));
}

test "a misspelled key is not a known key" {
    // The entire reason this registry exists: without it, each of these
    // silently keeps the default and the run is debugged as if it applied.
    try std.testing.expect(!isKnownKey("gpu.backends"));
    try std.testing.expect(!isKnownKey("gpu.vulkan_adaptor"));
    try std.testing.expect(!isKnownKey("audio.latency"));
    try std.testing.expect(!isKnownKey("backend"));
    try std.testing.expect(!isKnownKey(""));
}

test "key kinds follow the field types" {
    try std.testing.expectEqual(ValueKind.enumeration, specFor("gpu.backend").?.kind);
    try std.testing.expectEqual(ValueKind.boolean, specFor("gpu.vsync").?.kind);
    try std.testing.expectEqual(ValueKind.integer, specFor("gpu.resolution_scale").?.kind);
    // An optional string is still a string.
    try std.testing.expectEqual(ValueKind.text, specFor("gpu.vulkan_adapter").?.kind);
}

test "enum spellings match the config file text" {
    // stringToEnum is what a loader uses, so the quoted names have to round
    // trip from the exact words a person writes in TOML.
    try std.testing.expectEqual(GpuBackend.vulkan, std.meta.stringToEnum(GpuBackend, "vulkan").?);
    try std.testing.expectEqual(GpuBackend.@"null", std.meta.stringToEnum(GpuBackend, "null").?);
    try std.testing.expectEqual(LogLevel.@"error", std.meta.stringToEnum(LogLevel, "error").?);
    try std.testing.expectEqual(LogLevel.debug, std.meta.stringToEnum(LogLevel, "debug").?);
    try std.testing.expect(std.meta.stringToEnum(GpuBackend, "Vulkan") == null);
}

test "log levels admit by severity, not by ordinal accident" {
    // warning admits error and warning, and nothing chattier.
    try std.testing.expect(LogLevel.warning.admits(.@"error"));
    try std.testing.expect(LogLevel.warning.admits(.warning));
    try std.testing.expect(!LogLevel.warning.admits(.info));
    try std.testing.expect(!LogLevel.warning.admits(.debug));
    // debug admits everything; error admits only itself.
    try std.testing.expect(LogLevel.debug.admits(.debug));
    try std.testing.expect(LogLevel.@"error".admits(.@"error"));
    try std.testing.expect(!LogLevel.@"error".admits(.warning));
}

test "validation names the field that failed" {
    var config = defaults;
    config.gpu.resolution_scale = 0;
    try std.testing.expectEqual(ValidationFailure.resolution_scale_out_of_range, validate(config).?);

    config = defaults;
    config.gpu.resolution_scale = max_resolution_scale + 1;
    try std.testing.expectEqual(ValidationFailure.resolution_scale_out_of_range, validate(config).?);

    config = defaults;
    config.audio.latency_ms = 1;
    try std.testing.expectEqual(ValidationFailure.audio_latency_out_of_range, validate(config).?);

    config = defaults;
    config.audio.master_volume_percent = 101;
    try std.testing.expectEqual(ValidationFailure.master_volume_out_of_range, validate(config).?);
}

test "an empty adapter name is distinguishable from an absent one" {
    // null means "pick one"; "" means the user asked for a nameless adapter,
    // which is a mistake worth reporting rather than silently treating as
    // "pick one".
    var config = defaults;
    try std.testing.expect(config.gpu.vulkan_adapter == null);
    try std.testing.expect(validate(config) == null);

    config.gpu.vulkan_adapter = "";
    try std.testing.expectEqual(ValidationFailure.empty_vulkan_adapter, validate(config).?);

    config.gpu.vulkan_adapter = "Apple M1";
    try std.testing.expect(validate(config) == null);
}

test "defaults are stated once and reachable through the template" {
    try std.testing.expectEqual(GpuBackend.vulkan, defaults.gpu.backend);
    try std.testing.expectEqual(RenderTargetPath.rtl, defaults.gpu.render_target_path);
    try std.testing.expectEqual(AudioDriverKind.coreaudio, defaults.audio.driver);
    try std.testing.expectEqual(LogLevel.warning, defaults.debug.log_level);
    try std.testing.expectEqual(@as(usize, 0), defaults.patches.len);
}
