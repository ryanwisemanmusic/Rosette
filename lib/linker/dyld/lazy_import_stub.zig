const std = @import("std");

pub const entry_size: u64 = 10;

pub const Entry = struct {
    bind_slot: u32,
    shared_helper: u64,
};

pub const Dispatch = enum {
    /// Rosette has typed metadata for this stub and should invoke its import
    /// engine directly instead of entering the guest dyld binder.
    typed_import,
    /// This is an ordinary, non-null indirect transfer.
    follow_target,
    /// No import owns the stub and its indirect target is null.
    invalid_null_target,
};

/// Decode the classic x86_64 Mach-O lazy helper entry:
/// `push imm32; jmp rel32`.
pub fn decodeEntry(rip: u64, bytes: []const u8) ?Entry {
    if (bytes.len < entry_size) return null;
    if (bytes[0] != 0x68 or bytes[5] != 0xE9) return null;
    const bind_slot = std.mem.readInt(u32, bytes[1..5], .little);
    const relative = std.mem.readInt(i32, bytes[6..10], .little);
    const next: i64 = @intCast(rip + entry_size);
    const shared_helper: u64 = @bitCast(next + @as(i64, relative));
    return .{ .bind_slot = bind_slot, .shared_helper = shared_helper };
}

/// Recognize the classic shared helper prefix:
/// `lea ...,%r11; push %r11; jmpq *dyld_stub_binder(%rip)`.
pub fn isSharedHelper(bytes: []const u8) bool {
    if (bytes.len < 16) return false;
    return bytes[0] == 0x4C and bytes[1] == 0x8D and
        bytes[7] == 0x41 and bytes[8] == 0x53 and
        bytes[9] == 0xFF and bytes[10] == 0x25;
}

pub fn chooseDispatch(has_typed_import: bool, target: u64, target_is_lazy_helper: bool) Dispatch {
    // A non-null pointer outside __stub_helper has already been bound by the
    // image and must retain normal guest control flow. Only unresolved/null
    // pointers and pointers into the dyld lazy helper require typed emulation.
    if (has_typed_import and (target == 0 or target_is_lazy_helper)) return .typed_import;
    if (target != 0) return .follow_target;
    return .invalid_null_target;
}

test "classic lazy helper entry is decoded" {
    const bytes = [_]u8{ 0x68, 0x73, 0x49, 0x00, 0x00, 0xE9, 0xD6, 0xEC, 0xFF, 0xFF };
    const entry = decodeEntry(0x1332A80, &bytes).?;
    try std.testing.expectEqual(@as(u32, 0x4973), entry.bind_slot);
    try std.testing.expectEqual(@as(u64, 0x1331760), entry.shared_helper);
}

test "typed imports bypass only unresolved lazy dyld targets" {
    try std.testing.expectEqual(Dispatch.typed_import, chooseDispatch(true, 0x1332A80, true));
    try std.testing.expectEqual(Dispatch.typed_import, chooseDispatch(true, 0, false));
    try std.testing.expectEqual(Dispatch.follow_target, chooseDispatch(true, 0x1833A0, false));
    try std.testing.expectEqual(Dispatch.follow_target, chooseDispatch(false, 0x1000, false));
    try std.testing.expectEqual(Dispatch.invalid_null_target, chooseDispatch(false, 0, false));
}
