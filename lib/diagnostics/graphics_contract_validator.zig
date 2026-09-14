//! Pure graphics-boundary checks shared by the PE/Xenos diagnostics.
//!
//! These checks do not manufacture a Vulkan object or claim that a host
//! backend exists. They validate the pieces Rosetta can prove at the boundary:
//! struct shape and pNext ownership, Xenos word order/surface limits, PM4
//! packet bounds, image-layout transitions, and the Windows x64 argument
//! placement contract.

const std = @import("std");

pub const VulkanStructView = struct {
    byte_size: usize,
    expected_size: usize,
    s_type: u32,
    expected_s_type: u32,
    p_next: u64,
    alignment: usize,
    pointer_width: usize,
};

pub const VulkanValidation = enum {
    valid,
    size_mismatch,
    s_type_mismatch,
    unaligned,
    pointer_width_mismatch,
};

pub fn validateVulkanStruct(view: VulkanStructView) VulkanValidation {
    if (view.byte_size != view.expected_size) return .size_mismatch;
    if (view.s_type != view.expected_s_type) return .s_type_mismatch;
    if (view.alignment == 0 or view.byte_size % view.alignment != 0) return .unaligned;
    if (view.pointer_width != @sizeOf(usize)) return .pointer_width_mismatch;
    _ = view.p_next; // pNext is validated as a chain by validatePNextChain.
    return .valid;
}

/// Validate a bounded guest-visible pNext chain represented by its addresses.
/// Zero is the null terminator; repeated nonzero addresses are a cycle.
pub fn validatePNextChain(addresses: []const u64, max_depth: usize) bool {
    if (addresses.len > max_depth) return false;
    for (addresses, 0..) |address, index| {
        if (address == 0) {
            return index == addresses.len - 1 or addresses.len == 0;
        }
        for (addresses[0..index]) |previous| {
            if (previous != 0 and previous == address) return false;
        }
    }
    return addresses.len == 0 or addresses[addresses.len - 1] != 0;
}

/// Decode a four-byte Xenos word without silently treating the guest's
/// big-endian register layout as a host little-endian integer.
pub fn decodeXenosWord(bytes: [4]u8, guest_big_endian: bool) u32 {
    if (guest_big_endian) {
        return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
            (@as(u32, bytes[2]) << 8) | @as(u32, bytes[3]);
    }
    return (@as(u32, bytes[3]) << 24) | (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[1]) << 8) | @as(u32, bytes[0]);
}

pub const XenosSurface = struct {
    format: u32,
    tile_mode: u32,
    bytes_per_pixel: u32,
    width: u32,
    height: u32,
};

/// Check the structural part of a Xenos surface descriptor. Format values are
/// intentionally kept opaque here; package-owned Xenos tables decide whether
/// a particular format is semantically supported.
pub fn validateXenosSurface(surface: XenosSurface) bool {
    _ = surface.format;
    return surface.tile_mode <= 15 and surface.bytes_per_pixel >= 1 and
        surface.bytes_per_pixel <= 16 and surface.width > 0 and surface.height > 0 and
        surface.width <= 16384 and surface.height <= 16384;
}

pub const Pm4Validation = enum {
    valid,
    wrong_packet_type,
    payload_truncated,
    ring_overrun,
};

/// Validate a type-3 PM4 packet before its count can be used as a slice.
/// Type-3 count is the number of following dwords, so the packet consumes
/// count + 1 dwords including its header.
pub fn validatePm4Packet(header: u32, payload_dwords: usize, ring_dwords: usize) Pm4Validation {
    const packet_type = (header >> 30) & 0x3;
    if (packet_type != 3) return .wrong_packet_type;
    const count: usize = @intCast((header >> 16) & 0x3FFF);
    const total = count +| 1;
    if (count > payload_dwords) return .payload_truncated;
    if (total > ring_dwords) return .ring_overrun;
    return .valid;
}

pub const ImageLayout = enum {
    undefined,
    general,
    color_attachment,
    transfer_src,
    transfer_dst,
    present,
};

pub fn validateImageLayoutTransition(old: ImageLayout, new: ImageLayout) bool {
    if (old == new) return true;
    if (new == .undefined) return false;
    if (old == .present and new == .transfer_src) return false;
    return true;
}

pub const WindowsArgumentKind = enum { scalar, pointer, xmm };

pub const WindowsArgument = struct {
    position: usize,
    kind: WindowsArgumentKind,
};

/// Validate the placement metadata Rosetta uses before entering a Windows
/// x64 import: four register positions per integer/XMM family, followed by
/// 16-byte-aligned stack arguments and the mandatory 32-byte shadow space.
pub fn validateWindowsAbi(arguments: []const WindowsArgument, stack_bytes: usize, shadow_space: usize) bool {
    if (shadow_space < 32 or stack_bytes % 16 != 0) return false;
    var integer_seen: u4 = 0;
    var xmm_seen: u4 = 0;
    for (arguments) |argument| {
        if (argument.position < 4) {
            const mask: u4 = @as(u4, 1) << @intCast(argument.position);
            switch (argument.kind) {
                .xmm => {
                    if ((xmm_seen & mask) != 0) return false;
                    xmm_seen |= mask;
                },
                .scalar, .pointer => {
                    if ((integer_seen & mask) != 0) return false;
                    integer_seen |= mask;
                },
            }
        } else if ((argument.position - 4) * 8 >= stack_bytes) {
            return false;
        }
    }
    return true;
}

test "Vulkan struct contract catches ABI drift" {
    const valid = VulkanStructView{
        .byte_size = 32,
        .expected_size = 32,
        .s_type = 100,
        .expected_s_type = 100,
        .p_next = 0,
        .alignment = 8,
        .pointer_width = @sizeOf(usize),
    };
    try std.testing.expectEqual(VulkanValidation.valid, validateVulkanStruct(valid));
    try std.testing.expectEqual(VulkanValidation.s_type_mismatch, validateVulkanStruct(.{
        .byte_size = 32,
        .expected_size = 32,
        .s_type = 0,
        .expected_s_type = 100,
        .p_next = 0,
        .alignment = 8,
        .pointer_width = @sizeOf(usize),
    }));
}

test "pNext and PM4 checks are bounded" {
    try std.testing.expect(validatePNextChain(&[_]u64{ 0x10, 0x20, 0 }, 4));
    try std.testing.expect(!validatePNextChain(&[_]u64{ 0x10, 0x10 }, 4));
    const header = (@as(u32, 3) << 30) | (@as(u32, 2) << 16);
    try std.testing.expectEqual(Pm4Validation.valid, validatePm4Packet(header, 2, 3));
    try std.testing.expectEqual(Pm4Validation.payload_truncated, validatePm4Packet(header, 1, 3));
}

test "Xenos order, layout, and Windows ABI checks" {
    try std.testing.expectEqual(@as(u32, 0x12345678), decodeXenosWord(.{ 0x12, 0x34, 0x56, 0x78 }, true));
    try std.testing.expectEqual(@as(u32, 0x12345678), decodeXenosWord(.{ 0x78, 0x56, 0x34, 0x12 }, false));
    try std.testing.expect(validateXenosSurface(.{ .format = 1, .tile_mode = 3, .bytes_per_pixel = 4, .width = 1280, .height = 720 }));
    try std.testing.expect(validateImageLayoutTransition(.present, .color_attachment));
    try std.testing.expect(!validateImageLayoutTransition(.general, .undefined));
    try std.testing.expect(validateWindowsAbi(&[_]WindowsArgument{
        .{ .position = 0, .kind = .pointer },
        .{ .position = 1, .kind = .xmm },
        .{ .position = 4, .kind = .scalar },
    }, 16, 32));
}
