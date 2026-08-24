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
