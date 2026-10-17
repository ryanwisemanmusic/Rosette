//! Static macOS graphics-path facts for Xenia's ARM64 route.
//!
//! The guest-facing handoff is unchanged from x86: Xenia's FBO label describes
//! its Vulkan render-target/cache path, while native presentation is Vulkan WSI
//! backed by a CAMetalLayer. Only the host code-generation and pointer route
//! differ, so this package mirrors the same ordering independently.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";
pub const guest_pointer_bits: u8 = 32;
pub const host_pointer_bits: u8 = 64;
pub const guest_is_big_endian = true;
pub const host_is_little_endian = true;
pub const backend = "vulkan";
pub const render_target_path = "fbo";
pub const native_surface_api = "VK_EXT_metal_surface";
pub const native_surface_backing = "CAMetalLayer";
pub const directx9_active_on_macos = false;
pub const requires_guest_surface_call = true;
pub const requires_metal_layer_token = true;

pub const Stage = enum(u3) {
    native_window_ready,
    metal_layer_ready,
    vulkan_surface_created,
    swapchain_created,
    guest_output_ready,
    authentic_native_presented,
};

pub const Edge = struct {
    from: Stage,
    to: Stage,
    owner: []const u8,
};

pub const edges = [_]Edge{
    .{ .from = .native_window_ready, .to = .metal_layer_ready, .owner = "rosette:window" },
    .{ .from = .metal_layer_ready, .to = .vulkan_surface_created, .owner = "xenia:presenter" },
    .{ .from = .vulkan_surface_created, .to = .swapchain_created, .owner = "xenia:presenter" },
    .{ .from = .swapchain_created, .to = .guest_output_ready, .owner = "xenia:presenter" },
    .{ .from = .guest_output_ready, .to = .authentic_native_presented, .owner = "rosette:presenter" },
};

pub const terminal_stage: Stage = .authentic_native_presented;
pub const all_stages_mask: u8 = (@as(u8, 1) << (@as(u4, @intFromEnum(terminal_stage)) + 1)) - 1;

pub const Verdict = enum {
    native_window_missing,
    metal_layer_missing,
    vulkan_surface_missing,
    swapchain_missing,
    guest_output_missing,
    authentic_native_presented,
    ordering_violation,
};

pub fn stageBit(stage: Stage) u8 {
    return @as(u8, 1) << @as(u3, @intFromEnum(stage));
}

pub fn orderValid(observed: u8) bool {
    for (edges) |edge| {
        if (observed & stageBit(edge.to) != 0 and observed & stageBit(edge.from) == 0) return false;
    }
    return true;
}

pub fn classify(observed: u8) Verdict {
    if (!orderValid(observed)) return .ordering_violation;
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        if (observed & stageBit(stage) == 0) {
            return switch (stage) {
                .native_window_ready => .native_window_missing,
                .metal_layer_ready => .metal_layer_missing,
                .vulkan_surface_created => .vulkan_surface_missing,
                .swapchain_created => .swapchain_missing,
                .guest_output_ready => .guest_output_missing,
                .authentic_native_presented => .authentic_native_presented,
            };
        }
    }
    return .authentic_native_presented;
}

pub fn matchesReadyCompilerNames(names: []const []const u8) bool {
    const expected = [_][]const u8{
        "surface_ready",
        "guest_output_ready",
        "authentic_native_presented",
    };
    if (names.len != expected.len) return false;
    for (expected, 0..) |name, index| {
        if (!std.mem.eql(u8, name, names[index])) return false;
    }
    return true;
}

pub fn contractIsWellFormed() bool {
    return guest_pointer_bits == 32 and host_pointer_bits == 64 and
        guest_is_big_endian and host_is_little_endian and
        std.mem.eql(u8, backend, "vulkan") and
        std.mem.eql(u8, render_target_path, "fbo") and
        std.mem.eql(u8, native_surface_api, "VK_EXT_metal_surface") and
        std.mem.eql(u8, native_surface_backing, "CAMetalLayer") and
        directx9_active_on_macos == false and requires_guest_surface_call and
        requires_metal_layer_token and edges.len + 1 == @typeInfo(Stage).@"enum".fields.len and
        orderValid(all_stages_mask) and classify(all_stages_mask) == .authentic_native_presented;
}

test "the FBO render-target label does not imply a native presenter" {
    try std.testing.expectEqualStrings("vulkan", backend);
    try std.testing.expectEqualStrings("fbo", render_target_path);
    try std.testing.expect(!directx9_active_on_macos);
    try std.testing.expect(requires_guest_surface_call);
    try std.testing.expectEqual(Verdict.vulkan_surface_missing, classify(
        stageBit(.native_window_ready) | stageBit(.metal_layer_ready),
    ));
}

test "the native surface chain is ordered" {
    try std.testing.expectEqual(Verdict.ordering_violation, classify(
        stageBit(.native_window_ready) | stageBit(.swapchain_created),
    ));
    try std.testing.expectEqual(Verdict.authentic_native_presented, classify(all_stages_mask));
    try std.testing.expect(orderValid(all_stages_mask));
}

test "the package identity matches the ARM64 route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
    try std.testing.expectEqual(@as(u8, 32), guest_pointer_bits);
    try std.testing.expectEqual(@as(u8, 64), host_pointer_bits);
    try std.testing.expect(contractIsWellFormed());
    const names = [_][]const u8{ "surface_ready", "guest_output_ready", "authentic_native_presented" };
    try std.testing.expect(matchesReadyCompilerNames(names[0..]));
}
