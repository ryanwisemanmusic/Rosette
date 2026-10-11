//! Opt-in GFXReconstruct capture of the Vulkan stream Rosette sends to the
//! host driver.
//!
//! Rosette cannot see inside a frame: the brightness ladder reads three images
//! after the frame has finished, and Halo 3's campaign picture is already red
//! and blown out in the first of them (the swap texture), so the fault is
//! somewhere in the dozens of render passes before it. A GFXReconstruct
//! capture of one campaign frame records exactly what Rosette handed the
//! native driver, and it replays on this Mac without the emulator: every pass
//! can then be dumped, the same commands replayed on another MoltenVK, and
//! the stream checked by the Khronos validation layer.
//!
//! `ROSETTE_VULKAN_GFXR` selects the plan (`ROSETTE_VULKAN_CAPTURE` is the
//! older swapchain-PNG capture and is unrelated):
//!   unset, `0`, `off`        no capture (the default; nothing is loaded)
//!   `1`, `hotkey`            press F10 in game to capture one frame
//!   `hotkey:F7`              another trigger key (F1-F12, TAB, CONTROL)
//!   `frames:4600`, `4600`    capture fixed frames (GFXReconstruct counts
//!                            presents from 1; ranges as `3000,4600-4601`)
//!
//! The trigger defaults to F10 because Xenia's emulator window binds F1-F9,
//! F11 and F12 (`app/emulator_window.cc`), and Rosette forwards keystrokes to
//! it. Memory tracking is GFXReconstruct's `assisted` mode: its default
//! page-guard mode traps writes with SIGSEGV, which Rosette already owns for
//! guest memory, so the forwarder flushes every mapping before each submit
//! instead.
const std = @import("std");

pub const Mode = enum { off, hotkey, frames };

pub const layer_name = "VK_LAYER_LUNARG_gfxreconstruct";
pub const layer_manifest = "VkLayer_gfxreconstruct.json";
pub const default_key = "F10";
pub const environment = "ROSETTE_VULKAN_GFXR";
pub const layer_path_environment = "ROSETTE_VULKAN_GFXR_LAYER_PATH";

pub const Plan = struct {
    mode: Mode = .off,
    /// GFXRECON_CAPTURE_TRIGGER for `.hotkey`.
    key: []const u8 = default_key,
    /// GFXRECON_CAPTURE_FRAMES for `.frames`.
    frames: []const u8 = "",
    /// The raw value did not parse; the plan is off and the log says why.
    rejected: bool = false,

    pub fn armed(self: Plan) bool {
        return self.mode != .off;
    }
};

const trigger_keys = [_][]const u8{
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "TAB", "CONTROL",
};

fn validKey(key: []const u8) bool {
    for (trigger_keys) |candidate| {
        if (std.ascii.eqlIgnoreCase(key, candidate)) return true;
    }
    return false;
}

/// GFXReconstruct's frame-list syntax: comma-separated frames or
/// `first-last` ranges, ascending, 1-based.
fn validFrames(list: []const u8) bool {
    if (list.len == 0) return false;
    var previous: u64 = 0;
    var ranges = std.mem.splitScalar(u8, list, ',');
    while (ranges.next()) |range| {
        const dash = std.mem.indexOfScalar(u8, range, '-');
        const first_text = if (dash) |at| range[0..at] else range;
        const last_text = if (dash) |at| range[at + 1 ..] else range;
        const first = std.fmt.parseInt(u64, first_text, 10) catch return false;
        const last = std.fmt.parseInt(u64, last_text, 10) catch return false;
        if (first == 0 or last < first or first <= previous) return false;
        previous = last;
    }
    return true;
}

pub fn parse(raw: ?[]const u8) Plan {
    const value = std.mem.trim(u8, raw orelse return .{}, " \t");
    if (value.len == 0 or std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "off")) return .{};
    if (std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "hotkey")) return .{ .mode = .hotkey };
    if (std.ascii.startsWithIgnoreCase(value, "hotkey:")) {
        const key = value["hotkey:".len..];
        if (!validKey(key)) return .{ .rejected = true };
        return .{ .mode = .hotkey, .key = key };
    }
    const frames = if (std.ascii.startsWithIgnoreCase(value, "frames:")) value["frames:".len..] else value;
    if (validFrames(frames)) return .{ .mode = .frames, .frames = frames };
    return .{ .rejected = true };
}

/// Compare dotted version strings numerically (`1.4.341.0` > `1.3`). A name
/// that is not a version (`vulkan`, `Releases`) is never newer than one that is.
pub fn versionNewer(candidate: []const u8, current: []const u8) bool {
    const a_valid = isVersion(candidate);
    const b_valid = isVersion(current);
    if (a_valid != b_valid) return a_valid;
    if (!a_valid) return false;
    var a_parts = std.mem.splitScalar(u8, candidate, '.');
    var b_parts = std.mem.splitScalar(u8, current, '.');
    while (true) {
        const a_part = a_parts.next();
        const b_part = b_parts.next();
        if (a_part == null and b_part == null) return false;
        const a_value = if (a_part) |text| std.fmt.parseInt(u64, text, 10) catch 0 else 0;
        const b_value = if (b_part) |text| std.fmt.parseInt(u64, text, 10) catch 0 else 0;
        if (a_value != b_value) return a_value > b_value;
    }
}

fn isVersion(name: []const u8) bool {
    if (name.len == 0) return false;
    var parts = std.mem.splitScalar(u8, name, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |c| if (!std.ascii.isDigit(c)) return false;
        count += 1;
    }
    return count >= 2;
}

/// The directory a capture file and its log belong in: beside the run's
/// trace log when the runner exported one, else the working directory.
pub fn runDirectory(trace_path: ?[]const u8) []const u8 {
    const path = trace_path orelse return ".";
    return std.fs.path.dirname(path) orelse ".";
}

test "the capture plan is off unless asked for, and a malformed value stays off" {
    try std.testing.expectEqual(Mode.off, parse(null).mode);
    try std.testing.expectEqual(Mode.off, parse("0").mode);
    try std.testing.expectEqual(Mode.off, parse("off").mode);
    try std.testing.expect(!parse("").rejected);

    const hotkey = parse("1");
    try std.testing.expectEqual(Mode.hotkey, hotkey.mode);
    try std.testing.expectEqualStrings("F10", hotkey.key);
    try std.testing.expectEqualStrings("F7", parse("hotkey:F7").key);
    try std.testing.expect(parse("hotkey:F13").rejected);
    try std.testing.expect(!parse("hotkey:F13").armed());

    const frames = parse("frames:3000,4600-4601");
    try std.testing.expectEqual(Mode.frames, frames.mode);
    try std.testing.expectEqualStrings("3000,4600-4601", frames.frames);
    try std.testing.expectEqual(Mode.frames, parse("4600").mode);
    // GFXReconstruct wants ascending, non-overlapping, 1-based ranges.
    try std.testing.expect(parse("4600,3000").rejected);
    try std.testing.expect(parse("0").mode == .off);
    try std.testing.expect(parse("frames:0").rejected);
    try std.testing.expect(parse("frames:5-4").rejected);
    try std.testing.expect(parse("frames:12a").rejected);
}

test "the newest Vulkan SDK directory wins, and non-version names never do" {
    try std.testing.expect(versionNewer("1.4.341.0", "1.3"));
    try std.testing.expect(!versionNewer("1.3", "1.4.341.0"));
    try std.testing.expect(versionNewer("1.4.341.0", "vulkan"));
    try std.testing.expect(!versionNewer("vulkan", "1.4.341.0"));
    try std.testing.expect(!versionNewer("Releases", "vulkan"));
    // A trailing zero component is the same version, newer in neither order.
    try std.testing.expect(!versionNewer("1.3.275.0", "1.3.275"));
    try std.testing.expect(!versionNewer("1.3.275", "1.3.275.0"));
    try std.testing.expect(versionNewer("1.3.275.1", "1.3.275"));
}

test "captures land beside the run's trace log" {
    try std.testing.expectEqualStrings("/runs/current", runDirectory("/runs/current/rosette-xenia.trace.log"));
    try std.testing.expectEqualStrings(".", runDirectory(null));
}
