//! Rosetta-owned lowering for PM4 indexed draws.
//!
//! Xenia's Vulkan command processor has two ways to consume a Xenos rectangle
//! list.  A host geometry shader can consume the three guest vertices of each
//! rectangle directly.  When geometry shaders are unavailable (the
//! MoltenVK-backed route in the Xenia run), the primitive processor expands
//! each rectangle to a four-index triangle strip and selects a
//! rectangle-aware vertex shader.  The latter is the path that the current
//! Xenia snapshot rejects in IssueDraw.
//!
//! This module owns the missing PM4 draw contract on the Rosetta side.  It is
//! deliberately backend-neutral: it plans the host topology, index buffer,
//! restart policy, and guest-index metadata, and can fill the same built-in
//! index pattern Xenia uses.  It does not claim to have submitted a Vulkan
//! draw.  The PE runner's Xenia command processor remains the owner of that
//! submission, while this plan gives a Rosetta backend a complete and bounded
//! representation to consume when one is connected.

const std = @import("std");
const pipeline = @import("pipeline_state.zig");
const pm4_executor = @import("pm4_executor.zig");
const shader_execution = @import("shader_execution.zig");
const regs = @import("xenos_registers.zig");

pub const Backend = enum(u8) {
    /// The host can consume Xenos rectangle-list primitives with a geometry
    /// shader.  Xenia's pipeline cache uses triangle-list topology for this
    /// route and leaves the guest's three vertices intact.
    native_geometry,
    /// The host has no geometry shader.  Use Xenia's two-triangle-strip index
    /// buffer and the rectangle-aware vertex shader fallback.
    vertex_shader_indexed,

    pub fn label(self: Backend) []const u8 {
        return switch (self) {
            .native_geometry => "native-geometry",
            .vertex_shader_indexed => "vertex-shader-indexed",
        };
    }
};

pub const RejectReason = enum(u8) {
    unknown_source,
    immediate_source,
    host_index_count_overflow,

    pub fn label(self: RejectReason) []const u8 {
        return switch (self) {
            .unknown_source => "unknown-source",
            .immediate_source => "immediate-source",
            .host_index_count_overflow => "host-index-count-overflow",
        };
    }
};

/// Host capabilities that alter primitive lowering.  The default is the
/// capability set of the failing run: MoltenVK did not expose geometry
/// shaders, so Rosetta selects the vertex-shader indexed fallback.
pub const Capabilities = struct {
    geometry_shader: bool = false,
};

/// Geometry stages required by the selected lowering. Keeping this separate
/// from `host_vertex_shader` matters for the native rectangle route: Xenia
/// feeds three guest vertices to a rectangle-list geometry shader, while the
/// no-geometry fallback uses a normal vertex shader plus the built-in indexed
/// triangle strips.
pub const GeometryShader = enum(u8) {
    none,
    rectangle_list,

    pub fn label(self: GeometryShader) []const u8 {
        return switch (self) {
            .none => "none",
            .rectangle_list => "rectangle-list",
        };
    }
};

pub const Plan = struct {
    backend: Backend,
    guest_primitive: regs.PrimitiveType = .rectangle_list,
    guest_source: regs.SourceSelect,
    guest_index_format: regs.IndexFormat,
    guest_index_address: u32 = 0,
    guest_index_size_words: u32 = 0,
    guest_index_endian: regs.Endian = .none,
    index_offset: i32 = 0,
    instance_count: u32 = 1,
    requested_vertex_count: u32,
    /// The count after Xenia's DMA-size clamp.  The fallback never reads past
    /// this many guest indices.
    guest_vertex_count: u32,
    /// A rectangle consumes three guest vertices.  Xenia's primitive
    /// processor truncates a trailing incomplete rectangle; retaining the
    /// number here keeps that behavior visible to a caller rather than
    /// silently losing it.
    ignored_trailing_vertices: u2 = 0,
    rectangle_count: u32,
    host_topology: pipeline.Topology,
    host_vertex_shader: shader_execution.HostVertexShaderType,
    host_geometry_shader: GeometryShader,
    host_index_format: regs.IndexFormat,
    host_index_count: u32,
    host_primitive_restart: bool,
    uses_builtin_index_buffer: bool,

    pub fn isEmpty(self: Plan) bool {
        return self.rectangle_count == 0 or self.host_index_count == 0;
    }

    pub fn usesGuestIndexBuffer(self: Plan) bool {
        return self.guest_source == .dma and self.guest_vertex_count != 0;
    }
};

pub const Result = union(enum) {
    not_rectangle_list,
    rejected: RejectReason,
    ready: Plan,
};

pub const IndexWriteError = error{
    OutputTooSmall,
    CountOverflow,
};

/// Xenia's built-in index buffer contains four indices for every expanded
/// primitive and one UINT32_MAX primitive restart between adjacent strips.
/// Keeping the arithmetic in u64 makes the overflow boundary explicit before
/// a host draw receives a wrapped index count.
pub fn twoTriangleStripIndexCount(strip_count: u32) IndexWriteError!u32 {
    if (strip_count == 0) return 0;
    const count = @as(u64, strip_count) * 4 + @as(u64, strip_count - 1);
    if (count > std.math.maxInt(u32)) return error.CountOverflow;
    return @intCast(count);
}

/// Fill a caller-owned host index buffer with Xenia's deterministic fallback
/// pattern.  For two rectangles this writes:
/// 0,1,2,3, UINT32_MAX, 4,5,6,7.
pub fn writeTwoTriangleStripIndices(strip_count: u32, output: []u32) IndexWriteError!usize {
    const needed = try twoTriangleStripIndexCount(strip_count);
    if (output.len < needed) return error.OutputTooSmall;
    var cursor: usize = 0;
    for (0..@as(usize, strip_count)) |strip| {
        if (strip != 0) {
            output[cursor] = std.math.maxInt(u32);
            cursor += 1;
        }
        const first = @as(u64, @intCast(strip)) * 4;
        if (first + 3 > std.math.maxInt(u32)) return error.CountOverflow;
        for (0..4) |vertex| {
            output[cursor] = @intCast(first + vertex);
            cursor += 1;
        }
    }
    return cursor;
}

fn effectiveGuestVertexCount(draw: pm4_executor.Draw) u32 {
    if (draw.source != .dma) return draw.count;
    return @min(draw.count, draw.index_size_words);
}

/// Plan one PM4 draw.  Non-rectangle draws are intentionally returned as
/// not_rectangle_list so a caller can let its ordinary backend path handle
/// them.  A rectangle draw is never silently accepted if its source encoding
/// is not one of the two paths Xenia's primitive processor supports.
pub fn lower(draw: pm4_executor.Draw, capabilities: Capabilities) Result {
    if (draw.primitive != .rectangle_list) return .not_rectangle_list;

    const source: regs.SourceSelect = switch (draw.source) {
        .dma, .auto_index => draw.source,
        .immediate => return .{ .rejected = .immediate_source },
        _ => return .{ .rejected = .unknown_source },
    };
    const guest_count = effectiveGuestVertexCount(draw);
    const rectangle_count = guest_count / 3;
    const trailing = @as(u2, @intCast(guest_count % 3));

    if (capabilities.geometry_shader) {
        // This matches VulkanPipelineCache's native rectangle-list route:
        // triangle-list topology plus a geometry shader that expands each
        // group of three guest vertices.
        return .{ .ready = .{
            .backend = .native_geometry,
            .guest_source = source,
            .guest_index_format = draw.index_format,
            .guest_index_address = draw.index_address,
            .guest_index_size_words = draw.index_size_words,
            .guest_index_endian = draw.index_endian,
            .index_offset = draw.index_offset,
            .instance_count = draw.instance_count,
            .requested_vertex_count = draw.count,
            .guest_vertex_count = guest_count,
            .ignored_trailing_vertices = trailing,
            .rectangle_count = rectangle_count,
            .host_topology = .triangle_list,
            .host_vertex_shader = .vertex,
            .host_geometry_shader = .rectangle_list,
            .host_index_format = draw.index_format,
            .host_index_count = guest_count,
            .host_primitive_restart = false,
            .uses_builtin_index_buffer = false,
        } };
    }

    const host_index_count = twoTriangleStripIndexCount(rectangle_count) catch {
        return .{ .rejected = .host_index_count_overflow };
    };
    return .{
        .ready = .{
            .backend = .vertex_shader_indexed,
            .guest_source = source,
            .guest_index_format = draw.index_format,
            .guest_index_address = draw.index_address,
            .guest_index_size_words = draw.index_size_words,
            .guest_index_endian = draw.index_endian,
            .index_offset = draw.index_offset,
            .instance_count = draw.instance_count,
            .requested_vertex_count = draw.count,
            .guest_vertex_count = guest_count,
            .ignored_trailing_vertices = trailing,
            .rectangle_count = rectangle_count,
            .host_topology = .triangle_strip,
            .host_vertex_shader = .rectangle_list_as_triangle_strip,
            .host_geometry_shader = .none,
            // The generated indices are always 32-bit, even for a 16-bit guest
            // index buffer, because their values identify expanded host vertices.
            .host_index_format = .uint32,
            .host_index_count = host_index_count,
            .host_primitive_restart = true,
            .uses_builtin_index_buffer = true,
        },
    };
}

test "rectangle fallback lowers one auto-indexed rectangle exactly" {
    const result = lower(.{
        .primitive = .rectangle_list,
        .source = .auto_index,
        .index_format = .uint16,
        .count = 3,
    }, .{});
    const plan = result.ready;
    try std.testing.expectEqual(Backend.vertex_shader_indexed, plan.backend);
    try std.testing.expectEqual(pipeline.Topology.triangle_strip, plan.host_topology);
    try std.testing.expectEqual(shader_execution.HostVertexShaderType.rectangle_list_as_triangle_strip, plan.host_vertex_shader);
    try std.testing.expectEqual(GeometryShader.none, plan.host_geometry_shader);
    try std.testing.expectEqual(@as(u32, 1), plan.rectangle_count);
    try std.testing.expectEqual(@as(u32, 4), plan.host_index_count);
    try std.testing.expect(plan.host_primitive_restart);
    try std.testing.expect(plan.uses_builtin_index_buffer);
    try std.testing.expect(!plan.usesGuestIndexBuffer());

    var indices: [4]u32 = undefined;
    try std.testing.expectEqual(@as(usize, 4), try writeTwoTriangleStripIndices(1, &indices));
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2, 3 }, &indices);
}

test "rectangle fallback preserves DMA index metadata and restart boundaries" {
    const result = lower(.{
        .indexed = true,
        .primitive = .rectangle_list,
        .source = .dma,
        .index_format = .uint16,
        .count = 6,
        .index_address = 0x2000,
        .index_size_words = 6,
        .index_endian = .@"8in16",
        .index_offset = -4,
    }, .{});
    const plan = result.ready;
    try std.testing.expectEqual(@as(u32, 6), plan.guest_vertex_count);
    try std.testing.expectEqual(@as(u32, 2), plan.rectangle_count);
    try std.testing.expectEqual(@as(u32, 9), plan.host_index_count);
    try std.testing.expectEqual(@as(u32, 0x2000), plan.guest_index_address);
    try std.testing.expectEqual(regs.Endian.@"8in16", plan.guest_index_endian);
    try std.testing.expect(plan.usesGuestIndexBuffer());

    var indices: [9]u32 = undefined;
    _ = try writeTwoTriangleStripIndices(2, &indices);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2, 3, std.math.maxInt(u32), 4, 5, 6, 7 }, &indices);
}

test "native geometry route keeps three guest vertices per rectangle" {
    const result = lower(.{
        .primitive = .rectangle_list,
        .source = .auto_index,
        .index_format = .uint16,
        .count = 6,
    }, .{ .geometry_shader = true });
    const plan = result.ready;
    try std.testing.expectEqual(Backend.native_geometry, plan.backend);
    try std.testing.expectEqual(pipeline.Topology.triangle_list, plan.host_topology);
    try std.testing.expectEqual(shader_execution.HostVertexShaderType.vertex, plan.host_vertex_shader);
    try std.testing.expectEqual(GeometryShader.rectangle_list, plan.host_geometry_shader);
    try std.testing.expectEqual(@as(u32, 6), plan.host_index_count);
    try std.testing.expect(!plan.host_primitive_restart);
    try std.testing.expect(!plan.uses_builtin_index_buffer);
}

test "DMA size clamps safely and reports an incomplete trailing rectangle" {
    const result = lower(.{
        .indexed = true,
        .primitive = .rectangle_list,
        .source = .dma,
        .index_format = .uint32,
        .count = 9,
        .index_size_words = 4,
    }, .{});
    const plan = result.ready;
    try std.testing.expectEqual(@as(u32, 4), plan.guest_vertex_count);
    try std.testing.expectEqual(@as(u32, 1), plan.rectangle_count);
    try std.testing.expectEqual(@as(u2, 1), plan.ignored_trailing_vertices);
    try std.testing.expectEqual(@as(u32, 4), plan.host_index_count);
}

test "unsupported sources and non-rectangles are not disguised as backend success" {
    const immediate = lower(.{
        .primitive = .rectangle_list,
        .source = .immediate,
        .index_format = .uint16,
        .count = 3,
    }, .{});
    try std.testing.expectEqual(RejectReason.immediate_source, immediate.rejected);

    const other = lower(.{
        .primitive = .triangle_list,
        .source = .auto_index,
        .index_format = .uint16,
        .count = 3,
    }, .{});
    try std.testing.expectEqual(Result.not_rectangle_list, other);
}

test "index pattern arithmetic rejects a host count that would wrap" {
    try std.testing.expectEqual(@as(u32, 0), try twoTriangleStripIndexCount(0));
    try std.testing.expectEqual(@as(u32, 4), try twoTriangleStripIndexCount(1));
    try std.testing.expectEqual(@as(u32, 9), try twoTriangleStripIndexCount(2));
    try std.testing.expectError(error.CountOverflow, twoTriangleStripIndexCount(std.math.maxInt(u32) / 4));
    var too_small: [3]u32 = undefined;
    try std.testing.expectError(error.OutputTooSmall, writeTwoTriangleStripIndices(1, &too_small));
}
