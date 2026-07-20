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

pub fn validateMeta(meta: InstructionMeta) SafetyError!void {
    if (meta.max_width_bits <= VECTOR_BLOCK_BITS or meta.max_width_bits % VECTOR_BLOCK_BITS != 0) return SafetyError.InvalidWideWidth;
    if (meta.max_width_bits != 256 and meta.max_width_bits != 512 and meta.max_width_bits != 1024) return SafetyError.InvalidWideWidth;
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
        .width_ok = meta.max_width_bits > VECTOR_BLOCK_BITS and meta.max_width_bits % VECTOR_BLOCK_BITS == 0,
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
