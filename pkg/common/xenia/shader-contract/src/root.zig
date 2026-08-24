//! Route-independent: the Xenos shader unit's fixed resource limits and the
//! structural rules its microcode obeys.
//!
//! These bound any translator, whether the target is SPIR-V, MSL, or an
//! interpreter. They are silicon; one copy, no route mirror.
//!
//! ## Why a translator needs the limits stated separately from itself
//!
//! A shader translator fails in a way that is unusually hard to attribute. The
//! guest hands over a microcode blob, the translator emits *something*, the
//! host compiles it, and a frame appears — wrong, or black, or missing one
//! object. Nothing in that chain reports an error, because every stage did what
//! it was asked. The limits are the only place a structural mistake can be
//! caught mechanically: a constant index past the bank, a clause nesting deeper
//! than the hardware's loop stack, an export slot that does not exist.
//!
//! ## The bank sizes are derived, not remembered
//!
//! `pkg/common/xenos/register-map` owns the aperture *addresses*. The bank
//! sizes here follow from them by arithmetic, and are written that way on
//! purpose: ALU constants occupy 0x4000..0x4800, which is 2048 registers of one
//! dword, which is 512 vec4 constants. Anyone can re-derive that from the
//! register map and get the same number, whereas a remembered "512" is a number
//! that can quietly stop matching the aperture it is supposed to describe.
//!
//! ## What this package is not
//!
//! * It is not a decoder. It parses no microcode and holds no program;
//!   `lib/gpu/xenos_shader.zig` and `lib/gpu/shader/` own that.
//! * It is not a shader cache. A compiled shader is a host object with a
//!   lifetime, which makes it lib's.
//! * It emits no source. MSL and SPIR-V are host-API artefacts, not console
//!   facts, and nothing here should know their syntax.

const std = @import("std");

// ---------------------------------------------------------------------------
// The shader array
// ---------------------------------------------------------------------------

/// Unified shader ALUs: three SIMD groups of sixteen. Unified means every one
/// of them runs vertex or pixel work, which is why there is no separate vertex
/// and pixel limit anywhere below.
pub const simd_groups: u32 = 3;
pub const processors_per_group: u32 = 16;
pub const shader_processor_count: u32 = simd_groups * processors_per_group;

/// Texture fetch and address units.
pub const texture_fetch_units: u32 = 16;

// ---------------------------------------------------------------------------
// Register file and constant banks
// ---------------------------------------------------------------------------

/// General purpose vec4 registers visible to one shader invocation.
pub const gpr_count: u32 = 128;

/// One dword per register in the aperture; four dwords per vec4 constant.
pub const dwords_per_vec4: u32 = 4;

/// The ALU constant aperture, in registers: 0x4800 - 0x4000.
pub const alu_constant_registers: u32 = 0x4800 - 0x4000;
/// 512 vec4 float constants.
pub const float_constant_count: u32 = alu_constant_registers / dwords_per_vec4;

/// The bool aperture, in registers: 0x4908 - 0x4900. Eight dwords, one bit
/// each, so 256 boolean constants.
pub const bool_constant_registers: u32 = 0x4908 - 0x4900;
pub const bool_constant_count: u32 = bool_constant_registers * 32;

/// Loop constants, one dword each.
pub const loop_constant_count: u32 = 32;

/// Texture fetch constant slots. Each is six dwords; a vertex fetch constant is
/// two, which is why three vertex fetches share one texture fetch slot.
pub const fetch_constant_slots: u32 = 32;
pub const dwords_per_texture_fetch_constant: u32 = 6;
pub const dwords_per_vertex_fetch_constant: u32 = 2;
pub const vertex_fetch_constant_count: u32 = fetch_constant_slots * 3;

// ---------------------------------------------------------------------------
// Interpolators and exports
// ---------------------------------------------------------------------------

/// Values a vertex shader can hand a pixel shader.
pub const interpolator_count: u32 = 16;

/// Pixel shader colour exports. Four, matching the render target count.
pub const max_pixel_color_exports: u32 = 4;

/// The largest microcode blob the command processor will hand over.
pub const max_shader_bytes: u32 = 64 * 1024;

/// Microcode is dword-addressed, so a blob length that is not a multiple of
/// four is malformed rather than merely odd.
pub const microcode_dword_bytes: u32 = 4;

// ---------------------------------------------------------------------------
// Clause structure
// ---------------------------------------------------------------------------

/// Xenos shaders are clause programs: a control-flow instruction selects a
/// block of ALU or fetch instructions. There is no free-form branch, which is
/// why a translator can emit structured code at all.
pub const ControlFlowKind = enum(u8) {
    nop,
    exec,
    exec_end,
    cond_exec,
    cond_exec_end,
    loop_start,
    loop_end,
    cond_call,
    ret,
    jump,
    alloc,

    /// Whether this instruction terminates the shader.
    pub fn isTerminal(self: ControlFlowKind) bool {
        return self == .exec_end or self == .cond_exec_end;
    }

    /// Whether this instruction opens a block that must be closed.
    pub fn opensBlock(self: ControlFlowKind) bool {
        return self == .loop_start or self == .cond_call;
    }
};

/// The hardware's loop/call stack depth. A program nesting deeper than this
/// does not fault — it overwrites the stack, and the shader returns to the
/// wrong place. A translator that recurses without this bound will emit code
/// the hardware could never have run.
pub const max_control_flow_nesting: u32 = 8;

pub const ShaderStage = enum(u8) {
    vertex,
    pixel,

    /// Whether this stage may write depth.
    pub fn canExportDepth(self: ShaderStage) bool {
        return self == .pixel;
    }
};

// ---------------------------------------------------------------------------
// Pure predicates
// ---------------------------------------------------------------------------

pub fn isGprIndex(index: u32) bool {
    return index < gpr_count;
}

pub fn isFloatConstantIndex(index: u32) bool {
    return index < float_constant_count;
}

pub fn isBoolConstantIndex(index: u32) bool {
    return index < bool_constant_count;
}

pub fn isFetchSlot(index: u32) bool {
    return index < fetch_constant_slots;
}

pub fn isInterpolatorIndex(index: u32) bool {
    return index < interpolator_count;
}

/// Whether a microcode blob's length is one the hardware could have produced.
///
/// Length only. A true answer says the blob is dword-aligned and inside the
/// size bound, never that it decodes or that the guest wrote it.
pub fn isPlausibleMicrocodeLength(bytes: usize) bool {
    if (bytes == 0) return false;
    if (bytes % microcode_dword_bytes != 0) return false;
    return bytes <= max_shader_bytes;
}

/// Whether a colour export index exists for this stage.
pub fn isColorExportIndex(stage: ShaderStage, index: u32) bool {
    return switch (stage) {
        .pixel => index < max_pixel_color_exports,
        // A vertex shader exports through interpolators, not colour slots.
        .vertex => false,
    };
}

pub fn contractIsWellFormed() bool {
    if (float_constant_count != 512) return false;
    if (bool_constant_count != 256) return false;
    if (shader_processor_count != 48) return false;
    if (max_shader_bytes % microcode_dword_bytes != 0) return false;
    if (vertex_fetch_constant_count != fetch_constant_slots * 3) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the constant banks follow from the register apertures" {
    // Re-derivable from pkg/common/xenos/register-map: ALU constants live at
    // 0x4000..0x4800. 2048 dwords, four to a vec4, is 512 constants.
    try std.testing.expectEqual(@as(u32, 2048), alu_constant_registers);
    try std.testing.expectEqual(@as(u32, 512), float_constant_count);
    // Bools: 0x4900..0x4908 is eight dwords of 32 bits.
    try std.testing.expectEqual(@as(u32, 8), bool_constant_registers);
    try std.testing.expectEqual(@as(u32, 256), bool_constant_count);
}

test "there are 48 unified ALUs, not 320" {
    // The plan sketch asked for "sp_count": 320. That is not this number —
    // the Xenos has three SIMD groups of sixteen. 320 is the XMA decode
    // context count from a different subsystem entirely.
    try std.testing.expectEqual(@as(u32, 48), shader_processor_count);
    try std.testing.expectEqual(@as(u32, 3), simd_groups);
    try std.testing.expectEqual(@as(u32, 16), processors_per_group);
    try std.testing.expect(shader_processor_count != 320);
}

test "three vertex fetches share one texture fetch slot" {
    // Six dwords per texture fetch constant, two per vertex fetch constant.
    // A translator that treats the vertex fetch count as the slot count runs
    // off the end of the fetch aperture.
    try std.testing.expectEqual(@as(u32, 32), fetch_constant_slots);
    try std.testing.expectEqual(@as(u32, 96), vertex_fetch_constant_count);
    try std.testing.expectEqual(
        dwords_per_texture_fetch_constant,
        dwords_per_vertex_fetch_constant * 3,
    );
}

test "register and constant indices are bounded" {
    try std.testing.expect(isGprIndex(0));
    try std.testing.expect(isGprIndex(127));
    try std.testing.expect(!isGprIndex(128));

    try std.testing.expect(isFloatConstantIndex(511));
    try std.testing.expect(!isFloatConstantIndex(512));

    try std.testing.expect(isBoolConstantIndex(255));
    try std.testing.expect(!isBoolConstantIndex(256));

    try std.testing.expect(isFetchSlot(31));
    try std.testing.expect(!isFetchSlot(32));

    try std.testing.expect(isInterpolatorIndex(15));
    try std.testing.expect(!isInterpolatorIndex(16));
}

test "microcode length is checked for alignment as well as size" {
    // A blob that is not a whole number of dwords cannot be microcode. This
    // catches a truncated fetch, which otherwise decodes as far as it can and
    // then produces a shader missing its tail.
    try std.testing.expect(isPlausibleMicrocodeLength(4));
    try std.testing.expect(isPlausibleMicrocodeLength(max_shader_bytes));
    try std.testing.expect(!isPlausibleMicrocodeLength(0));
    try std.testing.expect(!isPlausibleMicrocodeLength(3));
    try std.testing.expect(!isPlausibleMicrocodeLength(6));
    try std.testing.expect(!isPlausibleMicrocodeLength(max_shader_bytes + 4));
}

test "only a pixel shader exports colour or depth" {
    try std.testing.expect(ShaderStage.pixel.canExportDepth());
    try std.testing.expect(!ShaderStage.vertex.canExportDepth());

    try std.testing.expect(isColorExportIndex(.pixel, 0));
    try std.testing.expect(isColorExportIndex(.pixel, 3));
    try std.testing.expect(!isColorExportIndex(.pixel, 4));
    // A vertex shader has no colour slots at all; it exports through
    // interpolators. Allowing index 0 here would let a translator emit a
    // vertex colour write that the hardware would drop.
    try std.testing.expect(!isColorExportIndex(.vertex, 0));
}

test "colour exports match the render target count" {
    // Four, the same four pkg/common/xenia/render-target-contract bounds. If
    // these disagree a shader can export to a target that cannot be bound.
    try std.testing.expectEqual(@as(u32, 4), max_pixel_color_exports);
}

test "clause structure distinguishes terminal from block-opening control flow" {
    try std.testing.expect(ControlFlowKind.exec_end.isTerminal());
    try std.testing.expect(ControlFlowKind.cond_exec_end.isTerminal());
    try std.testing.expect(!ControlFlowKind.exec.isTerminal());
    try std.testing.expect(!ControlFlowKind.loop_start.isTerminal());

    try std.testing.expect(ControlFlowKind.loop_start.opensBlock());
    try std.testing.expect(ControlFlowKind.cond_call.opensBlock());
    try std.testing.expect(!ControlFlowKind.exec.opensBlock());
    // A jump does not open a block: it is not paired with anything, which is
    // why it cannot be translated as structured control flow.
    try std.testing.expect(!ControlFlowKind.jump.opensBlock());
}

test "the nesting bound is finite and small" {
    // Eight. A translator that recurses without this emits programs the
    // hardware would have run off the end of its stack, and the corruption
    // shows up as a shader returning to the wrong clause.
    try std.testing.expectEqual(@as(u32, 8), max_control_flow_nesting);
}
