//! PowerPC integer, logical, shift, rotate, and compare execution.
//!
//! The Xenon is a 64-bit core, so `add` is a 64-bit add and only the
//! explicitly-32-bit instructions (`mullw`, `divw`, `slw`, `srawi`, `rlwinm`,
//! and the word compares) narrow. Getting that backwards produces results that
//! are right for small values and wrong for large ones - the hardest class of
//! bug to catch by sampling, so the width is named in every handler.
//!
//! Three side-channel effects run alongside the result and each is produced
//! from the operation rather than inferred from the result:
//!
//!   Rc=1  writes CR0 from a *signed 64-bit* compare of the result against 0
//!   OE=1  writes XER.OV from signed overflow, and latches XER.SO
//!   CA    is the carry out of the addition the instruction actually performed,
//!         which for the subtract family is `~rA + rB + 1`, not `rB - rA`

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");

const Context = ctx_mod.Context;
const Outcome = ctx_mod.Outcome;
const Instruction = ctx_mod.Instruction;
const fields = ppc_decode.fields;

/// The result of a 64-bit add with an explicit carry in, keeping both the
/// carry out and the signed overflow that PowerPC reports separately.
const AddResult = struct {
    value: u64,
    carry: bool,
    overflow: bool,
};

fn addWithCarry(a: u64, b: u64, carry_in: u1) AddResult {
    const first = @addWithOverflow(a, b);
    const second = @addWithOverflow(first[0], @as(u64, carry_in));
    const value = second[0];
    const carry = (first[1] | second[1]) != 0;
    // Signed overflow: both inputs share a sign and the result does not.
    const sa = a >> 63;
    const sb = b >> 63;
    const sr = value >> 63;
    const overflow = (sa == sb) and (sr != sa);
    return .{ .value = value, .carry = carry, .overflow = overflow };
}

/// Apply the Rc/OE side effects a computed result carries.
fn finish(c: *Context, insn: Instruction, rd: u5, result: AddResult, sets_carry: bool) void {
    c.setGpr(rd, result.value);
    if (sets_carry) c.state.xer.ca = result.carry;
    if (insn.oe()) c.state.xer.recordOverflow(result.overflow);
    c.recordCr0(insn, result.value);
}

pub fn execute(c: *Context, insn: Instruction) Outcome {
    return switch (insn.op) {
        // -- add family (XO/D forms) --------------------------------------
        .addx => arith(c, insn, .add, false),
        .addcx => arith(c, insn, .add, true),
        .addex => addExtended(c, insn, .register),
        .addmex => addExtended(c, insn, .minus_one),
        .addzex => addExtended(c, insn, .zero),
        .addi => addImmediate(c, insn, 0, false, false),
        .addis => addImmediate(c, insn, 16, false, false),
        .addic => addImmediate(c, insn, 0, true, false),
        .addicx => addImmediate(c, insn, 0, true, true),

        // -- subtract family ----------------------------------------------
        .subfx => arith(c, insn, .subtract, false),
        .subfcx => arith(c, insn, .subtract, true),
        .subfex => subtractExtended(c, insn, .register),
        .subfmex => subtractExtended(c, insn, .minus_one),
        .subfzex => subtractExtended(c, insn, .zero),
        .subficx => subtractImmediate(c, insn),
        .negx => negate(c, insn),

        // -- multiply and divide ------------------------------------------
        .mullwx => multiplyLowWord(c, insn),
        .mulldx => multiplyLowDouble(c, insn),
        .mulhwx => multiplyHighWord(c, insn, true),
        .mulhwux => multiplyHighWord(c, insn, false),
        .mulhdx => multiplyHighDouble(c, insn, true),
        .mulhdux => multiplyHighDouble(c, insn, false),
        .mulli => multiplyImmediate(c, insn),
        .divwx => divideWord(c, insn, true),
        .divwux => divideWord(c, insn, false),
        .divdx => divideDouble(c, insn, true),
        .divdux => divideDouble(c, insn, false),

        // -- logical -------------------------------------------------------
        .andx => logical(c, insn, .andop),
        .andcx => logical(c, insn, .andc),
        .orx => logical(c, insn, .orop),
        .orcx => logical(c, insn, .orc),
        .xorx => logical(c, insn, .xorop),
        .nandx => logical(c, insn, .nand),
        .norx => logical(c, insn, .nor),
        .eqvx => logical(c, insn, .eqv),
        .andix => logicalImmediate(c, insn, .andop, 0, true),
        .andisx => logicalImmediate(c, insn, .andop, 16, true),
        .ori => logicalImmediate(c, insn, .orop, 0, false),
        .oris => logicalImmediate(c, insn, .orop, 16, false),
        .xori => logicalImmediate(c, insn, .xorop, 0, false),
        .xoris => logicalImmediate(c, insn, .xorop, 16, false),

        // -- extend and count ----------------------------------------------
        .extsbx => extend(c, insn, 8),
        .extshx => extend(c, insn, 16),
        .extswx => extend(c, insn, 32),
        .cntlzwx => countLeadingZeros(c, insn, 32),
        .cntlzdx => countLeadingZeros(c, insn, 64),

        // -- shift ----------------------------------------------------------
        .slwx => shiftWordLeft(c, insn),
        .srwx => shiftWordRight(c, insn),
        .srawx => shiftWordArithmetic(c, insn),
        .srawix => shiftWordArithmeticImmediate(c, insn),
        .sldx => shiftDoubleLeft(c, insn),
        .srdx => shiftDoubleRight(c, insn),
        .sradx => shiftDoubleArithmetic(c, insn),
        .sradix => shiftDoubleArithmeticImmediate(c, insn),

        // -- rotate ---------------------------------------------------------
        .rlwinmx => rotateWordImmediate(c, insn),
        .rlwnmx => rotateWordRegister(c, insn),
        .rlwimix => rotateWordInsert(c, insn),
        .rldiclx => rotateDoubleClearLeft(c, insn),
        .rldicrx => rotateDoubleClearRight(c, insn),
        .rldicx => rotateDoubleClear(c, insn),
        .rldimix => rotateDoubleInsert(c, insn),
        .rldclx => rotateDoubleClearLeftRegister(c, insn),
        .rldcrx => rotateDoubleClearRightRegister(c, insn),

        // -- compare --------------------------------------------------------
        .cmp => compare(c, insn, true),
        .cmpl => compare(c, insn, false),
        .cmpi => compareImmediate(c, insn, true),
        .cmpli => compareImmediate(c, insn, false),

        else => .{ .unimplemented = insn.op },
    };
}

// ---------------------------------------------------------------------------
// Add / subtract
// ---------------------------------------------------------------------------

const ArithKind = enum { add, subtract };

fn arith(c: *Context, insn: Instruction, comptime kind: ArithKind, sets_carry: bool) Outcome {
    const f = insn.xo();
    const a = c.gpr(f.ra());
    const b = c.gpr(f.rb());
    // The subtract family is defined as `~rA + rB + 1`, and its carry out is
    // the carry out of *that* addition. Computing `b - a` instead gives the
    // right difference and the wrong XER.CA.
    const result = switch (kind) {
        .add => addWithCarry(a, b, 0),
        .subtract => addWithCarry(~a, b, 1),
    };
    finish(c, insn, f.rd(), result, sets_carry);
    return .advance;
}

const ExtendSource = enum { register, zero, minus_one };

fn addExtended(c: *Context, insn: Instruction, comptime source: ExtendSource) Outcome {
    const f = insn.xo();
    const a = c.gpr(f.ra());
    const b: u64 = switch (source) {
        .register => c.gpr(f.rb()),
        .zero => 0,
        .minus_one => std.math.maxInt(u64),
    };
    const result = addWithCarry(a, b, @intFromBool(c.state.xer.ca));
    finish(c, insn, f.rd(), result, true);
    return .advance;
}

fn subtractExtended(c: *Context, insn: Instruction, comptime source: ExtendSource) Outcome {
    const f = insn.xo();
    const a = c.gpr(f.ra());
    const b: u64 = switch (source) {
        .register => c.gpr(f.rb()),
        .zero => 0,
        .minus_one => std.math.maxInt(u64),
    };
    const result = addWithCarry(~a, b, @intFromBool(c.state.xer.ca));
    finish(c, insn, f.rd(), result, true);
    return .advance;
}

fn addImmediate(
    c: *Context,
    insn: Instruction,
    comptime shift: u6,
    sets_carry: bool,
    records: bool,
) Outcome {
    const f = insn.d();
    const imm: u64 = @bitCast(f.simm() << shift);
    // addi/addis read rA as literal zero when rA==0: that is how `li` and
    // `lis` are spelled. addic and addic. do not - they always read r0.
    const base = if (shift != 0 or !sets_carry) c.state.ra0(f.ra()) else c.gpr(f.ra());
    const result = addWithCarry(base, imm, 0);
    c.setGpr(f.rd(), result.value);
    if (sets_carry) c.state.xer.ca = result.carry;
    if (records) c.state.updateCr0(result.value);
    return .advance;
}

fn subtractImmediate(c: *Context, insn: Instruction) Outcome {
    const f = insn.d();
    const a = c.gpr(f.ra());
    const imm: u64 = @bitCast(f.simm());
    const result = addWithCarry(~a, imm, 1);
    c.setGpr(f.rd(), result.value);
    c.state.xer.ca = result.carry;
    return .advance;
}

fn negate(c: *Context, insn: Instruction) Outcome {
    const f = insn.xo();
    const a = c.gpr(f.ra());
    const value = ~a +% 1;
    c.setGpr(f.rd(), value);
    // The one negation that overflows is INT64_MIN, which negates to itself.
    if (insn.oe()) c.state.xer.recordOverflow(a == @as(u64, 1) << 63);
    c.recordCr0(insn, value);
    return .advance;
}

// ---------------------------------------------------------------------------
// Multiply / divide
// ---------------------------------------------------------------------------

fn multiplyLowWord(c: *Context, insn: Instruction) Outcome {
    const f = insn.xo();
    const a: i64 = @as(i32, @truncate(@as(i64, @bitCast(c.gpr(f.ra())))));
    const b: i64 = @as(i32, @truncate(@as(i64, @bitCast(c.gpr(f.rb())))));
    // mullw is the full 64-bit product of the two low words, not a 32-bit one.
    const product = a *% b;
    const value: u64 = @bitCast(product);
    c.setGpr(f.rd(), value);
    if (insn.oe()) {
        const fits = product >= std.math.minInt(i32) and product <= std.math.maxInt(i32);
        c.state.xer.recordOverflow(!fits);
    }
    c.recordCr0(insn, value);
    return .advance;
}

fn multiplyLowDouble(c: *Context, insn: Instruction) Outcome {
    const f = insn.xo();
    const a: i64 = @bitCast(c.gpr(f.ra()));
    const b: i64 = @bitCast(c.gpr(f.rb()));
    const value: u64 = @bitCast(a *% b);
    c.setGpr(f.rd(), value);
    if (insn.oe()) {
        const wide = @as(i128, a) * @as(i128, b);
        const fits = wide >= std.math.minInt(i64) and wide <= std.math.maxInt(i64);
        c.state.xer.recordOverflow(!fits);
    }
    c.recordCr0(insn, value);
    return .advance;
}

fn multiplyHighWord(c: *Context, insn: Instruction, comptime signed: bool) Outcome {
    const f = insn.xo();
    const value: u64 = if (signed) blk: {
        const a: i64 = @as(i32, @truncate(@as(i64, @bitCast(c.gpr(f.ra())))));
        const b: i64 = @as(i32, @truncate(@as(i64, @bitCast(c.gpr(f.rb())))));
        break :blk @bitCast((a *% b) >> 32);
    } else blk: {
        const a: u64 = @as(u32, @truncate(c.gpr(f.ra())));
        const b: u64 = @as(u32, @truncate(c.gpr(f.rb())));
        break :blk (a *% b) >> 32;
    };
    c.setGpr(f.rd(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn multiplyHighDouble(c: *Context, insn: Instruction, comptime signed: bool) Outcome {
    const f = insn.xo();
    const value: u64 = if (signed) blk: {
        const a: i128 = @as(i64, @bitCast(c.gpr(f.ra())));
        const b: i128 = @as(i64, @bitCast(c.gpr(f.rb())));
        break :blk @bitCast(@as(i64, @truncate((a * b) >> 64)));
    } else blk: {
        const a: u128 = c.gpr(f.ra());
        const b: u128 = c.gpr(f.rb());
        break :blk @truncate((a * b) >> 64);
    };
    c.setGpr(f.rd(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn multiplyImmediate(c: *Context, insn: Instruction) Outcome {
    const f = insn.d();
    const a: i64 = @bitCast(c.gpr(f.ra()));
    const value: u64 = @bitCast(a *% f.simm());
    c.setGpr(f.rd(), value);
    return .advance;
}

fn divideWord(c: *Context, insn: Instruction, comptime signed: bool) Outcome {
    const f = insn.xo();
    var overflow = false;
    var value: u64 = 0;
    if (signed) {
        const a: i32 = @truncate(@as(i64, @bitCast(c.gpr(f.ra()))));
        const b: i32 = @truncate(@as(i64, @bitCast(c.gpr(f.rb()))));
        // Divide by zero and INT32_MIN/-1 leave rD undefined and set OV. The
        // architecture says undefined; leaving the register untouched would
        // make the result depend on history, so a defined zero is written.
        if (b == 0 or (a == std.math.minInt(i32) and b == -1)) {
            overflow = true;
        } else {
            value = @bitCast(@as(i64, @divTrunc(a, b)));
        }
    } else {
        const a: u32 = @truncate(c.gpr(f.ra()));
        const b: u32 = @truncate(c.gpr(f.rb()));
        if (b == 0) {
            overflow = true;
        } else {
            value = a / b;
        }
    }
    c.setGpr(f.rd(), value);
    if (insn.oe()) c.state.xer.recordOverflow(overflow);
    c.recordCr0(insn, value);
    return .advance;
}

fn divideDouble(c: *Context, insn: Instruction, comptime signed: bool) Outcome {
    const f = insn.xo();
    var overflow = false;
    var value: u64 = 0;
    if (signed) {
        const a: i64 = @bitCast(c.gpr(f.ra()));
        const b: i64 = @bitCast(c.gpr(f.rb()));
        if (b == 0 or (a == std.math.minInt(i64) and b == -1)) {
            overflow = true;
        } else {
            value = @bitCast(@divTrunc(a, b));
        }
    } else {
        const a = c.gpr(f.ra());
        const b = c.gpr(f.rb());
        if (b == 0) {
            overflow = true;
        } else {
            value = a / b;
        }
    }
    c.setGpr(f.rd(), value);
    if (insn.oe()) c.state.xer.recordOverflow(overflow);
    c.recordCr0(insn, value);
    return .advance;
}

// ---------------------------------------------------------------------------
// Logical
// ---------------------------------------------------------------------------

const LogicalKind = enum { andop, andc, orop, orc, xorop, nand, nor, eqv };

fn applyLogical(comptime kind: LogicalKind, s: u64, b: u64) u64 {
    return switch (kind) {
        .andop => s & b,
        .andc => s & ~b,
        .orop => s | b,
        .orc => s | ~b,
        .xorop => s ^ b,
        .nand => ~(s & b),
        .nor => ~(s | b),
        .eqv => ~(s ^ b),
    };
}

fn logical(c: *Context, insn: Instruction, comptime kind: LogicalKind) Outcome {
    const f = insn.x();
    // The logical forms write rA and read rS: the destination is the *second*
    // named register, the reverse of the arithmetic forms.
    const value = applyLogical(kind, c.gpr(f.rs()), c.gpr(f.rb()));
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn logicalImmediate(
    c: *Context,
    insn: Instruction,
    comptime kind: LogicalKind,
    comptime shift: u6,
    records: bool,
) Outcome {
    const f = insn.d();
    const value = applyLogical(kind, c.gpr(f.rs()), f.uimm() << shift);
    c.setGpr(f.ra(), value);
    // andi. and andis. always write CR0; the or/xor immediates never do.
    if (records) c.state.updateCr0(value);
    return .advance;
}

fn extend(c: *Context, insn: Instruction, comptime width: u7) Outcome {
    const f = insn.x();
    const raw = c.gpr(f.rs());
    const shift: u6 = @intCast(64 - width);
    const value: u64 = @bitCast(@as(i64, @bitCast(raw << shift)) >> shift);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn countLeadingZeros(c: *Context, insn: Instruction, comptime width: u7) Outcome {
    const f = insn.x();
    const raw = c.gpr(f.rs());
    const value: u64 = if (width == 32)
        @clz(@as(u32, @truncate(raw)))
    else
        @clz(raw);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

// ---------------------------------------------------------------------------
// Shift
//
// PowerPC shifts take a *six*-bit count for the word forms and a *seven*-bit
// count for the doubleword forms, and a count at or past the width produces
// zero rather than wrapping. ARM64 and C both wrap, so the out-of-range case
// has to be handled before the shift, not after.
// ---------------------------------------------------------------------------

fn shiftWordLeft(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const n = c.gpr(f.rb()) & 0x3F;
    const raw: u64 = @as(u32, @truncate(c.gpr(f.rs())));
    const value: u64 = if (n >= 32) 0 else @as(u32, @truncate(raw << @intCast(n)));
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn shiftWordRight(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const n = c.gpr(f.rb()) & 0x3F;
    const raw: u64 = @as(u32, @truncate(c.gpr(f.rs())));
    const value: u64 = if (n >= 32) 0 else raw >> @intCast(n);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

/// The shared body of sraw/srawi: an arithmetic word shift whose carry-out is
/// "the value was negative and a one bit fell off the right".
fn arithmeticWordShift(c: *Context, insn: Instruction, raw_count: u64, ra: u5, rs: u5) void {
    const source: i32 = @truncate(@as(i64, @bitCast(c.gpr(rs))));
    const count: u5 = if (raw_count >= 32) 31 else @intCast(raw_count);
    const shifted: i32 = source >> count;
    const value: u64 = @bitCast(@as(i64, shifted));
    // Any bit shifted out is a one exactly when re-shifting left loses data.
    const lost = (@as(i32, shifted) << count) != source;
    c.state.xer.ca = source < 0 and lost;
    c.setGpr(ra, value);
    c.recordCr0(insn, value);
}

fn shiftWordArithmetic(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    arithmeticWordShift(c, insn, c.gpr(f.rb()) & 0x3F, f.ra(), f.rs());
    return .advance;
}

fn shiftWordArithmeticImmediate(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    arithmeticWordShift(c, insn, f.sh(), f.ra(), f.rs());
    return .advance;
}

fn shiftDoubleLeft(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const n = c.gpr(f.rb()) & 0x7F;
    const value: u64 = if (n >= 64) 0 else c.gpr(f.rs()) << @intCast(n);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn shiftDoubleRight(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const n = c.gpr(f.rb()) & 0x7F;
    const value: u64 = if (n >= 64) 0 else c.gpr(f.rs()) >> @intCast(n);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn arithmeticDoubleShift(c: *Context, insn: Instruction, raw_count: u64, ra: u5, rs: u5) void {
    const source: i64 = @bitCast(c.gpr(rs));
    const count: u6 = if (raw_count >= 64) 63 else @intCast(raw_count);
    const shifted = source >> count;
    const value: u64 = @bitCast(shifted);
    const lost = (shifted << count) != source;
    c.state.xer.ca = source < 0 and lost;
    c.setGpr(ra, value);
    c.recordCr0(insn, value);
}

fn shiftDoubleArithmetic(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    arithmeticDoubleShift(c, insn, c.gpr(f.rb()) & 0x7F, f.ra(), f.rs());
    return .advance;
}

fn shiftDoubleArithmeticImmediate(c: *Context, insn: Instruction) Outcome {
    const f = insn.xs();
    arithmeticDoubleShift(c, insn, f.sh(), f.ra(), f.rs());
    return .advance;
}

// ---------------------------------------------------------------------------
// Rotate and mask
//
// The word forms rotate the *low 32 bits* and duplicate them into both halves
// before masking, which is what makes `rlwinm rA, rS, 0, 0, 31` a zero-extend
// and `rlwinm rA, rS, n, 0, 31` a 32-bit rotate. Rotating the 64-bit register
// instead silently changes both.
// ---------------------------------------------------------------------------

fn rotl32Duplicated(value: u64, count: u6) u64 {
    const word: u32 = @truncate(value);
    const n: u5 = @intCast(count & 31);
    const rotated: u64 = std.math.rotl(u32, word, n);
    return rotated | (rotated << 32);
}

fn rotl64(value: u64, count: u6) u64 {
    return std.math.rotl(u64, value, count);
}

fn rotateWordImmediate(c: *Context, insn: Instruction) Outcome {
    const f = insn.m();
    const rotated = rotl32Duplicated(c.gpr(f.rs()), f.sh());
    const mask = fields.mask64(@as(u32, f.mb()) + 32, @as(u32, f.me()) + 32);
    const value = rotated & mask;
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateWordRegister(c: *Context, insn: Instruction) Outcome {
    const f = insn.m();
    const count: u6 = @intCast(c.gpr(f.rb()) & 31);
    const rotated = rotl32Duplicated(c.gpr(f.rs()), count);
    const mask = fields.mask64(@as(u32, f.mb()) + 32, @as(u32, f.me()) + 32);
    const value = rotated & mask;
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateWordInsert(c: *Context, insn: Instruction) Outcome {
    const f = insn.m();
    const rotated = rotl32Duplicated(c.gpr(f.rs()), f.sh());
    const mask = fields.mask64(@as(u32, f.mb()) + 32, @as(u32, f.me()) + 32);
    const value = (rotated & mask) | (c.gpr(f.ra()) & ~mask);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateDoubleClearLeft(c: *Context, insn: Instruction) Outcome {
    const f = insn.md();
    const value = rotl64(c.gpr(f.rs()), f.sh()) & fields.mask64(f.mb(), 63);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateDoubleClearRight(c: *Context, insn: Instruction) Outcome {
    const f = insn.md();
    const value = rotl64(c.gpr(f.rs()), f.sh()) & fields.mask64(0, f.me());
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateDoubleClear(c: *Context, insn: Instruction) Outcome {
    const f = insn.md();
    const mask = fields.mask64(f.mb(), 63 - @as(u32, f.sh()));
    const value = rotl64(c.gpr(f.rs()), f.sh()) & mask;
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateDoubleInsert(c: *Context, insn: Instruction) Outcome {
    const f = insn.md();
    const mask = fields.mask64(f.mb(), 63 - @as(u32, f.sh()));
    const rotated = rotl64(c.gpr(f.rs()), f.sh());
    const value = (rotated & mask) | (c.gpr(f.ra()) & ~mask);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateDoubleClearLeftRegister(c: *Context, insn: Instruction) Outcome {
    const f = insn.mds();
    const count: u6 = @intCast(c.gpr(f.rb()) & 63);
    const value = rotl64(c.gpr(f.rs()), count) & fields.mask64(f.mb(), 63);
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

fn rotateDoubleClearRightRegister(c: *Context, insn: Instruction) Outcome {
    const f = insn.mds();
    const count: u6 = @intCast(c.gpr(f.rb()) & 63);
    const value = rotl64(c.gpr(f.rs()), count) & fields.mask64(0, f.me());
    c.setGpr(f.ra(), value);
    c.recordCr0(insn, value);
    return .advance;
}

// ---------------------------------------------------------------------------
// Compare
// ---------------------------------------------------------------------------

fn compare(c: *Context, insn: Instruction, comptime signed: bool) Outcome {
    const f = insn.x();
    // The L bit picks the width. A 32-bit compare of two 64-bit registers is
    // not the same answer as a 64-bit one whenever the high words differ.
    if (f.l() != 0) {
        if (signed) {
            c.state.setCrCompare(f.crfd(), @bitCast(c.gpr(f.ra())), @bitCast(c.gpr(f.rb())));
        } else {
            c.state.setCrCompareUnsigned(f.crfd(), c.gpr(f.ra()), c.gpr(f.rb()));
        }
    } else if (signed) {
        const a: i64 = @as(i32, @truncate(@as(i64, @bitCast(c.gpr(f.ra())))));
        const b: i64 = @as(i32, @truncate(@as(i64, @bitCast(c.gpr(f.rb())))));
        c.state.setCrCompare(f.crfd(), a, b);
    } else {
        const a: u64 = @as(u32, @truncate(c.gpr(f.ra())));
        const b: u64 = @as(u32, @truncate(c.gpr(f.rb())));
        c.state.setCrCompareUnsigned(f.crfd(), a, b);
    }
    return .advance;
}

fn compareImmediate(c: *Context, insn: Instruction, comptime signed: bool) Outcome {
    const f = insn.d();
    if (f.l() != 0) {
        if (signed) {
            c.state.setCrCompare(f.crfd(), @bitCast(c.gpr(f.ra())), f.simm());
        } else {
            c.state.setCrCompareUnsigned(f.crfd(), c.gpr(f.ra()), f.uimm());
        }
    } else if (signed) {
        const a: i64 = @as(i32, @truncate(@as(i64, @bitCast(c.gpr(f.ra())))));
        c.state.setCrCompare(f.crfd(), a, f.simm());
    } else {
        const a: u64 = @as(u32, @truncate(c.gpr(f.ra())));
        c.state.setCrCompareUnsigned(f.crfd(), a, f.uimm());
    }
    return .advance;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const State = ctx_mod.State;
const Memory = ctx_mod.Memory;

const Harness = struct {
    state: State = .{},
    buf: [256]u8 = [_]u8{0} ** 256,

    fn context(self: *Harness) Context {
        return Context.init(&self.state, Memory.fromSlice(&self.buf, 0x8200_0000));
    }

    fn run(self: *Harness, word: u32) Outcome {
        var c = self.context();
        return execute(&c, ppc_decode.decodeWord(0x8200_0000, word));
    }
};

/// Build an XO-form word: `op rD, rA, rB`.
fn xoWord(primary: u32, rd: u32, ra: u32, rb: u32, oe: u32, xo: u32, rc: u32) u32 {
    return (primary << 26) | (rd << 21) | (ra << 16) | (rb << 11) |
        (oe << 10) | (xo << 1) | rc;
}

/// Build a D-form word: `op rD, rA, imm`.
fn dWord(primary: u32, rd: u32, ra: u32, imm: u16) u32 {
    return (primary << 26) | (rd << 21) | (ra << 16) | imm;
}

/// Build an X-form word: `op rA, rS, rB`.
fn xWord(primary: u32, rs: u32, ra: u32, rb: u32, xo: u32, rc: u32) u32 {
    return (primary << 26) | (rs << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc;
}

test "add is a 64-bit add and Rc writes CR0 from the full width" {
    var h = Harness{};
    h.state.gpr[4] = 0x0000_0001_0000_0000;
    h.state.gpr[5] = 0x0000_0000_0000_0001;
    _ = h.run(xoWord(31, 3, 4, 5, 0, 266, 1)); // add. r3, r4, r5
    try testing.expectEqual(@as(u64, 0x0000_0001_0000_0001), h.state.gpr[3]);
    try testing.expectEqual(@as(u4, 0b0100), h.state.crField(0)); // GT

    // A result whose low word is zero is still non-zero at 64 bits.
    h.state.gpr[4] = 0x0000_0001_0000_0000;
    h.state.gpr[5] = 0;
    _ = h.run(xoWord(31, 3, 4, 5, 0, 266, 1));
    try testing.expectEqual(@as(u4, 0b0100), h.state.crField(0)); // GT, not EQ
}

test "addo latches summary overflow and leaves it latched" {
    var h = Harness{};
    h.state.gpr[4] = @as(u64, 1) << 63;
    h.state.gpr[5] = @as(u64, 1) << 63;
    _ = h.run(xoWord(31, 3, 4, 5, 1, 266, 0)); // addo r3, r4, r5
    try testing.expect(h.state.xer.ov);
    try testing.expect(h.state.xer.so);

    h.state.gpr[4] = 1;
    h.state.gpr[5] = 1;
    _ = h.run(xoWord(31, 3, 4, 5, 1, 266, 0));
    try testing.expect(!h.state.xer.ov);
    try testing.expect(h.state.xer.so); // still latched
}

test "subf carry is the carry of ~rA + rB + 1, not of a plain subtract" {
    var h = Harness{};
    // 5 - 3: ~3 + 5 + 1 carries out.
    h.state.gpr[4] = 3;
    h.state.gpr[5] = 5;
    _ = h.run(xoWord(31, 3, 4, 5, 0, 8, 0)); // subfc r3, r4, r5
    try testing.expectEqual(@as(u64, 2), h.state.gpr[3]);
    try testing.expect(h.state.xer.ca);

    // 3 - 5 borrows, so no carry out.
    h.state.gpr[4] = 5;
    h.state.gpr[5] = 3;
    _ = h.run(xoWord(31, 3, 4, 5, 0, 8, 0));
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), h.state.gpr[3]);
    try testing.expect(!h.state.xer.ca);
}

test "addi reads r0 as literal zero, addic reads the register" {
    var h = Harness{};
    h.state.gpr[0] = 0xDEAD_BEEF;
    _ = h.run(dWord(14, 3, 0, 0x0010)); // li r3, 16
    try testing.expectEqual(@as(u64, 16), h.state.gpr[3]);

    _ = h.run(dWord(12, 3, 0, 0x0010)); // addic r3, r0, 16
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF + 16), h.state.gpr[3]);
}

test "mullw multiplies the low words into a full 64-bit product" {
    var h = Harness{};
    h.state.gpr[4] = 0xFFFF_FFFF_0001_0000; // low word 0x00010000
    h.state.gpr[5] = 0x0000_0000_0001_0000;
    _ = h.run(xoWord(31, 3, 4, 5, 0, 235, 0)); // mullw r3, r4, r5
    try testing.expectEqual(@as(u64, 0x0000_0001_0000_0000), h.state.gpr[3]);
}

test "divw by zero sets overflow instead of trapping" {
    var h = Harness{};
    h.state.gpr[4] = 100;
    h.state.gpr[5] = 0;
    const outcome = h.run(xoWord(31, 3, 4, 5, 1, 491, 0)); // divwo r3, r4, r5
    try testing.expectEqual(Outcome.advance, outcome);
    try testing.expect(h.state.xer.ov);
    try testing.expectEqual(@as(u64, 0), h.state.gpr[3]);
}

test "the logical forms write rA and read rS" {
    var h = Harness{};
    h.state.gpr[4] = 0xF0F0;
    h.state.gpr[5] = 0xFF00;
    _ = h.run(xWord(31, 4, 3, 5, 28, 0)); // and r3, r4, r5
    try testing.expectEqual(@as(u64, 0xF000), h.state.gpr[3]);
    _ = h.run(xWord(31, 4, 3, 5, 60, 0)); // andc r3, r4, r5
    try testing.expectEqual(@as(u64, 0x00F0), h.state.gpr[3]);
    _ = h.run(xWord(31, 4, 3, 5, 284, 0)); // eqv r3, r4, r5
    try testing.expectEqual(@as(u64, ~(@as(u64, 0xF0F0) ^ 0xFF00)), h.state.gpr[3]);
}

test "a word shift at or past 32 clears rather than wrapping" {
    var h = Harness{};
    h.state.gpr[4] = 0xFFFF_FFFF;
    h.state.gpr[5] = 32;
    _ = h.run(xWord(31, 4, 3, 5, 24, 0)); // slw r3, r4, r5
    try testing.expectEqual(@as(u64, 0), h.state.gpr[3]);
    h.state.gpr[5] = 33;
    _ = h.run(xWord(31, 4, 3, 5, 536, 0)); // srw r3, r4, r5
    try testing.expectEqual(@as(u64, 0), h.state.gpr[3]);
    // A wrapping shift would give 0xFFFFFFFF and 0x7FFFFFFF respectively.
}

test "srawi sets carry only when a one bit falls off a negative value" {
    var h = Harness{};
    h.state.gpr[4] = @bitCast(@as(i64, -8)); // ...11111000
    _ = h.run(xWord(31, 4, 3, 2, 824, 0)); // srawi r3, r4, 2
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), h.state.gpr[3]);
    try testing.expect(!h.state.xer.ca); // nothing but zeros shifted out

    h.state.gpr[4] = @bitCast(@as(i64, -7)); // ...11111001
    _ = h.run(xWord(31, 4, 3, 2, 824, 0));
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), h.state.gpr[3]);
    try testing.expect(h.state.xer.ca);

    h.state.gpr[4] = 7; // positive: carry never sets
    _ = h.run(xWord(31, 4, 3, 2, 824, 0));
    try testing.expect(!h.state.xer.ca);
}

test "rlwinm rotates the low word and duplicates it before masking" {
    var h = Harness{};
    h.state.gpr[4] = 0xFFFF_FFFF_8000_0001;
    // rlwinm r3, r4, 0, 0, 31 -> zero-extend the low word.
    const m_word = (21 << 26) | (4 << 21) | (3 << 16) | (0 << 11) | (0 << 6) | (31 << 1);
    _ = h.run(m_word);
    try testing.expectEqual(@as(u64, 0x8000_0001), h.state.gpr[3]);

    // rlwinm r3, r4, 1, 0, 31 -> rotate the low word left by one.
    const rot = (21 << 26) | (4 << 21) | (3 << 16) | (1 << 11) | (0 << 6) | (31 << 1);
    _ = h.run(rot);
    try testing.expectEqual(@as(u64, 0x0000_0003), h.state.gpr[3]);
}

test "rldicl clears the left, rldicr clears the right" {
    var h = Harness{};
    h.state.gpr[4] = 0xFFFF_FFFF_FFFF_FFFF;
    // rldicl r3, r4, 0, 32 -> keep the low 32 bits.
    const md_word: u32 = (30 << 26) | (4 << 21) | (3 << 16) | (0 << 11) |
        (0 << 6) | (1 << 5) | (0 << 2);
    _ = h.run(md_word);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), h.state.gpr[3]);

    // rldicr r3, r4, 0, 31 -> keep the high 32 bits.
    const md_r: u32 = (30 << 26) | (4 << 21) | (3 << 16) | (0 << 11) |
        (31 << 6) | (0 << 5) | (1 << 2);
    _ = h.run(md_r);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_0000_0000), h.state.gpr[3]);
}

test "cmp respects the L bit that picks 32-bit or 64-bit width" {
    var h = Harness{};
    // Low words compare equal; full registers do not.
    h.state.gpr[4] = 0x0000_0001_0000_0005;
    h.state.gpr[5] = 0x0000_0000_0000_0005;

    const cmp32 = (31 << 26) | (0 << 23) | (0 << 21) | (4 << 16) | (5 << 11) | (0 << 1);
    _ = h.run(cmp32);
    try testing.expectEqual(@as(u4, 0b0010), h.state.crField(0)); // EQ

    const cmp64 = (31 << 26) | (0 << 23) | (1 << 21) | (4 << 16) | (5 << 11) | (0 << 1);
    _ = h.run(cmp64);
    try testing.expectEqual(@as(u4, 0b0100), h.state.crField(0)); // GT
}

test "an instruction with no integer handler names itself" {
    var h = Harness{};
    const outcome = h.run(0x4e800020); // blr: not an integer instruction
    try testing.expect(outcome.isGap());
    try testing.expectEqual(ppc_decode.Op.bclrx, outcome.unimplemented);
}
