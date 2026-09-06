//! Route-independent: the Xenos (Xbox 360 GPU) register numbers and aperture
//! bounds.
//!
//! These are console hardware facts. A register index is what the silicon
//! decodes; it was fixed in 2005 and cannot change while a process runs, or
//! between one host and another. Rosette held them in `lib/gpu` next to the
//! live register file, which put an immutable hardware table and a piece of
//! mutable runtime state in the same file and made it easy to read one as the
//! other.
//!
//! ## Why `common/` and not a route
//!
//! Route packages describe the machine Rosette was *compiled for*. A Xenos
//! register index describes neither host nor emulator build — it describes the
//! console being emulated. Mirroring it per route would create two files that
//! must always agree and have no legitimate way to differ, which is the shape
//! that lets one copy rot while the tests stay green. Same reasoning as
//! `pkg/common/abi/receiver-classification`.
//!
//! ## What this package is not
//!
//! * It is not a register file. It holds no values, so it cannot say a register
//!   was written or read; `lib/gpu/xenos_registers.zig` still owns the live
//!   state and every decode that reads it.
//! * It does not claim the guest touched any of these. `isRegisterAperture`
//!   answers "is this index inside the aperture", never "did anything arrive".
//! * It decodes no bit fields. The field layouts move with Xenia's PM4
//!   executor and stay beside it.

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
/// Setup-unit vertex control, including the D3D-zero pixel-center rule used
/// by Xenos resolve rectangles.
pub const PA_SU_VTX_CNTL: Register = 0x2302;
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
pub const RB_HIZ_CLEAR: Register = 0x231C;
pub const RB_DEPTH_CLEAR: Register = 0x231D;
pub const RB_COLOR_CLEAR: Register = 0x231E;
pub const RB_COLOR_CLEAR_LO: Register = 0x231F;
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

/// Functional regions of the hardware register aperture. This is a property
/// of the Xenos index, not of a particular runtime register file, so every PM4
/// observer uses this one classification when deciding whether an encoded
/// register write is understood.
pub const Block = enum(u8) {
    command_processor,
    render_backend,
    raster_setup,
    geometry,
    shader_control,
    shader_constants,
    fetch_constants,
    unclassified,

    pub fn label(self: Block) []const u8 {
        return switch (self) {
            .command_processor => "command-processor",
            .render_backend => "render-backend",
            .raster_setup => "raster-setup",
            .geometry => "geometry",
            .shader_control => "shader-control",
            .shader_constants => "shader-constants",
            .fetch_constants => "fetch-constants",
            .unclassified => "unclassified",
        };
    }

    pub fn meaning(self: Block) []const u8 {
        return switch (self) {
            .command_processor => "ring and command-processor control",
            .render_backend => "where pixels land: colour, depth, surface and masks",
            .raster_setup => "viewport, scissor and rasteriser state",
            .geometry => "vertex/index fetch and draw initiation",
            .shader_control => "shader program selection and export setup",
            .shader_constants => "float, boolean and loop constants",
            .fetch_constants => "texture and vertex fetch descriptors",
            .unclassified => "an in-aperture index whose Xenia entry has no Rosette functional owner yet, or an index outside the copied table",
        };
    }
};

pub const block_count: usize = @typeInfo(Block).@"enum".fields.len;

/// One inclusive span from Xenia's `register_table.inc`.
///
/// This is a lossless compression of the exact one-register entries in that
/// table, not a functional range classifier. Holes between two spans remain
/// unknown. Keeping the copied hardware table here means a register write can
/// be identified as an exact Xenos register even when Rosette has not yet
/// assigned that register a richer functional `Block`.
pub const ExactRegisterRange = struct {
    first: Register,
    last: Register,
};

/// Exact in-aperture Xenos registers currently consumed by Xenia.
///
/// Source: `/xenia/src/xenia/gpu/register_table.inc`. The three entries at
/// 0x5000..0x5002 are intentionally excluded: they are outside Rosette's
/// retained 0x0000..0x4FFF aperture and must not make an out-of-range access
/// look valid. If Xenia's table changes, update this list and the source
/// revision in the same change; silently falling back to a neighbouring span
/// is precisely the failure this table prevents.
pub const xenia_register_table_ranges = [_]ExactRegisterRange{
    .{ .first = 0x0000, .last = 0x0002 },
    .{ .first = 0x0004, .last = 0x000B },
    .{ .first = 0x0038, .last = 0x003D },
    .{ .first = 0x0040, .last = 0x004A },
    .{ .first = 0x0064, .last = 0x0071 },
    .{ .first = 0x0080, .last = 0x0087 },
    .{ .first = 0x0091, .last = 0x0095 },
    .{ .first = 0x00A0, .last = 0x00A3 },
    .{ .first = 0x00A6, .last = 0x00AA },
    .{ .first = 0x0128, .last = 0x0129 },
    .{ .first = 0x012F, .last = 0x012F },
    .{ .first = 0x0132, .last = 0x0133 },
    .{ .first = 0x0135, .last = 0x0136 },
    .{ .first = 0x013C, .last = 0x013C },
    .{ .first = 0x0140, .last = 0x0144 },
    .{ .first = 0x015C, .last = 0x015C },
    .{ .first = 0x01C0, .last = 0x01C1 },
    .{ .first = 0x01C3, .last = 0x01CA },
    .{ .first = 0x01CC, .last = 0x01D3 },
    .{ .first = 0x01D5, .last = 0x01EA },
    .{ .first = 0x01EC, .last = 0x01FF },
    .{ .first = 0x0394, .last = 0x039D },
    .{ .first = 0x03A0, .last = 0x03A1 },
    .{ .first = 0x03B2, .last = 0x03B7 },
    .{ .first = 0x03F9, .last = 0x03FA },
    .{ .first = 0x0440, .last = 0x0440 },
    .{ .first = 0x0442, .last = 0x044F },
    .{ .first = 0x0452, .last = 0x0462 },
    .{ .first = 0x047E, .last = 0x047F },
    .{ .first = 0x04C0, .last = 0x0523 },
    .{ .first = 0x0578, .last = 0x0587 },
    .{ .first = 0x05C8, .last = 0x05C9 },
    .{ .first = 0x05F0, .last = 0x05F9 },
    .{ .first = 0x0600, .last = 0x0614 },
    .{ .first = 0x0800, .last = 0x082B },
    .{ .first = 0x0830, .last = 0x0832 },
    .{ .first = 0x0840, .last = 0x086B },
    .{ .first = 0x0870, .last = 0x0872 },
    .{ .first = 0x0A00, .last = 0x0A0D },
    .{ .first = 0x0A10, .last = 0x0A15 },
    .{ .first = 0x0A18, .last = 0x0A23 },
    .{ .first = 0x0A29, .last = 0x0A31 },
    .{ .first = 0x0A40, .last = 0x0A40 },
    .{ .first = 0x0BFE, .last = 0x0C22 },
    .{ .first = 0x0C2C, .last = 0x0C30 },
    .{ .first = 0x0C38, .last = 0x0C3C },
    .{ .first = 0x0C40, .last = 0x0C41 },
    .{ .first = 0x0C44, .last = 0x0C45 },
    .{ .first = 0x0C48, .last = 0x0C53 },
    .{ .first = 0x0C80, .last = 0x0C86 },
    .{ .first = 0x0C88, .last = 0x0C94 },
    .{ .first = 0x0C98, .last = 0x0CA5 },
    .{ .first = 0x0CC0, .last = 0x0CC0 },
    .{ .first = 0x0D00, .last = 0x0D09 },
    .{ .first = 0x0D34, .last = 0x0D36 },
    .{ .first = 0x0DAE, .last = 0x0DC1 },
    .{ .first = 0x0DC8, .last = 0x0DDF },
    .{ .first = 0x0E00, .last = 0x0E0A },
    .{ .first = 0x0E17, .last = 0x0E45 },
    .{ .first = 0x0E48, .last = 0x0E7D },
    .{ .first = 0x0F01, .last = 0x0F02 },
    .{ .first = 0x0F04, .last = 0x0F12 },
    .{ .first = 0x0F15, .last = 0x0F16 },
    .{ .first = 0x0F26, .last = 0x0F2C },
    .{ .first = 0x1004, .last = 0x1009 },
    .{ .first = 0x1800, .last = 0x181F },
    .{ .first = 0x1838, .last = 0x183C },
    .{ .first = 0x1840, .last = 0x1844 },
    .{ .first = 0x1846, .last = 0x1846 },
    .{ .first = 0x1848, .last = 0x184F },
    .{ .first = 0x1851, .last = 0x1852 },
    .{ .first = 0x1860, .last = 0x1861 },
    .{ .first = 0x1864, .last = 0x1864 },
    .{ .first = 0x1866, .last = 0x186B },
    .{ .first = 0x18C1, .last = 0x18C3 },
    .{ .first = 0x18E0, .last = 0x18EC },
    .{ .first = 0x1921, .last = 0x1925 },
    .{ .first = 0x1927, .last = 0x1927 },
    .{ .first = 0x1930, .last = 0x1936 },
    .{ .first = 0x1949, .last = 0x1955 },
    .{ .first = 0x195E, .last = 0x1961 },
    .{ .first = 0x1964, .last = 0x1965 },
    .{ .first = 0x1968, .last = 0x1968 },
    .{ .first = 0x196C, .last = 0x1974 },
    .{ .first = 0x1977, .last = 0x197A },
    .{ .first = 0x198C, .last = 0x198C },
    .{ .first = 0x19BA, .last = 0x19BA },
    .{ .first = 0x19BC, .last = 0x19BF },
    .{ .first = 0x1B20, .last = 0x1B22 },
    .{ .first = 0x1B24, .last = 0x1B25 },
    .{ .first = 0x1B2E, .last = 0x1B2F },
    .{ .first = 0x1C46, .last = 0x1C46 },
    .{ .first = 0x1E40, .last = 0x1E40 },
    .{ .first = 0x1E43, .last = 0x1E55 },
    .{ .first = 0x1F98, .last = 0x1F9C },
    .{ .first = 0x1FB4, .last = 0x1FB4 },
    .{ .first = 0x1FB7, .last = 0x1FB8 },
    .{ .first = 0x1FC0, .last = 0x1FC5 },
    .{ .first = 0x1FC8, .last = 0x1FCE },
    .{ .first = 0x1FD0, .last = 0x1FD0 },
    .{ .first = 0x1FE6, .last = 0x1FEF },
    .{ .first = 0x1FF2, .last = 0x200F },
    .{ .first = 0x2080, .last = 0x208B },
    .{ .first = 0x2100, .last = 0x2114 },
    .{ .first = 0x2180, .last = 0x2184 },
    .{ .first = 0x21F4, .last = 0x21F7 },
    .{ .first = 0x21F9, .last = 0x21FD },
    .{ .first = 0x2200, .last = 0x220B },
    .{ .first = 0x2210, .last = 0x2210 },
    .{ .first = 0x2280, .last = 0x2294 },
    .{ .first = 0x2300, .last = 0x2326 },
    .{ .first = 0x2340, .last = 0x2340 },
    .{ .first = 0x2357, .last = 0x2357 },
    .{ .first = 0x2360, .last = 0x2360 },
    .{ .first = 0x2380, .last = 0x239F },
    .{ .first = 0x4000, .last = 0x48BF },
    .{ .first = 0x4900, .last = 0x4927 },
};

/// Whether `register` is an exact Xenia-table entry, as opposed to merely
/// landing in the retained aperture or one of Rosette's coarse spans.
pub fn isKnownHardwareRegister(register: u32) bool {
    if (!isRegisterAperture(register)) return false;
    for (xenia_register_table_ranges) |range| {
        if (register >= @as(u32, range.first) and register <= @as(u32, range.last)) {
            return true;
        }
    }
    return false;
}

/// The best functional owner available for an exact Xenia-table entry.
///
/// Some of Xenia's entries are diagnostic/system registers whose functional
/// owner is intentionally not guessed. Those return `.unclassified` while
/// `classifiedByName` still returns true: exact hardware identity and
/// functional ownership are separate facts.
fn exactTableBlock(register: u32) ?Block {
    if (!isKnownHardwareRegister(register)) return null;
    return switch (register) {
        0x0000...0x07FF => .command_processor,
        0x2000...0x200D => .render_backend,
        0x200E...0x200F,
        0x2080...0x208B,
        0x210F...0x2114,
        0x2204...0x2206,
        0x2210...0x2210,
        0x2280...0x2283,
        0x2292...0x2293,
        0x2300...0x2306,
        0x2312...0x2312,
        0x2340...0x239F,
        => .raster_setup,
        0x2100...0x2103,
        0x2207...0x2207,
        0x2284...0x2291,
        0x2316...0x2317,
        0x21F9...0x21FD,
        => .geometry,
        0x2104...0x210E,
        0x2200...0x2203,
        0x2208...0x220B,
        0x2318...0x2326,
        => .render_backend,
        0x2180...0x2184,
        0x21F4...0x21F7,
        0x2307...0x2311,
        0x2313...0x2315,
        => .shader_control,
        0x4000...0x47FF,
        0x4900...0x4927,
        => .shader_constants,
        0x4800...0x48BF => .fetch_constants,
        else => .unclassified,
    };
}

/// The functional block a *named* register belongs to.
///
/// The Xenos index space is interleaved and the range fallback below cannot
/// see that. Every constant this file declares is placed here by what the
/// hardware actually does with it, and the ranges are only consulted for
/// indices nothing has named.
///
/// The 2026-09-01 run is why this exists. The journal reported `render-backend
/// writes=10 first=0x2080 last=0x2082` and the verdict "the render-backend
/// block was written but the surface/colour/depth registers were not" — while
/// `0x2080..0x2082` are `PA_SC_WINDOW_*`, scissor registers, and *no*
/// render-backend register had been written at all. Every other block row in
/// that report was wrong the same way: `SQ_PROGRAM_CNTL` and
/// `VGT_DRAW_INITIATOR` counted as raster setup, `RB_DEPTHCONTROL` and
/// `RB_MODECONTROL` as geometry, `RB_COPY_*` as shader control.
pub fn namedBlock(register: u32) ?Block {
    return switch (register) {
        // Ring and command-processor control.
        CP_RB_BASE,
        CP_RB_CNTL,
        CP_RB_RPTR_ADDR,
        CP_RB_RPTR,
        CP_RB_WPTR,
        CP_RB_WPTR_DELAY,
        CP_RB_RPTR_WR,
        CP_IB1_BASE,
        CP_IB1_BUFSZ,
        CP_IB2_BASE,
        CP_IB2_BUFSZ,
        CP_PROG_COUNTER,
        WRITEBACK_START,
        WRITEBACK_SIZE,
        => .command_processor,

        // Where pixels land.
        RB_SURFACE_INFO,
        RB_COLOR_INFO,
        RB_DEPTH_INFO,
        RB_COLOR1_INFO,
        RB_COLOR2_INFO,
        RB_COLOR3_INFO,
        RB_COLOR_MASK,
        RB_ALPHA_REF,
        RB_STENCILREFMASK,
        RB_STENCILREFMASK_BF,
        RB_DEPTHCONTROL,
        RB_COLORCONTROL,
        RB_MODECONTROL,
        RB_BLENDCONTROL0,
        RB_BLENDCONTROL1,
        RB_BLENDCONTROL2,
        RB_BLENDCONTROL3,
        RB_COPY_CONTROL,
        RB_COPY_DEST_BASE,
        RB_COPY_DEST_PITCH,
        RB_COPY_DEST_INFO,
        RB_HIZ_CLEAR,
        RB_DEPTH_CLEAR,
        RB_COLOR_CLEAR,
        RB_COLOR_CLEAR_LO,
        RB_SAMPLE_COUNT_ADDR,
        => .render_backend,

        // Viewport, scissor and rasteriser state.
        PA_SC_SCREEN_SCISSOR_TL,
        PA_SC_SCREEN_SCISSOR_BR,
        PA_SC_WINDOW_OFFSET,
        PA_SC_WINDOW_SCISSOR_TL,
        PA_SC_WINDOW_SCISSOR_BR,
        PA_SC_LINE_STIPPLE,
        PA_SC_MPASS_PS_CNTL,
        PA_SC_VIZ_QUERY,
        PA_SC_VIZ_QUERY_STATUS_0,
        PA_SC_VIZ_QUERY_STATUS_1,
        PA_CL_VPORT_XSCALE,
        PA_CL_VPORT_XOFFSET,
        PA_CL_VPORT_YSCALE,
        PA_CL_VPORT_YOFFSET,
        PA_CL_VPORT_ZSCALE,
        PA_CL_VPORT_ZOFFSET,
        PA_CL_CLIP_CNTL,
        PA_CL_VTE_CNTL,
        PA_CL_POINT_SIZE,
        PA_SU_SC_MODE_CNTL,
        PA_SU_VTX_CNTL,
        PA_SU_POINT_SIZE,
        PA_SU_POINT_MINMAX,
        PA_SU_LINE_CNTL,
        PA_SU_POLY_OFFSET_FRONT_SCALE,
        PA_SU_POLY_OFFSET_FRONT_OFFSET,
        PA_SU_POLY_OFFSET_BACK_SCALE,
        PA_SU_POLY_OFFSET_BACK_OFFSET,
        => .raster_setup,

        // Vertex/index fetch and draw initiation.
        VGT_EVENT_INITIATOR,
        VGT_DMA_BASE,
        VGT_DMA_SIZE,
        VGT_DRAW_INITIATOR,
        VGT_IMMED_DATA,
        VGT_INDX_OFFSET,
        VGT_OUTPUT_PATH_CNTL,
        VGT_HOS_CNTL,
        VGT_HOS_MAX_TESS_LEVEL,
        VGT_HOS_MIN_TESS_LEVEL,
        => .geometry,

        // Shader program selection and export setup.
        SQ_PROGRAM_CNTL,
        SQ_CONTEXT_MISC,
        SQ_INTERPOLATOR_CNTL,
        SQ_CF_RD_BASE,
        SQ_PS_PROGRAM,
        SQ_VS_PROGRAM,
        SQ_VS_CONST,
        SQ_PS_CONST,
        => .shader_control,

        else => null,
    };
}

/// Whether an index's block came from the exact table rather than a range.
///
/// Reported alongside the block counts, because a block total assembled mostly
/// from ranges is a guess about an interleaved index space and a reader has to
/// be able to tell the two apart.
pub fn classifiedByName(register: u32) bool {
    return namedBlock(register) != null or isKnownHardwareRegister(register);
}

/// Classify a raw index. `null` means it is outside the retained hardware
/// aperture; `.unclassified` means it is in-bounds but no known functional
/// block owns it. Keeping those distinct prevents an unknown in-range register
/// from being rounded into a neighbouring block.
pub fn blockForIndex(register: u32) ?Block {
    if (!isRegisterAperture(register)) return null;
    if (namedBlock(register)) |known| return known;
    if (exactTableBlock(register)) |known| return known;
    // The fallback, for indices nothing has named. Deliberately coarse: these
    // ranges are the dominant occupant of each span and not its only one, so a
    // count they produce is an approximation and `classifiedByName` is how a
    // reader knows which counts are which.
    return switch (register) {
        0x0000...0x07FF => .command_processor,
        0x2000...0x20FF => .render_backend,
        0x2100...0x21FF => .raster_setup,
        0x2200...0x22FF => .geometry,
        0x2300...0x28FF => .shader_control,
        0x4000...0x47FF => .shader_constants,
        0x4800...0x4FFF => .fetch_constants,
        else => .unclassified,
    };
}

pub fn blockOf(register: Register) Block {
    return blockForIndex(register) orelse .unclassified;
}

/// Whether an index falls inside the retained register aperture.
///
/// Bounds only. A true answer means a store to this index would be dispatched
/// to the register file, not that one ever was.
pub fn isRegisterAperture(register: u32) bool {
    return register < register_count;
}

/// The ring-buffer control block the command processor reads. Grouped because
/// a reader chasing a missing frame wants the set, and because the contiguity
/// below is the property that makes a block write recognisable.
pub const ring_buffer_registers = [_]Register{
    CP_RB_BASE,
    CP_RB_CNTL,
    CP_RB_RPTR_ADDR,
    CP_RB_RPTR,
    CP_RB_WPTR,
};

/// Every aperture base must sit inside the retained window, and the fetch
/// aperture must sit above the ordinary render/CP registers.
///
/// The second clause is the one with history: truncating the window at 0x4000
/// silently dropped the fetch constants, and shader/resource binding packets
/// disappeared with no diagnostic. A build error is the right place to catch
/// that, because at runtime it looks like a shader bug.
pub fn contractIsWellFormed() bool {
    const bases = [_]Register{
        shader_constant_fetch_base,
        shader_constant_alu_base,
        shader_constant_bool_base,
        shader_constant_loop_base,
        shader_constant_register_base,
        vertex_fetch_register_base,
    };
    for (bases) |base| {
        if (@as(usize, base) >= register_count) return false;
    }
    if (shader_constant_fetch_base <= shader_constant_alu_base) return false;
    if (vertex_fetch_constant_count != shader_constant_fetch_count * 3) return false;
    for (ring_buffer_registers) |register| {
        if (@as(usize, register) >= register_count) return false;
    }
    return true;
}

test "the ring control block is contiguous from CP_RB_BASE" {
    // A write walking the block is how a title programs the ring, so the
    // adjacency is load-bearing for recognising one.
    try std.testing.expectEqual(@as(Register, 0x01C0), CP_RB_BASE);
    try std.testing.expectEqual(@as(Register, 0x01C1), CP_RB_CNTL);
    try std.testing.expectEqual(@as(Register, 0x01C5), CP_RB_WPTR);
    try std.testing.expect(CP_RB_WPTR > CP_RB_BASE);
}

test "the fetch aperture is retained above the render registers" {
    try std.testing.expect(contractIsWellFormed());
    // The regression the wide window exists for: a 0x4000 bound drops the
    // fetch constants and the loss looks like a shader failure.
    try std.testing.expect(@as(usize, shader_constant_fetch_base) < register_count);
    try std.testing.expect(shader_constant_fetch_base > shader_constant_alu_base);
    try std.testing.expectEqual(@as(usize, 96), vertex_fetch_constant_count);
}

test "aperture membership is bounds only" {
    try std.testing.expect(isRegisterAperture(CP_RB_BASE));
    try std.testing.expect(isRegisterAperture(shader_constant_fetch_base));
    try std.testing.expect(!isRegisterAperture(@intCast(register_count)));
    try std.testing.expect(!isRegisterAperture(0xFFFF_FFFF));
}

test "register blocks distinguish unknown in-range and out-of-range indices" {
    try std.testing.expectEqual(Block.command_processor, blockForIndex(CP_RB_BASE).?);
    try std.testing.expectEqual(Block.render_backend, blockForIndex(RB_COLOR_INFO).?);
    try std.testing.expectEqual(Block.fetch_constants, blockForIndex(shader_constant_fetch_base).?);
    try std.testing.expectEqual(Block.unclassified, blockForIndex(0x1000).?);
    try std.testing.expect(blockForIndex(@intCast(register_count)) == null);
}

// The 2026-09-01 journal reported `render-backend writes=10 first=0x2080
// last=0x2082` and concluded "the render-backend block was written but the
// surface/colour/depth registers were not". Those indices are `PA_SC_WINDOW_*`
// — scissor — and no render-backend register had been written at all. The
// range fallback cannot see an interleaved index space, so every named
// register states its own block.
test "a scissor register is not a render-backend write" {
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SC_WINDOW_OFFSET));
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SC_WINDOW_SCISSOR_TL));
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SC_WINDOW_SCISSOR_BR));
    // Also inside the old render-backend range, and also scissor.
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SC_SCREEN_SCISSOR_TL));
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SC_SCREEN_SCISSOR_BR));
    // The registers the block is actually about keep it.
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_SURFACE_INFO));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_COLOR_INFO));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_DEPTH_INFO));
}

// The same defect in the other direction: render-backend state that the range
// filed under raster setup, geometry and shader control.
test "render-backend state outside its range is still render-backend" {
    // 0x2100..0x21FF was `raster_setup`.
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_COLOR_MASK));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_ALPHA_REF));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_STENCILREFMASK));
    // 0x2200..0x22FF was `geometry`.
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_DEPTHCONTROL));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_MODECONTROL));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_BLENDCONTROL0));
    // 0x2300..0x28FF was `shader_control`.
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_COPY_CONTROL));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_COPY_DEST_BASE));
    try std.testing.expectEqual(Block.render_backend, blockOf(RB_SAMPLE_COUNT_ADDR));
}

// The run's other mislabelled rows: the shader and draw-initiation registers
// the range filed under raster setup.
test "shader and geometry registers inside the raster range keep their block" {
    try std.testing.expectEqual(Block.shader_control, blockOf(SQ_PROGRAM_CNTL));
    try std.testing.expectEqual(Block.shader_control, blockOf(SQ_PS_PROGRAM));
    try std.testing.expectEqual(Block.shader_control, blockOf(SQ_VS_PROGRAM));
    try std.testing.expectEqual(Block.geometry, blockOf(VGT_DRAW_INITIATOR));
    try std.testing.expectEqual(Block.geometry, blockOf(VGT_EVENT_INITIATOR));
    try std.testing.expectEqual(Block.geometry, blockOf(VGT_INDX_OFFSET));
    // And the raster registers the range filed under geometry.
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SU_SC_MODE_CNTL));
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SU_POINT_SIZE));
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_SC_VIZ_QUERY));
    try std.testing.expectEqual(Block.raster_setup, blockOf(PA_CL_VPORT_XSCALE));
}

// A count assembled mostly from ranges is a guess about an interleaved index
// space, and a reader has to be able to tell that from an exact one.
test "a named classification is distinguishable from a range one" {
    try std.testing.expect(classifiedByName(RB_COLOR_INFO));
    try std.testing.expect(classifiedByName(PA_SC_WINDOW_OFFSET));
    try std.testing.expect(classifiedByName(CP_RB_WPTR));
    // These were previously range-only. They are exact entries in Xenia's
    // table now, even where their richer functional owner is not modeled by
    // this package.
    try std.testing.expect(classifiedByName(0x2312));
    try std.testing.expectEqual(Block.raster_setup, blockOf(0x2312));
    try std.testing.expect(classifiedByName(0x0A31));
    try std.testing.expectEqual(Block.unclassified, blockOf(0x0A31));
    try std.testing.expect(!classifiedByName(0x0A32));
    // Outside every exact range and every name: in-bounds and unowned.
    try std.testing.expectEqual(Block.unclassified, blockOf(0x0A32));
    // Outside the aperture entirely is a different answer from unclassified.
    try std.testing.expect(blockForIndex(register_count) == null);
}

test "the copied Xenia table recognizes holes and boundary entries exactly" {
    try std.testing.expect(isKnownHardwareRegister(0x0000));
    try std.testing.expect(isKnownHardwareRegister(0x4927));
    try std.testing.expect(!isKnownHardwareRegister(0x0003));
    try std.testing.expect(!isKnownHardwareRegister(0x4928));
    try std.testing.expect(!isKnownHardwareRegister(0x5000));
    try std.testing.expectEqual(@as(usize, 117), xenia_register_table_ranges.len);
}

// Every named register the map declares has to have a block, or the exact
// table silently degrades back to the ranges it replaced.
test "the named table covers a register from every block it claims" {
    var seen = [_]bool{false} ** block_count;
    const named = [_]Register{
        CP_RB_WPTR,         RB_COLOR_INFO,   PA_CL_VPORT_XSCALE,
        VGT_DRAW_INITIATOR, SQ_PROGRAM_CNTL,
    };
    for (named) |register| {
        const block = namedBlock(register) orelse return error.TestUnexpectedResult;
        seen[@intFromEnum(block)] = true;
    }
    try std.testing.expect(seen[@intFromEnum(Block.command_processor)]);
    try std.testing.expect(seen[@intFromEnum(Block.render_backend)]);
    try std.testing.expect(seen[@intFromEnum(Block.raster_setup)]);
    try std.testing.expect(seen[@intFromEnum(Block.geometry)]);
    try std.testing.expect(seen[@intFromEnum(Block.shader_control)]);
    // Constants and fetch descriptors are addressed by base rather than by a
    // named index, so they stay with the ranges.
    try std.testing.expectEqual(Block.shader_constants, blockOf(shader_constant_alu_base));
    try std.testing.expectEqual(Block.fetch_constants, blockOf(shader_constant_fetch_base));
}
