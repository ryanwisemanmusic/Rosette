//! Typed Xenos register state used by the PM4 executor and diagnostics.
//!
//! The MMIO observer tells us that a register was touched.  This module gives
//! the command processor a bounded register file and decodes the fields that
//! affect a draw, a resolve, or a synchronization event.  Unknown registers are
//! retained verbatim; silently dropping one makes later draw failures look like
//! shader failures.

const std = @import("std");

pub const Register = u16;
// The fetch-constant aperture begins above the ordinary render/CP registers
// (Xenia exposes it around 0x4800). Retaining that range is required for
// shader/resource binding packets; truncating at 0x4000 silently loses them.
pub const register_count: usize = 0x5000;

pub const CP_RB_BASE: Register = 0x01C0;
pub const CP_RB_CNTL: Register = 0x01C1;
pub const CP_RB_RPTR_ADDR: Register = 0x01C3;
pub const CP_RB_RPTR: Register = 0x01C4;
pub const CP_RB_WPTR: Register = 0x01C5;
pub const CP_RB_WPTR_DELAY: Register = 0x01C6;
pub const CP_RB_RPTR_WR: Register = 0x01C7;
pub const CP_IB1_BASE: Register = 0x01CC;
pub const CP_IB1_BUFSZ: Register = 0x01CD;
pub const CP_IB2_BASE: Register = 0x01CE;
pub const CP_IB2_BUFSZ: Register = 0x01CF;
/// The command processor's progress counter.  MEM_WRITE_CNTR snapshots this
/// value for guest-side progress/fence diagnostics.
pub const CP_PROG_COUNTER: Register = 0x044B;

pub const SQ_PROGRAM_CNTL: Register = 0x2180;
pub const SQ_CONTEXT_MISC: Register = 0x2181;
pub const SQ_INTERPOLATOR_CNTL: Register = 0x2182;
pub const SQ_CF_RD_BASE: Register = 0x21F5;
pub const SQ_PS_PROGRAM: Register = 0x21F6;
pub const SQ_VS_PROGRAM: Register = 0x21F7;
pub const VGT_EVENT_INITIATOR: Register = 0x21F9;
pub const VGT_DMA_BASE: Register = 0x21FA;
pub const VGT_DMA_SIZE: Register = 0x21FB;
pub const VGT_DRAW_INITIATOR: Register = 0x21FC;
pub const VGT_IMMED_DATA: Register = 0x21FD;
// Base-vertex/index offset applied by the Xenos primitive processor.  Xenia
// keeps the register's low 24 bits; the upper byte is padding and must not
// leak into indexed vertex calculations.
pub const VGT_INDX_OFFSET: Register = 0x2102;

pub const RB_DEPTHCONTROL: Register = 0x2200;
pub const RB_BLENDCONTROL0: Register = 0x2201;
pub const RB_COLORCONTROL: Register = 0x2202;
pub const PA_CL_CLIP_CNTL: Register = 0x2204;
pub const PA_SU_SC_MODE_CNTL: Register = 0x2205;
pub const PA_CL_VTE_CNTL: Register = 0x2206;
pub const RB_MODECONTROL: Register = 0x2208;
pub const RB_BLENDCONTROL1: Register = 0x2209;
pub const RB_BLENDCONTROL2: Register = 0x220A;
pub const RB_BLENDCONTROL3: Register = 0x220B;

pub const PA_SU_POINT_SIZE: Register = 0x2280;
pub const PA_SU_POINT_MINMAX: Register = 0x2281;
pub const PA_SU_LINE_CNTL: Register = 0x2282;
pub const PA_SC_LINE_STIPPLE: Register = 0x2283;
pub const VGT_OUTPUT_PATH_CNTL: Register = 0x2284;
pub const VGT_HOS_CNTL: Register = 0x2285;
pub const VGT_HOS_MAX_TESS_LEVEL: Register = 0x2286;
pub const VGT_HOS_MIN_TESS_LEVEL: Register = 0x2287;
pub const PA_SC_MPASS_PS_CNTL: Register = 0x2292;
pub const PA_SC_VIZ_QUERY: Register = 0x2293;
pub const PA_SC_VIZ_QUERY_STATUS_0: Register = 0x0C44;
pub const PA_SC_VIZ_QUERY_STATUS_1: Register = 0x0C45;

pub const PA_CL_VPORT_XSCALE: Register = 0x210F;
pub const PA_CL_VPORT_XOFFSET: Register = 0x2110;
pub const PA_CL_VPORT_YSCALE: Register = 0x2111;
pub const PA_CL_VPORT_YOFFSET: Register = 0x2112;
pub const PA_CL_VPORT_ZSCALE: Register = 0x2113;
pub const PA_CL_VPORT_ZOFFSET: Register = 0x2114;
pub const PA_SC_SCREEN_SCISSOR_TL: Register = 0x200E;
pub const PA_SC_SCREEN_SCISSOR_BR: Register = 0x200F;
pub const PA_SC_WINDOW_OFFSET: Register = 0x2080;
pub const PA_SC_WINDOW_SCISSOR_TL: Register = 0x2081;
pub const PA_SC_WINDOW_SCISSOR_BR: Register = 0x2082;

pub const RB_SURFACE_INFO: Register = 0x2000;
pub const RB_COLOR_INFO: Register = 0x2001;
pub const RB_DEPTH_INFO: Register = 0x2002;
pub const RB_COLOR1_INFO: Register = 0x2003;
pub const RB_COLOR2_INFO: Register = 0x2004;
pub const RB_COLOR3_INFO: Register = 0x2005;
pub const RB_COLOR_MASK: Register = 0x2104;
pub const RB_ALPHA_REF: Register = 0x210E;
pub const RB_STENCILREFMASK_BF: Register = 0x210C;
pub const RB_STENCILREFMASK: Register = 0x210D;
pub const RB_COPY_CONTROL: Register = 0x2318;
pub const RB_COPY_DEST_BASE: Register = 0x2319;
pub const RB_COPY_DEST_PITCH: Register = 0x231A;
pub const RB_COPY_DEST_INFO: Register = 0x231B;
pub const RB_SAMPLE_COUNT_ADDR: Register = 0x2325;
pub const WRITEBACK_START: Register = 0x0A04;
pub const WRITEBACK_SIZE: Register = 0x0A05;
pub const SQ_VS_CONST: Register = 0x2307;
pub const SQ_PS_CONST: Register = 0x2308;
pub const PA_SU_POLY_OFFSET_FRONT_SCALE: Register = 0x2380;
pub const PA_SU_POLY_OFFSET_FRONT_OFFSET: Register = 0x2381;
pub const PA_SU_POLY_OFFSET_BACK_SCALE: Register = 0x2382;
pub const PA_SU_POLY_OFFSET_BACK_OFFSET: Register = 0x2383;
pub const PA_CL_POINT_SIZE: Register = 0x2386;

pub const shader_constant_fetch_base: Register = 0x4800;
pub const shader_constant_fetch_count: usize = 32;
pub const vertex_fetch_constant_count: usize = shader_constant_fetch_count * 3;
pub const shader_constant_alu_base: Register = 0x4000;
// These are the PM4 constant-bank apertures used by Xenia's Mac command
// processor.  They are distinct from the compact shader translator's private
// metadata ranges; SET_CONSTANT and LOAD_ALU_CONSTANT address these registers
// one dword at a time.
pub const shader_constant_bool_base: Register = 0x4900;
pub const shader_constant_loop_base: Register = 0x4908;
pub const shader_constant_register_base: Register = 0x2000;
pub const vertex_fetch_register_base: Register = shader_constant_fetch_base;

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

pub fn isRegisterAperture(register: u32) bool {
    return register < register_count;
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
    try std.testing.expectEqual(@as(Register, 0x231B), RB_COPY_DEST_INFO);
}
