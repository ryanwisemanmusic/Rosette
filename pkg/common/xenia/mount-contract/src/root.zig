//! Route-independent: the Xbox 360 VFS namespace — device names, their
//! separator, and what each mount may be used for.
//!
//! ## Why the separator is the fact that matters most
//!
//! The console's device namespace is `game:\path\to\file`. Two characters in
//! that are hostile on a Mac: the colon, which macOS historically treats as a
//! path separator itself, and the backslash, which is an ordinary legal
//! filename character on a POSIX filesystem. So a guest path passed through to
//! the host without translation does not fail — it *succeeds*, creating or
//! looking for a single file literally named `game:\path\to\file` in the
//! current directory. The title then reports a missing asset while the host
//! filesystem shows a file that looks almost right.
//!
//! Making the device prefixes and the separator comptime facts means a
//! translation layer can assert it consumed a prefix rather than assume it did.
//!
//! ## Read-only is a fact, not a policy
//!
//! `game:` is a disc image. A write to it cannot succeed on real hardware, so a
//! runtime that permits one is not being permissive — it is accepting a write
//! the title will never see again, and the save that vanishes is debugged as a
//! save bug.
//!
//! ## What this package is not
//!
//! * It is not a filesystem. It opens nothing and lists nothing.
//! * It holds no mount table. Which host directory backs `game:` on this
//!   machine is runtime configuration and belongs to `lib/io/`.
//! * It does not translate paths. `lib/io/path_translation.zig` owns that; this
//!   package owns the vocabulary it translates from.

const std = @import("std");

/// The guest path separator. A legal filename byte on the host, which is why
/// an untranslated path silently becomes one long filename.
pub const guest_separator: u8 = '\\';
/// The host path separator.
pub const host_separator: u8 = '/';
/// Terminates a device name.
pub const device_delimiter: u8 = ':';

pub const MountKind = enum(u8) {
    /// The title's own disc image.
    disc,
    /// Persistent per-user storage.
    save,
    /// Storage the title may use and lose.
    cache,
    /// Kernel-provided, not backed by a host directory.
    system,
};

pub const Mount = struct {
    /// The device name *without* its colon.
    device: []const u8,
    kind: MountKind,
    writable: bool,

    /// The full prefix a guest path starts with, colon included.
    ///
    /// Comptime-concatenated so a caller cannot forget the colon, which is the
    /// mistake that makes `gamefoo\bar` match the `game` device.
    pub fn prefix(comptime self: Mount) []const u8 {
        return self.device ++ [_]u8{device_delimiter};
    }
};

pub const game: Mount = .{ .device = "game", .kind = .disc, .writable = false };
pub const d: Mount = .{ .device = "d", .kind = .disc, .writable = false };
pub const save: Mount = .{ .device = "save", .kind = .save, .writable = true };
pub const cache: Mount = .{ .device = "cache", .kind = .cache, .writable = true };
pub const system_mount: Mount = .{ .device = "systemroot", .kind = .system, .writable = false };

pub const mounts = [_]Mount{ game, d, save, cache, system_mount };

/// The mount a guest path names, or null when it carries no device prefix.
///
/// Requires the colon. A bare `game` is not a device reference, and matching it
/// as one would capture every path beginning with those four letters.
pub fn mountFor(path: []const u8) ?Mount {
    const colon = std.mem.indexOfScalar(u8, path, device_delimiter) orelse return null;
    const device = path[0..colon];
    if (device.len == 0) return null;
    for (mounts) |mount| {
        if (std.ascii.eqlIgnoreCase(mount.device, device)) return mount;
    }
    return null;
}

/// The remainder of a guest path after its device prefix.
///
/// Null when there is no recognised prefix — which is the answer a translator
/// must refuse on, rather than passing the whole string to the host.
pub fn pathAfterDevice(path: []const u8) ?[]const u8 {
    const colon = std.mem.indexOfScalar(u8, path, device_delimiter) orelse return null;
    if (mountFor(path) == null) return null;
    return path[colon + 1 ..];
}

/// Whether a path could be handed to the host as-is.
///
/// Always false for anything carrying a device prefix or a guest separator.
/// The predicate a translator asserts *before* the host call, because after it
/// the failure has already turned into a plausible-looking wrong file.
pub fn isHostReady(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, device_delimiter) != null) return false;
    if (std.mem.indexOfScalar(u8, path, guest_separator) != null) return false;
    return true;
}

/// Whether a write to this path could succeed on real hardware.
pub fn isWritable(path: []const u8) bool {
    const mount = mountFor(path) orelse return false;
    return mount.writable;
}

pub fn contractIsWellFormed() bool {
    if (guest_separator == host_separator) return false;
    if (game.writable) return false;
    if (!save.writable) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "a guest path is not host ready" {
    // The central failure: this string is a *legal* host filename, so passing
    // it through creates one file with a strange name instead of failing.
    try std.testing.expect(!isHostReady("game:\\media\\maps\\halo3.map"));
    try std.testing.expect(!isHostReady("game:"));
    try std.testing.expect(!isHostReady("media\\maps"));
    // Only a path with neither marker is ready.
    try std.testing.expect(isHostReady("media/maps/halo3.map"));
    try std.testing.expect(isHostReady(""));
}

test "the separators differ, and the guest one is legal on the host" {
    try std.testing.expectEqual(@as(u8, '\\'), guest_separator);
    try std.testing.expectEqual(@as(u8, '/'), host_separator);
    try std.testing.expect(guest_separator != host_separator);
    // Not a control character or a null: nothing about it will make a host
    // call fail, which is precisely the problem.
    try std.testing.expect(std.ascii.isPrint(guest_separator));
}

test "a device prefix requires its colon" {
    // Matching on the bare name would capture every path starting with those
    // letters, so `gameplay\x` would resolve to the disc.
    try std.testing.expect(mountFor("game:\\x") != null);
    try std.testing.expect(mountFor("game") == null);
    try std.testing.expect(mountFor("gameplay") == null);
    try std.testing.expect(mountFor("") == null);
    try std.testing.expect(mountFor(":\\x") == null);
    // `gameplay:` is a different device, and an unknown one.
    try std.testing.expect(mountFor("gameplay:\\x") == null);
}

test "device names are matched case insensitively" {
    // Titles are inconsistent about case and the console does not care.
    try std.testing.expectEqualStrings("game", mountFor("GAME:\\x").?.device);
    try std.testing.expectEqualStrings("game", mountFor("Game:\\x").?.device);
    try std.testing.expectEqualStrings("save", mountFor("SAVE:\\profile").?.device);
}

test "the disc is read only and saves are not" {
    // A permitted write to the disc is a write the title never sees again.
    try std.testing.expect(!isWritable("game:\\media\\x"));
    try std.testing.expect(!isWritable("d:\\media\\x"));
    try std.testing.expect(isWritable("save:\\profile"));
    try std.testing.expect(isWritable("cache:\\shaders"));
    try std.testing.expect(!isWritable("systemroot:\\x"));
    // An unrecognised device is not writable; refusing is the safe default.
    try std.testing.expect(!isWritable("unknown:\\x"));
    try std.testing.expect(!isWritable("no-device-here"));
}

test "the remainder after a device is what a translator rewrites" {
    try std.testing.expectEqualStrings("\\media\\maps", pathAfterDevice("game:\\media\\maps").?);
    try std.testing.expectEqualStrings("", pathAfterDevice("game:").?);
    // An unknown device yields null rather than a remainder, so a translator
    // cannot accidentally rewrite a path it did not recognise.
    try std.testing.expect(pathAfterDevice("unknown:\\x") == null);
    try std.testing.expect(pathAfterDevice("no-colon") == null);
}

test "prefixes carry their colon" {
    try std.testing.expectEqualStrings("game:", comptime game.prefix());
    try std.testing.expectEqualStrings("save:", comptime save.prefix());
}

test "every mount has a distinct device name" {
    // Two mounts sharing a name would make resolution order significant, and
    // whichever came second would be unreachable.
    for (mounts, 0..) |outer, i| {
        for (mounts[i + 1 ..]) |inner| {
            try std.testing.expect(!std.ascii.eqlIgnoreCase(outer.device, inner.device));
        }
    }
}
