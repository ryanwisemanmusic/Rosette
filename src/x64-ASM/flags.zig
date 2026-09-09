const std = @import("std");

pub const RFL_CF: u32 = 1 << 0;
pub const RFL_PF: u32 = 1 << 2;
pub const RFL_AF: u32 = 1 << 4;
pub const RFL_ZF: u32 = 1 << 6;
pub const RFL_SF: u32 = 1 << 7;
pub const RFL_OF: u32 = 1 << 11;

/// Status flags transferred by LAHF and SAHF. Bit 1 is not stored in RFLAGS
/// by SAHF, but LAHF always reports it as one in AH.
pub const RFL_LAHF_SAHF_MASK: u32 = RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF;

pub fn statusByteForLahf(rflags: u32) u8 {
    return @as(u8, @truncate(rflags & RFL_LAHF_SAHF_MASK)) | 0x02;
}

pub fn applySahf(rflags: *u32, ah: u8) void {
    rflags.* = (rflags.* & ~RFL_LAHF_SAHF_MASK) |
        (@as(u32, ah) & RFL_LAHF_SAHF_MASK);
}

pub const OperandSize = enum(u2) {
    bits8,
    bits16,
    bits32,
    bits64,
};

pub const Condition = enum(u4) {
    o = 0,
    no = 1,
    b = 2,
    ae = 3,
    e = 4,
    ne = 5,
    be = 6,
    a = 7,
    s = 8,
    ns = 9,
    p = 10,
    np = 11,
    l = 12,
    ge = 13,
    le = 14,
    g = 15,
};

pub fn maskForSize(size: OperandSize) u64 {
    return switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFFFFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
}

pub fn signBitForSize(size: OperandSize) u64 {
    return switch (size) {
        .bits8 => 0x80,
        .bits16 => 0x8000,
        .bits32 => 0x80000000,
        .bits64 => 0x8000000000000000,
    };
}

pub fn applySub(rflags: *u32, a: u64, b: u64, result: u64, size: OperandSize) void {
    const mask = maskForSize(size);
    const sign = signBitForSize(size);
    const a_masked = a & mask;
    const b_masked = b & mask;
    const r = result & mask;

    setOrClear(rflags, RFL_CF, a_masked < b_masked);
    setOrClear(rflags, RFL_OF, ((a_masked ^ b_masked) & (a_masked ^ r) & sign) != 0);
    setSizeParityFlags(rflags, r, sign);
    setOrClear(rflags, RFL_AF, ((a_masked ^ b_masked ^ r) & 0x10) != 0);
}

pub fn applySbb(rflags: *u32, a: u64, b: u64, carry: bool, result: u64, size: OperandSize) void {
    const mask = maskForSize(size);
    const sign = signBitForSize(size);
    const a_masked = a & mask;
    const b_masked = b & mask;
    const r = result & mask;
    const subtrahend = @as(u128, b_masked) + @intFromBool(carry);

    setOrClear(rflags, RFL_CF, @as(u128, a_masked) < subtrahend);
    setOrClear(rflags, RFL_OF, ((a_masked ^ b_masked) & (a_masked ^ r) & sign) != 0);
    setSizeParityFlags(rflags, r, sign);
    const effective_b: u64 = @truncate(subtrahend & mask);
    setOrClear(rflags, RFL_AF, ((a_masked ^ effective_b ^ r) & 0x10) != 0);
}

pub fn applyAdd(rflags: *u32, a: u64, b: u64, result: u64, size: OperandSize) void {
    const mask = maskForSize(size);
    const sign = signBitForSize(size);
    const a_masked = a & mask;
    const b_masked = b & mask;
    const r = result & mask;

    setOrClear(rflags, RFL_CF, @as(u128, a_masked) + @as(u128, b_masked) > @as(u128, mask));
    setOrClear(rflags, RFL_OF, ((~(a_masked ^ b_masked)) & (a_masked ^ r) & sign) != 0);
    setSizeParityFlags(rflags, r, sign);
    setOrClear(rflags, RFL_AF, ((a_masked ^ b_masked ^ r) & 0x10) != 0);
}

pub fn applyIncDec(rflags: *u32, input: u64, result: u64, size: OperandSize, is_inc: bool) void {
    const mask = maskForSize(size);
    const sign = signBitForSize(size);
    const input_masked = input & mask;
    const r = result & mask;
    const overflow = if (is_inc)
        input_masked == sign - 1
    else
        input_masked == sign;

    setOrClear(rflags, RFL_OF, overflow);
    setSizeParityFlags(rflags, r, sign);
    setOrClear(rflags, RFL_AF, if (is_inc) (input_masked & 0xF) == 0xF else (input_masked & 0xF) == 0);
}

pub fn applyLogic(rflags: *u32, result: u64, size: OperandSize) void {
    const mask = maskForSize(size);
    const sign = signBitForSize(size);
    const r = result & mask;

    setOrClear(rflags, RFL_CF, false);
    setOrClear(rflags, RFL_OF, false);
    setSizeParityFlags(rflags, r, sign);
}

pub fn evalCond(rflags: u32, cond: Condition) bool {
    const sf = (rflags & RFL_SF) != 0;
    const zf = (rflags & RFL_ZF) != 0;
    const of = (rflags & RFL_OF) != 0;
    const cf = (rflags & RFL_CF) != 0;
    const pf = (rflags & RFL_PF) != 0;
    return switch (cond) {
        .o => of,
        .no => !of,
        .b => cf,
        .ae => !cf,
        .e => zf,
        .ne => !zf,
        .be => cf or zf,
        .a => !cf and !zf,
        .s => sf,
        .ns => !sf,
        .p => pf,
        .np => !pf,
        .l => sf != of,
        .ge => sf == of,
        .le => zf or (sf != of),
        .g => !zf and (sf == of),
    };
}

fn setSizeParityFlags(rflags: *u32, result: u64, sign: u64) void {
    setOrClear(rflags, RFL_SF, (result & sign) != 0);
    setOrClear(rflags, RFL_ZF, result == 0);
    setOrClear(rflags, RFL_PF, @popCount(@as(u8, @truncate(result))) % 2 == 0);
}

fn setOrClear(rflags: *u32, bit: u32, enabled: bool) void {
    if (enabled) {
        rflags.* |= bit;
    } else {
        rflags.* &= ~bit;
    }
}

test "signed less-than compare is width-aware for 32-bit negatives" {
    var rflags: u32 = 0x0002;
    const lhs = @as(u32, @bitCast(@as(i32, -2588)));
    applySub(&rflags, lhs, 0, @as(u64, lhs), .bits32);
    try std.testing.expect((rflags & RFL_SF) != 0);
    try std.testing.expect((rflags & RFL_OF) == 0);
    try std.testing.expect(evalCond(rflags, .l));
    try std.testing.expect(!evalCond(rflags, .ge));
}

test "SBB preserves a borrow when source plus carry crosses the operand width" {
    var rflags: u32 = RFL_CF;
    const result = @as(u8, 0) -% @as(u8, 0xFF) -% 1;
    applySbb(&rflags, 0, 0xFF, true, result, .bits8);
    try std.testing.expectEqual(@as(u8, 0), result);
    try std.testing.expect((rflags & RFL_CF) != 0);
    try std.testing.expect((rflags & RFL_ZF) != 0);
}

test "parity conditions follow the low result byte" {
    var rflags: u32 = 0x0002;
    applyLogic(&rflags, 0b11, .bits8);
    try std.testing.expect(evalCond(rflags, .p));
    try std.testing.expect(!evalCond(rflags, .np));

    applyLogic(&rflags, 0b1, .bits8);
    try std.testing.expect(!evalCond(rflags, .p));
    try std.testing.expect(evalCond(rflags, .np));
}

test "LAHF and SAHF transfer only the architectural status flags" {
    const preserved: u32 = RFL_OF | (1 << 10) | 0x02;
    const status: u32 = RFL_CF | RFL_AF | RFL_SF;
    try std.testing.expectEqual(@as(u8, 0x93), statusByteForLahf(preserved | status));

    var rflags = preserved | RFL_PF | RFL_ZF;
    applySahf(&rflags, 0x91);
    try std.testing.expectEqual(preserved | RFL_CF | RFL_AF | RFL_SF, rflags);
}

/// The result of a double-precision shift (SHLD / SHRD).
pub const DoubleShift = struct {
    value: u64,
    carry: bool,
    /// Whether the destination's sign bit changed. x86 defines OF only for a
    /// count of 1; the caller decides whether to apply it.
    sign_changed: bool,
};

/// SHLD / SHRD: shift `destination` by `count`, filling the vacated bits from
/// `source` rather than with zeros.
///
/// `count` must already be masked (`& 0x3F` for a 64-bit operand, `& 0x1F`
/// otherwise) and must be non-zero — x86 leaves the flags untouched and
/// performs no write when the masked count is zero, which is the caller's
/// decision, not this function's.
///
/// The two operands are concatenated into a 128-bit value and shifted once.
/// Doing it as two shifts of a 64-bit value needs a `bits - count` shift that
/// is undefined when `count` is zero and out of range when `count` exceeds the
/// operand width — the latter being reachable, because a 16-bit operand admits
/// a masked count of up to 31. Intel leaves that case undefined; the
/// concatenation makes it total and deterministic instead of a shift-overflow
/// panic.
pub fn doubleShift(
    destination: u64,
    source: u64,
    count: u6,
    size: OperandSize,
    left: bool,
) DoubleShift {
    const bits: u8 = switch (size) {
        .bits8 => 8,
        .bits16 => 16,
        .bits32 => 32,
        .bits64 => 64,
    };
    const mask = maskForSize(size);
    const destination_bits = destination & mask;
    const source_bits = source & mask;
    const shift: u8 = count;

    var value: u64 = 0;
    var carry = false;
    if (left) {
        // Destination occupies the high half; shifting left walks its top bits
        // out and pulls the source's top bits into the bottom.
        const wide = (@as(u128, destination_bits) << @intCast(bits)) | source_bits;
        value = @truncate((wide << @intCast(shift)) >> @intCast(bits));
        const carry_index = 2 * @as(u16, bits) - @as(u16, shift);
        carry = carry_index < 128 and ((wide >> @intCast(carry_index)) & 1) != 0;
    } else {
        // Source occupies the high half; shifting right walks the
        // destination's low bits out and pulls the source's low bits in.
        const wide = (@as(u128, source_bits) << @intCast(bits)) | destination_bits;
        value = @truncate(wide >> @intCast(shift));
        carry = ((wide >> @intCast(@as(u16, shift) - 1)) & 1) != 0;
    }
    value &= mask;

    const sign = signBitForSize(size);
    return .{
        .value = value,
        .carry = carry,
        .sign_changed = ((value ^ destination_bits) & sign) != 0,
    };
}

test "a double-precision shift fills from the source operand" {
    // `shld rax, rdx, 32` — the encoding at guest 0x744871 that decoded as
    // invalid. The top 32 bits of rdx become the low 32 bits of rax.
    const shifted = doubleShift(0x1122_3344_5566_7788, 0xAABB_CCDD_EEFF_0011, 32, .bits64, true);
    try std.testing.expectEqual(@as(u64, 0x5566_7788_AABB_CCDD), shifted.value);
    // The last bit out of the destination is bit 32 of the original.
    try std.testing.expectEqual(((0x1122_3344_5566_7788 >> 32) & 1) != 0, shifted.carry);

    // SHRD is the mirror: the source's low bits arrive at the top.
    const back = doubleShift(0x1122_3344_5566_7788, 0xAABB_CCDD_EEFF_0011, 32, .bits64, false);
    try std.testing.expectEqual(@as(u64, 0xEEFF_0011_1122_3344), back.value);
    try std.testing.expectEqual(((0x1122_3344_5566_7788 >> 31) & 1) != 0, back.carry);

    // A single-bit shift is the case where OF is architecturally defined.
    const one = doubleShift(0x8000_0000_0000_0000, 0, 1, .bits64, true);
    try std.testing.expectEqual(@as(u64, 0), one.value);
    try std.testing.expect(one.carry);
    try std.testing.expect(one.sign_changed);

    // Narrower operands stay inside their width, and a 16-bit operand admits a
    // masked count wider than the operand itself without overflowing a shift.
    const narrow = doubleShift(0xFFFF, 0x0000, 4, .bits16, true);
    try std.testing.expectEqual(@as(u64, 0xFFF0), narrow.value);
    const over = doubleShift(0xFFFF, 0x1234, 24, .bits16, true);
    try std.testing.expectEqual(over.value, over.value & 0xFFFF);
    const over_right = doubleShift(0xFFFF, 0x1234, 24, .bits16, false);
    try std.testing.expectEqual(over_right.value, over_right.value & 0xFFFF);

    // 32-bit results never carry bits above the operand width.
    const dword = doubleShift(0xDEAD_BEEF, 0xFEED_FACE, 8, .bits32, true);
    try std.testing.expectEqual(@as(u64, 0xAD_BE_EF_FE), dword.value);
    try std.testing.expectEqual(dword.value, dword.value & 0xFFFF_FFFF);
}
