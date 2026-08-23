//! Immutable Xenia graphics handoff facts for the ARM64 host route.

const std = @import("std");

pub const host_architecture = "arm64";
pub const guest_pointer_bits: u8 = 32;
pub const host_pointer_bits: u8 = 64;
pub const guest_is_big_endian = true;
pub const host_is_little_endian = true;
pub const host_codegen = "arm64-native-bridge";

pub const VdSwapArgument = enum(u3) {
    buffer_ptr,
    fetch_ptr,
    frontbuffer_ptr,
    texture_format_ptr,
    width,
    height,
};

pub fn argumentBit(argument: VdSwapArgument) u8 {
    return @as(u8, 1) << @as(u3, @intFromEnum(argument));
}

pub const required_argument_mask: u8 = argumentBit(.buffer_ptr) |
    argumentBit(.fetch_ptr) |
    argumentBit(.frontbuffer_ptr) |
    argumentBit(.texture_format_ptr) |
    argumentBit(.width) |
    argumentBit(.height);

pub fn requiredArgumentsPresent(observed: u8) bool {
    return observed & required_argument_mask == required_argument_mask;
}

pub const HandoffStage = enum(u8) {
    guest_vdswap_entered,
    guest_swap_packet_encoded,
    guest_vdswap_completed,
    guest_swap_published,
    authentic_swap_consumed,
    authentic_refresh_succeeded,
    authentic_native_presented,
};

pub const HandoffEdge = struct {
    from: HandoffStage,
    to: HandoffStage,
    owner: []const u8,
};

pub const handoff_edges = [_]HandoffEdge{
    .{ .from = .guest_vdswap_entered, .to = .guest_swap_packet_encoded, .owner = "guest:title" },
    .{ .from = .guest_swap_packet_encoded, .to = .guest_vdswap_completed, .owner = "guest:title" },
    .{ .from = .guest_vdswap_completed, .to = .guest_swap_published, .owner = "guest:title" },
    .{ .from = .guest_swap_published, .to = .authentic_swap_consumed, .owner = "xenia:command_processor" },
    .{ .from = .authentic_swap_consumed, .to = .authentic_refresh_succeeded, .owner = "xenia:presenter" },
    .{ .from = .authentic_refresh_succeeded, .to = .authentic_native_presented, .owner = "rosette:presenter" },
};

pub const terminal_stage: HandoffStage = .authentic_native_presented;
pub const all_handoff_stages_mask: u16 = (@as(u16, 1) << @as(u4, @intFromEnum(terminal_stage) + 1)) - 1;

pub const HandoffVerdict = enum {
    ordering_violation,
    guest_vdswap_missing,
    packet_encoding_missing,
    guest_publication_missing,
    authentic_consumption_missing,
    refresh_missing,
    authentic_native_presented,
};

fn stageBit(stage: HandoffStage) u16 {
    return @as(u16, 1) << @as(u4, @intCast(@intFromEnum(stage)));
}

pub fn classifyHandoff(observed: u16) HandoffVerdict {
    if (!handoffOrderValid(observed)) return .ordering_violation;
    if (observed & stageBit(.guest_vdswap_entered) == 0) return .guest_vdswap_missing;
    if (observed & stageBit(.guest_swap_packet_encoded) == 0) return .packet_encoding_missing;
    if (observed & stageBit(.guest_swap_published) == 0) return .guest_publication_missing;
    if (observed & stageBit(.authentic_swap_consumed) == 0) return .authentic_consumption_missing;
    if (observed & stageBit(.authentic_refresh_succeeded) == 0) return .refresh_missing;
    return if (observed & stageBit(.authentic_native_presented) != 0)
        .authentic_native_presented
    else
        .refresh_missing;
}

pub fn handoffOrderValid(observed: u16) bool {
    for (handoff_edges) |edge| {
        if (observed & stageBit(edge.to) != 0 and observed & stageBit(edge.from) == 0) return false;
    }
    return true;
}

pub fn contractIsWellFormed() bool {
    if (!requiredArgumentsPresent(required_argument_mask)) return false;
    if (handoff_edges.len + 1 != @typeInfo(HandoffStage).@"enum".fields.len) return false;
    for (handoff_edges) |edge| {
        if (edge.owner.len == 0) return false;
    }
    return handoffOrderValid(all_handoff_stages_mask) and
        classifyHandoff(all_handoff_stages_mask) == .authentic_native_presented;
}

pub fn matchesReadyCompilerNames(names: []const []const u8) bool {
    if (names.len != @typeInfo(HandoffStage).@"enum".fields.len) return false;
    inline for (@typeInfo(HandoffStage).@"enum".fields, 0..) |field, index| {
        if (!std.mem.eql(u8, names[index], field.name)) return false;
    }
    return true;
}

test "VdSwap requires all caller-owned pointer arguments" {
    try std.testing.expect(requiredArgumentsPresent(required_argument_mask));
    try std.testing.expect(!requiredArgumentsPresent(required_argument_mask & ~argumentBit(.height)));
}

test "a diagnostic or partial handoff cannot become an authentic frame" {
    try std.testing.expectEqual(HandoffVerdict.guest_vdswap_missing, classifyHandoff(0));
    try std.testing.expectEqual(HandoffVerdict.guest_publication_missing, classifyHandoff(
        stageBit(.guest_vdswap_entered) | stageBit(.guest_swap_packet_encoded) | stageBit(.guest_vdswap_completed),
    ));
    try std.testing.expectEqual(HandoffVerdict.ordering_violation, classifyHandoff(
        stageBit(.guest_vdswap_entered) | stageBit(.guest_swap_packet_encoded) | stageBit(.guest_swap_published),
    ));
    try std.testing.expectEqual(HandoffVerdict.authentic_native_presented, classifyHandoff(all_handoff_stages_mask));
    try std.testing.expect(handoffOrderValid(all_handoff_stages_mask));
}

test "the package identity matches the ARM64 bridge route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
    try std.testing.expectEqual(@as(u8, 32), guest_pointer_bits);
    try std.testing.expectEqual(@as(u8, 64), host_pointer_bits);
    try std.testing.expect(guest_is_big_endian and host_is_little_endian);
    try std.testing.expect(contractIsWellFormed());
}
