const std = @import("std");

pub const CompatConfig = struct {
    prefer_rosette: ?bool = null,
    allow_rosetta2_fallback: ?bool = null,
    prefer_intel_slice: ?bool = null,
    strict: ?bool = null,
    abort_on_fallback: ?bool = null,
    abort_on_unsupported: ?bool = null,
    trace: ?bool = null,
};

pub fn load(io: std.Io, allocator: std.mem.Allocator) !CompatConfig {
    const path = configPath(allocator) catch return .{};
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024)) catch return .{};
    return parse(contents);
}

pub fn parse(contents: []const u8) CompatConfig {
    var cfg = CompatConfig{};
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |pos| raw_line[0..pos] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r\n");
        if (line.len == 0) continue;

        if (line[0] == '[' and line[line.len - 1] == ']') {
            section = std.mem.trim(u8, line[1 .. line.len - 1], " \t\r\n");
            continue;
        }
        if (!std.ascii.eqlIgnoreCase(section, "compat")) continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t\r\n");
        const value = trimTomlValue(std.mem.trim(u8, line[eq + 1 ..], " \t\r\n"));
        const parsed_bool = parseBoolText(value) orelse continue;

        if (std.ascii.eqlIgnoreCase(key, "prefer_rosette")) {
            cfg.prefer_rosette = parsed_bool;
        } else if (std.ascii.eqlIgnoreCase(key, "allow_rosetta2_fallback")) {
            cfg.allow_rosetta2_fallback = parsed_bool;
        } else if (std.ascii.eqlIgnoreCase(key, "prefer_intel_slice")) {
            cfg.prefer_intel_slice = parsed_bool;
        } else if (std.ascii.eqlIgnoreCase(key, "strict") or
            std.ascii.eqlIgnoreCase(key, "strict_rosette"))
        {
            cfg.strict = parsed_bool;
        } else if (std.ascii.eqlIgnoreCase(key, "abort_on_fallback")) {
            cfg.abort_on_fallback = parsed_bool;
        } else if (std.ascii.eqlIgnoreCase(key, "abort_on_unsupported") or
            std.ascii.eqlIgnoreCase(key, "abort_on_failure") or
            std.ascii.eqlIgnoreCase(key, "trap_on_failure"))
        {
            cfg.abort_on_unsupported = parsed_bool;
        } else if (std.ascii.eqlIgnoreCase(key, "trace")) {
            cfg.trace = parsed_bool;
        }
    }
    return cfg;
}

fn configPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = getenvSlice("HOME") orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, ".rosette", "config.toml" });
}

fn trimTomlValue(value: []const u8) []const u8 {
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) {
            return value[1 .. value.len - 1];
        }
    }
    return value;
}

pub fn parseBoolText(value: []const u8) ?bool {
    if (std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on") or
        std.ascii.eqlIgnoreCase(value, "enabled"))
    {
        return true;
    }
    if (std.mem.eql(u8, value, "0") or
        std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.ascii.eqlIgnoreCase(value, "off") or
        std.ascii.eqlIgnoreCase(value, "disabled"))
    {
        return false;
    }
    return null;
}

fn getenvSlice(name: [:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.sliceTo(value, 0);
}

test "parses compat policy keys" {
    const cfg = parse(
        \\[compat]
        \\allow_rosetta2_fallback = false
        \\trace = true
        \\prefer_intel_slice = "on"
        \\strict = yes
        \\abort_on_fallback = enabled
        \\abort_on_failure = 1
    );
    try std.testing.expectEqual(false, cfg.allow_rosetta2_fallback.?);
    try std.testing.expectEqual(true, cfg.trace.?);
    try std.testing.expectEqual(true, cfg.prefer_intel_slice.?);
    try std.testing.expectEqual(true, cfg.strict.?);
    try std.testing.expectEqual(true, cfg.abort_on_fallback.?);
    try std.testing.expectEqual(true, cfg.abort_on_unsupported.?);
}
