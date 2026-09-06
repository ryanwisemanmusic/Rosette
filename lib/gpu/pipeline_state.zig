//! Backend-neutral graphics pipeline state assembled from Xenos registers.
//!
//! This keeps the translation decisions (format, topology, depth, blend,
//! viewport and scissor) separate from a host Vulkan call.  It is also the key
//! used by the pipeline cache, so a draw that changes only dynamic state does
//! not cause an unnecessary pipeline recreation.

const std = @import("std");
const formats = @import("xenos_formats.zig");
const regs = @import("xenos_registers.zig");

pub const Topology = enum(u8) {
    point_list,
    line_list,
    line_strip,
    triangle_list,
    triangle_strip,
    triangle_fan,
    line_loop,
    patch_list,
};

pub const CullMode = enum(u8) { none, front, back, front_and_back };
pub const PolygonMode = enum(u8) { fill, line, point };
pub const FrontFace = enum(u1) { counter_clockwise, clockwise };
pub const CompareOp = enum(u8) { never, less, equal, less_or_equal, greater, not_equal, greater_or_equal, always };
pub const BlendOp = enum(u8) { add, subtract, reverse_subtract, min, max };
pub const BlendFactor = enum(u8) { zero, one, src_color, one_minus_src_color, dst_color, one_minus_dst_color, src_alpha, one_minus_src_alpha, dst_alpha, one_minus_dst_alpha, constant_color, one_minus_constant_color, constant_alpha, one_minus_constant_alpha, src_alpha_saturate };

pub const VertexBinding = struct {
    binding: u8 = 0,
    stride: u16 = 0,
    input_rate_instance: bool = false,
    /// Original Xenos fetch-constant identity.  The host binding index is a
    /// compact per-pipeline index, while this value is what lets a shader
    /// translator and memory residency tracker find the guest buffer again.
    fetch_constant: u8 = 0,
    address_dwords: u32 = 0,
    size_words: u32 = 0,
    endian: regs.Endian = .none,
};

pub const VertexAttribute = struct {
    location: u8,
    binding: u8,
    format: u32,
    offset: u16,
};

pub const Viewport = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    min_depth: f32 = 0,
    max_depth: f32 = 1,
};

pub const Scissor = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
};

pub const DepthStencil = struct {
    depth_test: bool = false,
    depth_write: bool = false,
    depth_compare: CompareOp = .always,
    stencil_test: bool = false,
    stencil_front_compare: CompareOp = .always,
    stencil_back_compare: CompareOp = .always,
    stencil_front_reference: u8 = 0,
    stencil_back_reference: u8 = 0,
    stencil_front_compare_mask: u8 = 0xFF,
    stencil_back_compare_mask: u8 = 0xFF,
    stencil_front_write_mask: u8 = 0xFF,
    stencil_back_write_mask: u8 = 0xFF,
};

pub const ColorTarget = struct {
    format: u32 = 0,
    blend_enable: bool = false,
    src_color: BlendFactor = .one,
    dst_color: BlendFactor = .zero,
    color_op: BlendOp = .add,
    src_alpha: BlendFactor = .one,
    dst_alpha: BlendFactor = .zero,
    alpha_op: BlendOp = .add,
    write_mask: u4 = 0xF,
};

pub const State = struct {
    vertex_bindings: [16]VertexBinding = undefined,
    vertex_binding_count: u8 = 0,
    vertex_attributes: [32]VertexAttribute = undefined,
    vertex_attribute_count: u8 = 0,
    topology: Topology = .triangle_list,
    primitive_restart: bool = false,
    polygon_mode: PolygonMode = .fill,
    cull_mode: CullMode = .none,
    front_face: FrontFace = .counter_clockwise,
    depth_clamp: bool = false,
    rasterizer_discard: bool = false,
    depth_bias_enable: bool = false,
    depth_bias_constant: f32 = 0,
    depth_bias_slope: f32 = 0,
    line_width: f32 = 1,
    samples: u8 = 1,
    sample_shading: bool = false,
    min_sample_shading: f32 = 0,
    alpha_to_coverage: bool = false,
    alpha_to_one: bool = false,
    depth_stencil: DepthStencil = .{},
    color_targets: [8]ColorTarget = [_]ColorTarget{.{}} ** 8,
    color_target_count: u8 = 1,
    blend_constants: [4]f32 = .{ 0, 0, 0, 0 },
    viewport: Viewport = .{},
    scissor: Scissor = .{},
    dynamic_viewport: bool = true,
    dynamic_scissor: bool = true,
    render_pass: u64 = 0,
    subpass: u32 = 0,
    vertex_shader: u64 = 0,
    fragment_shader: u64 = 0,
    index_format: regs.IndexFormat = .uint16,
};

pub const CacheEntry = struct {
    key: u64 = 0,
    pipeline: u64 = 0,
    last_use: u64 = 0,
};

pub const Cache = struct {
    entries: [256]CacheEntry = [_]CacheEntry{.{}} ** 256,
    tick: u64 = 0,
    hits: u64 = 0,
    misses: u64 = 0,

    pub fn lookup(self: *Cache, query_key: u64) ?u64 {
        self.tick +%= 1;
        for (&self.entries) |*entry| {
            if (entry.key != query_key or entry.pipeline == 0) continue;
            entry.last_use = self.tick;
            self.hits +%= 1;
            return entry.pipeline;
        }
        self.misses +%= 1;
        return null;
    }

    pub fn insert(self: *Cache, query_key: u64, pipeline: u64) void {
        self.tick +%= 1;
        var target: *CacheEntry = &self.entries[0];
        for (&self.entries) |*entry| {
            if (entry.key == query_key or entry.pipeline == 0) {
                target = entry;
                break;
            }
            if (entry.last_use < target.last_use) target = entry;
        }
        target.* = .{ .key = query_key, .pipeline = pipeline, .last_use = self.tick };
    }
};

pub fn key(state: State) u64 {
    var hasher = std.hash.Wyhash.init(0x5845_4E4F_535F_5049);
    hasher.update(std.mem.asBytes(&state.topology));
    hasher.update(std.mem.asBytes(&state.primitive_restart));
    hasher.update(std.mem.asBytes(&state.polygon_mode));
    hasher.update(std.mem.asBytes(&state.cull_mode));
    hasher.update(std.mem.asBytes(&state.front_face));
    hasher.update(std.mem.asBytes(&state.depth_clamp));
    hasher.update(std.mem.asBytes(&state.rasterizer_discard));
    hasher.update(std.mem.asBytes(&state.depth_bias_enable));
    hasher.update(std.mem.asBytes(&state.depth_bias_constant));
    hasher.update(std.mem.asBytes(&state.depth_bias_slope));
    hasher.update(std.mem.asBytes(&state.line_width));
    hasher.update(std.mem.asBytes(&state.samples));
    hasher.update(std.mem.asBytes(&state.sample_shading));
    hasher.update(std.mem.asBytes(&state.min_sample_shading));
    hasher.update(std.mem.asBytes(&state.alpha_to_coverage));
    hasher.update(std.mem.asBytes(&state.alpha_to_one));
    hasher.update(std.mem.asBytes(&state.depth_stencil));
    hasher.update(std.mem.asBytes(&state.color_target_count));
    hasher.update(std.mem.sliceAsBytes(state.color_targets[0..state.color_target_count]));
    hasher.update(std.mem.asBytes(&state.render_pass));
    hasher.update(std.mem.asBytes(&state.subpass));
    hasher.update(std.mem.asBytes(&state.vertex_shader));
    hasher.update(std.mem.asBytes(&state.fragment_shader));
    hasher.update(std.mem.asBytes(&state.vertex_binding_count));
    hasher.update(std.mem.sliceAsBytes(state.vertex_bindings[0..state.vertex_binding_count]));
    hasher.update(std.mem.asBytes(&state.vertex_attribute_count));
    hasher.update(std.mem.sliceAsBytes(state.vertex_attributes[0..state.vertex_attribute_count]));
    hasher.update(std.mem.asBytes(&state.dynamic_viewport));
    if (!state.dynamic_viewport) hasher.update(std.mem.asBytes(&state.viewport));
    hasher.update(std.mem.asBytes(&state.dynamic_scissor));
    if (!state.dynamic_scissor) hasher.update(std.mem.asBytes(&state.scissor));
    hasher.update(std.mem.asBytes(&state.index_format));
    return hasher.final();
}

pub fn topologyFromPrimitive(primitive: regs.PrimitiveType) Topology {
    return switch (primitive) {
        .point_list => .point_list,
        .line_list => .line_list,
        .line_strip => .line_strip,
        .triangle_list => .triangle_list,
        .triangle_strip => .triangle_strip,
        .triangle_fan, .polygon => .triangle_fan,
        .rectangle_list, .quad_list, .quad_strip => .triangle_strip,
        _ => .triangle_list,
    };
}

pub fn compareFromXenos(raw: u32) CompareOp {
    return switch (raw & 7) {
        0 => .never,
        1 => .less,
        2 => .equal,
        3 => .less_or_equal,
        4 => .greater,
        5 => .not_equal,
        6 => .greater_or_equal,
        else => .always,
    };
}

pub fn cullModeFromRaster(raster: regs.RasterState) CullMode {
    return if (raster.cull_front and raster.cull_back)
        .front_and_back
    else if (raster.cull_front)
        .front
    else if (raster.cull_back)
        .back
    else
        .none;
}

pub fn polygonModeFromRaster(raster: regs.RasterState) PolygonMode {
    return switch (raster.polygon_mode) {
        1 => .line,
        2 => .point,
        else => .fill,
    };
}

pub fn blendFactorFromXenos(raw: u32) BlendFactor {
    return switch (raw & 0x1F) {
        0 => .zero,
        1 => .one,
        4 => .src_color,
        5 => .one_minus_src_color,
        6 => .src_alpha,
        7 => .one_minus_src_alpha,
        8 => .dst_color,
        9 => .one_minus_dst_color,
        10 => .dst_alpha,
        11 => .one_minus_dst_alpha,
        12 => .constant_color,
        13 => .one_minus_constant_color,
        14 => .constant_alpha,
        15 => .one_minus_constant_alpha,
        16 => .src_alpha_saturate,
        else => .one,
    };
}

pub fn blendOpFromXenos(raw: u32) BlendOp {
    return switch (raw & 7) {
        1 => .subtract,
        2 => .min,
        3 => .max,
        4 => .reverse_subtract,
        else => .add,
    };
}

pub fn vertexAttribute(format: u32, location: u8, binding: u8, offset: u16) ?VertexAttribute {
    return vertexAttributeSigned(format, .unsigned, location, binding, offset);
}

/// The signed form, which is the one a real `vfetch` can answer.
///
/// Kept separate rather than replacing the call above so no existing caller
/// silently changes meaning: an attribute built without a signedness is
/// unsigned, which is what it always was.
pub fn vertexAttributeSigned(
    format: u32,
    signedness: formats.VertexSignedness,
    location: u8,
    binding: u8,
    offset: u16,
) ?VertexAttribute {
    return .{
        .location = location,
        .binding = binding,
        .format = formats.vertexVulkanFormatSigned(format, signedness) orelse return null,
        .offset = offset,
    };
}

pub fn dynamicViewportFromRegisters(registers: *const regs.RegisterFile) Viewport {
    const viewport = registers.viewport();
    return .{
        .x = viewport.x_offset - viewport.x_scale,
        .y = viewport.y_offset - viewport.y_scale,
        .width = viewport.x_scale * 2,
        .height = viewport.y_scale * 2,
        .min_depth = viewport.z_offset - viewport.z_scale,
        .max_depth = viewport.z_offset + viewport.z_scale,
    };
}

test "Xenos primitive and depth comparisons map to stable host state" {
    try std.testing.expectEqual(Topology.triangle_strip, topologyFromPrimitive(.rectangle_list));
    try std.testing.expectEqual(CompareOp.greater_or_equal, compareFromXenos(6));
    const attr = vertexAttribute(38, 0, 1, 16).?;
    try std.testing.expectEqual(@as(u8, 0), attr.location);
}

test "Xenos raster and blend fields map to host enums" {
    try std.testing.expectEqual(CullMode.front_and_back, cullModeFromRaster(.{ .cull_front = true, .cull_back = true }));
    try std.testing.expectEqual(PolygonMode.line, polygonModeFromRaster(.{ .polygon_mode = 1 }));
    try std.testing.expectEqual(BlendFactor.src_alpha, blendFactorFromXenos(6));
    try std.testing.expectEqual(BlendOp.reverse_subtract, blendOpFromXenos(4));
}

test "pipeline cache reuses identical state and evicts least recently used entries" {
    var state: State = .{};
    state.topology = .triangle_list;
    const first_key = key(state);
    var cache: Cache = .{};
    try std.testing.expect(cache.lookup(first_key) == null);
    cache.insert(first_key, 0x1234);
    try std.testing.expectEqual(@as(u64, 0x1234), cache.lookup(first_key).?);
    try std.testing.expectEqual(@as(u64, 1), cache.hits);
}

test "pipeline key includes every static pipeline-affecting state boundary" {
    var state: State = .{};
    const baseline = key(state);

    state.line_width = 2;
    try std.testing.expect(key(state) != baseline);

    state = .{};
    state.vertex_attribute_count = 1;
    state.vertex_attributes[0] = .{ .location = 0, .binding = 1, .format = 44, .offset = 16 };
    try std.testing.expect(key(state) != baseline);

    state = .{};
    state.color_target_count = 2;
    try std.testing.expect(key(state) != baseline);

    state = .{};
    state.sample_shading = true;
    state.min_sample_shading = 0.5;
    try std.testing.expect(key(state) != baseline);
}

test "dynamic viewport and scissor values do not churn the pipeline key" {
    var state: State = .{};
    const baseline = key(state);
    state.viewport.width = 1280;
    state.viewport.height = 720;
    state.scissor.width = 1280;
    state.scissor.height = 720;
    try std.testing.expectEqual(baseline, key(state));

    state.dynamic_viewport = false;
    try std.testing.expect(key(state) != baseline);
    const fixed_viewport = key(state);
    state.viewport.width = 1920;
    try std.testing.expect(key(state) != fixed_viewport);
}
