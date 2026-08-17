//! Attributing a guest address to the module image that should contain it.
//!
//! A guest fault reports a program counter. On its own that is a number: it
//! says where execution stopped and nothing about how it got there. The
//! difference between "the title branched into its own code and something went
//! wrong there" and "the title branched into an image that was never loaded" is
//! the whole diagnosis, and neither the address nor the register file
//! distinguishes them.
//!
//! A title that loads plug-in modules at run time (audio codecs, middleware)
//! asks the kernel to map an image, gets a handle back, and later calls into
//! it. If a later load of an already-loaded image silently returns a null
//! handle, the title carries on with a stale or zero base and eventually
//! branches into a region it believes is code. The fault surfaces thousands of
//! instructions after the load that actually failed, in a module nobody
//! mentioned, and the load itself logged no error — it returned a value.
//!
//! So this keeps two things and joins them:
//!
//!   * **Where each module image lives**, from the allocations the guest
//!     performs while decoding an image, so any address can be named.
//!   * **What each completed load transaction returned**, from an explicit
//!     post-call result emitted by Xenia. Export-entry traces contain the
//!     caller's old out-parameter value and are never treated as results.
//!
//! It records what it observed and never guesses. An address in no known image
//! is reported as exactly that, which is itself a strong finding: guest code
//! does not live outside the images the guest loaded.

const std = @import("std");

/// Modules tracked. A title's plug-in set is small and bounded; overflow is
/// counted rather than silently dropping the newest, because a map that
/// forgot an image would attribute its addresses to nothing and read as
/// "unmapped", which is the exact conclusion the map exists to justify.
pub const max_modules: usize = 32;
pub const max_name: usize = 96;

pub const Module = struct {
    name: [max_name]u8 = undefined,
    name_len: usize = 0,
    base: u64 = 0,
    size: u64 = 0,
    /// Loads of this module that returned a usable handle.
    loads_succeeded: u32 = 0,
    /// Loads that returned a failure status or no usable handle. A load that
    /// resolved its path and then returned neither SUCCESS nor a valid handle
    /// is the silent failure this map exists to catch.
    loads_failed: u32 = 0,
    /// Handle from the most recent load, success or not.
    last_handle: u64 = 0,
    /// Status from the most recent completed load transaction.
    last_status: u32 = 0,
    active: bool = false,

    pub fn nameSlice(self: *const Module) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn contains(self: *const Module, address: u64) bool {
        return self.active and self.size != 0 and
            address >= self.base and address < self.base +| self.size;
    }
};

pub const Attribution = struct {
    name: []const u8,
    base: u64,
    offset: u64,
    size: u64,
    loads_failed: u32,
    last_handle: u64,
    last_status: u32,
};

pub const Map = struct {
    modules: [max_modules]Module = [_]Module{.{}} ** max_modules,
    count: usize = 0,
    overflowed: u32 = 0,
    /// Failed completed load transactions, across every module.
    failed_loads: u32 = 0,

    fn find(self: *Map, name: []const u8) ?*Module {
        for (self.modules[0..self.count]) |*module| {
            if (!module.active) continue;
            if (eqlIgnoreCase(module.nameSlice(), name)) return module;
        }
        return null;
    }

    fn insert(self: *Map, name: []const u8) ?*Module {
        if (self.count == max_modules) {
            self.overflowed +|= 1;
            return null;
        }
        const module = &self.modules[self.count];
        self.count += 1;
        const length = @min(name.len, max_name);
        @memcpy(module.name[0..length], name[0..length]);
        module.name_len = length;
        module.active = true;
        return module;
    }

    /// Record that an image was mapped at `base` for `size` bytes.
    ///
    /// Re-mapping the same name updates the placement rather than adding a
    /// second entry: a module reloaded at a new base has moved, and the map
    /// must answer for where it is now, not where it was.
    pub fn noteImage(self: *Map, name: []const u8, base: u64, size: u64) void {
        if (name.len == 0 or base == 0 or size == 0) return;
        const module = self.find(name) orelse (self.insert(name) orelse return);
        module.base = base;
        module.size = size;
    }

    /// Record the authoritative result of a completed load transaction.
    ///
    /// A failed load is recorded against the module even when its image is
    /// already mapped — that is precisely the interesting case, because the
    /// caller is left holding nothing for an image that exists.
    pub fn noteLoadResult(self: *Map, name: []const u8, status: u32, handle: u64) void {
        if (name.len == 0) return;
        const module = self.find(name) orelse (self.insert(name) orelse return);
        module.last_handle = handle;
        module.last_status = status;
        if (status != 0 or handle == 0) {
            module.loads_failed +|= 1;
            self.failed_loads +|= 1;
        } else {
            module.loads_succeeded +|= 1;
        }
    }

    /// Name the image containing `address`, or null when no image does.
    pub fn attribute(self: *const Map, address: u64) ?Attribution {
        for (self.modules[0..self.count]) |*module| {
            if (!module.contains(address)) continue;
            return .{
                .name = module.nameSlice(),
                .base = module.base,
                .offset = address - module.base,
                .size = module.size,
                .loads_failed = module.loads_failed,
                .last_handle = module.last_handle,
                .last_status = module.last_status,
            };
        }
        return null;
    }

    /// Whether any load anywhere failed or returned a null handle. A run with
    /// one of these and a fault in an unrelated module is still a run whose
    /// module table is not what the title believes it is.
    pub fn hasFailedLoads(self: *const Map) bool {
        return self.failed_loads != 0;
    }

    pub fn active(self: *const Map) bool {
        return self.count != 0;
    }
};

/// Guest paths are case-insensitive, so the map's identity must be too.
/// Matching case-sensitively would file `Game:\Waves\L360.dll` and
/// `game:\waves\l360.dll` as two modules and lose the connection between the
/// image that is mapped and the load that failed to find it.
pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

/// Extract the leaf name from a guest path, ignoring separator style.
/// Guest paths mix `\` and `/` and carry a device prefix; the leaf is the
/// stable identity across `game:\waves\l360.dll` and `\Device\Cdrom0\waves\L360.dll`.
pub fn leafName(path: []const u8) []const u8 {
    var start: usize = 0;
    for (path, 0..) |byte, index| {
        if (byte == '\\' or byte == '/' or byte == ':') start = index + 1;
    }
    return path[start..];
}

/// Text between the first `open` and the next `close` after it.
pub fn between(text: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, text, open) orelse return null;
    const rest = text[start + open.len ..];
    const end = std.mem.indexOf(u8, rest, close) orelse return null;
    return rest[0..end];
}

/// Text inside the LAST balanced-looking `open`/`close` pair. Guest trace lines
/// put the interesting return value last, after the arguments.
pub fn lastBetween(text: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
    // Anchor on the last `open`, then take the first `close` after it. Anchoring
    // on the last `close` instead picks up the call's own outer parenthesis and
    // returns the inner group plus a stray delimiter.
    const open_at = std.mem.lastIndexOf(u8, text, open) orelse return null;
    const rest = text[open_at + open.len ..];
    const end = std.mem.indexOf(u8, rest, close) orelse return null;
    return rest[0..end];
}

/// Hexadecimal value following `key`, stopping at the first non-hex byte.
/// Returns null rather than a partial value, so a changed log format degrades
/// to "not observed" instead of to a wrong number.
pub fn hexAfter(text: []const u8, key: []const u8) ?u64 {
    const at = std.mem.indexOf(u8, text, key) orelse return null;
    const rest = text[at + key.len ..];
    var length: usize = 0;
    while (length < rest.len and std.ascii.isHex(rest[length])) length += 1;
    if (length == 0 or length > 16) return null;
    return std.fmt.parseInt(u64, rest[0..length], 16) catch null;
}

test "line fields are extracted, and a changed format yields nothing" {
    const image = "[DEBUG] XexModule::ReadImage post-decode transition path='\\Device\\Cdrom0\\waves\\L360.dll' patch=NO base=89400000 image_size=00070000";
    try std.testing.expectEqualStrings(
        "\\Device\\Cdrom0\\waves\\L360.dll",
        between(image, "path='", "'").?,
    );
    try std.testing.expectEqual(@as(?u64, 0x8940_0000), hexAfter(image, " base="));
    try std.testing.expectEqual(@as(?u64, 0x7_0000), hexAfter(image, " image_size="));

    const load = "XEX MODULE LOAD RESULT: name='Game:\\Waves\\L360.dll' status=00000000 hmodule=30070000 load_count=3 source=existing";
    try std.testing.expectEqualStrings("Game:\\Waves\\L360.dll", between(load, "name='", "'").?);
    try std.testing.expectEqual(@as(?u64, 0), hexAfter(load, " status="));
    try std.testing.expectEqual(@as(?u64, 0x3007_0000), hexAfter(load, " hmodule="));

    // Absent keys and malformed values are reported as absent, never guessed.
    try std.testing.expectEqual(@as(?u64, null), hexAfter(image, " nonexistent="));
    try std.testing.expectEqual(@as(?[]const u8, null), between(image, "path=\"", "\""));
    try std.testing.expectEqual(@as(?u64, null), hexAfter("base=zzz", "base="));
}

test "an address inside a mapped image is named with its offset" {
    var map = Map{};
    map.noteImage("l360.dll", 0x8940_0000, 0x7_0000);

    const found = map.attribute(0x8941_5B00) orelse return error.TestFailed;
    try std.testing.expectEqualStrings("l360.dll", found.name);
    try std.testing.expectEqual(@as(u64, 0x8940_0000), found.base);
    try std.testing.expectEqual(@as(u64, 0x1_5B00), found.offset);

    // Just past the end is not inside it. An image that ends is a fact worth
    // keeping, because a branch just past one is a different bug.
    try std.testing.expectEqual(@as(?Attribution, null), map.attribute(0x8947_0000));
    try std.testing.expect(map.attribute(0x8946_FFFF) != null);
}

test "an address in no image is reported as such" {
    var map = Map{};
    map.noteImage("default.xex", 0x8200_0000, 0x12A_0000);
    try std.testing.expectEqual(@as(?Attribution, null), map.attribute(0x8941_5B00));
    try std.testing.expect(map.attribute(0x8200_0004) != null);
}

// The failure this exists for: an image is mapped, a later load of the same
// image under different casing returns handle 0, and the title then branches
// into the image believing it holds a valid handle. Neither half is an error
// on its own; the join is.
test "a null-handle load is carried on the module the fault lands in" {
    var map = Map{};
    map.noteImage("l360.dll", 0x8940_0000, 0x7_0000);
    map.noteLoadResult("l360.dll", 0, 0x3007_0000);
    try std.testing.expect(!map.hasFailedLoads());

    // Same module, different casing, no handle returned.
    map.noteLoadResult("L360.dll", 0xC000_000F, 0);
    try std.testing.expect(map.hasFailedLoads());

    const found = map.attribute(0x8941_5B00) orelse return error.TestFailed;
    try std.testing.expectEqualStrings("l360.dll", found.name);
    try std.testing.expectEqual(@as(u32, 1), found.loads_failed);
    try std.testing.expectEqual(@as(u64, 0), found.last_handle);
    try std.testing.expectEqual(@as(u32, 0xC000_000F), found.last_status);
    // One module, not two: the casing must not split the identity.
    try std.testing.expectEqual(@as(usize, 1), map.count);
}

test "guest path leaf names survive device prefixes and separator style" {
    try std.testing.expectEqualStrings("l360.dll", leafName("game:\\waves\\l360.dll"));
    try std.testing.expectEqualStrings("L360.dll", leafName("\\Device\\Cdrom0\\Waves\\L360.dll"));
    try std.testing.expectEqualStrings("default.xex", leafName("game:\\default.xex"));
    try std.testing.expectEqualStrings("q10.dll", leafName("q10.dll"));
    try std.testing.expectEqualStrings("", leafName("game:\\waves\\"));
}

test "case-insensitive identity matches guest path semantics" {
    try std.testing.expect(eqlIgnoreCase("L360.dll", "l360.dll"));
    try std.testing.expect(eqlIgnoreCase("WaveShell-Xbox.dll", "waveshell-xbox.DLL"));
    try std.testing.expect(!eqlIgnoreCase("l360.dll", "q10.dll"));
    try std.testing.expect(!eqlIgnoreCase("l360.dll", "l360.dl"));
}

test "a module remapped at a new base answers for where it is now" {
    var map = Map{};
    map.noteImage("plugin.dll", 0x8940_0000, 0x1_0000);
    map.noteImage("plugin.dll", 0x8A00_0000, 0x2_0000);
    try std.testing.expectEqual(@as(usize, 1), map.count);
    try std.testing.expectEqual(@as(?Attribution, null), map.attribute(0x8940_0000));
    const found = map.attribute(0x8A00_5000) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 0x5000), found.offset);
}

test "the map refuses degenerate placements instead of recording them" {
    var map = Map{};
    map.noteImage("", 0x1000, 0x1000);
    map.noteImage("zero-base.dll", 0, 0x1000);
    map.noteImage("zero-size.dll", 0x1000, 0);
    try std.testing.expectEqual(@as(usize, 0), map.count);
    try std.testing.expect(!map.active());
}

test "overflow is counted rather than silently dropping images" {
    var map = Map{};
    var buffer: [32]u8 = undefined;
    for (0..max_modules + 4) |i| {
        const name = std.fmt.bufPrint(&buffer, "module{d}.dll", .{i}) catch unreachable;
        map.noteImage(name, 0x8000_0000 + i * 0x1_0000, 0x1_0000);
    }
    try std.testing.expectEqual(max_modules, map.count);
    try std.testing.expectEqual(@as(u32, 4), map.overflowed);
}
