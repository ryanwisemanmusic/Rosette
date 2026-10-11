//! What Xenia's fragment-shader-interlock (FSI) render backend requires from
//! the host and what it creates, so the bridge can recognise each object as
//! it is made and name the clause a run broke.
//!
//! Read from Xenia's source (a read-only reference, src/xenia/gpu/vulkan):
//!   - Path selection (`VulkanRenderTargetCache::Initialize`): `fsi` is used
//!     only with fragmentShaderSampleInterlock or fragmentShaderPixelInterlock,
//!     fragmentStoresAndAtomics, sampleRateShading, standardSampleLocations,
//!     and fewer shared-memory bindings than maxPerStageDescriptorStorageBuffers.
//!     Missing any of them makes Xenia fall back to host render targets
//!     without saying so.
//!   - One render pass with no attachments, one subpass, and two by-region
//!     FRAGMENT_SHADER read/write dependencies (EXTERNAL -> 0 and 0 -> EXTERNAL).
//!     That external dependency is what orders EDRAM writes between two
//!     instances of the pass, so ending the pass and beginning it again keeps
//!     every pixel's EDRAM history intact.
//!   - One framebuffer with no attachments, 8192 x draw-resolution-scale on
//!     each side (clamped to maxFramebufferWidth/Height). Every instance of the
//!     pass is begun with that whole extent as its render area
//!     (`SubmitBarriersAndEnterRenderTargetCacheRenderPass`; Xenia's own TODO
//!     says it should be the dirty extent), so only the scissor bounds how far
//!     a large triangle rasterises.
//!   - One storage-buffer descriptor set: binding 0 the 512 MiB shared memory
//!     (1, 2 or 4 descriptors), 1 the EDRAM buffer, 2 the ZPD occlusion counter
//!     (see `descriptor_repair.zig`).
//!   - Pixel shaders declaring SampleInterlockOrderedEXT or
//!     PixelInterlockOrderedEXT that begin the interlock once in `main` and end
//!     it at the end of `main`; the guest's whole shader body runs inside the
//!     critical section. MoltenVK implements that with Metal raster order
//!     groups, so overlapping fragments run one after another.
const std = @import("std");

/// `xenos::kTexture2DCubeMaxWidthHeight`, the side of Xenia's FSI framebuffer
/// at 1x draw resolution scale.
pub const framebuffer_side_at_1x: u32 = 8192;

/// The device answers Xenia's path selection reads.
pub const Prerequisites = struct {
    fragment_shader_sample_interlock: bool = false,
    fragment_shader_pixel_interlock: bool = false,
    fragment_stores_and_atomics: bool = false,
    sample_rate_shading: bool = false,
    standard_sample_locations: bool = false,
    max_per_stage_storage_buffers: u32 = 0,
    shared_memory_binding_count: u32 = 1,

    /// The first requirement Xenia would find missing, in its own order, or
    /// null when Xenia keeps the FSI path.
    pub fn firstMissing(self: Prerequisites) ?[]const u8 {
        if (!self.fragment_shader_sample_interlock and !self.fragment_shader_pixel_interlock) return "fragmentShaderSampleInterlock|fragmentShaderPixelInterlock";
        if (!self.fragment_stores_and_atomics) return "fragmentStoresAndAtomics";
        if (!self.sample_rate_shading) return "sampleRateShading";
        if (!self.standard_sample_locations) return "standardSampleLocations";
        if (self.shared_memory_binding_count >= self.max_per_stage_storage_buffers) return "maxPerStageDescriptorStorageBuffers";
        return null;
    }
};

/// The counts that identify a render pass, read from a host
/// VkRenderPassCreateInfo (64-bit layout: attachmentCount at 20,
/// subpassCount at 32, dependencyCount at 48).
pub const RenderPassShape = struct {
    attachment_count: u32,
    subpass_count: u32,
    dependency_count: u32,

    pub fn fromCreateInfoBytes(bytes: []const u8) ?RenderPassShape {
        if (bytes.len < 56) return null;
        return .{
            .attachment_count = std.mem.readInt(u32, bytes[20..24], .little),
            .subpass_count = std.mem.readInt(u32, bytes[32..36], .little),
            .dependency_count = std.mem.readInt(u32, bytes[48..52], .little),
        };
    }

    /// No attachment means nothing is loaded or stored when an instance of
    /// the pass begins or ends, so the bridge may end one and begin another
    /// anywhere between two draws. One subpass means there is no
    /// vkCmdNextSubpass position to restore.
    pub fn canBeSplit(self: RenderPassShape) bool {
        return self.attachment_count == 0 and self.subpass_count == 1;
    }

    /// Exactly the render pass Xenia creates for FSI.
    pub fn isXeniaFsi(self: RenderPassShape) bool {
        return self.canBeSplit() and self.dependency_count == 2;
    }
};

/// The fields that identify a framebuffer, read from a host
/// VkFramebufferCreateInfo (attachmentCount at 32, width at 48, height at 52,
/// layers at 56).
pub const FramebufferShape = struct {
    attachment_count: u32,
    width: u32,
    height: u32,
    layers: u32,

    pub fn fromCreateInfoBytes(bytes: []const u8) ?FramebufferShape {
        if (bytes.len < 60) return null;
        return .{
            .attachment_count = std.mem.readInt(u32, bytes[32..36], .little),
            .width = std.mem.readInt(u32, bytes[48..52], .little),
            .height = std.mem.readInt(u32, bytes[52..56], .little),
            .layers = std.mem.readInt(u32, bytes[56..60], .little),
        };
    }

    /// Xenia's FSI framebuffer: no attachments and at least the 1x EDRAM
    /// side on each axis (larger at higher draw resolution scales, unless
    /// clamped by the device to a smaller power).
    pub fn isXeniaFsi(self: FramebufferShape) bool {
        return self.attachment_count == 0 and self.layers == 1 and
            self.width >= framebuffer_side_at_1x / 2 and self.height >= framebuffer_side_at_1x / 2;
    }

    pub fn pixels(self: FramebufferShape) u64 {
        return @as(u64, self.width) * self.height;
    }
};

/// The pixels a draw can touch: the scissor clipped to the render area.
/// Under FSI nothing else bounds rasterisation, so this is the worst-case
/// fragment count of one triangle.
pub fn scissoredPixels(scissor_x: i32, scissor_y: i32, scissor_width: u32, scissor_height: u32, area_width: u32, area_height: u32) u64 {
    const x0: i64 = @max(@as(i64, scissor_x), 0);
    const y0: i64 = @max(@as(i64, scissor_y), 0);
    const x1: i64 = @min(@as(i64, scissor_x) + scissor_width, @as(i64, area_width));
    const y1: i64 = @min(@as(i64, scissor_y) + scissor_height, @as(i64, area_height));
    if (x1 <= x0 or y1 <= y0) return 0;
    return @intCast((x1 - x0) * (y1 - y0));
}

test "Xenia keeps FSI only when every prerequisite is present, checked in its order" {
    const complete = Prerequisites{
        .fragment_shader_sample_interlock = true,
        .fragment_shader_pixel_interlock = true,
        .fragment_stores_and_atomics = true,
        .sample_rate_shading = true,
        .standard_sample_locations = true,
        .max_per_stage_storage_buffers = 31,
        .shared_memory_binding_count = 1,
    };
    // MoltenVK 1.2.7 on an M2 Max, measured with vulkaninfo on 2026-10-04.
    try std.testing.expect(complete.firstMissing() == null);
    var pixel_only = complete;
    pixel_only.fragment_shader_sample_interlock = false;
    try std.testing.expect(pixel_only.firstMissing() == null);
    var no_interlock = pixel_only;
    no_interlock.fragment_shader_pixel_interlock = false;
    try std.testing.expectEqualStrings("fragmentShaderSampleInterlock|fragmentShaderPixelInterlock", no_interlock.firstMissing().?);
    var too_few_buffers = complete;
    too_few_buffers.max_per_stage_storage_buffers = 1;
    try std.testing.expectEqualStrings("maxPerStageDescriptorStorageBuffers", too_few_buffers.firstMissing().?);
}

test "the FSI render pass and framebuffer are recognised from their host create-infos" {
    var render_pass = [_]u8{0} ** 64;
    std.mem.writeInt(u32, render_pass[32..36], 1, .little);
    std.mem.writeInt(u32, render_pass[48..52], 2, .little);
    const shape = RenderPassShape.fromCreateInfoBytes(&render_pass).?;
    try std.testing.expect(shape.canBeSplit());
    try std.testing.expect(shape.isXeniaFsi());
    // A host render target pass has attachments whose contents a new
    // instance would have to load, so the bridge never splits it.
    std.mem.writeInt(u32, render_pass[20..24], 2, .little);
    try std.testing.expect(!RenderPassShape.fromCreateInfoBytes(&render_pass).?.canBeSplit());
    try std.testing.expect(RenderPassShape.fromCreateInfoBytes(render_pass[0..40]) == null);

    var framebuffer = [_]u8{0} ** 64;
    std.mem.writeInt(u32, framebuffer[48..52], 8192, .little);
    std.mem.writeInt(u32, framebuffer[52..56], 8192, .little);
    std.mem.writeInt(u32, framebuffer[56..60], 1, .little);
    const fb = FramebufferShape.fromCreateInfoBytes(&framebuffer).?;
    try std.testing.expect(fb.isXeniaFsi());
    try std.testing.expectEqual(@as(u64, 67_108_864), fb.pixels());
    std.mem.writeInt(u32, framebuffer[32..36], 1, .little);
    try std.testing.expect(!FramebufferShape.fromCreateInfoBytes(&framebuffer).?.isXeniaFsi());
}

test "only the scissor bounds an FSI draw inside the 8192-square render area" {
    // Halo 3's 1152x640 front buffer.
    try std.testing.expectEqual(@as(u64, 737_280), scissoredPixels(0, 0, 1152, 640, 8192, 8192));
    // An unclipped scissor covers the whole virtual framebuffer: 91x more
    // fragments, every one of them interlocked.
    try std.testing.expectEqual(@as(u64, 67_108_864), scissoredPixels(0, 0, 8192, 8192, 8192, 8192));
    try std.testing.expectEqual(@as(u64, 0), scissoredPixels(9000, 0, 16, 16, 8192, 8192));
    try std.testing.expectEqual(@as(u64, 100), scissoredPixels(-10, -10, 20, 20, 8192, 8192));
}
