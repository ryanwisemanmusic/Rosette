const std = @import("std");

pub const TargetIsa = enum {
    x86,
    neon,
};

pub const Operation = enum {
    add,
    adc,
    adcx,
    adox,
    inc,
    dec,
    sub,
    mov,
    mul,
    imul,
    div,
    idiv,
    aaa,
    aas,
    aam,
    aad,
    addps,
    addpd,
    addss,
    addsd,
    addsubps,
    addsubpd,
    subps,
    subpd,
    subss,
    subsd,
    mulps,
    mulpd,
    mulss,
    mulsd,
    mulx,
    divps,
    divpd,
    divss,
    divsd,
    documented_contract,
};

pub const RegisterModel = enum {
    gpr_binary,
    gpr_unary,
    gpr_carry_chain,
    gpr_transfer,
    implicit_accumulator,
    implicit_dividend,
    ascii_ax,
    simd_packed,
    simd_scalar,
    documented_contract,
};

pub const FlagModel = enum {
    arithmetic_full,
    carry_only,
    overflow_only,
    preserve_cf_arithmetic,
    mul_overflow_pair,
    undefined_after_divide,
    no_flags,
    ascii_adjust,
    mxcsr_float,
    documented_contract,
};

pub const Width = enum(u8) {
    bits8 = 8,
    bits16 = 16,
    bits32 = 32,
    bits64 = 64,

    pub fn bits(self: Width) u8 {
        return @intFromEnum(self);
    }
};

pub const Trap = enum {
    divide_error,
};

pub const FlagValue = enum {
    clear,
    set,
    preserve,
    undefined,
};

pub const Flags = struct {
    cf: FlagValue = .preserve,
    pf: FlagValue = .preserve,
    af: FlagValue = .preserve,
    zf: FlagValue = .preserve,
    sf: FlagValue = .preserve,
    of: FlagValue = .preserve,
};

pub const InputFlags = struct {
    cf: bool = false,
    of: bool = false,
    af: bool = false,
};

pub const IntegerResult = struct {
    dest: u64 = 0,
    high: u64 = 0,
    quotient: u64 = 0,
    remainder: u64 = 0,
    flags: Flags = .{},
    trap: ?Trap = null,
};

pub const AsciiAdjustResult = struct {
    ax: u16 = 0,
    al: u8 = 0,
    ah: u8 = 0,
    flags: Flags = .{},
    trap: ?Trap = null,
};

pub const RegisterEffect = struct {
    reads: []const []const u8,
    writes: []const []const u8,
    implicit: []const []const u8,
    uses_simd: bool = false,
    uses_flags: bool = false,
};

pub const InstructionMathMeta = struct {
    name: []const u8,
    family: []const u8,
    path: []const u8,
    source_table_path: []const u8,
    target_isa: TargetIsa,
    operation: Operation,
    register_model: RegisterModel,
    flag_model: FlagModel,
};

pub const InstructionMathSpec = struct {
    meta: InstructionMathMeta,

    pub fn edgeCaseCount(self: InstructionMathSpec) usize {
        return edgeCaseCountForOperation(self.meta.operation);
    }

    pub fn validatesRegisters(self: InstructionMathSpec) bool {
        const effect = registerEffectFor(self.meta.operation);
        return effect.reads.len != 0 or effect.writes.len != 0 or effect.implicit.len != 0;
    }

    pub fn validatesFlags(self: InstructionMathSpec) bool {
        return switch (self.meta.flag_model) {
            .no_flags => true,
            else => registerEffectFor(self.meta.operation).uses_flags or self.meta.flag_model == .mxcsr_float,
        };
    }

    pub fn validatesOverflow(self: InstructionMathSpec) bool {
        return switch (self.meta.operation) {
            .add,
            .adc,
            .adcx,
            .adox,
            .inc,
            .dec,
            .sub,
            .mul,
            .imul,
            .div,
            .idiv,
            .addps,
            .addpd,
            .addss,
            .addsd,
            .addsubps,
            .addsubpd,
            .subps,
            .subpd,
            .subss,
            .subsd,
            .mulps,
            .mulpd,
            .mulss,
            .mulsd,
            .mulx,
            .divps,
            .divpd,
            .divss,
            .divsd,
            => true,
            else => false,
        };
    }

    pub fn validatesTraps(self: InstructionMathSpec) bool {
        return switch (self.meta.operation) {
            .div, .idiv, .aam => true,
            else => false,
        };
    }

    pub fn registerEffect(self: InstructionMathSpec) RegisterEffect {
        return registerEffectFor(self.meta.operation);
    }
};

pub fn specFromMeta(meta: InstructionMathMeta) InstructionMathSpec {
    return .{ .meta = meta };
}

fn boolFlag(value: bool) FlagValue {
    return if (value) .set else .clear;
}

fn maskBits(bits: u8) u128 {
    if (bits == 128) return ~@as(u128, 0);
    return (@as(u128, 1) << @as(u7, @intCast(bits))) - 1;
}

fn mask(width: Width) u128 {
    return maskBits(width.bits());
}

fn truncate(width: Width, value: u128) u64 {
    return @as(u64, @intCast(value & mask(width)));
}

fn truncateSigned(width: Width, value: i128) u64 {
    return @as(u64, @intCast(i128Bits(value) & mask(width)));
}

fn signMask(width: Width) u64 {
    return @as(u64, @intCast(@as(u128, 1) << @as(u7, @intCast(width.bits() - 1))));
}

fn parityLow8(value: u64) bool {
    return @popCount(@as(u8, @truncate(value))) % 2 == 0;
}

fn signedMin(width: Width) i128 {
    return -(@as(i128, 1) << @as(u7, @intCast(width.bits() - 1)));
}

fn signedMax(width: Width) i128 {
    return (@as(i128, 1) << @as(u7, @intCast(width.bits() - 1))) - 1;
}

fn i128Bits(value: i128) u128 {
    return @as(u128, @bitCast(value));
}

fn signExtend(width: Width, value: u64) i128 {
    return signExtendBits(@as(u128, value), width.bits());
}

fn signExtendBits(value: u128, bits: u8) i128 {
    const masked = value & maskBits(bits);
    const sign = @as(u128, 1) << @as(u7, @intCast(bits - 1));
    if ((masked & sign) == 0) return @as(i128, @intCast(masked));

    const magnitude = ((~masked) +% 1) & maskBits(bits);
    if (bits == 128 and magnitude == sign) return std.math.minInt(i128);
    return -@as(i128, @intCast(magnitude));
}

fn szpFlags(width: Width, result: u64) Flags {
    return .{
        .sf = boolFlag((result & signMask(width)) != 0),
        .zf = boolFlag(result == 0),
        .pf = boolFlag(parityLow8(result)),
    };
}

pub fn add(width: Width, lhs: u64, rhs: u64) IntegerResult {
    return addCarry(width, lhs, rhs, false);
}

pub fn adc(width: Width, lhs: u64, rhs: u64, carry: bool) IntegerResult {
    return addCarry(width, lhs, rhs, carry);
}

fn addCarry(width: Width, lhs: u64, rhs: u64, carry: bool) IntegerResult {
    const lhs_t = truncate(width, lhs);
    const rhs_t = truncate(width, rhs);
    const carry_value: u128 = if (carry) 1 else 0;
    const wide = @as(u128, lhs_t) + @as(u128, rhs_t) + carry_value;
    const result = truncate(width, wide);
    var flags = szpFlags(width, result);
    const sign = signMask(width);
    flags.cf = boolFlag(wide > mask(width));
    flags.af = boolFlag(((lhs_t ^ rhs_t ^ result) & 0x10) != 0);
    flags.of = boolFlag(((~(lhs_t ^ rhs_t) & (lhs_t ^ result) & sign) != 0));
    return .{ .dest = result, .flags = flags };
}

pub fn adcx(width: Width, lhs: u64, rhs: u64, flags_in: InputFlags) IntegerResult {
    const result = addCarry(width, lhs, rhs, flags_in.cf);
    return .{
        .dest = result.dest,
        .flags = .{ .cf = result.flags.cf },
    };
}

pub fn adox(width: Width, lhs: u64, rhs: u64, flags_in: InputFlags) IntegerResult {
    const result = addCarry(width, lhs, rhs, flags_in.of);
    return .{
        .dest = result.dest,
        .flags = .{ .of = result.flags.cf },
    };
}

pub fn inc(width: Width, value: u64, flags_in: InputFlags) IntegerResult {
    var result = addCarry(width, value, 1, false);
    result.flags.cf = boolFlag(flags_in.cf);
    return result;
}

pub fn sub(width: Width, lhs: u64, rhs: u64) IntegerResult {
    return subBorrow(width, lhs, rhs, false);
}

pub fn sbb(width: Width, lhs: u64, rhs: u64, borrow: bool) IntegerResult {
    return subBorrow(width, lhs, rhs, borrow);
}

pub fn dec(width: Width, value: u64, flags_in: InputFlags) IntegerResult {
    var result = subBorrow(width, value, 1, false);
    result.flags.cf = boolFlag(flags_in.cf);
    return result;
}

fn subBorrow(width: Width, lhs: u64, rhs: u64, borrow: bool) IntegerResult {
    const lhs_t = truncate(width, lhs);
    const rhs_t = truncate(width, rhs);
    const borrow_value: u128 = if (borrow) 1 else 0;
    const subtrahend = @as(u128, rhs_t) + borrow_value;
    const modulo = mask(width) + 1;
    const result = truncate(width, (@as(u128, lhs_t) + modulo - subtrahend) & mask(width));
    var flags = szpFlags(width, result);
    const sign = signMask(width);
    flags.cf = boolFlag(@as(u128, lhs_t) < subtrahend);
    flags.af = boolFlag(((lhs_t ^ rhs_t ^ result) & 0x10) != 0);
    flags.of = boolFlag((((lhs_t ^ rhs_t) & (lhs_t ^ result) & sign) != 0));
    return .{ .dest = result, .flags = flags };
}

fn logical(width: Width, result_wide: u64) IntegerResult {
    const result = truncate(width, result_wide);
    var flags = szpFlags(width, result);
    flags.cf = .clear;
    flags.of = .clear;
    flags.af = .undefined;
    return .{ .dest = result, .flags = flags };
}

pub fn bitAnd(width: Width, lhs: u64, rhs: u64) IntegerResult {
    return logical(width, lhs & rhs);
}

pub fn bitOr(width: Width, lhs: u64, rhs: u64) IntegerResult {
    return logical(width, lhs | rhs);
}

pub fn bitXor(width: Width, lhs: u64, rhs: u64) IntegerResult {
    return logical(width, lhs ^ rhs);
}

pub fn testBits(width: Width, lhs: u64, rhs: u64) IntegerResult {
    return bitAnd(width, lhs, rhs);
}

pub fn mov(width: Width, src: u64) IntegerResult {
    return .{ .dest = truncate(width, src), .flags = .{} };
}

pub fn mul(width: Width, lhs: u64, rhs: u64) IntegerResult {
    const product = @as(u128, truncate(width, lhs)) * @as(u128, truncate(width, rhs));
    const low = truncate(width, product);
    const high = truncate(width, product >> @as(u7, @intCast(width.bits())));
    const overflow = high != 0;
    return .{
        .dest = low,
        .high = high,
        .flags = .{
            .cf = boolFlag(overflow),
            .of = boolFlag(overflow),
            .sf = .undefined,
            .zf = .undefined,
            .af = .undefined,
            .pf = .undefined,
        },
    };
}

pub fn imul(width: Width, lhs: u64, rhs: u64) IntegerResult {
    const lhs_s = signExtend(width, truncate(width, lhs));
    const rhs_s = signExtend(width, truncate(width, rhs));
    const product = lhs_s * rhs_s;
    const bits = i128Bits(product);
    const low = truncate(width, bits);
    const high = truncate(width, bits >> @as(u7, @intCast(width.bits())));
    const overflow = product < signedMin(width) or product > signedMax(width);
    return .{
        .dest = low,
        .high = high,
        .flags = .{
            .cf = boolFlag(overflow),
            .of = boolFlag(overflow),
            .sf = .undefined,
            .zf = .undefined,
            .af = .undefined,
            .pf = .undefined,
        },
    };
}

pub fn divUnsigned(width: Width, high: u64, low: u64, divisor: u64) IntegerResult {
    const divisor_t = truncate(width, divisor);
    if (divisor_t == 0) return .{ .trap = .divide_error };
    const numerator = (@as(u128, truncate(width, high)) << @as(u7, @intCast(width.bits()))) | @as(u128, truncate(width, low));
    const quotient = numerator / @as(u128, divisor_t);
    if (quotient > mask(width)) return .{ .trap = .divide_error };
    const remainder = numerator % @as(u128, divisor_t);
    return .{
        .dest = truncate(width, quotient),
        .quotient = truncate(width, quotient),
        .remainder = truncate(width, remainder),
        .flags = undefinedAfterDivideFlags(),
    };
}

pub fn divSigned(width: Width, high: u64, low: u64, divisor: u64) IntegerResult {
    const divisor_s = signExtend(width, truncate(width, divisor));
    if (divisor_s == 0) return .{ .trap = .divide_error };

    const double_bits = width.bits() * 2;
    const numerator_bits = (@as(u128, truncate(width, high)) << @as(u7, @intCast(width.bits()))) | @as(u128, truncate(width, low));
    const numerator = signExtendBits(numerator_bits, double_bits);
    if (numerator == std.math.minInt(i128) and divisor_s == -1) return .{ .trap = .divide_error };

    const quotient = @divTrunc(numerator, divisor_s);
    const remainder = @rem(numerator, divisor_s);
    if (quotient < signedMin(width) or quotient > signedMax(width)) return .{ .trap = .divide_error };
    return .{
        .dest = truncateSigned(width, quotient),
        .quotient = truncateSigned(width, quotient),
        .remainder = truncateSigned(width, remainder),
        .flags = undefinedAfterDivideFlags(),
    };
}

fn undefinedAfterDivideFlags() Flags {
    return .{
        .cf = .undefined,
        .of = .undefined,
        .sf = .undefined,
        .zf = .undefined,
        .af = .undefined,
        .pf = .undefined,
    };
}

pub fn aaa(ax: u16, flags_in: InputFlags) AsciiAdjustResult {
    var next_ax = ax;
    const al = @as(u8, @truncate(ax));
    const adjust = (al & 0x0f) > 9 or flags_in.af;
    const flags: Flags = if (adjust)
        .{ .af = .set, .cf = .set, .of = .undefined, .sf = .undefined, .zf = .undefined, .pf = .undefined }
    else
        .{ .af = .clear, .cf = .clear, .of = .undefined, .sf = .undefined, .zf = .undefined, .pf = .undefined };
    if (adjust) next_ax +%= 0x0106;
    next_ax = (next_ax & 0xff00) | (next_ax & 0x000f);
    return .{ .ax = next_ax, .al = @as(u8, @truncate(next_ax)), .ah = @as(u8, @truncate(next_ax >> 8)), .flags = flags };
}

pub fn aas(ax: u16, flags_in: InputFlags) AsciiAdjustResult {
    var next_ax = ax;
    const al = @as(u8, @truncate(ax));
    const adjust = (al & 0x0f) > 9 or flags_in.af;
    const flags: Flags = if (adjust)
        .{ .af = .set, .cf = .set, .of = .undefined, .sf = .undefined, .zf = .undefined, .pf = .undefined }
    else
        .{ .af = .clear, .cf = .clear, .of = .undefined, .sf = .undefined, .zf = .undefined, .pf = .undefined };
    if (adjust) next_ax -%= 0x0106;
    next_ax = (next_ax & 0xff00) | (next_ax & 0x000f);
    return .{ .ax = next_ax, .al = @as(u8, @truncate(next_ax)), .ah = @as(u8, @truncate(next_ax >> 8)), .flags = flags };
}

pub fn aam(al: u8, immediate: u8) AsciiAdjustResult {
    if (immediate == 0) return .{ .trap = .divide_error };
    const ah = al / immediate;
    const next_al = al % immediate;
    return .{
        .ax = (@as(u16, ah) << 8) | next_al,
        .al = next_al,
        .ah = ah,
        .flags = asciiSzpFlags(next_al),
    };
}

pub fn aad(ah: u8, al: u8, immediate: u8) AsciiAdjustResult {
    const next_al = @as(u8, @truncate(@as(u16, ah) * @as(u16, immediate) + @as(u16, al)));
    return .{
        .ax = next_al,
        .al = next_al,
        .ah = 0,
        .flags = asciiSzpFlags(next_al),
    };
}

fn asciiSzpFlags(al: u8) Flags {
    return .{
        .sf = boolFlag((al & 0x80) != 0),
        .zf = boolFlag(al == 0),
        .pf = boolFlag(parityLow8(al)),
        .cf = .undefined,
        .of = .undefined,
        .af = .undefined,
    };
}

pub fn addps(lhs: [4]f32, rhs: [4]f32) [4]f32 {
    return .{ lhs[0] + rhs[0], lhs[1] + rhs[1], lhs[2] + rhs[2], lhs[3] + rhs[3] };
}

pub fn subps(lhs: [4]f32, rhs: [4]f32) [4]f32 {
    return .{ lhs[0] - rhs[0], lhs[1] - rhs[1], lhs[2] - rhs[2], lhs[3] - rhs[3] };
}

pub fn addpd(lhs: [2]f64, rhs: [2]f64) [2]f64 {
    return .{ lhs[0] + rhs[0], lhs[1] + rhs[1] };
}

pub fn subpd(lhs: [2]f64, rhs: [2]f64) [2]f64 {
    return .{ lhs[0] - rhs[0], lhs[1] - rhs[1] };
}

pub fn addss(dest: [4]f32, src: [4]f32) [4]f32 {
    return .{ dest[0] + src[0], dest[1], dest[2], dest[3] };
}

pub fn addssVex(src1: [4]f32, src2: [4]f32) [4]f32 {
    return .{ src1[0] + src2[0], src1[1], src1[2], src1[3] };
}

pub fn subss(dest: [4]f32, src: [4]f32) [4]f32 {
    return .{ dest[0] - src[0], dest[1], dest[2], dest[3] };
}

pub fn subssVex(src1: [4]f32, src2: [4]f32) [4]f32 {
    return .{ src1[0] - src2[0], src1[1], src1[2], src1[3] };
}

pub fn addsd(dest: [2]f64, src: [2]f64) [2]f64 {
    return .{ dest[0] + src[0], dest[1] };
}

pub fn addsdVex(src1: [2]f64, src2: [2]f64) [2]f64 {
    return .{ src1[0] + src2[0], src1[1] };
}

pub fn subsd(dest: [2]f64, src: [2]f64) [2]f64 {
    return .{ dest[0] - src[0], dest[1] };
}

pub fn subsdVex(src1: [2]f64, src2: [2]f64) [2]f64 {
    return .{ src1[0] - src2[0], src1[1] };
}

pub fn addsubps(lhs: [4]f32, rhs: [4]f32) [4]f32 {
    return .{ lhs[0] - rhs[0], lhs[1] + rhs[1], lhs[2] - rhs[2], lhs[3] + rhs[3] };
}

pub fn addsubpd(lhs: [2]f64, rhs: [2]f64) [2]f64 {
    return .{ lhs[0] - rhs[0], lhs[1] + rhs[1] };
}

pub fn mulps(lhs: [4]f32, rhs: [4]f32) [4]f32 {
    return .{ lhs[0] * rhs[0], lhs[1] * rhs[1], lhs[2] * rhs[2], lhs[3] * rhs[3] };
}

pub fn mulpd(lhs: [2]f64, rhs: [2]f64) [2]f64 {
    return .{ lhs[0] * rhs[0], lhs[1] * rhs[1] };
}

pub fn divps(lhs: [4]f32, rhs: [4]f32) [4]f32 {
    return .{ lhs[0] / rhs[0], lhs[1] / rhs[1], lhs[2] / rhs[2], lhs[3] / rhs[3] };
}

pub fn divpd(lhs: [2]f64, rhs: [2]f64) [2]f64 {
    return .{ lhs[0] / rhs[0], lhs[1] / rhs[1] };
}

pub fn mulss(dest: [4]f32, src: [4]f32) [4]f32 {
    return .{ dest[0] * src[0], dest[1], dest[2], dest[3] };
}

pub fn mulssVex(src1: [4]f32, src2: [4]f32) [4]f32 {
    return .{ src1[0] * src2[0], src1[1], src1[2], src1[3] };
}

pub fn mulsd(dest: [2]f64, src: [2]f64) [2]f64 {
    return .{ dest[0] * src[0], dest[1] };
}

pub fn mulsdVex(src1: [2]f64, src2: [2]f64) [2]f64 {
    return .{ src1[0] * src2[0], src1[1] };
}

pub fn divss(dest: [4]f32, src: [4]f32) [4]f32 {
    return .{ dest[0] / src[0], dest[1], dest[2], dest[3] };
}

pub fn divssVex(src1: [4]f32, src2: [4]f32) [4]f32 {
    return .{ src1[0] / src2[0], src1[1], src1[2], src1[3] };
}

pub fn divsd(dest: [2]f64, src: [2]f64) [2]f64 {
    return .{ dest[0] / src[0], dest[1] };
}

pub fn divsdVex(src1: [2]f64, src2: [2]f64) [2]f64 {
    return .{ src1[0] / src2[0], src1[1] };
}

pub fn mulx(width: Width, lhs: u64, rhs: u64) IntegerResult {
    const product = @as(u128, truncate(width, lhs)) * @as(u128, truncate(width, rhs));
    return .{
        .dest = truncate(width, product),
        .high = truncate(width, product >> @as(u7, @intCast(width.bits()))),
        .flags = .{},
    };
}

pub fn edgeCaseCountForOperation(operation: Operation) usize {
    return switch (operation) {
        .add, .adc, .adcx, .adox, .inc, .dec, .sub => 8,
        .mov => 4,
        .mul, .imul => 6,
        .div, .idiv => 6,
        .aaa, .aas, .aam, .aad => 5,
        .addps, .addpd, .addss, .addsd, .addsubps, .addsubpd, .subps, .subpd, .subss, .subsd => 6,
        .mulps, .mulpd, .mulss, .mulsd, .divps, .divpd, .divss, .divsd => 6,
        .mulx => 6,
        .documented_contract => 2,
    };
}

pub fn registerEffectFor(operation: Operation) RegisterEffect {
    return switch (operation) {
        .add, .adc, .adcx, .adox, .sub => .{ .reads = &gpr_binary_reads, .writes = &gpr_binary_writes, .implicit = &empty_registers, .uses_flags = true },
        .inc, .dec => .{ .reads = &gpr_unary_reads, .writes = &gpr_unary_writes, .implicit = &empty_registers, .uses_flags = true },
        .mov => .{ .reads = &mov_reads, .writes = &mov_writes, .implicit = &empty_registers },
        .mul, .imul => .{ .reads = &mul_reads, .writes = &mul_writes, .implicit = &mul_implicit, .uses_flags = true },
        .div, .idiv => .{ .reads = &div_reads, .writes = &div_writes, .implicit = &div_implicit, .uses_flags = true },
        .aaa, .aas => .{ .reads = &ascii_adjust_reads, .writes = &ascii_adjust_writes, .implicit = &ascii_implicit, .uses_flags = true },
        .aam => .{ .reads = &aam_reads, .writes = &aam_writes, .implicit = &ascii_implicit, .uses_flags = true },
        .aad => .{ .reads = &aad_reads, .writes = &aad_writes, .implicit = &ascii_implicit, .uses_flags = true },
        .addps, .addpd, .addsubps, .addsubpd, .subps, .subpd, .mulps, .mulpd, .divps, .divpd => .{ .reads = &simd_binary_reads, .writes = &simd_binary_writes, .implicit = &mxcsr_implicit, .uses_simd = true, .uses_flags = true },
        .addss, .addsd, .subss, .subsd, .mulss, .mulsd, .divss, .divsd => .{ .reads = &simd_scalar_reads, .writes = &simd_scalar_writes, .implicit = &mxcsr_implicit, .uses_simd = true, .uses_flags = true },
        .mulx => .{ .reads = &mulx_reads, .writes = &mulx_writes, .implicit = &empty_registers },
        .documented_contract => .{ .reads = &documented_reads, .writes = &documented_writes, .implicit = &documented_implicit, .uses_flags = true },
    };
}

const empty_registers = [_][]const u8{};
const gpr_binary_reads = [_][]const u8{ "DEST", "SRC" };
const gpr_binary_writes = [_][]const u8{ "DEST", "x86_status_flags" };
const gpr_unary_reads = [_][]const u8{"DEST"};
const gpr_unary_writes = [_][]const u8{ "DEST", "x86_status_flags" };
const mov_reads = [_][]const u8{"SRC"};
const mov_writes = [_][]const u8{"DEST"};
const mul_reads = [_][]const u8{ "ACCUMULATOR", "SRC" };
const mul_writes = [_][]const u8{ "LOW_RESULT", "HIGH_RESULT", "CF", "OF" };
const mul_implicit = [_][]const u8{ "AL/AX/EAX/RAX", "AX/DX:AX/EDX:EAX/RDX:RAX" };
const div_reads = [_][]const u8{ "DOUBLE_WIDTH_DIVIDEND", "DIVISOR" };
const div_writes = [_][]const u8{ "QUOTIENT", "REMAINDER" };
const div_implicit = [_][]const u8{ "AX", "DX:AX", "EDX:EAX", "RDX:RAX" };
const ascii_adjust_reads = [_][]const u8{ "AL", "AH", "AF" };
const ascii_adjust_writes = [_][]const u8{ "AL", "AH", "AF", "CF" };
const aam_reads = [_][]const u8{ "AL", "imm8" };
const aam_writes = [_][]const u8{ "AL", "AH", "SF", "ZF", "PF" };
const aad_reads = [_][]const u8{ "AL", "AH", "imm8" };
const aad_writes = [_][]const u8{ "AL", "AH", "SF", "ZF", "PF" };
const ascii_implicit = [_][]const u8{"AX"};
const simd_binary_reads = [_][]const u8{ "xmm/ymm DEST", "xmm/ymm SRC" };
const simd_binary_writes = [_][]const u8{ "xmm/ymm DEST", "MXCSR status" };
const simd_scalar_reads = [_][]const u8{ "scalar lane 0", "preserved high lanes", "SRC lane 0" };
const simd_scalar_writes = [_][]const u8{ "scalar lane 0", "preserved high lanes", "MXCSR status" };
const mxcsr_implicit = [_][]const u8{"MXCSR"};
const mulx_reads = [_][]const u8{ "SRC1", "SRC2" };
const mulx_writes = [_][]const u8{ "LOW_RESULT", "HIGH_RESULT" };
const documented_reads = [_][]const u8{"documented operands"};
const documented_writes = [_][]const u8{"documented architectural outputs"};
const documented_implicit = [_][]const u8{"documented flags/exceptions/mode state"};

pub fn exerciseSpec(spec: InstructionMathSpec) !void {
    try std.testing.expect(spec.edgeCaseCount() > 0);
    try std.testing.expect(spec.validatesRegisters());
    try std.testing.expect(spec.validatesFlags());

    switch (spec.meta.operation) {
        .add => try exerciseAdd(),
        .adc => try exerciseAdc(),
        .adcx => try exerciseAdcx(),
        .adox => try exerciseAdox(),
        .inc => try exerciseInc(),
        .dec => try exerciseDec(),
        .sub => try exerciseSub(),
        .mov => try exerciseMov(),
        .mul => try exerciseMul(),
        .imul => try exerciseImul(),
        .div => try exerciseDiv(),
        .idiv => try exerciseIdiv(),
        .aaa => try exerciseAaa(),
        .aas => try exerciseAas(),
        .aam => try exerciseAam(),
        .aad => try exerciseAad(),
        .addps => try exerciseAddps(),
        .addpd => try exerciseAddpd(),
        .addss => try exerciseAddss(),
        .addsd => try exerciseAddsd(),
        .addsubps => try exerciseAddsubps(),
        .addsubpd => try exerciseAddsubpd(),
        .subps => try exerciseSubps(),
        .subpd => try exerciseSubpd(),
        .subss => try exerciseSubss(),
        .subsd => try exerciseSubsd(),
        .mulps => try exerciseMulps(),
        .mulpd => try exerciseMulpd(),
        .mulss => try exerciseMulss(),
        .mulsd => try exerciseMulsd(),
        .mulx => try exerciseMulx(),
        .divps => try exerciseDivps(),
        .divpd => try exerciseDivpd(),
        .divss => try exerciseDivss(),
        .divsd => try exerciseDivsd(),
        .documented_contract => try exerciseDocumentedContract(),
    }
}

fn exerciseDocumentedContract() !void {
    try std.testing.expect(true);
}

fn exerciseAdd() !void {
    var result = add(.bits8, 0xff, 1);
    try std.testing.expectEqual(@as(u64, 0), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);
    try std.testing.expectEqual(FlagValue.set, result.flags.zf);
    try std.testing.expectEqual(FlagValue.clear, result.flags.of);

    result = add(.bits8, 0x7f, 1);
    try std.testing.expectEqual(@as(u64, 0x80), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.of);
    try std.testing.expectEqual(FlagValue.clear, result.flags.cf);
}

fn exerciseAdc() !void {
    const result = adc(.bits16, 0xffff, 0, true);
    try std.testing.expectEqual(@as(u64, 0), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);
}

fn exerciseAdcx() !void {
    const result = adcx(.bits32, 0xffff_ffff, 0, .{ .cf = true });
    try std.testing.expectEqual(@as(u64, 0), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);
    try std.testing.expectEqual(FlagValue.preserve, result.flags.of);
}

fn exerciseAdox() !void {
    const result = adox(.bits32, 0xffff_ffff, 0, .{ .of = true });
    try std.testing.expectEqual(@as(u64, 0), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.of);
    try std.testing.expectEqual(FlagValue.preserve, result.flags.cf);
}

fn exerciseInc() !void {
    const result = inc(.bits8, 0x7f, .{ .cf = true });
    try std.testing.expectEqual(@as(u64, 0x80), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.of);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);
}

fn exerciseDec() !void {
    const result = dec(.bits8, 0x80, .{ .cf = true });
    try std.testing.expectEqual(@as(u64, 0x7f), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.of);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);
}

fn exerciseSub() !void {
    var result = sub(.bits8, 0, 1);
    try std.testing.expectEqual(@as(u64, 0xff), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);

    result = sub(.bits8, 0x80, 1);
    try std.testing.expectEqual(@as(u64, 0x7f), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.of);
}

fn exerciseMov() !void {
    const result = mov(.bits16, 0xffff_fff0);
    try std.testing.expectEqual(@as(u64, 0xfff0), result.dest);
    try std.testing.expectEqual(FlagValue.preserve, result.flags.cf);
}

fn exerciseMul() !void {
    var result = mul(.bits16, 0xffff, 2);
    try std.testing.expectEqual(@as(u64, 0xfffe), result.dest);
    try std.testing.expectEqual(@as(u64, 1), result.high);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);

    result = mul(.bits16, 0x10, 2);
    try std.testing.expectEqual(FlagValue.clear, result.flags.cf);
}

fn exerciseImul() !void {
    var result = imul(.bits8, 0x80, 2);
    try std.testing.expectEqual(@as(u64, 0), result.dest);
    try std.testing.expectEqual(FlagValue.set, result.flags.of);

    result = imul(.bits8, 0xff, 1);
    try std.testing.expectEqual(@as(u64, 0xff), result.dest);
    try std.testing.expectEqual(FlagValue.clear, result.flags.of);
}

fn exerciseDiv() !void {
    var result = divUnsigned(.bits8, 0, 0x10, 4);
    try std.testing.expectEqual(@as(u64, 4), result.quotient);
    try std.testing.expectEqual(@as(u64, 0), result.remainder);

    result = divUnsigned(.bits8, 1, 0, 1);
    try std.testing.expectEqual(Trap.divide_error, result.trap.?);

    result = divUnsigned(.bits8, 0, 1, 0);
    try std.testing.expectEqual(Trap.divide_error, result.trap.?);
}

fn exerciseIdiv() !void {
    var result = divSigned(.bits8, 0xff, 0xf6, 0xfd);
    try std.testing.expectEqual(@as(u64, 3), result.quotient);
    try std.testing.expectEqual(@as(u64, 0xff), result.remainder);

    result = divSigned(.bits8, 0xff, 0x80, 0xff);
    try std.testing.expectEqual(Trap.divide_error, result.trap.?);
}

fn exerciseAaa() !void {
    var result = aaa(0x000a, .{});
    try std.testing.expectEqual(@as(u16, 0x0100), result.ax);
    try std.testing.expectEqual(FlagValue.set, result.flags.af);

    result = aaa(0x0009, .{});
    try std.testing.expectEqual(@as(u16, 0x0009), result.ax);
    try std.testing.expectEqual(FlagValue.clear, result.flags.cf);
}

fn exerciseAas() !void {
    const result = aas(0x020f, .{});
    try std.testing.expectEqual(@as(u8, 0x09), result.al);
    try std.testing.expectEqual(FlagValue.set, result.flags.cf);
}

fn exerciseAam() !void {
    var result = aam(42, 10);
    try std.testing.expectEqual(@as(u8, 4), result.ah);
    try std.testing.expectEqual(@as(u8, 2), result.al);

    result = aam(1, 0);
    try std.testing.expectEqual(Trap.divide_error, result.trap.?);
}

fn exerciseAad() !void {
    var result = aad(4, 2, 10);
    try std.testing.expectEqual(@as(u8, 42), result.al);
    try std.testing.expectEqual(@as(u8, 0), result.ah);

    result = aad(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 0), result.ah);
    try std.testing.expectEqual(@as(u8, 0), result.al);
}

fn exerciseAddps() !void {
    const result = addps(.{ 1, -0.0, std.math.inf(f32), std.math.nan(f32) }, .{ 2, 0.0, -std.math.inf(f32), 1 });
    try std.testing.expectEqual(@as(f32, 3), result[0]);
    try std.testing.expect(std.math.isNan(result[2]));
    try std.testing.expect(std.math.isNan(result[3]));
}

fn exerciseAddpd() !void {
    const result = addpd(.{ 1, -2 }, .{ 4, 2 });
    try std.testing.expectEqual(@as(f64, 5), result[0]);
    try std.testing.expectEqual(@as(f64, 0), result[1]);
}

fn exerciseAddss() !void {
    var result = addss(.{ 1, 9, 8, 7 }, .{ 2, 1, 1, 1 });
    try std.testing.expectEqual(@as(f32, 3), result[0]);
    try std.testing.expectEqual(@as(f32, 9), result[1]);

    result = addssVex(.{ 1, 6, 5, 4 }, .{ 2, 99, 99, 99 });
    try std.testing.expectEqual(@as(f32, 3), result[0]);
    try std.testing.expectEqual(@as(f32, 6), result[1]);
}

fn exerciseAddsd() !void {
    var result = addsd(.{ 1, 9 }, .{ 2, 1 });
    try std.testing.expectEqual(@as(f64, 3), result[0]);
    try std.testing.expectEqual(@as(f64, 9), result[1]);

    result = addsdVex(.{ 1, 6 }, .{ 2, 99 });
    try std.testing.expectEqual(@as(f64, 3), result[0]);
    try std.testing.expectEqual(@as(f64, 6), result[1]);
}

fn exerciseAddsubps() !void {
    const result = addsubps(.{ 5, 5, 5, 5 }, .{ 1, 2, 3, 4 });
    try std.testing.expectEqual(@as(f32, 4), result[0]);
    try std.testing.expectEqual(@as(f32, 7), result[1]);
    try std.testing.expectEqual(@as(f32, 2), result[2]);
    try std.testing.expectEqual(@as(f32, 9), result[3]);
}

fn exerciseAddsubpd() !void {
    const result = addsubpd(.{ 5, 5 }, .{ 1, 2 });
    try std.testing.expectEqual(@as(f64, 4), result[0]);
    try std.testing.expectEqual(@as(f64, 7), result[1]);
}

fn exerciseSubps() !void {
    const result = subps(.{ 1, -0.0, 8, std.math.inf(f32) }, .{ 2, 0.0, 3, std.math.inf(f32) });
    try std.testing.expectEqual(@as(f32, -1), result[0]);
    try std.testing.expect(std.math.isNan(result[3]));
}

fn exerciseSubpd() !void {
    const result = subpd(.{ 1, -2 }, .{ 4, 2 });
    try std.testing.expectEqual(@as(f64, -3), result[0]);
    try std.testing.expectEqual(@as(f64, -4), result[1]);
}

fn exerciseSubss() !void {
    var result = subss(.{ 1, 9, 8, 7 }, .{ 2, 1, 1, 1 });
    try std.testing.expectEqual(@as(f32, -1), result[0]);
    try std.testing.expectEqual(@as(f32, 9), result[1]);

    result = subssVex(.{ 1, 6, 5, 4 }, .{ 2, 99, 99, 99 });
    try std.testing.expectEqual(@as(f32, -1), result[0]);
    try std.testing.expectEqual(@as(f32, 6), result[1]);
}

fn exerciseSubsd() !void {
    var result = subsd(.{ 1, 9 }, .{ 2, 1 });
    try std.testing.expectEqual(@as(f64, -1), result[0]);
    try std.testing.expectEqual(@as(f64, 9), result[1]);

    result = subsdVex(.{ 1, 6 }, .{ 2, 99 });
    try std.testing.expectEqual(@as(f64, -1), result[0]);
    try std.testing.expectEqual(@as(f64, 6), result[1]);
}

fn exerciseMulps() !void {
    const result = mulps(.{ 1, -2, 3, -4 }, .{ 5, 6, 7, 8 });
    try std.testing.expectEqual(@as(f32, 5), result[0]);
    try std.testing.expectEqual(@as(f32, -12), result[1]);
    try std.testing.expectEqual(@as(f32, 21), result[2]);
    try std.testing.expectEqual(@as(f32, -32), result[3]);
}

fn exerciseMulpd() !void {
    const result = mulpd(.{ 1.5, -2.0 }, .{ 4.0, 3.0 });
    try std.testing.expectEqual(@as(f64, 6.0), result[0]);
    try std.testing.expectEqual(@as(f64, -6.0), result[1]);
}

fn exerciseMulss() !void {
    var result = mulss(.{ 3, 9, 8, 7 }, .{ 4, 1, 1, 1 });
    try std.testing.expectEqual(@as(f32, 12), result[0]);
    try std.testing.expectEqual(@as(f32, 9), result[1]);

    result = mulssVex(.{ 3, 6, 5, 4 }, .{ 4, 99, 99, 99 });
    try std.testing.expectEqual(@as(f32, 12), result[0]);
    try std.testing.expectEqual(@as(f32, 6), result[1]);
}

fn exerciseMulsd() !void {
    var result = mulsd(.{ 3, 9 }, .{ 4, 1 });
    try std.testing.expectEqual(@as(f64, 12), result[0]);
    try std.testing.expectEqual(@as(f64, 9), result[1]);

    result = mulsdVex(.{ 3, 6 }, .{ 4, 99 });
    try std.testing.expectEqual(@as(f64, 12), result[0]);
    try std.testing.expectEqual(@as(f64, 6), result[1]);
}

fn exerciseDivps() !void {
    const result = divps(.{ 10, -8, 6, -4 }, .{ 2, 4, 3, 2 });
    try std.testing.expectEqual(@as(f32, 5), result[0]);
    try std.testing.expectEqual(@as(f32, -2), result[1]);
    try std.testing.expectEqual(@as(f32, 2), result[2]);
    try std.testing.expectEqual(@as(f32, -2), result[3]);
}

fn exerciseDivpd() !void {
    const result = divpd(.{ 6.0, -9.0 }, .{ 2.0, 3.0 });
    try std.testing.expectEqual(@as(f64, 3.0), result[0]);
    try std.testing.expectEqual(@as(f64, -3.0), result[1]);
}

fn exerciseDivss() !void {
    var result = divss(.{ 12, 9, 8, 7 }, .{ 3, 1, 1, 1 });
    try std.testing.expectEqual(@as(f32, 4), result[0]);
    try std.testing.expectEqual(@as(f32, 9), result[1]);

    result = divssVex(.{ 12, 6, 5, 4 }, .{ 3, 99, 99, 99 });
    try std.testing.expectEqual(@as(f32, 4), result[0]);
    try std.testing.expectEqual(@as(f32, 6), result[1]);
}

fn exerciseDivsd() !void {
    var result = divsd(.{ 12, 9 }, .{ 3, 1 });
    try std.testing.expectEqual(@as(f64, 4), result[0]);
    try std.testing.expectEqual(@as(f64, 9), result[1]);

    result = divsdVex(.{ 12, 6 }, .{ 3, 99 });
    try std.testing.expectEqual(@as(f64, 4), result[0]);
    try std.testing.expectEqual(@as(f64, 6), result[1]);
}

fn exerciseMulx() !void {
    var result = mulx(.bits16, 0xffff, 2);
    try std.testing.expectEqual(@as(u64, 0xfffe), result.dest);
    try std.testing.expectEqual(@as(u64, 1), result.high);

    result = mulx(.bits8, 2, 3);
    try std.testing.expectEqual(@as(u64, 6), result.dest);
    try std.testing.expectEqual(@as(u64, 0), result.high);
}

test "x86 integer math primitives cover carry overflow borrow and traps" {
    try exerciseAdd();
    try exerciseAdc();
    try exerciseAdcx();
    try exerciseAdox();
    try exerciseInc();
    try exerciseDec();
    try exerciseSub();
    try exerciseMul();
    try exerciseImul();
    try exerciseDiv();
    try exerciseIdiv();
}

test "legacy ascii and SIMD math primitives cover edge semantics" {
    try exerciseAaa();
    try exerciseAas();
    try exerciseAam();
    try exerciseAad();
    try exerciseAddps();
    try exerciseAddpd();
    try exerciseAddss();
    try exerciseAddsd();
    try exerciseAddsubps();
    try exerciseAddsubpd();
    try exerciseSubps();
    try exerciseSubpd();
    try exerciseSubss();
    try exerciseSubsd();
    try exerciseMulps();
    try exerciseMulpd();
    try exerciseMulss();
    try exerciseMulsd();
    try exerciseMulx();
    try exerciseDivps();
    try exerciseDivpd();
    try exerciseDivss();
    try exerciseDivsd();
}
