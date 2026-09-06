//! Typed Xenos register state used by the PM4 executor and diagnostics.
//!
//! The MMIO observer tells us that a register was touched.  This module gives
//! the command processor a bounded register file and decodes the fields that
//! affect a draw, a resolve, or a synchronization event.  Unknown registers are
//! retained verbatim; silently dropping one makes later draw failures look like
//! shader failures.

const std = @import("std");

/// The Xenos register numbers and aperture bounds moved to
/// `pkg/common/xenos/register-map`: they are console hardware facts, fixed
/// when the silicon was, and they were sitting in the same file as the live
/// register file below — an immutable table and mutable state one scroll
/// apart. The names are re-exported so every consumer keeps spelling them
/// `regs.CP_RB_BASE`, and so this file stays the one place that owns the
/// *values* a register holds.
const register_map = @import("xenos_register_map");
const journal_module = @import("register_journal.zig");

pub const Register = register_map.Register;
pub const register_count = register_map.register_count;
pub const CP_RB_BASE = register_map.CP_RB_BASE;
pub const CP_RB_CNTL = register_map.CP_RB_CNTL;
pub const CP_RB_RPTR_ADDR = register_map.CP_RB_RPTR_ADDR;
pub const CP_RB_RPTR = register_map.CP_RB_RPTR;
pub const CP_RB_WPTR = register_map.CP_RB_WPTR;
pub const CP_RB_WPTR_DELAY = register_map.CP_RB_WPTR_DELAY;
pub const CP_RB_RPTR_WR = register_map.CP_RB_RPTR_WR;
pub const CP_IB1_BASE = register_map.CP_IB1_BASE;
pub const CP_IB1_BUFSZ = register_map.CP_IB1_BUFSZ;
pub const CP_IB2_BASE = register_map.CP_IB2_BASE;
pub const CP_IB2_BUFSZ = register_map.CP_IB2_BUFSZ;
pub const CP_PROG_COUNTER = register_map.CP_PROG_COUNTER;
pub const SQ_PROGRAM_CNTL = register_map.SQ_PROGRAM_CNTL;
pub const SQ_CONTEXT_MISC = register_map.SQ_CONTEXT_MISC;
pub const SQ_INTERPOLATOR_CNTL = register_map.SQ_INTERPOLATOR_CNTL;
pub const SQ_CF_RD_BASE = register_map.SQ_CF_RD_BASE;
pub const SQ_PS_PROGRAM = register_map.SQ_PS_PROGRAM;
pub const SQ_VS_PROGRAM = register_map.SQ_VS_PROGRAM;
pub const VGT_EVENT_INITIATOR = register_map.VGT_EVENT_INITIATOR;
pub const VGT_DMA_BASE = register_map.VGT_DMA_BASE;
pub const VGT_DMA_SIZE = register_map.VGT_DMA_SIZE;
pub const VGT_DRAW_INITIATOR = register_map.VGT_DRAW_INITIATOR;
pub const VGT_IMMED_DATA = register_map.VGT_IMMED_DATA;
pub const VGT_INDX_OFFSET = register_map.VGT_INDX_OFFSET;
pub const RB_DEPTHCONTROL = register_map.RB_DEPTHCONTROL;
pub const RB_BLENDCONTROL0 = register_map.RB_BLENDCONTROL0;
pub const RB_COLORCONTROL = register_map.RB_COLORCONTROL;
pub const PA_CL_CLIP_CNTL = register_map.PA_CL_CLIP_CNTL;
pub const PA_SU_SC_MODE_CNTL = register_map.PA_SU_SC_MODE_CNTL;
pub const PA_SU_VTX_CNTL = register_map.PA_SU_VTX_CNTL;
pub const PA_CL_VTE_CNTL = register_map.PA_CL_VTE_CNTL;
pub const RB_MODECONTROL = register_map.RB_MODECONTROL;
pub const RB_BLENDCONTROL1 = register_map.RB_BLENDCONTROL1;
pub const RB_BLENDCONTROL2 = register_map.RB_BLENDCONTROL2;
pub const RB_BLENDCONTROL3 = register_map.RB_BLENDCONTROL3;
pub const PA_SU_POINT_SIZE = register_map.PA_SU_POINT_SIZE;
pub const PA_SU_POINT_MINMAX = register_map.PA_SU_POINT_MINMAX;
pub const PA_SU_LINE_CNTL = register_map.PA_SU_LINE_CNTL;
pub const PA_SC_LINE_STIPPLE = register_map.PA_SC_LINE_STIPPLE;
pub const VGT_OUTPUT_PATH_CNTL = register_map.VGT_OUTPUT_PATH_CNTL;
pub const VGT_HOS_CNTL = register_map.VGT_HOS_CNTL;
pub const VGT_HOS_MAX_TESS_LEVEL = register_map.VGT_HOS_MAX_TESS_LEVEL;
pub const VGT_HOS_MIN_TESS_LEVEL = register_map.VGT_HOS_MIN_TESS_LEVEL;
pub const PA_SC_MPASS_PS_CNTL = register_map.PA_SC_MPASS_PS_CNTL;
pub const PA_SC_VIZ_QUERY = register_map.PA_SC_VIZ_QUERY;
pub const PA_SC_VIZ_QUERY_STATUS_0 = register_map.PA_SC_VIZ_QUERY_STATUS_0;
pub const PA_SC_VIZ_QUERY_STATUS_1 = register_map.PA_SC_VIZ_QUERY_STATUS_1;
pub const PA_CL_VPORT_XSCALE = register_map.PA_CL_VPORT_XSCALE;
pub const PA_CL_VPORT_XOFFSET = register_map.PA_CL_VPORT_XOFFSET;
pub const PA_CL_VPORT_YSCALE = register_map.PA_CL_VPORT_YSCALE;
pub const PA_CL_VPORT_YOFFSET = register_map.PA_CL_VPORT_YOFFSET;
pub const PA_CL_VPORT_ZSCALE = register_map.PA_CL_VPORT_ZSCALE;
pub const PA_CL_VPORT_ZOFFSET = register_map.PA_CL_VPORT_ZOFFSET;
pub const PA_SC_SCREEN_SCISSOR_TL = register_map.PA_SC_SCREEN_SCISSOR_TL;
pub const PA_SC_SCREEN_SCISSOR_BR = register_map.PA_SC_SCREEN_SCISSOR_BR;
pub const PA_SC_WINDOW_OFFSET = register_map.PA_SC_WINDOW_OFFSET;
pub const PA_SC_WINDOW_SCISSOR_TL = register_map.PA_SC_WINDOW_SCISSOR_TL;
pub const PA_SC_WINDOW_SCISSOR_BR = register_map.PA_SC_WINDOW_SCISSOR_BR;
pub const RB_SURFACE_INFO = register_map.RB_SURFACE_INFO;
pub const RB_COLOR_INFO = register_map.RB_COLOR_INFO;
pub const RB_DEPTH_INFO = register_map.RB_DEPTH_INFO;
pub const RB_COLOR1_INFO = register_map.RB_COLOR1_INFO;
pub const RB_COLOR2_INFO = register_map.RB_COLOR2_INFO;
pub const RB_COLOR3_INFO = register_map.RB_COLOR3_INFO;
pub const RB_COLOR_MASK = register_map.RB_COLOR_MASK;
pub const RB_ALPHA_REF = register_map.RB_ALPHA_REF;
pub const RB_STENCILREFMASK_BF = register_map.RB_STENCILREFMASK_BF;
pub const RB_STENCILREFMASK = register_map.RB_STENCILREFMASK;
pub const RB_COPY_CONTROL = register_map.RB_COPY_CONTROL;
pub const RB_COPY_DEST_BASE = register_map.RB_COPY_DEST_BASE;
pub const RB_COPY_DEST_PITCH = register_map.RB_COPY_DEST_PITCH;
pub const RB_COPY_DEST_INFO = register_map.RB_COPY_DEST_INFO;
pub const RB_HIZ_CLEAR = register_map.RB_HIZ_CLEAR;
pub const RB_DEPTH_CLEAR = register_map.RB_DEPTH_CLEAR;
pub const RB_COLOR_CLEAR = register_map.RB_COLOR_CLEAR;
pub const RB_COLOR_CLEAR_LO = register_map.RB_COLOR_CLEAR_LO;
pub const RB_SAMPLE_COUNT_ADDR = register_map.RB_SAMPLE_COUNT_ADDR;
pub const WRITEBACK_START = register_map.WRITEBACK_START;
pub const WRITEBACK_SIZE = register_map.WRITEBACK_SIZE;
pub const SQ_VS_CONST = register_map.SQ_VS_CONST;
pub const SQ_PS_CONST = register_map.SQ_PS_CONST;
pub const PA_SU_POLY_OFFSET_FRONT_SCALE = register_map.PA_SU_POLY_OFFSET_FRONT_SCALE;
pub const PA_SU_POLY_OFFSET_FRONT_OFFSET = register_map.PA_SU_POLY_OFFSET_FRONT_OFFSET;
pub const PA_SU_POLY_OFFSET_BACK_SCALE = register_map.PA_SU_POLY_OFFSET_BACK_SCALE;
pub const PA_SU_POLY_OFFSET_BACK_OFFSET = register_map.PA_SU_POLY_OFFSET_BACK_OFFSET;
pub const PA_CL_POINT_SIZE = register_map.PA_CL_POINT_SIZE;
pub const shader_constant_fetch_base = register_map.shader_constant_fetch_base;
pub const shader_constant_fetch_count = register_map.shader_constant_fetch_count;
pub const vertex_fetch_constant_count = register_map.vertex_fetch_constant_count;
pub const shader_constant_alu_base = register_map.shader_constant_alu_base;
pub const shader_constant_bool_base = register_map.shader_constant_bool_base;
pub const shader_constant_loop_base = register_map.shader_constant_loop_base;
pub const shader_constant_register_base = register_map.shader_constant_register_base;
pub const vertex_fetch_register_base = register_map.vertex_fetch_register_base;

pub const PrimitiveType = enum(u8) {
    point_list = 0,
    line_list = 1,
    line_strip = 2,
    triangle_list = 4,
    triangle_fan = 5,
    triangle_strip = 6,
    rectangle_list = 8,
    quad_list = 9,
    quad_strip = 10,
    polygon = 11,
    _,
};

pub const SourceSelect = enum(u2) {
    dma = 0,
    immediate = 1,
    auto_index = 2,
    _,
};

pub const IndexFormat = enum(u1) {
    uint16 = 0,
    uint32 = 1,
};

/// The two dwords in a Xenos vertex fetch constant.  These are deliberately
/// kept separate from the texture fetch metadata: Xenia uses the same
/// register aperture for both, but the vertex constant has only an address,
/// endian mode, and word count.
pub const FetchConstantType = enum(u2) {
    invalid_texture = 0,
    invalid_vertex = 1,
    texture = 2,
    vertex = 3,
};

pub const TextureDimension = enum(u2) {
    one_d = 0,
    two_d = 1,
    three_d = 2,
    cube = 3,
};

pub const Endian = enum(u2) {
    none = 0,
    @"8in16" = 1,
    @"8in32" = 2,
    @"16in32" = 3,
};

pub const VertexFetch = struct {
    type: FetchConstantType = .invalid_texture,
    address_dwords: u32 = 0,
    endian: Endian = .none,
    size_words: u32 = 0,

    pub fn decode(raw: [2]u32) VertexFetch {
        return .{
            .type = @enumFromInt(@as(u2, @truncate(raw[0] & 0x3))),
            .address_dwords = raw[0] >> 2,
            .endian = @enumFromInt(@as(u2, @truncate(raw[1] & 0x3))),
            .size_words = (raw[1] >> 2) & 0x00FF_FFFF,
        };
    }

    pub fn addressBytes(self: VertexFetch) u64 {
        return @as(u64, self.address_dwords) * 4;
    }

    pub fn sizeBytes(self: VertexFetch) u64 {
        return @as(u64, self.size_words) * 4;
    }
};

fn signedBits(value: u32, bits: u5) i32 {
    const mask = (@as(u32, 1) << bits) - 1;
    const raw: i32 = @intCast(value & mask);
    const sign = @as(i32, 1) << (bits - 1);
    return if ((raw & sign) != 0) raw - (@as(i32, 1) << bits) else raw;
}

/// Decoded form of the six-dword Xenos texture fetch constant.  The Vulkan
/// path normally receives the finished SPIR-V/resource bindings from Xenia,
/// but retaining this state is still important for the fallback presenter,
/// diagnostics, and texture-cache invalidation.  Stored dimensions and
/// addresses are expanded to the units callers actually use.
pub const TextureFetch = struct {
    type: FetchConstantType = .invalid_texture,
    sign: [4]u2 = .{ 0, 0, 0, 0 },
    clamp: [3]u3 = .{ 0, 0, 0 },
    pitch_pixels: u32 = 0,
    tiled: bool = false,
    format: u6 = 0,
    endian: Endian = .none,
    request_size: u2 = 0,
    stacked: bool = false,
    nearest_clamp_policy: bool = false,
    base_address_bytes: u64 = 0,
    width: u32 = 1,
    height: u32 = 1,
    depth: u32 = 1,
    num_format: bool = false,
    swizzle: u12 = 0,
    exp_adjust: i8 = 0,
    mag_filter: u2 = 0,
    min_filter: u2 = 0,
    mip_filter: u2 = 0,
    aniso_filter: u3 = 0,
    arbitrary_filter: u3 = 0,
    border_size: bool = false,
    volume_mag_filter: bool = false,
    volume_min_filter: bool = false,
    mip_min_level: u4 = 0,
    mip_max_level: u4 = 0,
    mag_aniso_walk: bool = false,
    min_aniso_walk: bool = false,
    lod_bias: i16 = 0,
    grad_exp_adjust_h: i8 = 0,
    grad_exp_adjust_v: i8 = 0,
    border_color: u2 = 0,
    force_bc_w_to_max: bool = false,
    tri_clamp: u2 = 0,
    aniso_bias: i8 = 0,
    dimension: TextureDimension = .two_d,
    packed_mips: bool = false,
    mip_address_bytes: u64 = 0,

    pub fn decode(raw: [6]u32) TextureFetch {
        const dimension: TextureDimension = @enumFromInt(@as(u2, @truncate(raw[5] >> 9)));
        var result = TextureFetch{
            .type = @enumFromInt(@as(u2, @truncate(raw[0]))),
            .sign = .{
                @truncate(raw[0] >> 2),
                @truncate(raw[0] >> 4),
                @truncate(raw[0] >> 6),
                @truncate(raw[0] >> 8),
            },
            .clamp = .{
                @truncate(raw[0] >> 10),
                @truncate(raw[0] >> 13),
                @truncate(raw[0] >> 16),
            },
            .pitch_pixels = ((raw[0] >> 22) & 0x1FF) << 5,
            .tiled = (raw[0] & 0x8000_0000) != 0,
            .format = @truncate(raw[1]),
            .endian = @enumFromInt(@as(u2, @truncate(raw[1] >> 6))),
            .request_size = @truncate(raw[1] >> 8),
            .stacked = (raw[1] & (1 << 10)) != 0,
            .nearest_clamp_policy = (raw[1] & (1 << 11)) != 0,
            .base_address_bytes = @as(u64, raw[1] >> 12) << 12,
            .num_format = (raw[3] & 1) != 0,
            .swizzle = @truncate(raw[3] >> 1),
            .exp_adjust = @intCast(signedBits(raw[3] >> 13, 6)),
            .mag_filter = @truncate(raw[3] >> 19),
            .min_filter = @truncate(raw[3] >> 21),
            .mip_filter = @truncate(raw[3] >> 23),
            .aniso_filter = @truncate(raw[3] >> 25),
            .arbitrary_filter = @truncate(raw[3] >> 28),
            .border_size = (raw[3] & 0x8000_0000) != 0,
            .volume_mag_filter = (raw[4] & 1) != 0,
            .volume_min_filter = (raw[4] & 2) != 0,
            .mip_min_level = @truncate(raw[4] >> 2),
            .mip_max_level = @truncate(raw[4] >> 6),
            .mag_aniso_walk = (raw[4] & (1 << 10)) != 0,
            .min_aniso_walk = (raw[4] & (1 << 11)) != 0,
            .lod_bias = @intCast(signedBits(raw[4] >> 12, 10)),
            .grad_exp_adjust_h = @intCast(signedBits(raw[4] >> 22, 5)),
            .grad_exp_adjust_v = @intCast(signedBits(raw[4] >> 27, 5)),
            .border_color = @truncate(raw[5]),
            .force_bc_w_to_max = (raw[5] & (1 << 2)) != 0,
            .tri_clamp = @truncate(raw[5] >> 3),
            .aniso_bias = @intCast(signedBits(raw[5] >> 5, 4)),
            .dimension = dimension,
            .packed_mips = (raw[5] & (1 << 11)) != 0,
            .mip_address_bytes = @as(u64, raw[5] >> 12) << 12,
        };

        switch (dimension) {
            .one_d => {
                result.width = (raw[2] & 0x00FF_FFFF) + 1;
            },
            .two_d => {
                result.width = (raw[2] & 0x1FFF) + 1;
                result.height = ((raw[2] >> 13) & 0x1FFF) + 1;
                result.depth = if (result.stacked) ((raw[2] >> 26) & 0x3F) + 1 else 1;
            },
            .three_d => {
                result.width = (raw[2] & 0x7FF) + 1;
                result.height = ((raw[2] >> 11) & 0x7FF) + 1;
                result.depth = ((raw[2] >> 22) & 0x3FF) + 1;
            },
            .cube => {
                result.width = (raw[2] & 0x1FFF) + 1;
                result.height = ((raw[2] >> 13) & 0x1FFF) + 1;
                result.depth = if (result.stacked) ((raw[2] >> 26) & 0x3F) + 1 else 6;
            },
        }
        return result;
    }
};

pub const IndexBufferState = struct {
    address_bytes: u32 = 0,
    num_words: u32 = 0,
    endian: Endian = .none,
    format: IndexFormat = .uint16,

    pub fn byteLength(self: IndexBufferState) u64 {
        return @as(u64, self.num_words) * if (self.format == .uint32) 4 else 2;
    }
};

pub const IndexOffset = struct {
    value: i32 = 0,

    pub fn decode(raw: u32) IndexOffset {
        const narrowed: i32 = @intCast(raw & 0x00FF_FFFF);
        return .{ .value = if ((narrowed & 0x0080_0000) != 0) narrowed - 0x0100_0000 else narrowed };
    }
};

pub const DrawInitiator = struct {
    primitive: PrimitiveType,
    source: SourceSelect,
    major_mode_explicit: bool,
    index_format: IndexFormat,
    not_end_of_pipe: bool,
    index_count: u32,

    pub fn decode(raw: u32) DrawInitiator {
        return .{
            .primitive = @enumFromInt(@as(u8, @truncate(raw & 0x3F))),
            .source = @enumFromInt(@as(u2, @truncate(raw >> 6))),
            .major_mode_explicit = ((raw >> 8) & 0x3) != 0,
            .index_format = @enumFromInt(@as(u1, @truncate(raw >> 11))),
            .not_end_of_pipe = ((raw >> 12) & 1) != 0,
            .index_count = (raw >> 16) & 0xFFFF,
        };
    }

    pub fn encode(self: DrawInitiator) u32 {
        return @as(u32, @intFromEnum(self.primitive)) |
            (@as(u32, @intFromEnum(self.source)) << 6) |
            (@as(u32, @intFromBool(self.major_mode_explicit)) << 8) |
            (@as(u32, @intFromEnum(self.index_format)) << 11) |
            (@as(u32, @intFromBool(self.not_end_of_pipe)) << 12) |
            ((self.index_count & 0xFFFF) << 16);
    }
};

pub const Viewport = struct {
    x_scale: f32 = 1,
    x_offset: f32 = 0,
    y_scale: f32 = 1,
    y_offset: f32 = 0,
    z_scale: f32 = 1,
    z_offset: f32 = 0,
};

pub const Scissor = struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

pub const RenderTargetState = struct {
    color_base_tiles: u32 = 0,
    color_format: u32 = 0,
    color_exp_bias: i32 = 0,
    depth_base_tiles: u32 = 0,
    depth_format: u32 = 0,
    surface_pitch_pixels: u32 = 0,
    msaa_mode: u2 = 0,
    color_mask: u8 = 0xFF,
};

pub const RasterState = struct {
    cull_front: bool = false,
    cull_back: bool = false,
    front_face_clockwise: bool = false,
    polygon_mode: u2 = 0,
    polygon_offset_front_enable: bool = false,
    polygon_offset_back_enable: bool = false,
    polygon_offset_para_enable: bool = false,
    polygon_offset_front_scale: f32 = 0,
    polygon_offset_front_offset: f32 = 0,
    polygon_offset_back_scale: f32 = 0,
    polygon_offset_back_offset: f32 = 0,
    msaa_enable: bool = false,
    primitive_restart: bool = false,
    clip_disable: bool = false,
    depth_clamp: bool = false,
    viewport_transform: bool = false,
};

/// SQ_PROGRAM_CNTL controls register allocation and export conventions for
/// both Xenos shader stages.  Keep the raw minus-one register counts visible:
/// zero is a meaningful hardware value, while callers can use `registerCount`
/// when they need the actual number of GPRs.
pub const ProgramControl = struct {
    vs_num_reg: u6 = 0,
    ps_num_reg: u6 = 0,
    vs_resource: bool = false,
    ps_resource: bool = false,
    param_gen: bool = false,
    gen_index_pix: bool = false,
    vs_export_count: u4 = 0,
    vs_export_mode: u3 = 0,
    ps_export_mode: u4 = 0,
    gen_index_vtx: bool = false,

    pub fn decode(raw: u32) ProgramControl {
        return .{
            .vs_num_reg = @truncate(raw),
            .ps_num_reg = @truncate(raw >> 8),
            .vs_resource = (raw & (1 << 16)) != 0,
            .ps_resource = (raw & (1 << 17)) != 0,
            .param_gen = (raw & (1 << 18)) != 0,
            .gen_index_pix = (raw & (1 << 19)) != 0,
            .vs_export_count = @truncate(raw >> 20),
            .vs_export_mode = @truncate(raw >> 24),
            .ps_export_mode = @truncate(raw >> 27),
            .gen_index_vtx = (raw & (1 << 31)) != 0,
        };
    }

    pub fn vertexRegisterCount(self: ProgramControl) u8 {
        return @as(u8, self.vs_num_reg) + 1;
    }

    pub fn pixelRegisterCount(self: ProgramControl) u8 {
        return @as(u8, self.ps_num_reg) + 1;
    }
};

pub const ContextMisc = struct {
    inst_pred_optimize: bool = false,
    output_screen_xy: bool = false,
    sample_control: u2 = 0,
    param_gen_pos: u8 = 0,
    tx_cache_select: bool = false,

    pub fn decode(raw: u32) ContextMisc {
        return .{
            .inst_pred_optimize = (raw & 1) != 0,
            .output_screen_xy = (raw & (1 << 1)) != 0,
            .sample_control = @truncate(raw >> 2),
            .param_gen_pos = @truncate(raw >> 8),
            .tx_cache_select = (raw & (1 << 18)) != 0,
        };
    }
};

pub const OutputPathState = struct {
    path_select: u2 = 0,
    tessellation_mode: u2 = 0,
    max_tessellation_level: f32 = 0,
    min_tessellation_level: f32 = 0,
};

pub const PointState = struct {
    min_diameter: f32 = 0,
    max_diameter: f32 = 0,
    constant_width: f32 = 0,
    constant_height: f32 = 0,
};

pub const DepthStencilState = struct {
    stencil_enable: bool = false,
    depth_enable: bool = false,
    depth_write_enable: bool = false,
    depth_compare: u3 = 7,
    stencil_compare: u3 = 7,
    stencil_fail: u3 = 0,
    stencil_depth_pass: u3 = 0,
    stencil_depth_fail: u3 = 0,
    back_stencil_compare: u3 = 7,
    back_stencil_fail: u3 = 0,
    back_stencil_depth_pass: u3 = 0,
    back_stencil_depth_fail: u3 = 0,
    front_reference: u8 = 0,
    front_compare_mask: u8 = 0xFF,
    front_write_mask: u8 = 0xFF,
    back_reference: u8 = 0,
    back_compare_mask: u8 = 0xFF,
    back_write_mask: u8 = 0xFF,
};

pub const BlendState = struct {
    source_color: u5 = 1,
    color_op: u3 = 0,
    destination_color: u5 = 0,
    source_alpha: u5 = 1,
    alpha_op: u3 = 0,
    destination_alpha: u5 = 0,
    alpha_test_enable: bool = false,
    alpha_to_mask_enable: bool = false,
    alpha_compare: u3 = 7,
    alpha_reference: f32 = 0,
};

pub const RegisterFile = struct {
    values: [register_count]u32 = [_]u32{0} ** register_count,
    write_count: u64 = 0,
    read_count: u64 = 0,
    unknown_write_count: u64 = 0,
    last_register: Register = 0,
    /// Which registers the writes actually addressed.
    ///
    /// `write_count` alone cannot separate a title that programmed forty
    /// shader constants from one that programmed a colour target, and that
    /// distinction is the difference between a guest fact and a harness
    /// defect. Journalled here rather than at the executor because this is the
    /// one place every write funnels through, including the range writes that
    /// a per-call-site hook would miss.
    journal: journal_module.Journal = .{},

    pub fn read(self: *RegisterFile, register: Register) u32 {
        self.read_count +%= 1;
        if (register >= register_count) return 0;
        return self.values[register];
    }

    pub fn peek(self: *const RegisterFile, register: Register) u32 {
        if (register >= register_count) return 0;
        return self.values[register];
    }

    pub fn write(self: *RegisterFile, register: Register, value: u32) void {
        self.write_count +%= 1;
        self.last_register = register;
        self.journal.record(register, value, self.write_count);
        if (register >= register_count) {
            self.unknown_write_count +%= 1;
            return;
        }
        self.values[register] = value;
    }

    pub fn writeRange(self: *RegisterFile, start: Register, values: []const u32) void {
        for (values, 0..) |value, index| {
            const register = @as(u32, start) + @as(u32, @intCast(index));
            if (register > std.math.maxInt(Register)) break;
            self.write(@intCast(register), value);
        }
    }

    pub fn drawInitiator(self: *const RegisterFile) DrawInitiator {
        return DrawInitiator.decode(self.peek(VGT_DRAW_INITIATOR));
    }

    pub fn viewport(self: *const RegisterFile) Viewport {
        return .{
            .x_scale = @bitCast(self.peek(PA_CL_VPORT_XSCALE)),
            .x_offset = @bitCast(self.peek(PA_CL_VPORT_XOFFSET)),
            .y_scale = @bitCast(self.peek(PA_CL_VPORT_YSCALE)),
            .y_offset = @bitCast(self.peek(PA_CL_VPORT_YOFFSET)),
            .z_scale = @bitCast(self.peek(PA_CL_VPORT_ZSCALE)),
            .z_offset = @bitCast(self.peek(PA_CL_VPORT_ZOFFSET)),
        };
    }

    pub fn scissor(self: *const RegisterFile) Scissor {
        const tl = self.peek(PA_SC_SCREEN_SCISSOR_TL);
        const br = self.peek(PA_SC_SCREEN_SCISSOR_BR);
        return .{
            .left = signExtend15(tl & 0x7FFF),
            .top = signExtend15((tl >> 16) & 0x7FFF),
            .right = signExtend15(br & 0x7FFF),
            .bottom = signExtend15((br >> 16) & 0x7FFF),
        };
    }

    pub fn renderTarget(self: *const RegisterFile, index: usize) ?RenderTargetState {
        if (index >= 4) return null;
        const color_register = RB_COLOR_INFO + @as(Register, @intCast(index));
        const color = self.peek(color_register);
        // Target 0 is always the primary color register.  A zero secondary
        // register is the hardware's reset value and is therefore not an
        // enabled MRT; a programmed target may still legitimately use tile 0
        // because its format bits make the register non-zero.
        if (index != 0 and color == 0) return null;
        const depth = self.peek(RB_DEPTH_INFO);
        const surface = self.peek(RB_SURFACE_INFO);
        return .{
            .color_base_tiles = (color & 0x7FF) | (((color >> 11) & 1) << 11),
            .color_format = (color >> 16) & 0xF,
            .color_exp_bias = signExtend6((color >> 20) & 0x3F),
            .depth_base_tiles = (depth & 0x7FF) | (((depth >> 11) & 1) << 11),
            .depth_format = (depth >> 16) & 1,
            .surface_pitch_pixels = surface & 0x3FFF,
            .msaa_mode = @truncate(surface >> 16),
            .color_mask = @truncate(self.peek(RB_COLOR_MASK) >> @as(u5, @intCast(index * 4))),
        };
    }

    pub fn renderTargets(self: *const RegisterFile) RenderTargetState {
        return self.renderTarget(0).?;
    }

    pub fn raster(self: *const RegisterFile) RasterState {
        const mode = self.peek(PA_SU_SC_MODE_CNTL);
        const vte = self.peek(PA_CL_VTE_CNTL);
        return .{
            .cull_front = (mode & 1) != 0,
            .cull_back = (mode & 2) != 0,
            .front_face_clockwise = (mode & (1 << 2)) != 0,
            .polygon_mode = @truncate((mode >> 3) & 3),
            .polygon_offset_front_enable = (mode & (1 << 11)) != 0,
            .polygon_offset_back_enable = (mode & (1 << 12)) != 0,
            .polygon_offset_para_enable = (mode & (1 << 13)) != 0,
            .polygon_offset_front_scale = @bitCast(self.peek(PA_SU_POLY_OFFSET_FRONT_SCALE)),
            .polygon_offset_front_offset = @bitCast(self.peek(PA_SU_POLY_OFFSET_FRONT_OFFSET)),
            .polygon_offset_back_scale = @bitCast(self.peek(PA_SU_POLY_OFFSET_BACK_SCALE)),
            .polygon_offset_back_offset = @bitCast(self.peek(PA_SU_POLY_OFFSET_BACK_OFFSET)),
            .msaa_enable = (mode & (1 << 15)) != 0,
            .primitive_restart = (mode & (1 << 21)) != 0,
            .clip_disable = (self.peek(PA_CL_CLIP_CNTL) & (1 << 16)) != 0,
            // Xenos clipping is implemented through the clip-control and
            // shader viewport path rather than a Vulkan depth-clamp toggle.
            // Do not reinterpret an unrelated clip bit as depth clamping.
            .depth_clamp = false,
            .viewport_transform = (vte & 0x3F) != 0,
        };
    }

    pub fn programControl(self: *const RegisterFile) ProgramControl {
        return ProgramControl.decode(self.peek(SQ_PROGRAM_CNTL));
    }

    pub fn contextMisc(self: *const RegisterFile) ContextMisc {
        return ContextMisc.decode(self.peek(SQ_CONTEXT_MISC));
    }

    pub fn outputPath(self: *const RegisterFile) OutputPathState {
        return .{
            .path_select = @truncate(self.peek(VGT_OUTPUT_PATH_CNTL)),
            .tessellation_mode = @truncate(self.peek(VGT_HOS_CNTL)),
            .max_tessellation_level = @bitCast(self.peek(VGT_HOS_MAX_TESS_LEVEL)),
            .min_tessellation_level = @bitCast(self.peek(VGT_HOS_MIN_TESS_LEVEL)),
        };
    }

    pub fn pointState(self: *const RegisterFile) PointState {
        const minmax = self.peek(PA_SU_POINT_MINMAX);
        const size = self.peek(PA_SU_POINT_SIZE);
        return .{
            .min_diameter = @as(f32, @floatFromInt(minmax & 0xFFFF)) / 8.0,
            .max_diameter = @as(f32, @floatFromInt(minmax >> 16)) / 8.0,
            .constant_width = @as(f32, @floatFromInt(size >> 16)) / 8.0,
            .constant_height = @as(f32, @floatFromInt(size & 0xFFFF)) / 8.0,
        };
    }

    pub fn depthStencil(self: *const RegisterFile) DepthStencilState {
        const depth = self.peek(RB_DEPTHCONTROL);
        const front = self.peek(RB_STENCILREFMASK);
        const back = self.peek(RB_STENCILREFMASK_BF);
        return .{
            .stencil_enable = (depth & 1) != 0,
            .depth_enable = (depth & (1 << 1)) != 0,
            .depth_write_enable = (depth & (1 << 2)) != 0,
            .depth_compare = @truncate((depth >> 4) & 7),
            .stencil_compare = @truncate((depth >> 8) & 7),
            .stencil_fail = @truncate((depth >> 11) & 7),
            .stencil_depth_pass = @truncate((depth >> 14) & 7),
            .stencil_depth_fail = @truncate((depth >> 17) & 7),
            .back_stencil_compare = @truncate((depth >> 20) & 7),
            .back_stencil_fail = @truncate((depth >> 23) & 7),
            .back_stencil_depth_pass = @truncate((depth >> 26) & 7),
            .back_stencil_depth_fail = @truncate((depth >> 29) & 7),
            .front_reference = @truncate(front),
            .front_compare_mask = @truncate(front >> 8),
            .front_write_mask = @truncate(front >> 16),
            .back_reference = @truncate(back),
            .back_compare_mask = @truncate(back >> 8),
            .back_write_mask = @truncate(back >> 16),
        };
    }

    pub fn blend(self: *const RegisterFile, target: usize) BlendState {
        const blend_register = switch (target) {
            0 => RB_BLENDCONTROL0,
            1 => RB_BLENDCONTROL1,
            2 => RB_BLENDCONTROL2,
            else => RB_BLENDCONTROL3,
        };
        const value = self.peek(blend_register);
        const color_control = self.peek(RB_COLORCONTROL);
        return .{
            .source_color = @truncate(value),
            .color_op = @truncate(value >> 5),
            .destination_color = @truncate(value >> 8),
            .source_alpha = @truncate(value >> 16),
            .alpha_op = @truncate(value >> 21),
            .destination_alpha = @truncate(value >> 24),
            .alpha_test_enable = (color_control & (1 << 3)) != 0,
            .alpha_to_mask_enable = (color_control & (1 << 4)) != 0,
            .alpha_compare = @truncate(color_control & 7),
            .alpha_reference = @bitCast(self.peek(RB_ALPHA_REF)),
        };
    }

    pub fn aluConstant(self: *const RegisterFile, index: usize) ?[4]u32 {
        const base = @as(usize, shader_constant_alu_base) + index * 4;
        if (base + 4 > register_count) return null;
        return .{ self.values[base], self.values[base + 1], self.values[base + 2], self.values[base + 3] };
    }

    pub fn fetchConstant(self: *const RegisterFile, index: usize) ?[6]u32 {
        if (index >= shader_constant_fetch_count) return null;
        var result: [6]u32 = undefined;
        const base = @as(usize, shader_constant_fetch_base) + index * result.len;
        if (base + result.len > register_count) return null;
        for (&result, 0..) |*value, offset| value.* = self.values[base + offset];
        return result;
    }

    pub fn textureFetch(self: *const RegisterFile, index: usize) ?TextureFetch {
        return TextureFetch.decode(self.fetchConstant(index) orelse return null);
    }

    pub fn vertexFetchConstant(self: *const RegisterFile, index: usize) ?[2]u32 {
        if (index >= vertex_fetch_constant_count) return null;
        const base = @as(usize, vertex_fetch_register_base) + index * 2;
        if (base + 2 > register_count) return null;
        return .{ self.values[base], self.values[base + 1] };
    }

    pub fn vertexFetch(self: *const RegisterFile, index: usize) ?VertexFetch {
        return VertexFetch.decode(self.vertexFetchConstant(index) orelse return null);
    }

    pub fn indexBuffer(self: *const RegisterFile) IndexBufferState {
        const initiator = self.drawInitiator();
        const size = self.peek(VGT_DMA_SIZE);
        const bytes_per_index: u32 = if (initiator.index_format == .uint32) 4 else 2;
        return .{
            .address_bytes = self.peek(VGT_DMA_BASE) & ~(bytes_per_index - 1),
            .num_words = size & 0x00FF_FFFF,
            .endian = @enumFromInt(@as(u2, @truncate(size >> 30))),
            .format = initiator.index_format,
        };
    }

    pub fn indexOffset(self: *const RegisterFile) i32 {
        return IndexOffset.decode(self.peek(VGT_INDX_OFFSET)).value;
    }

    pub fn shaderProgramAddresses(self: *const RegisterFile) struct { vertex: u32, pixel: u32 } {
        return .{ .vertex = self.peek(SQ_VS_PROGRAM), .pixel = self.peek(SQ_PS_PROGRAM) };
    }

    fn signExtend15(value: u32) i32 {
        const narrowed: i32 = @intCast(value & 0x7FFF);
        return if ((value & 0x4000) != 0) narrowed - 0x8000 else narrowed;
    }

    fn signExtend6(value: u32) i32 {
        const narrowed: i32 = @intCast(value & 0x3F);
        return if ((value & 0x20) != 0) narrowed - 0x40 else narrowed;
    }
};

/// Bounds check against the retained aperture. Delegated so the window size
/// and the test against it cannot drift apart.
pub fn isRegisterAperture(register: u32) bool {
    return register_map.isRegisterAperture(register);
}

test "draw initiator round-trips the Xenos bit fields" {
    const input = DrawInitiator{
        .primitive = .triangle_list,
        .source = .dma,
        .major_mode_explicit = true,
        .index_format = .uint32,
        .not_end_of_pipe = true,
        .index_count = 1024,
    };
    try std.testing.expectEqual(input.encode(), DrawInitiator.decode(input.encode()).encode());
    try std.testing.expectEqual(@as(u32, 1024), DrawInitiator.decode(input.encode()).index_count);
}

test "index offset keeps the Xenos 24-bit signed domain" {
    var regs: RegisterFile = .{};
    regs.write(VGT_INDX_OFFSET, 0x0000_0024);
    try std.testing.expectEqual(@as(i32, 0x24), regs.indexOffset());
    regs.write(VGT_INDX_OFFSET, 0x00FF_FFF0);
    try std.testing.expectEqual(@as(i32, -16), regs.indexOffset());
    regs.write(VGT_INDX_OFFSET, 0xAB00_0007);
    try std.testing.expectEqual(@as(i32, 7), regs.indexOffset());
}

test "texture fetch decoder expands Xenos dimensions and addresses" {
    const raw = [_]u32{
        2 | (1 << 2) | (2 << 13) | (37 << 22) | 0x8000_0000,
        3 | (2 << 6) | (1 << 10) | (0x12345 << 12),
        127 | (63 << 11) | (3 << 22),
        1 | (0xA55 << 1) | (0x3F << 13) | (1 << 19) | (2 << 21) | (3 << 23),
        1 | 2 | (2 << 2) | (9 << 6) | (1 << 10) | (1 << 11) | (0x3FF << 12),
        2 | (1 << 2) | (3 << 3) | (0xF << 5) | (2 << 9) | (0x54321 << 12),
    };
    const fetch = TextureFetch.decode(raw);
    try std.testing.expectEqual(FetchConstantType.texture, fetch.type);
    try std.testing.expectEqual(@as(u32, 37 << 5), fetch.pitch_pixels);
    try std.testing.expect(fetch.tiled);
    try std.testing.expectEqual(@as(u32, 128), fetch.width);
    try std.testing.expectEqual(@as(u32, 64), fetch.height);
    try std.testing.expectEqual(@as(u32, 4), fetch.depth);
    try std.testing.expectEqual(@as(u64, 0x12345 << 12), fetch.base_address_bytes);
    try std.testing.expectEqual(TextureDimension.three_d, fetch.dimension);
    try std.testing.expectEqual(@as(i16, -1), fetch.lod_bias);
    try std.testing.expect(fetch.volume_mag_filter);
    try std.testing.expect(fetch.volume_min_filter);
    try std.testing.expect(fetch.mag_aniso_walk);
    try std.testing.expect(fetch.min_aniso_walk);
    try std.testing.expectEqual(@as(u2, 2), fetch.border_color);
    try std.testing.expect(fetch.force_bc_w_to_max);
    try std.testing.expectEqual(@as(u2, 3), fetch.tri_clamp);
    try std.testing.expectEqual(@as(i8, -1), fetch.aniso_bias);
}

test "register file decodes shader program, context, point, and polygon state" {
    var regs: RegisterFile = .{};
    regs.write(SQ_PROGRAM_CNTL, 3 | (5 << 8) | (1 << 16) | (2 << 20) | (4 << 24) | (7 << 27));
    regs.write(SQ_CONTEXT_MISC, 1 | (2 << 2) | (9 << 8) | (1 << 18));
    regs.write(VGT_OUTPUT_PATH_CNTL, 2);
    regs.write(VGT_HOS_CNTL, 1);
    regs.write(VGT_HOS_MAX_TESS_LEVEL, @bitCast(@as(f32, 32)));
    regs.write(VGT_HOS_MIN_TESS_LEVEL, @bitCast(@as(f32, 1)));
    regs.write(PA_SU_SC_MODE_CNTL, (1 << 11) | (1 << 15) | (1 << 16));
    regs.write(PA_CL_CLIP_CNTL, 1 << 16);
    regs.write(PA_SU_POLY_OFFSET_FRONT_SCALE, @bitCast(@as(f32, 2)));
    regs.write(PA_SU_POLY_OFFSET_FRONT_OFFSET, @bitCast(@as(f32, 3)));
    regs.write(PA_SU_POINT_MINMAX, 8 | (16 << 16));
    regs.write(PA_SU_POINT_SIZE, 24 | (32 << 16));
    const program = regs.programControl();
    const context = regs.contextMisc();
    const output = regs.outputPath();
    const raster = regs.raster();
    const point = regs.pointState();
    try std.testing.expectEqual(@as(u8, 4), program.vertexRegisterCount());
    try std.testing.expectEqual(@as(u8, 6), program.pixelRegisterCount());
    try std.testing.expect(program.vs_resource);
    try std.testing.expectEqual(@as(u2, 2), context.sample_control);
    try std.testing.expectEqual(@as(u8, 9), context.param_gen_pos);
    try std.testing.expectEqual(@as(u2, 2), output.path_select);
    try std.testing.expectEqual(@as(f32, 32), output.max_tessellation_level);
    try std.testing.expect(raster.polygon_offset_front_enable);
    try std.testing.expect(raster.msaa_enable);
    try std.testing.expect(raster.clip_disable);
    try std.testing.expectEqual(@as(f32, 2), raster.polygon_offset_front_scale);
    try std.testing.expectEqual(@as(f32, 3), raster.polygon_offset_front_offset);
    try std.testing.expectEqual(@as(f32, 1), point.min_diameter);
    try std.testing.expectEqual(@as(f32, 2), point.max_diameter);
    try std.testing.expectEqual(@as(f32, 4), point.constant_width);
    try std.testing.expectEqual(@as(f32, 3), point.constant_height);
}

test "register file decodes viewport, scissor, and render target state" {
    var regs: RegisterFile = .{};
    regs.write(PA_CL_VPORT_XSCALE, @bitCast(@as(f32, 640)));
    regs.write(PA_CL_VPORT_YOFFSET, @bitCast(@as(f32, 360)));
    regs.write(PA_SC_SCREEN_SCISSOR_TL, 2 | (3 << 16));
    regs.write(PA_SC_SCREEN_SCISSOR_BR, 1278 | (717 << 16));
    regs.write(RB_SURFACE_INFO, 1280 | (2 << 16));
    regs.write(RB_COLOR_INFO, 0x101 | (6 << 16));
    regs.write(RB_COLOR_INFO + 1, 0x202 | (7 << 16));
    regs.write(RB_COLOR_MASK, 0xA5);
    const viewport = regs.viewport();
    const scissor = regs.scissor();
    const targets = regs.renderTargets();
    try std.testing.expectEqual(@as(f32, 640), viewport.x_scale);
    try std.testing.expectEqual(@as(i32, 2), scissor.left);
    try std.testing.expectEqual(@as(u32, 6), targets.color_format);
    try std.testing.expectEqual(@as(u32, 1280), targets.surface_pitch_pixels);
    try std.testing.expectEqual(@as(u8, 0xA), regs.renderTarget(1).?.color_mask);
}

test "register indices match the Xenos register aperture" {
    try std.testing.expectEqual(@as(Register, 0x200E), PA_SC_SCREEN_SCISSOR_TL);
    try std.testing.expectEqual(@as(Register, 0x200F), PA_SC_SCREEN_SCISSOR_BR);
    try std.testing.expectEqual(@as(Register, 0x210F), PA_CL_VPORT_XSCALE);
    try std.testing.expectEqual(@as(Register, 0x2114), PA_CL_VPORT_ZOFFSET);
    try std.testing.expectEqual(@as(Register, 0x2102), VGT_INDX_OFFSET);
    try std.testing.expectEqual(@as(Register, 0x2302), PA_SU_VTX_CNTL);
    try std.testing.expectEqual(@as(Register, 0x231B), RB_COPY_DEST_INFO);
    try std.testing.expectEqual(@as(Register, 0x231D), RB_DEPTH_CLEAR);
    try std.testing.expectEqual(@as(Register, 0x231E), RB_COLOR_CLEAR);
    try std.testing.expectEqual(@as(Register, 0x231F), RB_COLOR_CLEAR_LO);
}

test "the register file journals which registers a write addressed" {
    // `write_count` cannot tell forty shader constants from a colour target,
    // and that difference decides whether a missing render target is the
    // title's doing or the harness losing the write.
    var regs = RegisterFile{};
    var index: u32 = 0;
    while (index < 40) : (index += 1) {
        regs.write(@intCast(0x4000 + index), 1 + index);
    }
    try std.testing.expectEqual(@as(u64, 40), regs.write_count);
    try std.testing.expectEqual(journal_module.Verdict.target_never_addressed, regs.journal.verdict());
    try std.testing.expect(regs.journal.block(.shader_constants).touched());
    try std.testing.expect(!regs.journal.block(.render_backend).touched());

    regs.write(RB_COLOR_INFO, 0x101 | (6 << 16));
    try std.testing.expectEqual(journal_module.Verdict.target_programmed, regs.journal.verdict());
    try std.testing.expect(regs.journal.target(RB_COLOR_INFO).?.ever_nonzero);
}

test "a range write is journalled register by register" {
    var regs = RegisterFile{};
    const values = [_]u32{ 1280 | (2 << 16), 0x101 | (6 << 16), 0x1 };
    regs.writeRange(RB_SURFACE_INFO, &values);
    try std.testing.expectEqual(@as(u64, 3), regs.journal.writes);
    try std.testing.expectEqual(@as(usize, 3), regs.journal.summary().target_nonzero);
}

test "an out-of-range write is journalled as well as dropped" {
    var regs = RegisterFile{};
    regs.write(0xFFFF, 1);
    try std.testing.expectEqual(@as(u64, 1), regs.unknown_write_count);
    try std.testing.expectEqual(@as(u64, 1), regs.journal.out_of_range_writes);
    try std.testing.expectEqual(@as(u32, 0), regs.peek(0xFFFF));
}
