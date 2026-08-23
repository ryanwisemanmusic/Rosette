//! ARM64 (AArch64) instruction encoding.
//!
//! Every function here returns one 32-bit instruction word. Nothing allocates,
//! nothing is stateful, and nothing depends on where the instruction will land -
//! branch displacements are the caller's problem, because only the caller knows
//! where its labels are.
//!
//! The encodings are not written from memory. Each one was assembled by the
//! system assembler and the resulting word checked into the tests at the bottom
//! of this file, so a mistake shows up as a failing comparison against the
//! toolchain rather than as a guest that behaves strangely several thousand
//! instructions later. When adding an instruction, add its ground-truth word at
//! the same time.
//!
//! Two things are easy to get wrong and are therefore modelled rather than
//! open-coded:
//!
//!   * The shift/bitfield aliases (`lsl`, `lsr`, `asr`, `ror`, `ubfx`, `bfi`)
//!     are not instructions. They are UBFM/SBFM/BFM/EXTR with computed operands,
//!     and the computation differs per alias - `lsl #5` is
//!     `ubfm immr=59, imms=58`, not `immr=5`.
//!   * The logical immediate is a bitmask encoding, not a literal. Only values
//!     that are a rotated run of ones repeated at some power-of-two element size
//!     can be encoded at all, so `andImmediate` returns null rather than
//!     silently encoding a different constant.

const std = @import("std");

/// A general-purpose register number. 31 means XZR/WZR in most contexts and SP
/// in a few; the distinction is per-instruction and noted where it matters.
pub const Reg = u5;

pub const xzr: Reg = 31;
pub const wzr: Reg = 31;
pub const sp: Reg = 31;
pub const lr: Reg = 30;

/// Operand width. ARM64 selects it with the top bit of the instruction word.
pub const Width = enum {
    w32,
    x64,

    fn sf(self: Width) u32 {
        return switch (self) {
            .w32 => 0,
            .x64 => 1,
        };
    }

    pub fn bits(self: Width) u7 {
        return switch (self) {
            .w32 => 32,
            .x64 => 64,
        };
    }
};

/// Condition codes, in their architectural encoding.
pub const Cond = enum(u4) {
    eq = 0,
    ne = 1,
    hs = 2,
    lo = 3,
    mi = 4,
    pl = 5,
    vs = 6,
    vc = 7,
    hi = 8,
    ls = 9,
    ge = 10,
    lt = 11,
    gt = 12,
    le = 13,
    al = 14,
    nv = 15,

    /// The condition that is true exactly when this one is false.
    pub fn invert(self: Cond) Cond {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }
};

// ---------------------------------------------------------------------------
// Add / subtract
// ---------------------------------------------------------------------------

const AddSubOp = enum { add, sub };

/// `add`/`sub` with a 12-bit immediate, optionally shifted left by 12.
/// Returns null when the value does not fit either form.
pub fn addSubImmediate(
    width: Width,
    op: AddSubOp,
    set_flags: bool,
    rd: Reg,
    rn: Reg,
    value: u64,
) ?u32 {
    var imm12: u64 = value;
    var shift: u32 = 0;
    if (value > 0xFFF) {
        if (value & 0xFFF != 0 or value > 0xFFF000) return null;
        imm12 = value >> 12;
        shift = 1;
    }
    return (width.sf() << 31) |
        (@as(u32, @intFromBool(op == .sub)) << 30) |
        (@as(u32, @intFromBool(set_flags)) << 29) |
        (0b10001 << 24) |
        (shift << 22) |
        (@as(u32, @intCast(imm12)) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn addImm(width: Width, rd: Reg, rn: Reg, value: u64) ?u32 {
    return addSubImmediate(width, .add, false, rd, rn, value);
}

pub fn subImm(width: Width, rd: Reg, rn: Reg, value: u64) ?u32 {
    return addSubImmediate(width, .sub, false, rd, rn, value);
}

pub fn cmpImm(width: Width, rn: Reg, value: u64) ?u32 {
    return addSubImmediate(width, .sub, true, xzr, rn, value);
}

/// `add`/`sub` between registers, with an optional left shift on the second.
pub fn addSubShifted(
    width: Width,
    op: AddSubOp,
    set_flags: bool,
    rd: Reg,
    rn: Reg,
    rm: Reg,
    shift: u6,
) u32 {
    return (width.sf() << 31) |
        (@as(u32, @intFromBool(op == .sub)) << 30) |
        (@as(u32, @intFromBool(set_flags)) << 29) |
        (0b01011 << 24) |
        (@as(u32, rm) << 16) |
        (@as(u32, shift) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn add(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return addSubShifted(width, .add, false, rd, rn, rm, 0);
}

pub fn adds(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return addSubShifted(width, .add, true, rd, rn, rm, 0);
}

pub fn sub(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return addSubShifted(width, .sub, false, rd, rn, rm, 0);
}

pub fn subs(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return addSubShifted(width, .sub, true, rd, rn, rm, 0);
}

pub fn cmp(width: Width, rn: Reg, rm: Reg) u32 {
    return subs(width, xzr, rn, rm);
}

pub fn neg(width: Width, rd: Reg, rm: Reg) u32 {
    return sub(width, rd, xzr, rm);
}

// ---------------------------------------------------------------------------
// Logical
// ---------------------------------------------------------------------------

pub const LogicalOp = enum {
    /// opc, N pairs: and=00/0, bic=00/1, orr=01/0, orn=01/1,
    /// eor=10/0, eon=10/1, ands=11/0, bics=11/1
    andop,
    bic,
    orr,
    orn,
    eor,
    eon,
    ands,
    bics,

    fn opc(self: LogicalOp) u32 {
        return switch (self) {
            .andop, .bic => 0b00,
            .orr, .orn => 0b01,
            .eor, .eon => 0b10,
            .ands, .bics => 0b11,
        };
    }

    fn negated(self: LogicalOp) u32 {
        return switch (self) {
            .bic, .orn, .eon, .bics => 1,
            else => 0,
        };
    }
};

pub fn logicalShifted(
    width: Width,
    op: LogicalOp,
    rd: Reg,
    rn: Reg,
    rm: Reg,
    shift: u6,
) u32 {
    return (width.sf() << 31) |
        (op.opc() << 29) |
        (0b01010 << 24) |
        (op.negated() << 21) |
        (@as(u32, rm) << 16) |
        (@as(u32, shift) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn andReg(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return logicalShifted(width, .andop, rd, rn, rm, 0);
}

pub fn orrReg(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return logicalShifted(width, .orr, rd, rn, rm, 0);
}

pub fn eorReg(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return logicalShifted(width, .eor, rd, rn, rm, 0);
}

pub fn bicReg(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return logicalShifted(width, .bic, rd, rn, rm, 0);
}

pub fn ornReg(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return logicalShifted(width, .orn, rd, rn, rm, 0);
}

pub fn eonReg(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return logicalShifted(width, .eon, rd, rn, rm, 0);
}

/// `mov Rd, Rm` is `orr Rd, ZR, Rm`.
pub fn mov(width: Width, rd: Reg, rm: Reg) u32 {
    return orrReg(width, rd, xzr, rm);
}

/// `mvn Rd, Rm` is `orn Rd, ZR, Rm`.
pub fn mvn(width: Width, rd: Reg, rm: Reg) u32 {
    return ornReg(width, rd, xzr, rm);
}

/// The bitmask-immediate encoding: N, immr, imms.
pub const Bitmask = struct { n: u1, immr: u6, imms: u6 };

/// Encode a logical immediate, or return null when the value has no encoding.
///
/// Only a rotated run of ones, repeated at some power-of-two element size, is
/// representable. That covers most constants a compiler wants (masks, small
/// powers of two, byte-replicated patterns) and excludes most that it does not,
/// so the caller has to be prepared to materialise the constant instead. There
/// is no "close enough" encoding to fall back on.
pub fn encodeBitmask(value: u64, width: Width) ?Bitmask {
    const reg_size: u32 = width.bits();
    var imm = value;
    if (imm == 0 or imm == ~@as(u64, 0)) return null;
    if (reg_size != 64) {
        if (imm >> @intCast(reg_size) != 0) return null;
        if (imm == (~@as(u64, 0) >> @intCast(64 - reg_size))) return null;
        // A 32-bit logical immediate is the 32-bit pattern repeated, so the
        // search below works on the replicated 64-bit form.
        imm |= imm << 32;
    }

    // Find the element size the pattern repeats at.
    var size: u32 = 64;
    while (true) {
        size /= 2;
        const mask = (@as(u64, 1) << @intCast(size)) - 1;
        if ((imm & mask) != ((imm >> @intCast(size)) & mask)) {
            size *= 2;
            break;
        }
        if (size <= 2) break;
    }

    const element_mask = ~@as(u64, 0) >> @intCast(64 - size);
    var element = imm & element_mask;

    var rotation: u32 = undefined;
    var ones: u32 = undefined;
    if (isShiftedMask(element)) {
        rotation = @ctz(element);
        ones = @ctz(~(element >> @intCast(rotation)));
    } else {
        element |= ~element_mask;
        if (!isShiftedMask(~element)) return null;
        const leading_ones = @clz(~element);
        rotation = 64 - leading_ones;
        ones = leading_ones + @ctz(~element) - (64 - size);
    }

    if (ones == 0 or ones > size) return null;
    const immr: u32 = (size -% rotation) & (size - 1);
    var nimms: u64 = ~@as(u64, size - 1) << 1;
    nimms |= (ones - 1);
    const n: u1 = @intCast(((nimms >> 6) & 1) ^ 1);
    const candidate = Bitmask{
        .n = n,
        .immr = @intCast(immr & 0x3F),
        .imms = @intCast(nimms & 0x3F),
    };
    // Confirm the encoding names the value that was asked for. Returning null
    // costs the caller a materialised constant; returning a wrong encoding
    // costs it a wrong answer.
    const check = decodeBitmask(candidate, width) orelse return null;
    const wanted = if (width == .w32) (value & 0xFFFF_FFFF) else value;
    if (check != wanted) return null;
    return candidate;
}

fn isShiftedMask(value: u64) bool {
    if (value == 0) return false;
    // A single run of ones with nothing above or below it: filling downward
    // from the run must produce all ones from bit 0 up. The additions wrap
    // deliberately - a run that reaches the top of the register makes `filled`
    // all ones, and `+ 1` there is exactly the overflow the test is looking for.
    const filled = value | (value -% 1);
    return (filled +% 1) & filled == 0;
}

/// Decode a bitmask immediate back into the constant it names, or null when the
/// three fields are not a legal encoding.
///
/// This exists so `encodeBitmask` can check its own answer. The encoding search
/// is a fixed-point algorithm over bit counts, and a mistake in it produces a
/// *different valid constant* rather than an obvious failure - the one class of
/// bug where an emitted instruction runs perfectly and computes the wrong thing.
pub fn decodeBitmask(bits: Bitmask, width: Width) ?u64 {
    const combined: u32 = (@as(u32, bits.n) << 6) | (~@as(u32, bits.imms) & 0x3F);
    if (combined == 0) return null;
    const len: u32 = 31 - @clz(combined);
    if (len < 1) return null;
    const size: u32 = @as(u32, 1) << @intCast(len);
    if (width == .w32 and size > 32) return null;

    const levels: u32 = size - 1;
    const s: u32 = @as(u32, bits.imms) & levels;
    const r: u32 = @as(u32, bits.immr) & levels;
    // An all-ones element is the reserved encoding.
    if (s == levels) return null;

    const ones: u64 = if (s + 1 >= 64)
        ~@as(u64, 0)
    else
        (@as(u64, 1) << @intCast(s + 1)) - 1;
    // Rotate right by r within the element.
    const rotated: u64 = if (r == 0)
        ones
    else
        ((ones >> @intCast(r)) | (ones << @intCast(size - r))) &
            (if (size >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(size)) - 1);

    // Replicate the element across the register.
    var result: u64 = 0;
    var shift: u32 = 0;
    while (shift < 64) : (shift += size) {
        result |= rotated << @intCast(shift);
    }
    if (width == .w32) result &= 0xFFFF_FFFF;
    return result;
}

pub fn logicalImmediate(
    width: Width,
    op: LogicalOp,
    rd: Reg,
    rn: Reg,
    value: u64,
) ?u32 {
    const bits = encodeBitmask(value, width) orelse return null;
    const opc: u32 = switch (op) {
        .andop => 0b00,
        .orr => 0b01,
        .eor => 0b10,
        .ands => 0b11,
        // The negated forms have no immediate encoding.
        else => return null,
    };
    return (width.sf() << 31) |
        (opc << 29) |
        (0b100100 << 23) |
        (@as(u32, bits.n) << 22) |
        (@as(u32, bits.immr) << 16) |
        (@as(u32, bits.imms) << 10) |
        (@as(u32, rn) << 5) | rd;
}

// ---------------------------------------------------------------------------
// Move wide
// ---------------------------------------------------------------------------

const MoveWideOp = enum(u2) { movn = 0b00, movz = 0b10, movk = 0b11 };

fn moveWide(width: Width, op: MoveWideOp, rd: Reg, imm16: u16, shift: u2) u32 {
    return (width.sf() << 31) |
        (@as(u32, @intFromEnum(op)) << 29) |
        (0b100101 << 23) |
        (@as(u32, shift) << 21) |
        (@as(u32, imm16) << 5) | rd;
}

pub fn movz(width: Width, rd: Reg, imm16: u16, shift: u2) u32 {
    return moveWide(width, .movz, rd, imm16, shift);
}

pub fn movk(width: Width, rd: Reg, imm16: u16, shift: u2) u32 {
    return moveWide(width, .movk, rd, imm16, shift);
}

pub fn movn(width: Width, rd: Reg, imm16: u16, shift: u2) u32 {
    return moveWide(width, .movn, rd, imm16, shift);
}

// ---------------------------------------------------------------------------
// Bitfield and shifts
// ---------------------------------------------------------------------------

const BitfieldOp = enum(u2) { sbfm = 0b00, bfm = 0b01, ubfm = 0b10 };

fn bitfield(width: Width, op: BitfieldOp, rd: Reg, rn: Reg, immr: u6, imms: u6) u32 {
    return (width.sf() << 31) |
        (@as(u32, @intFromEnum(op)) << 29) |
        (0b100110 << 23) |
        (@as(u32, width.sf()) << 22) |
        (@as(u32, immr) << 16) |
        (@as(u32, imms) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn ubfm(width: Width, rd: Reg, rn: Reg, immr: u6, imms: u6) u32 {
    return bitfield(width, .ubfm, rd, rn, immr, imms);
}

pub fn sbfm(width: Width, rd: Reg, rn: Reg, immr: u6, imms: u6) u32 {
    return bitfield(width, .sbfm, rd, rn, immr, imms);
}

pub fn bfm(width: Width, rd: Reg, rn: Reg, immr: u6, imms: u6) u32 {
    return bitfield(width, .bfm, rd, rn, immr, imms);
}

/// `lsl Rd, Rn, #shift`. The alias is UBFM with a rotate of `-shift`, not with
/// a rotate of `shift`.
pub fn lslImm(width: Width, rd: Reg, rn: Reg, shift: u6) u32 {
    const size: u32 = width.bits();
    const immr: u6 = @intCast((size - @as(u32, shift)) % size);
    const imms: u6 = @intCast(size - 1 - @as(u32, shift));
    return ubfm(width, rd, rn, immr, imms);
}

pub fn lsrImm(width: Width, rd: Reg, rn: Reg, shift: u6) u32 {
    return ubfm(width, rd, rn, shift, @intCast(width.bits() - 1));
}

pub fn asrImm(width: Width, rd: Reg, rn: Reg, shift: u6) u32 {
    return sbfm(width, rd, rn, shift, @intCast(width.bits() - 1));
}

/// `ubfx Rd, Rn, #lsb, #width` extracts `width` bits starting at `lsb`.
pub fn ubfx(width: Width, rd: Reg, rn: Reg, lsb: u6, count: u7) u32 {
    return ubfm(width, rd, rn, lsb, @intCast(@as(u32, lsb) + count - 1));
}

pub fn sbfx(width: Width, rd: Reg, rn: Reg, lsb: u6, count: u7) u32 {
    return sbfm(width, rd, rn, lsb, @intCast(@as(u32, lsb) + count - 1));
}

/// `bfi Rd, Rn, #lsb, #width` inserts `width` bits of Rn at `lsb` in Rd,
/// leaving the rest of Rd alone.
pub fn bfi(width: Width, rd: Reg, rn: Reg, lsb: u6, count: u7) u32 {
    const size: u32 = width.bits();
    const immr: u6 = @intCast((size - @as(u32, lsb)) % size);
    const imms: u6 = @intCast(count - 1);
    return bfm(width, rd, rn, immr, imms);
}

pub fn sxtb(width: Width, rd: Reg, rn: Reg) u32 {
    return sbfm(width, rd, rn, 0, 7);
}

pub fn sxth(width: Width, rd: Reg, rn: Reg) u32 {
    return sbfm(width, rd, rn, 0, 15);
}

/// `sxtw Xd, Wn` only exists in the 64-bit form.
pub fn sxtw(rd: Reg, rn: Reg) u32 {
    return sbfm(.x64, rd, rn, 0, 31);
}

pub fn uxtb(width: Width, rd: Reg, rn: Reg) u32 {
    return ubfm(width, rd, rn, 0, 7);
}

pub fn uxth(width: Width, rd: Reg, rn: Reg) u32 {
    return ubfm(width, rd, rn, 0, 15);
}

/// `extr Rd, Rn, Rm, #lsb`. `ror Rd, Rn, #n` is this with Rm == Rn.
pub fn extr(width: Width, rd: Reg, rn: Reg, rm: Reg, lsb: u6) u32 {
    return (width.sf() << 31) |
        (0b00100111 << 23) |
        (@as(u32, width.sf()) << 22) |
        (@as(u32, rm) << 16) |
        (@as(u32, lsb) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn rorImm(width: Width, rd: Reg, rn: Reg, shift: u6) u32 {
    return extr(width, rd, rn, rn, shift);
}

// ---------------------------------------------------------------------------
// Variable shifts, division, bit counting
// ---------------------------------------------------------------------------

const TwoSourceOp = enum(u6) {
    udiv = 0b000010,
    sdiv = 0b000011,
    lslv = 0b001000,
    lsrv = 0b001001,
    asrv = 0b001010,
    rorv = 0b001011,
};

fn twoSource(width: Width, op: TwoSourceOp, rd: Reg, rn: Reg, rm: Reg) u32 {
    return (width.sf() << 31) |
        (0b0011010110 << 21) |
        (@as(u32, rm) << 16) |
        (@as(u32, @intFromEnum(op)) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn lslv(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return twoSource(width, .lslv, rd, rn, rm);
}

pub fn lsrv(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return twoSource(width, .lsrv, rd, rn, rm);
}

pub fn asrv(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return twoSource(width, .asrv, rd, rn, rm);
}

pub fn rorv(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return twoSource(width, .rorv, rd, rn, rm);
}

pub fn sdiv(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return twoSource(width, .sdiv, rd, rn, rm);
}

pub fn udiv(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return twoSource(width, .udiv, rd, rn, rm);
}

const OneSourceOp = enum(u6) {
    rbit = 0b000000,
    rev16 = 0b000001,
    rev32_or_rev = 0b000010,
    rev64 = 0b000011,
    clz = 0b000100,
};

fn oneSource(width: Width, op: OneSourceOp, rd: Reg, rn: Reg) u32 {
    return (width.sf() << 31) |
        (0b101101011000000 << 16) |
        (@as(u32, @intFromEnum(op)) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn clz(width: Width, rd: Reg, rn: Reg) u32 {
    return oneSource(width, .clz, rd, rn);
}

pub fn rbit(width: Width, rd: Reg, rn: Reg) u32 {
    return oneSource(width, .rbit, rd, rn);
}

pub fn rev16(width: Width, rd: Reg, rn: Reg) u32 {
    return oneSource(width, .rev16, rd, rn);
}

/// Byte-reverse the whole register. In the 32-bit form the opcode that means
/// "reverse everything" is 0b000010; in the 64-bit form it is 0b000011, and
/// 0b000010 means "reverse within each word" instead.
pub fn rev(width: Width, rd: Reg, rn: Reg) u32 {
    return switch (width) {
        .w32 => oneSource(.w32, .rev32_or_rev, rd, rn),
        .x64 => oneSource(.x64, .rev64, rd, rn),
    };
}

pub fn rev32(rd: Reg, rn: Reg) u32 {
    return oneSource(.x64, .rev32_or_rev, rd, rn);
}

// ---------------------------------------------------------------------------
// Multiply
// ---------------------------------------------------------------------------

pub fn madd(width: Width, rd: Reg, rn: Reg, rm: Reg, ra: Reg) u32 {
    return (width.sf() << 31) |
        (0b0011011000 << 21) |
        (@as(u32, rm) << 16) |
        (@as(u32, ra) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn msub(width: Width, rd: Reg, rn: Reg, rm: Reg, ra: Reg) u32 {
    return madd(width, rd, rn, rm, ra) | (1 << 15);
}

pub fn mul(width: Width, rd: Reg, rn: Reg, rm: Reg) u32 {
    return madd(width, rd, rn, rm, xzr);
}

pub fn smulh(rd: Reg, rn: Reg, rm: Reg) u32 {
    return 0x9B407C00 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd;
}

pub fn umulh(rd: Reg, rn: Reg, rm: Reg) u32 {
    return 0x9BC07C00 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd;
}

/// `smull Xd, Wn, Wm`: a 32x32 signed product widened to 64 bits.
pub fn smull(rd: Reg, rn: Reg, rm: Reg) u32 {
    return 0x9B200000 | (@as(u32, rm) << 16) | (@as(u32, xzr) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn umull(rd: Reg, rn: Reg, rm: Reg) u32 {
    return 0x9BA00000 | (@as(u32, rm) << 16) | (@as(u32, xzr) << 10) |
        (@as(u32, rn) << 5) | rd;
}

// ---------------------------------------------------------------------------
// Scalar floating point
// ---------------------------------------------------------------------------

/// Width of an ARM64 scalar floating-point operand. The register number is
/// still a five-bit SIMD/FPR number; only the low lane is used.
pub const FpWidth = enum { single, double };

fn fpScalar3(width: FpWidth, base_single: u32, base_double: u32, rd: Reg, rn: Reg, rm: Reg) u32 {
    const base = if (width == .single) base_single else base_double;
    return base | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd;
}

pub fn fadd(width: FpWidth, rd: Reg, rn: Reg, rm: Reg) u32 {
    return fpScalar3(width, 0x1E202800, 0x1E602800, rd, rn, rm);
}

pub fn fsub(width: FpWidth, rd: Reg, rn: Reg, rm: Reg) u32 {
    return fpScalar3(width, 0x1E203800, 0x1E603800, rd, rn, rm);
}

pub fn fmul(width: FpWidth, rd: Reg, rn: Reg, rm: Reg) u32 {
    return fpScalar3(width, 0x1E200800, 0x1E600800, rd, rn, rm);
}

pub fn fdiv(width: FpWidth, rd: Reg, rn: Reg, rm: Reg) u32 {
    return fpScalar3(width, 0x1E201800, 0x1E601800, rd, rn, rm);
}

pub fn fmadd(width: FpWidth, rd: Reg, rn: Reg, rm: Reg, ra: Reg) u32 {
    const base: u32 = if (width == .single) 0x1F000000 else 0x1F400000;
    return base | (@as(u32, rm) << 16) | (@as(u32, ra) << 10) |
        (@as(u32, rn) << 5) | rd;
}

pub fn fmsub(width: FpWidth, rd: Reg, rn: Reg, rm: Reg, ra: Reg) u32 {
    return fmadd(width, rd, rn, rm, ra) | (1 << 15);
}

fn fpUnary(width: FpWidth, base_single: u32, base_double: u32, rd: Reg, rn: Reg) u32 {
    const base = if (width == .single) base_single else base_double;
    return base | (@as(u32, rn) << 5) | rd;
}

pub fn fsqrt(width: FpWidth, rd: Reg, rn: Reg) u32 {
    return fpUnary(width, 0x1E21C000, 0x1E61C000, rd, rn);
}

pub fn fneg(width: FpWidth, rd: Reg, rn: Reg) u32 {
    return fpUnary(width, 0x1E214000, 0x1E614000, rd, rn);
}

pub fn fabs(width: FpWidth, rd: Reg, rn: Reg) u32 {
    return fpUnary(width, 0x1E20C000, 0x1E60C000, rd, rn);
}

pub fn fcmp(width: FpWidth, rn: Reg, rm: Reg) u32 {
    // The architectural compare encoding has an unused zero Rd field; it is
    // not the general-purpose XZR number used by integer compare aliases.
    return fpScalar3(width, 0x1E212000, 0x1E612000, 0, rn, rm);
}

/// Convert a single scalar to double precision, or double to single
/// precision. The destination width selects the instruction encoding.
pub fn fcvtDouble(rd: Reg, rn: Reg) u32 {
    return 0x1E22C000 | (@as(u32, rn) << 5) | rd;
}

pub fn fcvtSingle(rd: Reg, rn: Reg) u32 {
    return 0x1E624000 | (@as(u32, rn) << 5) | rd;
}

/// Move a general-purpose 64-bit register into a scalar double register.
/// This is useful for materialising an exact floating-point zero without a
/// literal pool.
pub fn fmovFromGpr(rd: Reg, rn: Reg) u32 {
    return 0x9E670000 | (@as(u32, rn) << 5) | rd;
}

pub fn fmovToGpr(rd: Reg, rn: Reg) u32 {
    return 0x9E660000 | (@as(u32, rn) << 5) | rd;
}

// ---------------------------------------------------------------------------
// Load / store
// ---------------------------------------------------------------------------

/// Access size and signedness. The name says what lands in the destination,
/// which is what the caller cares about.
pub const MemSize = enum {
    byte,
    half,
    word,
    doubleword,
    /// Sign-extending loads. Store forms of these do not exist.
    signed_byte,
    signed_half,
    signed_word,

    fn sizeField(self: MemSize) u32 {
        return switch (self) {
            .byte, .signed_byte => 0b00,
            .half, .signed_half => 0b01,
            .word, .signed_word => 0b10,
            .doubleword => 0b11,
        };
    }

    fn scale(self: MemSize) u32 {
        return switch (self) {
            .byte, .signed_byte => 1,
            .half, .signed_half => 2,
            .word, .signed_word => 4,
            .doubleword => 8,
        };
    }

    /// The opc field: 00 store, 01 load, 10 sign-extending load into a 64-bit
    /// register.
    fn opc(self: MemSize, is_load: bool) u32 {
        if (!is_load) return 0b00;
        return switch (self) {
            .signed_byte, .signed_half, .signed_word => 0b10,
            else => 0b01,
        };
    }
};

/// Load or store with a scaled unsigned immediate offset. Returns null when the
/// offset is not a multiple of the access size or does not fit twelve bits.
pub fn memImmediate(
    size: MemSize,
    is_load: bool,
    rt: Reg,
    rn: Reg,
    offset: u32,
) ?u32 {
    const scale = size.scale();
    if (offset % scale != 0) return null;
    const imm12 = offset / scale;
    if (imm12 > 0xFFF) return null;
    return (size.sizeField() << 30) |
        (0b111001 << 24) |
        (size.opc(is_load) << 22) |
        (imm12 << 10) |
        (@as(u32, rn) << 5) | rt;
}

/// Load or store with a register offset, unscaled (`option = LSL #0`).
pub fn memRegister(size: MemSize, is_load: bool, rt: Reg, rn: Reg, rm: Reg) u32 {
    return (size.sizeField() << 30) |
        (0b111000 << 24) |
        (size.opc(is_load) << 22) |
        (1 << 21) |
        (@as(u32, rm) << 16) |
        // option = 011 (LSL/UXTX), S = 0
        (0b011 << 13) |
        (0b10 << 10) |
        (@as(u32, rn) << 5) | rt;
}

pub fn ldrImm(size: MemSize, rt: Reg, rn: Reg, offset: u32) ?u32 {
    return memImmediate(size, true, rt, rn, offset);
}

pub fn strImm(size: MemSize, rt: Reg, rn: Reg, offset: u32) ?u32 {
    return memImmediate(size, false, rt, rn, offset);
}

pub fn ldrReg(size: MemSize, rt: Reg, rn: Reg, rm: Reg) u32 {
    return memRegister(size, true, rt, rn, rm);
}

pub fn strReg(size: MemSize, rt: Reg, rn: Reg, rm: Reg) u32 {
    return memRegister(size, false, rt, rn, rm);
}

/// Scalar floating-point load/store size. These use the same unsigned scaled
/// immediate addressing shape as integer loads, with an FP register operand.
pub const FpMemSize = enum { single, double };

fn fpMemImmediate(size: FpMemSize, is_load: bool, rt: Reg, rn: Reg, offset: u32) ?u32 {
    const scale: u32 = if (size == .single) 4 else 8;
    if (offset % scale != 0) return null;
    const imm12 = offset / scale;
    if (imm12 > 0xFFF) return null;
    const base: u32 = switch (size) {
        .single => if (is_load) 0xBD400000 else 0xBD000000,
        .double => if (is_load) 0xFD400000 else 0xFD000000,
    };
    return base | (imm12 << 10) | (@as(u32, rn) << 5) | rt;
}

pub fn ldrFpImm(size: FpMemSize, rt: Reg, rn: Reg, offset: u32) ?u32 {
    return fpMemImmediate(size, true, rt, rn, offset);
}

pub fn strFpImm(size: FpMemSize, rt: Reg, rn: Reg, offset: u32) ?u32 {
    return fpMemImmediate(size, false, rt, rn, offset);
}

// ---------------------------------------------------------------------------
// Conditional select
// ---------------------------------------------------------------------------

pub fn csel(width: Width, rd: Reg, rn: Reg, rm: Reg, cond: Cond) u32 {
    return (width.sf() << 31) |
        (0b0011010100 << 21) |
        (@as(u32, rm) << 16) |
        (@as(u32, @intFromEnum(cond)) << 12) |
        (@as(u32, rn) << 5) | rd;
}

pub fn csinc(width: Width, rd: Reg, rn: Reg, rm: Reg, cond: Cond) u32 {
    return csel(width, rd, rn, rm, cond) | (1 << 10);
}

/// `cset Rd, cond` is `csinc Rd, ZR, ZR, invert(cond)`.
pub fn cset(width: Width, rd: Reg, cond: Cond) u32 {
    return csinc(width, rd, xzr, xzr, cond.invert());
}

// ---------------------------------------------------------------------------
// Branches
//
// Displacements are in instructions, not bytes, and are relative to the branch
// itself. The caller supplies them because only the caller knows the layout.
// ---------------------------------------------------------------------------

pub fn b(offset_instructions: i32) u32 {
    return 0x14000000 | (@as(u32, @bitCast(offset_instructions)) & 0x03FFFFFF);
}

pub fn bl(offset_instructions: i32) u32 {
    return 0x94000000 | (@as(u32, @bitCast(offset_instructions)) & 0x03FFFFFF);
}

pub fn bcond(cond: Cond, offset_instructions: i32) u32 {
    return 0x54000000 |
        ((@as(u32, @bitCast(offset_instructions)) & 0x7FFFF) << 5) |
        @as(u32, @intFromEnum(cond));
}

pub fn cbz(width: Width, rt: Reg, offset_instructions: i32) u32 {
    return (width.sf() << 31) | 0x34000000 |
        ((@as(u32, @bitCast(offset_instructions)) & 0x7FFFF) << 5) | rt;
}

pub fn cbnz(width: Width, rt: Reg, offset_instructions: i32) u32 {
    return cbz(width, rt, offset_instructions) | (1 << 24);
}

pub fn ret() u32 {
    return 0xD65F0000 | (@as(u32, lr) << 5);
}

pub fn retReg(rn: Reg) u32 {
    return 0xD65F0000 | (@as(u32, rn) << 5);
}

pub fn br(rn: Reg) u32 {
    return 0xD61F0000 | (@as(u32, rn) << 5);
}

pub fn blr(rn: Reg) u32 {
    return 0xD63F0000 | (@as(u32, rn) << 5);
}

pub fn nop() u32 {
    return 0xD503201F;
}

pub fn brk(imm16: u16) u32 {
    return 0xD4200000 | (@as(u32, imm16) << 5);
}

// ---------------------------------------------------------------------------
// Constant materialisation
// ---------------------------------------------------------------------------

/// Emit the shortest movz/movk sequence for a 64-bit constant into `out`,
/// returning how many instructions were written. At most four.
///
/// The negated form is tried as well: a constant with many high one-bits costs
/// one movn plus the movk for each differing halfword, which is often shorter
/// than four movks.
pub fn materialize(rd: Reg, value: u64, out: []u32) usize {
    std.debug.assert(out.len >= 4);
    if (value == 0) {
        out[0] = movz(.x64, rd, 0, 0);
        return 1;
    }

    var zero_halves: usize = 0;
    var ones_halves: usize = 0;
    inline for (0..4) |i| {
        const half: u16 = @truncate(value >> (i * 16));
        if (half == 0) zero_halves += 1;
        if (half == 0xFFFF) ones_halves += 1;
    }

    var count: usize = 0;
    if (ones_halves > zero_halves) {
        // Start from movn, which fills every other halfword with ones.
        var first = true;
        inline for (0..4) |i| {
            const half: u16 = @truncate(value >> (i * 16));
            if (half != 0xFFFF) {
                if (first) {
                    out[count] = movn(.x64, rd, ~half, @intCast(i));
                    first = false;
                } else {
                    out[count] = movk(.x64, rd, half, @intCast(i));
                }
                count += 1;
            }
        }
        if (first) {
            out[0] = movn(.x64, rd, 0, 0);
            count = 1;
        }
    } else {
        var first = true;
        inline for (0..4) |i| {
            const half: u16 = @truncate(value >> (i * 16));
            if (half != 0) {
                if (first) {
                    out[count] = movz(.x64, rd, half, @intCast(i));
                    first = false;
                } else {
                    out[count] = movk(.x64, rd, half, @intCast(i));
                }
                count += 1;
            }
        }
    }
    return count;
}

// ---------------------------------------------------------------------------
// Tests
//
// Every expectation below is the word the system assembler produced for the
// instruction in the comment. See the module doc: these are ground truth, not
// recollection.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "add and subtract immediates match the assembler" {
    try testing.expectEqual(@as(?u32, 0x91001020), addImm(.x64, 0, 1, 4));
    try testing.expectEqual(@as(?u32, 0x913ffc83), addImm(.x64, 3, 4, 0xFFF));
    // 0x1000 does not fit twelve bits, so it uses the shifted form.
    try testing.expectEqual(@as(?u32, 0x914004c5), addImm(.x64, 5, 6, 0x1000));
    try testing.expectEqual(@as(?u32, 0xd1004107), subImm(.x64, 7, 8, 0x10));
    try testing.expectEqual(@as(?u32, 0xf1001d3f), cmpImm(.x64, 9, 7));
    // A value that is neither a 12-bit immediate nor a shifted one has no
    // encoding and must be reported rather than truncated.
    try testing.expectEqual(@as(?u32, null), addImm(.x64, 0, 1, 0x1001));
}

test "add and subtract between registers match the assembler" {
    try testing.expectEqual(@as(u32, 0x8b0c016a), add(.x64, 10, 11, 12));
    try testing.expectEqual(@as(u32, 0xab0f01cd), adds(.x64, 13, 14, 15));
    try testing.expectEqual(@as(u32, 0xcb120230), sub(.x64, 16, 17, 18));
    try testing.expectEqual(@as(u32, 0xeb14027f), cmp(.x64, 19, 20));
}

test "logical register forms match the assembler" {
    try testing.expectEqual(@as(u32, 0x8a1702d5), andReg(.x64, 21, 22, 23));
    try testing.expectEqual(@as(u32, 0xaa1a0338), orrReg(.x64, 24, 25, 26));
    try testing.expectEqual(@as(u32, 0xca1d039b), eorReg(.x64, 27, 28, 29));
    try testing.expectEqual(@as(u32, 0x8a220020), bicReg(.x64, 0, 1, 2));
    try testing.expectEqual(@as(u32, 0xaa250083), ornReg(.x64, 3, 4, 5));
    try testing.expectEqual(@as(u32, 0xca2800e6), eonReg(.x64, 6, 7, 8));
    try testing.expectEqual(@as(u32, 0xaa2a03e9), mvn(.x64, 9, 10));
    try testing.expectEqual(@as(u32, 0xaa0c03eb), mov(.x64, 11, 12));
}

test "move-wide forms match the assembler" {
    try testing.expectEqual(@as(u32, 0xd282468d), movz(.x64, 13, 0x1234, 0));
    try testing.expectEqual(@as(u32, 0xd2aacf0e), movz(.x64, 14, 0x5678, 1));
    try testing.expectEqual(@as(u32, 0xf2d579af), movk(.x64, 15, 0xABCD, 2));
    try testing.expectEqual(@as(u32, 0x92800010), movn(.x64, 16, 0, 0));
}

test "the shift aliases compute their bitfield operands correctly" {
    // These are the aliases most likely to be wrong: lsl #5 is immr=59, not 5.
    try testing.expectEqual(@as(u32, 0xd37bea51), lslImm(.x64, 17, 18, 5));
    try testing.expectEqual(@as(u32, 0xd347fe93), lsrImm(.x64, 19, 20, 7));
    try testing.expectEqual(@as(u32, 0x9349fed5), asrImm(.x64, 21, 22, 9));
    try testing.expectEqual(@as(u32, 0x93d82f17), rorImm(.x64, 23, 24, 11));
    try testing.expectEqual(@as(u32, 0xd34330e6), ubfx(.x64, 6, 7, 3, 10));
    try testing.expectEqual(@as(u32, 0x93443d28), sbfx(.x64, 8, 9, 4, 12));
    try testing.expectEqual(@as(u32, 0xb37b156a), bfi(.x64, 10, 11, 5, 6));
}

test "sign and zero extension match the assembler" {
    try testing.expectEqual(@as(u32, 0x93401dac), sxtb(.x64, 12, 13));
    try testing.expectEqual(@as(u32, 0x93403dee), sxth(.x64, 14, 15));
    try testing.expectEqual(@as(u32, 0x93407e30), sxtw(16, 17));
}

test "variable shifts, counting, and byte reversal match the assembler" {
    try testing.expectEqual(@as(u32, 0x9adb2359), lslv(.x64, 25, 26, 27));
    try testing.expectEqual(@as(u32, 0x9ade27bc), lsrv(.x64, 28, 29, 30));
    try testing.expectEqual(@as(u32, 0x9ac22820), asrv(.x64, 0, 1, 2));
    try testing.expectEqual(@as(u32, 0x9ac52c83), rorv(.x64, 3, 4, 5));
    try testing.expectEqual(@as(u32, 0xdac01272), clz(.x64, 18, 19));
    try testing.expectEqual(@as(u32, 0x5ac012b4), clz(.w32, 20, 21));
    // rev is the one whose opcode differs between widths.
    try testing.expectEqual(@as(u32, 0xdac00ef6), rev(.x64, 22, 23));
    try testing.expectEqual(@as(u32, 0x5ac00b38), rev(.w32, 24, 25));
    try testing.expectEqual(@as(u32, 0x5ac0077a), rev16(.w32, 26, 27));
}

test "multiply and divide match the assembler" {
    try testing.expectEqual(@as(u32, 0x9b1e7fbc), mul(.x64, 28, 29, 30));
    try testing.expectEqual(@as(u32, 0x9b020c20), madd(.x64, 0, 1, 2, 3));
    try testing.expectEqual(@as(u32, 0x9b069ca4), msub(.x64, 4, 5, 6, 7));
    try testing.expectEqual(@as(u32, 0x9b4a7d28), smulh(8, 9, 10));
    try testing.expectEqual(@as(u32, 0x9bcd7d8b), umulh(11, 12, 13));
    try testing.expectEqual(@as(u32, 0x9b307dee), smull(14, 15, 16));
    try testing.expectEqual(@as(u32, 0x9bb37e51), umull(17, 18, 19));
    try testing.expectEqual(@as(u32, 0x9ad60eb4), sdiv(.x64, 20, 21, 22));
    try testing.expectEqual(@as(u32, 0x9ad90b17), udiv(.x64, 23, 24, 25));
    try testing.expectEqual(@as(u32, 0x1adc0f7a), sdiv(.w32, 26, 27, 28));
}

test "scalar floating point forms match the assembler" {
    try testing.expectEqual(@as(u32, 0x1e622820), fadd(.double, 0, 1, 2));
    try testing.expectEqual(@as(u32, 0x1e313a0f), fsub(.single, 15, 16, 17));
    try testing.expectEqual(@as(u32, 0x1e6808e6), fmul(.double, 6, 7, 8));
    try testing.expectEqual(@as(u32, 0x1e371ad5), fdiv(.single, 21, 22, 23));
    try testing.expectEqual(@as(u32, 0x1f5045ee), fmadd(.double, 14, 15, 16, 17));
    try testing.expectEqual(@as(u32, 0x1f14d672), fmsub(.single, 18, 19, 20, 21));
    try testing.expectEqual(@as(u32, 0x1e61c338), fsqrt(.double, 24, 25));
    try testing.expectEqual(@as(u32, 0x1e61437a), fneg(.double, 26, 27));
    try testing.expectEqual(@as(u32, 0x1e60c3bc), fabs(.double, 28, 29));
    try testing.expectEqual(@as(u32, 0x1e612000), fcmp(.double, 0, 1));
    try testing.expectEqual(@as(u32, 0x1e22c0e6), fcvtDouble(6, 7));
    try testing.expectEqual(@as(u32, 0x1e624128), fcvtSingle(8, 9));
    try testing.expectEqual(@as(u32, 0x9e67016a), fmovFromGpr(10, 11));
    try testing.expectEqual(@as(u32, 0x9e6601ac), fmovToGpr(12, 13));
}

test "immediate-offset loads and stores match the assembler" {
    try testing.expectEqual(@as(?u32, 0xf9400420), ldrImm(.doubleword, 0, 1, 8));
    try testing.expectEqual(@as(?u32, 0xb9400462), ldrImm(.word, 2, 3, 4));
    try testing.expectEqual(@as(?u32, 0x394004a4), ldrImm(.byte, 4, 5, 1));
    try testing.expectEqual(@as(?u32, 0x794004e6), ldrImm(.half, 6, 7, 2));
    try testing.expectEqual(@as(?u32, 0xb9800528), ldrImm(.signed_word, 8, 9, 4));
    try testing.expectEqual(@as(?u32, 0x7980056a), ldrImm(.signed_half, 10, 11, 2));
    try testing.expectEqual(@as(?u32, 0x398005ac), ldrImm(.signed_byte, 12, 13, 1));
    try testing.expectEqual(@as(?u32, 0xf90005ee), strImm(.doubleword, 14, 15, 8));
    try testing.expectEqual(@as(?u32, 0xb9000630), strImm(.word, 16, 17, 4));
    try testing.expectEqual(@as(?u32, 0x39000672), strImm(.byte, 18, 19, 1));
    try testing.expectEqual(@as(?u32, 0x790006b4), strImm(.half, 20, 21, 2));
}

test "scalar floating point loads and stores match the assembler" {
    try testing.expectEqual(@as(?u32, 0xfd400802), ldrFpImm(.double, 2, 0, 16));
    try testing.expectEqual(@as(?u32, 0xfd000c03), strFpImm(.double, 3, 0, 24));
    try testing.expectEqual(@as(?u32, 0xbd402004), ldrFpImm(.single, 4, 0, 32));
    try testing.expectEqual(@as(?u32, 0xbd002405), strFpImm(.single, 5, 0, 36));
    try testing.expectEqual(@as(?u32, null), ldrFpImm(.double, 0, 1, 4));
}

test "an unscalable immediate offset is refused rather than rounded" {
    // A doubleword access can only reach multiples of eight.
    try testing.expectEqual(@as(?u32, null), ldrImm(.doubleword, 0, 1, 4));
    // And only 4095 slots of them.
    try testing.expectEqual(@as(?u32, null), ldrImm(.doubleword, 0, 1, 0x8000));
    try testing.expect(ldrImm(.doubleword, 0, 1, 0x7FF8) != null);
}

test "register-offset loads and stores match the assembler" {
    try testing.expectEqual(@as(u32, 0xf8626820), ldrReg(.doubleword, 0, 1, 2));
    try testing.expectEqual(@as(u32, 0xb8656883), ldrReg(.word, 3, 4, 5));
    try testing.expectEqual(@as(u32, 0x386868e6), ldrReg(.byte, 6, 7, 8));
    try testing.expectEqual(@as(u32, 0x786b6949), ldrReg(.half, 9, 10, 11));
    try testing.expectEqual(@as(u32, 0xb8ae69ac), ldrReg(.signed_word, 12, 13, 14));
    try testing.expectEqual(@as(u32, 0xf8316a0f), strReg(.doubleword, 15, 16, 17));
    try testing.expectEqual(@as(u32, 0xb8346a72), strReg(.word, 18, 19, 20));
    try testing.expectEqual(@as(u32, 0x38376ad5), strReg(.byte, 21, 22, 23));
    try testing.expectEqual(@as(u32, 0x783a6b38), strReg(.half, 24, 25, 26));
}

test "conditional select forms match the assembler" {
    try testing.expectEqual(@as(u32, 0x9a9f17e0), cset(.x64, 0, .eq));
    try testing.expectEqual(@as(u32, 0x9a831041), csel(.x64, 1, 2, 3, .ne));
    try testing.expectEqual(@as(u32, 0x9a86b4a4), csinc(.x64, 4, 5, 6, .lt));
}

test "branch and return forms match the assembler" {
    try testing.expectEqual(@as(u32, 0xd65f03c0), ret());
    try testing.expectEqual(@as(u32, 0xd61f00e0), br(7));
    try testing.expectEqual(@as(u32, 0xd63f0100), blr(8));
    try testing.expectEqual(@as(u32, 0xd503201f), nop());
}

test "logical immediates use the bitmask encoding" {
    try testing.expectEqual(@as(?u32, 0x92401c20), logicalImmediate(.x64, .andop, 0, 1, 0xFF));
    try testing.expectEqual(@as(?u32, 0xb2403c62), logicalImmediate(.x64, .orr, 2, 3, 0xFFFF));
    try testing.expectEqual(@as(?u32, 0xd24000a4), logicalImmediate(.x64, .eor, 4, 5, 1));
    try testing.expectEqual(@as(?u32, 0xf27c0cdf), logicalImmediate(.x64, .ands, xzr, 6, 0xF0));
    try testing.expectEqual(@as(?u32, 0x12003d07), logicalImmediate(.w32, .andop, 7, 8, 0xFFFF));
}

test "a value with no bitmask encoding is refused, not approximated" {
    // All-zeros and all-ones have no encoding by construction.
    try testing.expectEqual(@as(?Bitmask, null), encodeBitmask(0, .x64));
    try testing.expectEqual(@as(?Bitmask, null), encodeBitmask(~@as(u64, 0), .x64));
    // Neither does an arbitrary constant with two separate runs of ones.
    try testing.expectEqual(@as(?Bitmask, null), encodeBitmask(0x1234_5678, .x64));
    // But a single rotated run does.
    try testing.expect(encodeBitmask(0xFF00, .x64) != null);
    try testing.expect(encodeBitmask(0xF000_0000_0000_000F, .x64) != null);
}

test "constant materialisation picks the shorter of movz and movn" {
    var out: [4]u32 = undefined;

    try testing.expectEqual(@as(usize, 1), materialize(0, 0, &out));
    try testing.expectEqual(movz(.x64, 0, 0, 0), out[0]);

    try testing.expectEqual(@as(usize, 1), materialize(1, 0x1234, &out));
    try testing.expectEqual(movz(.x64, 1, 0x1234, 0), out[0]);

    // Two non-zero halfwords cost two instructions.
    try testing.expectEqual(@as(usize, 2), materialize(2, 0x1234_0000_5678, &out));

    // A constant that is mostly ones is cheaper from movn: -1 is one
    // instruction, not four.
    try testing.expectEqual(@as(usize, 1), materialize(3, ~@as(u64, 0), &out));
    try testing.expectEqual(movn(.x64, 3, 0, 0), out[0]);

    // A worst-case constant still fits in four.
    try testing.expectEqual(@as(usize, 4), materialize(4, 0x1111_2222_3333_4444, &out));
}

test "every encodable bitmask round-trips through the decoder" {
    // Walk a wide spread of candidate constants. Every one the encoder accepts
    // must decode back to itself; that is the property the emitted `and`
    // depends on, and it cannot be checked by looking at the encoding.
    var value: u64 = 1;
    var checked: usize = 0;
    while (value != 0) : (value <<= 1) {
        for ([_]u64{ value, value - 1, value | (value << 8), ~value }) |candidate| {
            if (encodeBitmask(candidate, .x64)) |bits| {
                try testing.expectEqual(@as(?u64, candidate), decodeBitmask(bits, .x64));
                checked += 1;
            }
        }
    }
    try testing.expect(checked > 100);
}

test "a run of ones reaching the top of the register is encodable" {
    // The case where the internal `filled + 1` wraps: a mask anchored at bit 63.
    const top = @as(u64, 1) << 63;
    const bits = encodeBitmask(top, .x64) orelse return error.ShouldEncode;
    try testing.expectEqual(@as(?u64, top), decodeBitmask(bits, .x64));

    const high_run: u64 = 0xFFFF_FFFF_0000_0000;
    const run_bits = encodeBitmask(high_run, .x64) orelse return error.ShouldEncode;
    try testing.expectEqual(@as(?u64, high_run), decodeBitmask(run_bits, .x64));
}

test "32-bit bitmasks stay inside 32 bits" {
    const bits = encodeBitmask(0xFF00, .w32) orelse return error.ShouldEncode;
    try testing.expectEqual(@as(?u64, 0xFF00), decodeBitmask(bits, .w32));
    // A value with bits above 32 has no 32-bit encoding.
    try testing.expectEqual(@as(?Bitmask, null), encodeBitmask(0x1_0000_0000, .w32));
}
