const std = @import("std");

pub const RFL_CF: u32 = 1 << 0;
pub const RFL_PF: u32 = 1 << 2;
pub const RFL_AF: u32 = 1 << 4;
pub const RFL_ZF: u32 = 1 << 6;
pub const RFL_SF: u32 = 1 << 7;
pub const RFL_OF: u32 = 1 << 11;

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
    setOrClear(rflags, RFL_SF, (r & sign) != 0);
    setOrClear(rflags, RFL_ZF, r == 0);
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
    setOrClear(rflags, RFL_SF, (r & sign) != 0);
    setOrClear(rflags, RFL_ZF, r == 0);
}

pub fn applyAdd(rflags: *u32, a: u64, b: u64, result: u64, size: OperandSize) void {
    const mask = maskForSize(size);
    const sign = signBitForSize(size);
    const a_masked = a & mask;
    const b_masked = b & mask;
    const r = result & mask;

    setOrClear(rflags, RFL_CF, @as(u128, a_masked) + @as(u128, b_masked) > @as(u128, mask));
    setOrClear(rflags, RFL_OF, ((~(a_masked ^ b_masked)) & (a_masked ^ r) & sign) != 0);
    setOrClear(rflags, RFL_SF, (r & sign) != 0);
    setOrClear(rflags, RFL_ZF, r == 0);
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
    setOrClear(rflags, RFL_SF, (r & sign) != 0);
    setOrClear(rflags, RFL_ZF, r == 0);
}

pub fn applyLogic(rflags: *u32, result: u64, size: OperandSize) void {
    const mask = maskForSize(size);
    const sign = signBitForSize(size);
    const r = result & mask;

    setOrClear(rflags, RFL_CF, false);
    setOrClear(rflags, RFL_OF, false);
    setOrClear(rflags, RFL_SF, (r & sign) != 0);
    setOrClear(rflags, RFL_ZF, r == 0);
}

pub fn evalCond(rflags: u32, cond: Condition) bool {
    const sf = (rflags & RFL_SF) != 0;
    const zf = (rflags & RFL_ZF) != 0;
    const of = (rflags & RFL_OF) != 0;
    const cf = (rflags & RFL_CF) != 0;
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
        .p => false,
        .np => true,
        .l => sf != of,
        .ge => sf == of,
        .le => zf or (sf != of),
        .g => !zf and (sf == of),
    };
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
