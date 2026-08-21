const std = @import("std");
const builtin = @import("builtin");

pub const VECTOR_BLOCK_BITS = 128;
pub const VECTOR_BLOCK_BYTES = VECTOR_BLOCK_BITS / 8;

pub const Feature = enum(u8) {
    sse,
    sse2,
    avx,
    avx2,
    avx512f,
    avx512dq,
    avx512vl,
    avx512bw,
    avx512bf16,
    gfni,
    sha,
    vaes,
    amx_tile,
    keylocker,
    movdir64b,
    fma,
    neon,
};

pub const FeatureSet = struct {
    sse: bool = false,
    sse2: bool = false,
    avx: bool = false,
    avx2: bool = false,
    avx512f: bool = false,
    avx512dq: bool = false,
    avx512vl: bool = false,
    avx512bw: bool = false,
    avx512bf16: bool = false,
    gfni: bool = false,
    sha: bool = false,
    vaes: bool = false,
    amx_tile: bool = false,
    keylocker: bool = false,
    movdir64b: bool = false,
    fma: bool = false,
    neon: bool = false,

    pub fn host() FeatureSet {
        var result = FeatureSet{};
        switch (builtin.target.cpu.arch) {
            .aarch64 => {
                result.neon = true;
                result.fma = true;
            },
            .x86_64 => {
                result.sse = true;
                result.sse2 = true;
            },
            else => {},
        }
        return result;
    }

    pub fn cleoEmulated() FeatureSet {
        var result = host();
        switch (builtin.target.cpu.arch) {
            .aarch64 => {
                result.sse = true;
                result.sse2 = true;
            },
            .x86_64 => {
                result.avx = true;
                result.avx2 = true;
                result.fma = true;
                result.gfni = true;
                result.sha = true;
            },
            else => {},
        }
        return result;
    }

    pub fn all() FeatureSet {
        return .{
            .sse = true,
            .sse2 = true,
            .avx = true,
            .avx2 = true,
            .avx512f = true,
            .avx512dq = true,
            .avx512vl = true,
            .avx512bw = true,
            .avx512bf16 = true,
            .gfni = true,
            .sha = true,
            .vaes = true,
            .amx_tile = true,
            .keylocker = true,
            .movdir64b = true,
            .fma = true,
            .neon = true,
        };
    }

    pub fn contains(self: FeatureSet, feature: Feature) bool {
        return switch (feature) {
            .sse => self.sse,
            .sse2 => self.sse2,
            .avx => self.avx,
            .avx2 => self.avx2,
            .avx512f => self.avx512f,
            .avx512dq => self.avx512dq,
            .avx512vl => self.avx512vl,
            .avx512bw => self.avx512bw,
            .avx512bf16 => self.avx512bf16,
            .gfni => self.gfni,
            .sha => self.sha,
            .vaes => self.vaes,
            .amx_tile => self.amx_tile,
            .keylocker => self.keylocker,
            .movdir64b => self.movdir64b,
            .fma => self.fma,
            .neon => self.neon,
        };
    }

    pub fn mask(self: FeatureSet) u64 {
        var bits: u64 = 0;
        inline for (@typeInfo(Feature).@"enum".fields) |field| {
            const feature: Feature = @enumFromInt(field.value);
            if (self.contains(feature)) bits |= @as(u64, 1) << @intCast(field.value);
        }
        return bits;
    }
};

pub const Width = enum(u16) {
    bits128 = 128,
    bits256 = 256,
    bits512 = 512,
    bits1024 = 1024,

    pub fn bits(self: Width) usize {
        return @intFromEnum(self);
    }

    pub fn bytes(self: Width) usize {
        return self.bits() / 8;
    }

    pub fn blockCount(self: Width) usize {
        return self.bits() / VECTOR_BLOCK_BITS;
    }
};

pub const Operation = enum {
    move,
    aligned_move,
    unaligned_move,
    non_temporal_move,
    add_ps,
    add_pd,
    sub_ps,
    sub_pd,
    addsub_ps,
    addsub_pd,
    or_ps,
    or_pd,
    xor_ps,
    xor_pd,
    mul_ps,
    mul_pd,
    div_ps,
    div_pd,
    and_ps,
    and_pd,
    andn_ps,
    andn_pd,
    cmp_ps,
    cmp_pd,
    sqrt_ps,
    sqrt_pd,
    blend_ps,
    blend_pd,
    blendv_ps,
    blendv_pd,
    shuf_ps,
    shuf_pd,
    dpps,
    vdpbf16ps,
    aesenc,
    aesdec,
    aesenclast,
    aesdeclast,
    pmin_signed,
    pmin_unsigned,
    pmax_signed,
    pmax_unsigned,
    movemask_ps,
    movemask_pd,
    duplicate_odd_ps,
    duplicate_even_ps,
    duplicate_low_pd,
    control,
    system_512,
    key_256,
    fma_ps,
    fma_pd,
    fms_ps,
    fms_pd,
    fnma_ps,
    fnma_pd,
    fnms_ps,
    fnms_pd,
    fma_addsub_ps,
    fma_addsub_pd,
    fma_subadd_ps,
    fma_subadd_pd,
    padd,
    psub,
    pcmpeq,
    pcmpgt,
    pmull,
    psubs,
    psubus,
    // CONVERT group (P0 — critical for correctness)
    cvt_pd2ps,
    cvt_ps2pd,
    cvt_dq2ps,
    cvt_ps2dq,
    cvtt_ps2dq,
    // SHIFT group (P0 — packed shift operations)
    psll,
    psra,
    psrl,
    // PACK group (P0 — saturated pack operations)
    packss,
    packus,
    // AVX512 compute stubs (registered but not yet implemented)
    scale_ps,
    scale_pd,
    range_ps,
    range_pd,
    fixup_ps,
    fixup_pd,
    compress_ps,
    compress_pd,
    expand_ps,
    expand_pd,
    permute_d,
    permute_q,
    // P1 operations (absolute value, sign, bitwise NOT, unpack interleave)
    pabs,
    psign,
    pnot,
    unpck_low,
    unpck_high,
    // P1 operations (broadcast, block insert)
    broadcast_lane,
    move_high_low,
    move_low_high,
    insert_block,
    // P2 operations (down-convert, element extract/insert)
    down_convert_trunc,
    down_convert_signed,
    down_convert_unsigned,
    extract_element,
    insert_element,
    insert_ps,
    // P3 operations (align, average, rotate)
    @"align",
    avg,
    rotate_left,
    rotate_right,
    rotate_left_variable,
    rotate_right_variable,
    // P3 operations (bitwise ternary, Galois field, rounding, SHA, two-source permute)
    ternary_logic,
    gf2p8_mul,
    gf2p8_affine,
    gf2p8_affine_inv,
    round_to_int,
    sha1_msg1,
    sha1_msg2,
    sha1_nexte,
    sha1_rnds4,
    sha256_msg1,
    sha256_msg2,
    sha256_rnds2,
    two_source_permute,
    // GATHER/SCATTER — indexed memory access
    gather_ps,
    gather_pd,
    gather_d,
    gather_q,
    scatter_ps,
    scatter_pd,
    scatter_d,
    scatter_q,
    // CONVERT group additions (P0 — critical conversions)
    cvt_pd2dq,
    cvtt_pd2dq,
    cvt_dq2pd,
    cvt_ph2ps,
    cvt_ps2ph,
    cvt_bf16,
    // SHIFT group additions (byte shift within 128-bit lane)
    byte_shift_left,
    byte_shift_right,
    // PERMUTE group additional ops
    permil,
    // INSERT group element insert
    // (insert_element already defined above)
};

pub const Alignment = enum(u16) {
    any = 1,
    aligned16 = 16,
    aligned32 = 32,
    aligned64 = 64,

    pub fn bytes(self: Alignment) usize {
        return @intFromEnum(self);
    }
};

pub const SafetyError = error{
    InvalidWideWidth,
    InvalidElementWidth,
    InvalidBlockWidth,
    UnsupportedFeature,
    UnsupportedInstructionWidth,
    BufferTooSmall,
    MisalignedMemory,
};

/// MXCSR status flags that should be updated after floating-point SIMD
/// operations.  Real x86 hardware sets these bits architecturally; CLEO
/// tracks them so that guest code that reads MXCSR via VSTMXCSR / STMXCSR
/// gets plausible values rather than always 0x1F80 (all flags clear).
///
/// Bit positions match the x86 MXCSR register:
///   bit 0 = IE (Invalid Operation)
///   bit 1 = DE (Denormal)
///   bit 2 = ZE (Divide-by-Zero)
///   bit 3 = OE (Overflow)
///   bit 4 = UE (Underflow)
///   bit 5 = PE (Precision)
pub const MxcsrFlags = packed struct {
    ie: bool = false,
    de: bool = false,
    ze: bool = false,
    oe: bool = false,
    ue: bool = false,
    pe: bool = false,
    _padding: u2 = 0,
    im: bool = true,
    dm: bool = true,
    zm: bool = true,
    om: bool = true,
    um: bool = true,
    pm: bool = true,
    _rsvd: u6 = 0,
    fz: bool = false,
    daz: bool = false,
    _rsvd2: u2 = 0,

    pub fn defaultValue() MxcsrFlags {
        return .{};
    }

    pub fn toU32(self: MxcsrFlags) u32 {
        return @bitCast(self);
    }

    pub fn fromU32(value: u32) MxcsrFlags {
        return @bitCast(value);
    }

    /// After a floating-point operation, update the IE (invalid),
    /// ZE (divide-by-zero), OE (overflow), UE (underflow), and PE (precision)
    /// flags based on the inputs and result.
    /// `has_divisor` should be true for division (may set ZE on x/0),
    /// `has_negative_src` for unary negation ops (may set IE on sqrt(x<0)),
    /// `has_inf_diff` for subtraction operations where both infinities
    /// produce an invalid result (Inf - Inf = NaN).
    pub fn updateAfterArith(T: type, lhs: T, rhs: T, result: T, has_divisor: bool, has_negative_src: bool, has_inf_diff: bool) MxcsrFlags {
        var flags = MxcsrFlags{};
        if (@typeInfo(T) != .float) return flags;
        const is_inf_lhs = std.math.isInf(lhs);
        const is_inf_rhs = std.math.isInf(rhs);
        const is_nan_lhs = std.math.isNan(lhs);
        const is_nan_rhs = std.math.isNan(rhs);
        if (is_nan_lhs or is_nan_rhs) flags.ie = true;
        if (has_divisor and rhs == 0 and lhs != 0) flags.ze = true;
        if (has_negative_src and lhs < 0) flags.ie = true;
        // Infinity - Infinity => invalid; Infinity + Infinity is valid
        if (has_inf_diff and is_inf_lhs and is_inf_rhs) flags.ie = true;
        if (std.math.isInf(result)) flags.oe = true;
        if (result != 0 and @abs(result) < std.math.floatMin(T)) flags.ue = true;
        flags.pe = true;
        return flags;
    }
};

pub const LoweringPlan = struct {
    width_bits: usize,
    block_bits: usize,
    block_count: usize,
    required_feature: Feature,
    uses_neon_blocks: bool,
    requires_scalar_fixup: bool,
    supports_masking: bool,
    supports_broadcast: bool,

    pub fn complete(self: LoweringPlan) bool {
        return self.width_bits >= VECTOR_BLOCK_BITS and
            self.width_bits % self.block_bits == 0 and
            self.block_bits == VECTOR_BLOCK_BITS and
            self.block_count == self.width_bits / VECTOR_BLOCK_BITS;
    }
};

pub const InstructionMeta = struct {
    name: []const u8,
    family: []const u8,
    source_path: []const u8,
    required_feature: Feature,
    max_width_bits: usize,
    element_bits: usize,
    operation: Operation,
    alignment: Alignment = .any,
    supports_masking: bool = false,
    supports_broadcast: bool = false,
    asm_template: []const u8 = "split into 128-bit NEON blocks; execute block kernel; merge x86-visible register state",

    pub fn blockCount(self: InstructionMeta) usize {
        return self.max_width_bits / VECTOR_BLOCK_BITS;
    }

    pub fn plan(self: InstructionMeta) LoweringPlan {
        return .{
            .width_bits = self.max_width_bits,
            .block_bits = VECTOR_BLOCK_BITS,
            .block_count = self.blockCount(),
            .required_feature = self.required_feature,
            .uses_neon_blocks = true,
            .requires_scalar_fixup = switch (self.operation) {
                .movemask_ps,
                .movemask_pd,
                .dpps,
                .vdpbf16ps,
                .aesenc,
                .aesdec,
                .aesenclast,
                .aesdeclast,
                .control,
                .system_512,
                .key_256,
                .cvt_pd2ps,
                .cvt_ps2pd,
                .cvt_dq2ps,
                .cvt_ps2dq,
                .cvtt_ps2dq,
                .packss,
                .packus,
                .unpck_low,
                .unpck_high,
                .pabs,
                .psign,
                .pnot,
                .broadcast_lane,
                .insert_block,
                .down_convert_trunc,
                .down_convert_signed,
                .down_convert_unsigned,
                .extract_element,
                .insert_element,
                .insert_ps,
                .@"align",
                .avg,
                .rotate_left,
                .rotate_right,
                .rotate_left_variable,
                .rotate_right_variable,
                .ternary_logic,
                .gf2p8_mul,
                .gf2p8_affine,
                .gf2p8_affine_inv,
                .round_to_int,
                .sha1_msg1,
                .sha1_msg2,
                .sha1_nexte,
                .sha1_rnds4,
                .sha256_msg1,
                .sha256_msg2,
                .sha256_rnds2,
                .two_source_permute,
                .gather_ps,
                .gather_pd,
                .gather_d,
                .gather_q,
                .scatter_ps,
                .scatter_pd,
                .scatter_d,
                .scatter_q,
                .cvt_pd2dq,
                .cvtt_pd2dq,
                .cvt_dq2pd,
                .cvt_ph2ps,
                .cvt_ps2ph,
                .cvt_bf16,
                .byte_shift_left,
                .byte_shift_right,
                .permil,
                => true,
                else => false,
            },
            .supports_masking = self.supports_masking,
            .supports_broadcast = self.supports_broadcast,
        };
    }
};

pub const SafetyReport = struct {
    instruction_name: []const u8,
    source_path: []const u8,
    required_feature: Feature,
    feature_available: bool,
    width_bits: usize,
    element_bits: usize,
    block_count: usize,
    width_ok: bool,
    element_ok: bool,
    block_ok: bool,
    asm_template_present: bool,

    pub fn ok(self: SafetyReport) bool {
        return self.feature_available and self.width_ok and self.element_ok and self.block_ok and self.asm_template_present;
    }
};

pub fn validateWideWidth(comptime bits: usize) void {
    if (bits != 128 and bits != 256 and bits != 512 and bits != 1024) {
        @compileError("CLEO supports 128, 256, 512, and internal 1024-bit vectors");
    }
    if (bits % VECTOR_BLOCK_BITS != 0) @compileError("CLEO widths must divide into 128-bit NEON blocks");
}

pub fn laneCount(comptime bits: usize, comptime T: type) usize {
    validateWideWidth(bits);
    const scalar_bits = @bitSizeOf(T);
    if (scalar_bits == 0 or bits % scalar_bits != 0) {
        @compileError("CLEO element type must divide the selected wide vector width");
    }
    return bits / scalar_bits;
}

/// Whether a declared maximum width is one CLEO can lower: a whole number of
/// 128-bit NEON blocks, from a single block up to the internal 1024-bit
/// vector.
///
/// `validateWideWidth` — the comptime gate the lowering itself goes through —
/// has always accepted 128. The two runtime checks that used to spell this
/// rule out by hand both required *more* than one block, so every
/// 128-bit-only instruction in the registry (MOVSS, MOVSD, MOVLPS, MOVHPS,
/// MOVHLPS, MOVLHPS and their VEX forms) failed a rule its own lowering
/// passes: `validateMeta` refused them outright and `safetyReport` reported
/// them permanently incomplete. One predicate, used by both.
pub fn isLowerableWidth(bits: usize) bool {
    return switch (bits) {
        VECTOR_BLOCK_BITS, 256, 512, 1024 => true,
        else => false,
    };
}

pub fn validateMeta(meta: InstructionMeta) SafetyError!void {
    if (!isLowerableWidth(meta.max_width_bits)) return SafetyError.InvalidWideWidth;
    if (meta.element_bits == 0 or meta.max_width_bits % meta.element_bits != 0) return SafetyError.InvalidElementWidth;
    if (meta.blockCount() == 0) return SafetyError.InvalidBlockWidth;
}

pub fn safetyReport(meta: InstructionMeta, features: FeatureSet) SafetyReport {
    return .{
        .instruction_name = meta.name,
        .source_path = meta.source_path,
        .required_feature = meta.required_feature,
        .feature_available = features.contains(meta.required_feature),
        .width_bits = meta.max_width_bits,
        .element_bits = meta.element_bits,
        .block_count = meta.blockCount(),
        .width_ok = isLowerableWidth(meta.max_width_bits),
        .element_ok = meta.element_bits != 0 and meta.max_width_bits % meta.element_bits == 0,
        .block_ok = meta.blockCount() == meta.max_width_bits / VECTOR_BLOCK_BITS,
        .asm_template_present = meta.asm_template.len != 0,
    };
}

pub fn requireFeature(meta: InstructionMeta, features: FeatureSet) SafetyError!void {
    if (!features.contains(meta.required_feature)) return SafetyError.UnsupportedFeature;
}

pub fn requireWidth(meta: InstructionMeta, comptime bits: usize) SafetyError!void {
    validateWideWidth(bits);
    if (bits > meta.max_width_bits) return SafetyError.UnsupportedInstructionWidth;
}

test "CLEO feature masks separate host and emulated support" {
    const emulated = FeatureSet.cleoEmulated();
    try std.testing.expect(emulated.contains(.sse));
    try std.testing.expect(emulated.contains(.sse2));
    try std.testing.expect(emulated.mask() != 0);
    const host = FeatureSet.host();
    try std.testing.expect(host.contains(.neon) or host.contains(.sse));
}
