//! Fixed-width values and boundary checks shared by the Xenia package.
//!
//! The important distinction here is between a guest address and a host
//! pointer. A guest address is a 32-bit value in the Xbox address space. A
//! host pointer is a 64-bit process value. They are never interchangeable,
//! even when truncation happens to produce a number that looks plausible.

const builtin = @import("builtin");
const std = @import("std");
const target = @import("target.zig");
const x86_64 = @import("targets/x86_64.zig");
const ppc64 = @import("targets/ppc64.zig");
const arm64 = @import("targets/arm64.zig");

pub const GuestAddress = u32;
pub const GuestWord = u32;
pub const HostToken = u64;

pub const guest_address_low: GuestAddress = 0x8000_0000;
pub const guest_address_high: GuestAddress = 0xa000_0000;

pub const BridgeRecord = extern struct {
    /// A value copied through a typed boundary, never a native pointer.
    value: u64,
    guest_address: GuestAddress,
    width_bits: u16,
    flags: u16,
};

pub const bridge_record_size = @sizeOf(BridgeRecord);
pub const bridge_record_alignment = @alignOf(BridgeRecord);

comptime {
    if (bridge_record_size != 16) @compileError("BridgeRecord layout changed; update the package ABI epoch");
    if (@offsetOf(BridgeRecord, "value") != 0) @compileError("BridgeRecord.value moved");
    if (@offsetOf(BridgeRecord, "guest_address") != 8) @compileError("BridgeRecord.guest_address moved");
    if (@offsetOf(BridgeRecord, "width_bits") != 12) @compileError("BridgeRecord.width_bits moved");
    if (@offsetOf(BridgeRecord, "flags") != 14) @compileError("BridgeRecord.flags moved");
}

pub const PointerClass = enum {
    null_pointer,
    guest_pointer,
    byte_reversed_guest_pointer,
    host_width_value,
    outside_guest_window,
};

pub const PointerObservation = struct {
    class: PointerClass,
    raw: u64,
    canonical_guest: ?GuestAddress = null,
};

pub const GuestWindow = struct {
    low: GuestAddress = guest_address_low,
    high_exclusive: GuestAddress = guest_address_high,

    pub fn contains(self: GuestWindow, address: GuestAddress) bool {
        return address >= self.low and address < self.high_exclusive;
    }
};

pub fn classifyPointer(raw: u64, window: GuestWindow) PointerObservation {
    if (raw == 0) return .{ .class = .null_pointer, .raw = raw };
    if (raw > std.math.maxInt(GuestAddress)) {
        return .{ .class = .host_width_value, .raw = raw };
    }

    const candidate: GuestAddress = @truncate(raw);
    if (window.contains(candidate)) {
        return .{ .class = .guest_pointer, .raw = raw, .canonical_guest = candidate };
    }

    const reversed = @byteSwap(candidate);
    if (window.contains(reversed)) {
        return .{
            .class = .byte_reversed_guest_pointer,
            .raw = raw,
            .canonical_guest = reversed,
        };
    }

    return .{ .class = .outside_guest_window, .raw = raw };
}

pub fn readWord(bytes: []const u8, endian: target.Endian) ?u32 {
    if (bytes.len < 4) return null;
    return switch (endian) {
        .little => std.mem.readInt(u32, bytes[0..4], .little),
        .big => std.mem.readInt(u32, bytes[0..4], .big),
    };
}

pub fn writeWord(bytes: []u8, value: u32, endian: target.Endian) bool {
    if (bytes.len < 4) return false;
    switch (endian) {
        .little => std.mem.writeInt(u32, bytes[0..4], value, .little),
        .big => std.mem.writeInt(u32, bytes[0..4], value, .big),
    }
    return true;
}

pub fn encodeRecord(record: BridgeRecord, output: []u8) bool {
    if (output.len < bridge_record_size) return false;
    std.mem.writeInt(u64, output[0..8], record.value, .little);
    std.mem.writeInt(u32, output[8..12], record.guest_address, .little);
    std.mem.writeInt(u16, output[12..14], record.width_bits, .little);
    std.mem.writeInt(u16, output[14..16], record.flags, .little);
    return true;
}

pub fn decodeRecord(input: []const u8) ?BridgeRecord {
    if (input.len < bridge_record_size) return null;
    return .{
        .value = std.mem.readInt(u64, input[0..8], .little),
        .guest_address = std.mem.readInt(u32, input[8..12], .little),
        .width_bits = std.mem.readInt(u16, input[12..14], .little),
        .flags = std.mem.readInt(u16, input[14..16], .little),
    };
}

pub fn profile(architecture: target.Architecture) target.Profile {
    return switch (architecture) {
        .x86_64 => x86_64.profile,
        .ppc64 => ppc64.profile,
        .arm64 => arm64.profile,
    };
}

pub fn currentArchitecture() ?target.Architecture {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => .x86_64,
        .powerpc64 => .ppc64,
        .aarch64 => .arm64,
        else => null,
    };
}

pub fn currentProfile() ?target.Profile {
    const architecture = currentArchitecture() orelse return null;
    return profile(architecture);
}

pub fn fingerprint() u64 {
    var result = std.hash.Wyhash.hash(0, "R3XABI1");
    inline for (.{ x86_64.profile, ppc64.profile, arm64.profile }) |entry| {
        result = std.hash.Wyhash.hash(result, entry.label());
        result = std.hash.Wyhash.hash(result, entry.host_endian.label());
        result = std.hash.Wyhash.hash(result, entry.guest_endian.label());
        result = std.hash.Wyhash.hash(result, entry.host_nop_bytes);
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&entry.host_nop_word));
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&entry.host_nop_width));
    }
    const record_size: u64 = bridge_record_size;
    const address_low: u64 = guest_address_low;
    const address_high: u64 = guest_address_high;
    result = std.hash.Wyhash.hash(result, std.mem.asBytes(&record_size));
    result = std.hash.Wyhash.hash(result, std.mem.asBytes(&address_low));
    result = std.hash.Wyhash.hash(result, std.mem.asBytes(&address_high));
    return result;
}

test "bridge record layout and bytes are fixed width" {
    var encoded: [bridge_record_size]u8 = undefined;
    const original = BridgeRecord{
        .value = 0x1122_3344_5566_7788,
        .guest_address = 0x8258_2cc8,
        .width_bits = 32,
        .flags = 0x0041,
    };
    try std.testing.expect(encodeRecord(original, &encoded));
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{
            0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11,
            0xc8, 0x2c, 0x58, 0x82, 0x20, 0x00, 0x41, 0x00,
        },
        &encoded,
    );
    try std.testing.expectEqual(original, decodeRecord(&encoded).?);
}

test "guest pointer classification refuses host-width values and catches reversal" {
    const window = GuestWindow{};
    try std.testing.expectEqual(PointerClass.null_pointer, classifyPointer(0, window).class);
    try std.testing.expectEqual(PointerClass.guest_pointer, classifyPointer(0x8258_2cc8, window).class);
    try std.testing.expectEqual(
        PointerClass.byte_reversed_guest_pointer,
        classifyPointer(0xc82c_5882, window).class,
    );
    try std.testing.expectEqual(PointerClass.host_width_value, classifyPointer(0x0000_0001_8258_2cc8, window).class);
    try std.testing.expectEqual(PointerClass.outside_guest_window, classifyPointer(0x13fa70, window).class);
}

test "guest PPC words are big endian on every host profile" {
    const bytes = [_]u8{ 0x60, 0x00, 0x00, 0x00 };
    try std.testing.expectEqual(@as(u32, 0x6000_0000), readWord(&bytes, .big).?);
    try std.testing.expectEqual(@as(u32, 0x0000_0060), readWord(&bytes, .little).?);
    inline for (.{ target.Architecture.x86_64, .ppc64, .arm64 }) |architecture| {
        try std.testing.expectEqual(target.Endian.big, profile(architecture).guest_endian);
    }
}

test "current target is one of the supported host routes" {
    try std.testing.expect(currentProfile() != null);
}

test "ABI fingerprint is stable and nonzero" {
    try std.testing.expect(fingerprint() != 0);
    try std.testing.expectEqual(fingerprint(), fingerprint());
}
