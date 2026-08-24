//! TOML configuration loading and typed access.
//!
//! The schema — every key, its type, and its default — is
//! `pkg/common/xenia/config-schema`. This file is the runtime half: it parses
//! TOML with the existing `lib/processor/TOML_processor` and binds the result
//! onto the schema's typed structure.
//!
//! ## Unknown keys are reported, not ignored
//!
//! This is the whole reason the schema carries a key registry. A configuration
//! loader that silently ignores a key it does not recognise turns every typo
//! into a setting that appears to be applied and is not:
//!
//!     [gpu]
//!     vulkan_adaptor = "Apple M1"     # note the spelling
//!
//! With silent ignoring, the run proceeds on the default adapter and the user
//! spends the next hour wondering why their adapter selection "does nothing".
//! Every diagnosis that follows is downstream of a mistake that a single string
//! comparison would have caught. So the loader collects unknown keys and the
//! caller can refuse or warn — but it can never not know.
//!
//! ## Type mismatches are errors, not coercions
//!
//! `resolution_scale = "2"` is a mistake. Coercing the string to 2 would be
//! convenient and wrong: it teaches the file's author that quoting is optional,
//! and the next value they quote will be one where it matters.

const std = @import("std");
const schema = @import("xenia_config_schema");
const toml = @import("toml_processor");

pub const Config = schema.Config;

pub const Error = error{
    UnknownKey,
    TypeMismatch,
    ValueOutOfRange,
    InvalidEnumValue,
    OutOfMemory,
};

/// What went wrong, and where.
///
/// A failure that does not name the key sends someone re-reading their whole
/// file, which for a config error is most of the cost.
pub const Diagnostic = struct {
    key: []const u8,
    detail: Detail,

    pub const Detail = union(enum) {
        unknown_key,
        expected_boolean,
        expected_integer,
        expected_text,
        invalid_enum_value,
        out_of_range: schema.ValidationFailure,
    };

    pub fn describe(self: Diagnostic) []const u8 {
        return switch (self.detail) {
            .unknown_key => "not a key Rosette honours; check the spelling",
            .expected_boolean => "expected true or false",
            .expected_integer => "expected an integer, unquoted",
            .expected_text => "expected a quoted string",
            .invalid_enum_value => "not one of the accepted values for this key",
            .out_of_range => "outside the range this key accepts",
        };
    }
};

/// A parsed configuration together with everything questionable about it.
///
/// The result owns every string the config points at. The parse table is
/// released before this function returns, so a borrowed `[]const u8` in a
/// config field would dangle the moment the caller read it — and it would
/// dangle into freed-but-plausible memory, so the adapter name would usually
/// still *look* right in a debugger.
pub const LoadResult = struct {
    config: Config,
    /// Keys that are not in the schema. Collected rather than fatal so a
    /// caller can report all of them at once — fixing typos one run at a time
    /// is its own kind of slow.
    diagnostics: std.ArrayListUnmanaged(Diagnostic) = .empty,
    /// Strings the config fields point into, owned here.
    owned_strings: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn deinit(self: *LoadResult, allocator: std.mem.Allocator) void {
        for (self.diagnostics.items) |diagnostic| allocator.free(diagnostic.key);
        self.diagnostics.deinit(allocator);
        for (self.owned_strings.items) |text| allocator.free(text);
        self.owned_strings.deinit(allocator);
    }

    /// Take ownership of a copy of `text` and return the copy.
    fn own(self: *LoadResult, allocator: std.mem.Allocator, text: []const u8) Error![]const u8 {
        const copy = allocator.dupe(u8, text) catch return error.OutOfMemory;
        self.owned_strings.append(allocator, copy) catch {
            allocator.free(copy);
            return error.OutOfMemory;
        };
        return copy;
    }

    pub fn isClean(self: *const LoadResult) bool {
        return self.diagnostics.items.len == 0;
    }
};

/// Parse `source` and overlay it onto the schema defaults.
///
/// Never fails on an unrecognised or malformed key: those become diagnostics
/// and the corresponding default is kept, so a caller always receives a usable
/// configuration alongside a complete account of what was wrong with the file.
pub fn loadFromSlice(
    allocator: std.mem.Allocator,
    source: []const u8,
) (toml.types.ParseError || Error)!LoadResult {
    var parser = toml.parser.Parser.init(allocator, source);
    var table = try parser.parse();
    defer table.deinit(allocator);

    var result = LoadResult{ .config = schema.defaults };
    errdefer result.deinit(allocator);

    // Top level holds sections. A bare scalar there is never valid — every
    // schema key is sectioned — and a table whose name is not a schema
    // section is equally a mistake. Both are reported; neither is fatal.
    const section_names = [_][]const u8{ "cpu", "gpu", "audio", "debug" };
    for (table.keys()) |key| {
        const value = table.get(key).?;
        const is_section = value.* == .table;
        if (!is_section) {
            try note(allocator, &result, key, .unknown_key);
            continue;
        }
        var known = false;
        for (section_names) |name| {
            if (std.mem.eql(u8, name, key)) known = true;
        }
        if (!known) try note(allocator, &result, key, .unknown_key);
    }

    try bindSection(allocator, &result, &table, "cpu", &result.config.cpu);
    try bindSection(allocator, &result, &table, "gpu", &result.config.gpu);
    try bindSection(allocator, &result, &table, "audio", &result.config.audio);
    try bindSection(allocator, &result, &table, "debug", &result.config.debug);

    if (schema.validate(result.config)) |failure| {
        try note(allocator, &result, keyForFailure(failure), .{ .out_of_range = failure });
        // Fall back to the default for the offending field so the returned
        // config is still usable. A caller that wants strictness checks
        // `isClean` rather than receiving a half-valid structure.
        result.config = restoreDefault(result.config, failure);
    }

    return result;
}

fn keyForFailure(failure: schema.ValidationFailure) []const u8 {
    return switch (failure) {
        .resolution_scale_out_of_range => "gpu.resolution_scale",
        .audio_latency_out_of_range => "audio.latency_ms",
        .master_volume_out_of_range => "audio.master_volume_percent",
        .empty_vulkan_adapter => "gpu.vulkan_adapter",
    };
}

fn restoreDefault(config: Config, failure: schema.ValidationFailure) Config {
    var restored = config;
    switch (failure) {
        .resolution_scale_out_of_range => restored.gpu.resolution_scale =
            schema.defaults.gpu.resolution_scale,
        .audio_latency_out_of_range => restored.audio.latency_ms =
            schema.defaults.audio.latency_ms,
        .master_volume_out_of_range => restored.audio.master_volume_percent =
            schema.defaults.audio.master_volume_percent,
        .empty_vulkan_adapter => restored.gpu.vulkan_adapter =
            schema.defaults.gpu.vulkan_adapter,
    }
    return restored;
}

fn note(
    allocator: std.mem.Allocator,
    result: *LoadResult,
    key: []const u8,
    detail: Diagnostic.Detail,
) Error!void {
    const owned = allocator.dupe(u8, key) catch return error.OutOfMemory;
    result.diagnostics.append(allocator, .{ .key = owned, .detail = detail }) catch {
        allocator.free(owned);
        return error.OutOfMemory;
    };
}

fn bindSection(
    allocator: std.mem.Allocator,
    result: *LoadResult,
    table: *const toml.types.Table,
    comptime section_name: []const u8,
    target: anytype,
) Error!void {
    const entry = table.get(section_name) orelse return;
    const section = switch (entry.*) {
        .table => |*inner| inner,
        else => return,
    };

    for (section.keys()) |key| {
        const value = section.get(key).?;
        var matched = false;
        inline for (@typeInfo(@TypeOf(target.*)).@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                matched = true;
                try bindField(allocator, result, section_name, field.name, value, &@field(target, field.name));
            }
        }
        if (!matched) {
            // Report the dotted path, which is what appears in the file.
            const path = std.fmt.allocPrint(allocator, "{s}.{s}", .{ section_name, key }) catch
                return error.OutOfMemory;
            defer allocator.free(path);
            try note(allocator, result, path, .unknown_key);
        }
    }
}

fn bindField(
    allocator: std.mem.Allocator,
    result: *LoadResult,
    comptime section_name: []const u8,
    comptime field_name: []const u8,
    value: *const toml.types.Value,
    target: anytype,
) Error!void {
    const path = section_name ++ "." ++ field_name;
    const Target = @typeInfo(@TypeOf(target)).pointer.child;

    switch (@typeInfo(Target)) {
        .bool => switch (value.*) {
            .boolean => |flag| target.* = flag,
            else => try note(allocator, result, path, .expected_boolean),
        },
        .int => switch (value.*) {
            // Negative values cannot reach an unsigned field. Wrapping one
            // into a huge positive is exactly the coercion this refuses.
            .integer => |number| {
                if (number >= 0 and number <= std.math.maxInt(Target)) {
                    target.* = @intCast(number);
                } else {
                    try note(allocator, result, path, .expected_integer);
                }
            },
            else => try note(allocator, result, path, .expected_integer),
        },
        .@"enum" => switch (value.*) {
            .string => |text| {
                if (std.meta.stringToEnum(Target, text)) |parsed| {
                    target.* = parsed;
                } else {
                    try note(allocator, result, path, .invalid_enum_value);
                }
            },
            else => try note(allocator, result, path, .expected_text),
        },
        .optional => |optional| switch (@typeInfo(optional.child)) {
            .pointer => switch (value.*) {
                .string => |text| target.* = try result.own(allocator, text),
                else => try note(allocator, result, path, .expected_text),
            },
            else => @compileError("config: unsupported optional field " ++ path),
        },
        .pointer => switch (value.*) {
            .string => |text| target.* = try result.own(allocator, text),
            else => try note(allocator, result, path, .expected_text),
        },
        else => @compileError("config: unsupported field type for " ++ path),
    }
}

test "an empty file yields the defaults and no complaints" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator, "");
    defer result.deinit(allocator);
    try std.testing.expect(result.isClean());
    try std.testing.expectEqual(schema.defaults.gpu.backend, result.config.gpu.backend);
    try std.testing.expectEqual(schema.defaults.audio.latency_ms, result.config.audio.latency_ms);
}

test "a value overrides its default" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\resolution_scale = 2
        \\vsync = false
        \\
        \\[audio]
        \\latency_ms = 40
    );
    defer result.deinit(allocator);
    try std.testing.expect(result.isClean());
    try std.testing.expectEqual(@as(u32, 2), result.config.gpu.resolution_scale);
    try std.testing.expectEqual(false, result.config.gpu.vsync);
    try std.testing.expectEqual(@as(u32, 40), result.config.audio.latency_ms);
    // Untouched keys keep their defaults.
    try std.testing.expectEqual(schema.defaults.gpu.backend, result.config.gpu.backend);
}

test "an enum is read from its config-file spelling" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\backend = "metal"
        \\render_target_path = "ts"
        \\
        \\[debug]
        \\log_level = "debug"
    );
    defer result.deinit(allocator);
    try std.testing.expect(result.isClean());
    try std.testing.expectEqual(schema.GpuBackend.metal, result.config.gpu.backend);
    try std.testing.expectEqual(schema.RenderTargetPath.ts, result.config.gpu.render_target_path);
    try std.testing.expectEqual(schema.LogLevel.debug, result.config.debug.log_level);
}

test "the keyword-spelled enum values round trip" {
    // `null` and `error` collide with Zig keywords but are what a person
    // writes in the file, so they must be accepted verbatim.
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\backend = "null"
        \\
        \\[debug]
        \\log_level = "error"
    );
    defer result.deinit(allocator);
    try std.testing.expect(result.isClean());
    try std.testing.expectEqual(schema.GpuBackend.@"null", result.config.gpu.backend);
    try std.testing.expectEqual(schema.LogLevel.@"error", result.config.debug.log_level);
}

test "a misspelled key is reported and named" {
    // The entire reason for the key registry. Silently ignoring this makes
    // the adapter selection appear to do nothing.
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\vulkan_adaptor = "Apple M1"
    );
    defer result.deinit(allocator);
    try std.testing.expect(!result.isClean());
    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.items.len);
    try std.testing.expectEqualStrings("gpu.vulkan_adaptor", result.diagnostics.items[0].key);
    try std.testing.expectEqualStrings(
        "not a key Rosette honours; check the spelling",
        result.diagnostics.items[0].describe(),
    );
    // The correctly spelled key kept its default.
    try std.testing.expect(result.config.gpu.vulkan_adapter == null);
}

test "every unknown key is reported, not just the first" {
    // Fixing typos one run at a time is its own kind of slow.
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\nonsense = 1
        \\garbage = 2
        \\
        \\[audio]
        \\also_wrong = 3
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), result.diagnostics.items.len);
}

test "a quoted number is a type error, not a coercion" {
    // Coercing teaches the file's author that quoting is optional, and the
    // next value they quote will be one where it matters.
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\resolution_scale = "2"
    );
    defer result.deinit(allocator);
    try std.testing.expect(!result.isClean());
    try std.testing.expectEqualStrings("gpu.resolution_scale", result.diagnostics.items[0].key);
    try std.testing.expectEqualStrings(
        "expected an integer, unquoted",
        result.diagnostics.items[0].describe(),
    );
    try std.testing.expectEqual(@as(u32, 1), result.config.gpu.resolution_scale);
}

test "a negative value cannot wrap into an unsigned field" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[audio]
        \\latency_ms = -1
    );
    defer result.deinit(allocator);
    try std.testing.expect(!result.isClean());
    // Not 4294967295.
    try std.testing.expectEqual(schema.defaults.audio.latency_ms, result.config.audio.latency_ms);
}

test "an unaccepted enum value is named as such" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\backend = "opengl"
    );
    defer result.deinit(allocator);
    try std.testing.expectEqualStrings(
        "not one of the accepted values for this key",
        result.diagnostics.items[0].describe(),
    );
    try std.testing.expectEqual(schema.defaults.gpu.backend, result.config.gpu.backend);
}

test "a wrong boolean type is reported" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\vsync = 1
    );
    defer result.deinit(allocator);
    try std.testing.expectEqualStrings("expected true or false", result.diagnostics.items[0].describe());
    try std.testing.expectEqual(true, result.config.gpu.vsync);
}

test "an out of range value is reported and reverted" {
    // The returned config stays usable; a caller wanting strictness checks
    // isClean rather than receiving a half-valid structure.
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\resolution_scale = 99
    );
    defer result.deinit(allocator);
    try std.testing.expect(!result.isClean());
    try std.testing.expectEqualStrings("gpu.resolution_scale", result.diagnostics.items[0].key);
    try std.testing.expectEqual(schema.defaults.gpu.resolution_scale, result.config.gpu.resolution_scale);
    try std.testing.expect(schema.validate(result.config) == null);
}

test "a bare top level key is not a valid setting" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator, "backend = \"vulkan\"");
    defer result.deinit(allocator);
    try std.testing.expect(!result.isClean());
    try std.testing.expectEqualStrings("backend", result.diagnostics.items[0].key);
}

test "an adapter name outlives the parse table it came from" {
    // The parse table is freed before loadFromSlice returns. A borrowed
    // slice here would dangle into freed-but-plausible memory, so the name
    // would usually still look right while being read after free.
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\vulkan_adapter = "Apple M1 Pro"
    );
    defer result.deinit(allocator);
    try std.testing.expect(result.isClean());
    try std.testing.expectEqualStrings("Apple M1 Pro", result.config.gpu.vulkan_adapter.?);
}

test "an empty adapter name is refused rather than treated as absent" {
    const allocator = std.testing.allocator;
    var result = try loadFromSlice(allocator,
        \\[gpu]
        \\vulkan_adapter = ""
    );
    defer result.deinit(allocator);
    try std.testing.expect(!result.isClean());
    try std.testing.expect(result.config.gpu.vulkan_adapter == null);
}
