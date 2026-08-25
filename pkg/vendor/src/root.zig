//! Build-time view of the canonical vendored-library catalogue.
//!
//! The TOML file is the one source of version/commit truth. This package does
//! not duplicate those values in Zig; it embeds the catalogue and proves that
//! the build graph has not silently lost it. The host-side checker performs
//! parsing, hashing, provider inspection, and cross-target compilation.

const std = @import("std");

pub const catalogue = @embedFile("manifest.toml");

const required_markers = [_][]const u8{
    "catalogue = \"rosette-vendored-library-catalogue\"",
    "vulkan_header_version = \"",
    "vulkan_instance_default_api = \"",
    "vulkan_runtime_minimum_api = \"",
    "sdl_version = \"",
    "vma_version = \"",
    "moltenvk_version = \"",
    "id = \"vulkan-headers\"",
    "id = \"vulkan-loader\"",
    "id = \"sdl2\"",
    "id = \"vulkan-memory-allocator\"",
    "id = \"moltenvk\"",
    "expected_target_count = 9",
};

pub fn contractIsWellFormed() bool {
    if (catalogue.len == 0) return false;
    for (required_markers) |marker| {
        if (std.mem.indexOf(u8, catalogue, marker) == null) return false;
    }
    return true;
}

fn valueAfterPrefix(comptime prefix: []const u8) []const u8 {
    const marker_start = std.mem.indexOf(u8, catalogue, prefix) orelse return "";
    const value_start = marker_start + prefix.len;
    const value_end = std.mem.indexOfScalarPos(u8, catalogue, value_start, '"') orelse return "";
    return catalogue[value_start..value_end];
}

pub fn canonicalVulkanHeaderVersion() []const u8 {
    return valueAfterPrefix("vulkan_header_version = \"");
}

pub fn xeniaVulkanMinimumApi() []const u8 {
    return valueAfterPrefix("vulkan_runtime_minimum_api = \"");
}

test "embedded vendor catalogue is present and contains the shared version truth" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expect(canonicalVulkanHeaderVersion().len != 0);
    try std.testing.expect(xeniaVulkanMinimumApi().len != 0);
}

test "the catalogue is not a runtime-state package" {
    try std.testing.expect(catalogue.len > 128);
    try std.testing.expect(std.mem.indexOf(u8, catalogue, "source_tree_sha256") != null);
}
