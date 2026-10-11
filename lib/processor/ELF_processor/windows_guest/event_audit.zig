//! Read-only snapshots of Xenia's guest dispatcher-event ABI.
//!
//! Xenia stores a native object handle in the guest X_KEVENT header after
//! lazily creating its XEvent wrapper. Keeping this wire-format parser out of
//! process.zig makes the event failure report testable without changing the
//! guest or Xenia's behavior.

const std = @import("std");

pub const xenia_object_signature: u32 = 0x004E_4558; // make_fourcc('X', 'E', 'N', '\0')

pub const Operation = enum(u8) {
    none,
    initialize,
    set,
    pulse,
    reset,

    pub fn forExport(name: []const u8) ?Operation {
        if (std.mem.eql(u8, name, "KeInitializeEvent")) return .initialize;
        if (std.mem.eql(u8, name, "KeSetEvent")) return .set;
        if (std.mem.eql(u8, name, "KePulseEvent")) return .pulse;
        if (std.mem.eql(u8, name, "KeResetEvent")) return .reset;
        return null;
    }
};

pub const Header = struct {
    object_type: u8,
    signal_state: u32,
    flink: u32,
    blink: u32,

    pub fn hasXeniaObjectSignature(self: Header) bool {
        return self.flink == xenia_object_signature;
    }

    pub fn isEventType(self: Header) bool {
        return self.object_type == 0 or self.object_type == 1;
    }
};

/// Capture of the PPCContext arguments and X_KEVENT bytes as observed at an
/// Xbox kernel export boundary. A missing header is retained as evidence: it
/// can mean a null, unmapped, or malformed event pointer.
pub const CallSnapshot = struct {
    operation: Operation = .none,
    step: u64 = 0,
    context: u64 = 0,
    membase: u64 = 0,
    guest_event: u32 = 0,
    host_event: u64 = 0,
    argument2: u32 = 0,
    argument3: u32 = 0,
    header: ?Header = null,
};

/// Xenia's X_DISPATCH_HEADER is 16 bytes. Its 32-bit members are stored in
/// guest big-endian order, including the two list-entry words used by Xenia
/// to mark a lazily-created native object and stash its handle.
pub fn parseHeader(bytes: []const u8) ?Header {
    if (bytes.len < 16) return null;
    return .{
        .object_type = bytes[0],
        .signal_state = std.mem.readInt(u32, bytes[4..8], .big),
        .flink = std.mem.readInt(u32, bytes[8..12], .big),
        .blink = std.mem.readInt(u32, bytes[12..16], .big),
    };
}

test "Xenia event header parser recognizes the big-endian native-object marker" {
    const header_bytes = [_]u8{
        1,    0,    0,    0,
        0,    0,    0,    1,
        0,    0x4e, 0x45, 0x58,
        0xf8, 0,    0,    0x10,
    };
    const header = parseHeader(&header_bytes).?;
    try std.testing.expectEqual(@as(u8, 1), header.object_type);
    try std.testing.expectEqual(@as(u32, 1), header.signal_state);
    try std.testing.expectEqual(xenia_object_signature, header.flink);
    try std.testing.expectEqual(@as(u32, 0xF800_0010), header.blink);
    try std.testing.expect(header.hasXeniaObjectSignature());
    try std.testing.expect(header.isEventType());
}

test "Xenia event header parser rejects short memory and non-event object types" {
    try std.testing.expect(parseHeader(&[_]u8{0} ** 15) == null);
    const bytes = [_]u8{
        2,    0,    0,    0,
        0,    0,    0,    0,
        0,    0x4e, 0x45, 0x58,
        0xf8, 0,    0,    0x10,
    };
    try std.testing.expect(!parseHeader(&bytes).?.isEventType());
}
