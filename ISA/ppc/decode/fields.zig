//! PowerPC instruction field extraction.
//!
//! Every PowerPC instruction is exactly four bytes with fixed field positions,
//! so decoding is field extraction rather than the prefix/ModRM walk the x86
//! decoder has to do. There is no instruction-length problem and no prefix
//! state: the form tells you where every operand lives.
//!
//! Two bit numberings meet here and mixing them is the classic PowerPC bug.
//! The architecture books number bits from the *most* significant end (bit 0 is
//! the top bit of the word); shifts are naturally expressed from the *least*
//! significant end. Every accessor below is written in LSB terms, with the
//! architectural bit range named in a comment, so the conversion happens once,
//! here, instead of at each call site.

const std = @import("std");

/// Extract `width` bits ending at LSB position `lsb`.
pub inline fn bits(word: u32, comptime lsb: u5, comptime width: u6) u32 {
    return (word >> lsb) & ((@as(u32, 1) << @intCast(width)) - 1);
}

/// Extract a single bit by its LSB position.
pub inline fn bit(word: u32, comptime lsb: u5) u1 {
    return @truncate(word >> lsb);
}

/// Sign-extend the low `width` bits of `value` to 64 bits.
pub inline fn signExtend(value: u32, comptime width: u7) i64 {
    const shift: u6 = @intCast(@as(u8, 64) - @as(u8, width));
    const wide: u64 = value;
    return @as(i64, @bitCast(wide << shift)) >> shift;
}

/// Primary opcode: architectural bits 0..5.
pub inline fn primary(word: u32) u6 {
    return @truncate(bits(word, 26, 6));
}

/// Record bit: architectural bit 31. Updates CR0 (integer) or CR1 (float).
pub inline fn rc(word: u32) bool {
    return bit(word, 0) != 0;
}

/// Link bit: architectural bit 31 of a branch. Writes LR.
pub inline fn lk(word: u32) bool {
    return bit(word, 0) != 0;
}

/// Absolute-address bit: architectural bit 30 of a branch.
pub inline fn aa(word: u32) bool {
    return bit(word, 1) != 0;
}

/// Overflow-enable bit: architectural bit 21 of an XO form. Writes XER.OV/SO.
pub inline fn oe(word: u32) bool {
    return bit(word, 10) != 0;
}

/// The PowerPC 64-bit mask built from a start and stop bit, inclusive.
/// When start > stop the mask wraps, which is what rlwinm and friends rely on.
pub fn mask64(mstart: u32, mstop: u32) u64 {
    const start: u6 = @intCast(mstart & 0x3F);
    const stop: u6 = @intCast(mstop & 0x3F);
    const all: u64 = std.math.maxInt(u64);
    const upper = all >> start;
    const lower = if (stop >= 63) 0 else all >> @as(u6, @intCast(stop + 1));
    const value = upper ^ lower;
    return if (start <= stop) value else ~value;
}

/// D form: `op RT, RA, SIMM` and every displacement load/store.
pub const D = struct {
    word: u32,

    /// bits 6..10
    pub inline fn rt(self: D) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn rd(self: D) u5 {
        return self.rt();
    }
    pub inline fn rs(self: D) u5 {
        return self.rt();
    }
    pub inline fn fd(self: D) u5 {
        return self.rt();
    }
    pub inline fn fs(self: D) u5 {
        return self.rt();
    }
    pub inline fn to(self: D) u5 {
        return self.rt();
    }
    /// bits 11..15
    pub inline fn ra(self: D) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    /// bits 16..31, raw
    pub inline fn ds(self: D) u32 {
        return bits(self.word, 0, 16);
    }
    pub inline fn simm(self: D) i64 {
        return signExtend(self.ds(), 16);
    }
    pub inline fn uimm(self: D) u64 {
        return self.ds();
    }
    /// bits 6..8 when the RT slot names a CR field (cmpi/cmpli).
    pub inline fn crfd(self: D) u3 {
        return @truncate(self.rt() >> 2);
    }
    /// bit 10: 0 selects a 32-bit compare, 1 a 64-bit compare.
    pub inline fn l(self: D) u1 {
        return @truncate(self.rt() & 1);
    }
};

/// DS form: `ld`, `std`, and their update variants. The low two displacement
/// bits are implied zero and carry the extended opcode instead.
pub const DS = struct {
    word: u32,

    pub inline fn rt(self: DS) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn rs(self: DS) u5 {
        return self.rt();
    }
    pub inline fn ra(self: DS) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    /// bits 16..29 scaled by four.
    pub inline fn dsField(self: DS) i64 {
        return signExtend(bits(self.word, 2, 14) << 2, 16);
    }
    /// bits 30..31
    pub inline fn xo(self: DS) u2 {
        return @truncate(bits(self.word, 0, 2));
    }
};

/// B form: conditional branch with a 14-bit displacement.
pub const B = struct {
    word: u32,

    pub inline fn bo(self: B) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn bi(self: B) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    /// bits 16..29 scaled by four, sign-extended.
    pub inline fn bd(self: B) i64 {
        return signExtend(bits(self.word, 2, 14) << 2, 16);
    }
    pub inline fn aa(self: B) bool {
        return bit(self.word, 1) != 0;
    }
    pub inline fn lk(self: B) bool {
        return bit(self.word, 0) != 0;
    }
};

/// I form: unconditional branch with a 24-bit displacement.
pub const I = struct {
    word: u32,

    /// bits 6..29 scaled by four, sign-extended from 26 bits.
    pub inline fn li(self: I) i64 {
        return signExtend(bits(self.word, 2, 24) << 2, 26);
    }
    pub inline fn aa(self: I) bool {
        return bit(self.word, 1) != 0;
    }
    pub inline fn lk(self: I) bool {
        return bit(self.word, 0) != 0;
    }
};

/// SC form: system call.
pub const SC = struct {
    word: u32,

    /// bits 20..26
    pub inline fn lev(self: SC) u7 {
        return @truncate(bits(self.word, 5, 7));
    }
};

/// X form: the general three-register shape, and every indexed load/store.
pub const X = struct {
    word: u32,

    pub inline fn rt(self: X) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn rd(self: X) u5 {
        return self.rt();
    }
    pub inline fn rs(self: X) u5 {
        return self.rt();
    }
    pub inline fn fd(self: X) u5 {
        return self.rt();
    }
    pub inline fn fs(self: X) u5 {
        return self.rt();
    }
    pub inline fn vd(self: X) u5 {
        return self.rt();
    }
    pub inline fn vs(self: X) u5 {
        return self.rt();
    }
    pub inline fn to(self: X) u5 {
        return self.rt();
    }
    pub inline fn ra(self: X) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn fa(self: X) u5 {
        return self.ra();
    }
    pub inline fn rb(self: X) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn fb(self: X) u5 {
        return self.rb();
    }
    pub inline fn nb(self: X) u5 {
        return self.rb();
    }
    pub inline fn sh(self: X) u5 {
        return self.rb();
    }
    /// bits 21..30
    pub inline fn xo(self: X) u10 {
        return @truncate(bits(self.word, 1, 10));
    }
    pub inline fn rc(self: X) bool {
        return bit(self.word, 0) != 0;
    }
    /// bits 6..8
    pub inline fn crfd(self: X) u3 {
        return @truncate(self.rt() >> 2);
    }
    /// bits 11..13
    pub inline fn crfs(self: X) u3 {
        return @truncate(self.ra() >> 2);
    }
    /// bit 10
    pub inline fn l(self: X) u1 {
        return @truncate(self.rt() & 1);
    }
};

/// XL form: branch-to-register and the condition-register logical ops.
pub const XL = struct {
    word: u32,

    pub inline fn bo(self: XL) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn crbd(self: XL) u5 {
        return self.bo();
    }
    pub inline fn bi(self: XL) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn crba(self: XL) u5 {
        return self.bi();
    }
    pub inline fn crbb(self: XL) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn crfd(self: XL) u3 {
        return @truncate(self.bo() >> 2);
    }
    pub inline fn crfs(self: XL) u3 {
        return @truncate(self.bi() >> 2);
    }
    pub inline fn xo(self: XL) u10 {
        return @truncate(bits(self.word, 1, 10));
    }
    pub inline fn lk(self: XL) bool {
        return bit(self.word, 0) != 0;
    }
};

/// XFX form: mtspr / mfspr / mtcrf / mftb.
pub const XFX = struct {
    word: u32,

    pub inline fn rt(self: XFX) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn rs(self: XFX) u5 {
        return self.rt();
    }
    pub inline fn rd(self: XFX) u5 {
        return self.rt();
    }
    /// bits 11..20, stored with its two five-bit halves swapped.
    pub inline fn sprRaw(self: XFX) u10 {
        return @truncate(bits(self.word, 11, 10));
    }
    /// The architected SPR number, with the halves put back in order.
    pub inline fn spr(self: XFX) u10 {
        const raw = self.sprRaw();
        return ((raw & 0x1F) << 5) | ((raw >> 5) & 0x1F);
    }
    pub inline fn tbr(self: XFX) u10 {
        return self.spr();
    }
    /// bits 12..19
    pub inline fn crm(self: XFX) u8 {
        return @truncate(bits(self.word, 12, 8));
    }
    pub inline fn xo(self: XFX) u10 {
        return @truncate(bits(self.word, 1, 10));
    }
    pub inline fn rc(self: XFX) bool {
        return bit(self.word, 0) != 0;
    }
};

/// XFL form: mtfsf.
pub const XFL = struct {
    word: u32,

    /// bits 7..14
    pub inline fn fm(self: XFL) u8 {
        return @truncate(bits(self.word, 17, 8));
    }
    pub inline fn fb(self: XFL) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn xo(self: XFL) u10 {
        return @truncate(bits(self.word, 1, 10));
    }
    pub inline fn rc(self: XFL) bool {
        return bit(self.word, 0) != 0;
    }
};

/// XS form: sradi, whose six-bit shift is split across bits 16..20 and bit 30.
pub const XS = struct {
    word: u32,

    pub inline fn rs(self: XS) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn ra(self: XS) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn sh(self: XS) u6 {
        return @truncate(bits(self.word, 11, 5) | (@as(u32, bit(self.word, 1)) << 5));
    }
    /// bits 21..29
    pub inline fn xo(self: XS) u9 {
        return @truncate(bits(self.word, 2, 9));
    }
    pub inline fn rc(self: XS) bool {
        return bit(self.word, 0) != 0;
    }
};

/// XO form: the arithmetic shape that carries the overflow-enable bit.
pub const XO = struct {
    word: u32,

    pub inline fn rd(self: XO) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn ra(self: XO) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn rb(self: XO) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn oe(self: XO) bool {
        return bit(self.word, 10) != 0;
    }
    /// bits 22..30
    pub inline fn xo(self: XO) u9 {
        return @truncate(bits(self.word, 1, 9));
    }
    pub inline fn rc(self: XO) bool {
        return bit(self.word, 0) != 0;
    }
};

/// A form: the floating-point four-register shape.
pub const A = struct {
    word: u32,

    pub inline fn fd(self: A) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn fa(self: A) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn fb(self: A) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn fc(self: A) u5 {
        return @truncate(bits(self.word, 6, 5));
    }
    /// bits 26..30
    pub inline fn xo(self: A) u5 {
        return @truncate(bits(self.word, 1, 5));
    }
    pub inline fn rc(self: A) bool {
        return bit(self.word, 0) != 0;
    }
};

/// M form: the 32-bit rotate-and-mask shape.
pub const M = struct {
    word: u32,

    pub inline fn rs(self: M) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn ra(self: M) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn rb(self: M) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn sh(self: M) u5 {
        return self.rb();
    }
    /// bits 21..25
    pub inline fn mb(self: M) u5 {
        return @truncate(bits(self.word, 6, 5));
    }
    /// bits 26..30
    pub inline fn me(self: M) u5 {
        return @truncate(bits(self.word, 1, 5));
    }
    pub inline fn rc(self: M) bool {
        return bit(self.word, 0) != 0;
    }
};

/// MD form: the 64-bit rotate-and-mask shape. Both the shift and the mask
/// bound are six-bit values split across the word.
pub const MD = struct {
    word: u32,

    pub inline fn rs(self: MD) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn ra(self: MD) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn sh(self: MD) u6 {
        return @truncate(bits(self.word, 11, 5) | (@as(u32, bit(self.word, 1)) << 5));
    }
    /// bits 21..26, low five bits first.
    pub inline fn mb(self: MD) u6 {
        return @truncate(bits(self.word, 6, 5) | (@as(u32, bit(self.word, 5)) << 5));
    }
    pub inline fn me(self: MD) u6 {
        return self.mb();
    }
    /// bits 27..29
    pub inline fn xo(self: MD) u3 {
        return @truncate(bits(self.word, 2, 3));
    }
    pub inline fn rc(self: MD) bool {
        return bit(self.word, 0) != 0;
    }
};

/// MDS form: MD with the shift taken from a register.
pub const MDS = struct {
    word: u32,

    pub inline fn rs(self: MDS) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn ra(self: MDS) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn rb(self: MDS) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn mb(self: MDS) u6 {
        return @truncate(bits(self.word, 6, 5) | (@as(u32, bit(self.word, 5)) << 5));
    }
    pub inline fn me(self: MDS) u6 {
        return self.mb();
    }
    /// bits 27..30
    pub inline fn xo(self: MDS) u4 {
        return @truncate(bits(self.word, 1, 4));
    }
    pub inline fn rc(self: MDS) bool {
        return bit(self.word, 0) != 0;
    }
};

/// VX form: the AltiVec three-register shape.
pub const VX = struct {
    word: u32,

    pub inline fn vd(self: VX) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn va(self: VX) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn vb(self: VX) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    /// The immediate that vspltb/vspltisb and friends take in the VA slot.
    pub inline fn uimm(self: VX) u5 {
        return self.va();
    }
    pub inline fn simm(self: VX) i64 {
        return signExtend(self.va(), 5);
    }
    /// bits 21..31
    pub inline fn xo(self: VX) u11 {
        return @truncate(bits(self.word, 0, 11));
    }
};

/// VC form: an AltiVec compare, whose record bit lands on CR6.
pub const VC = struct {
    word: u32,

    pub inline fn vd(self: VC) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn va(self: VC) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn vb(self: VC) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    /// bit 21
    pub inline fn rc(self: VC) bool {
        return bit(self.word, 10) != 0;
    }
    /// bits 22..31
    pub inline fn xo(self: VC) u10 {
        return @truncate(bits(self.word, 0, 10));
    }
};

/// VA form: the AltiVec four-register shape (vperm, vsel, vsldoi, vmadd).
pub const VA = struct {
    word: u32,

    pub inline fn vd(self: VA) u5 {
        return @truncate(bits(self.word, 21, 5));
    }
    pub inline fn va(self: VA) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn vb(self: VA) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
    pub inline fn vc(self: VA) u5 {
        return @truncate(bits(self.word, 6, 5));
    }
    /// bits 22..25, the byte shift vsldoi takes.
    pub inline fn shb(self: VA) u4 {
        return @truncate(bits(self.word, 6, 4));
    }
    /// bits 26..31
    pub inline fn xo(self: VA) u6 {
        return @truncate(bits(self.word, 0, 6));
    }
};

// ---------------------------------------------------------------------------
// VMX128
//
// The Xenon extends AltiVec from 32 to 128 vector registers without widening
// the instruction word, so each register number is reassembled from two or
// three scattered pieces. Reading only the low five bits gives register
// `n % 32` - a wrong-register bug that looks like data corruption rather than
// a decode fault, which is why every piece is spelled out here.
// ---------------------------------------------------------------------------

inline fn vd128(word: u32) u7 {
    return @truncate(bits(word, 21, 5) | (bits(word, 2, 2) << 5));
}

inline fn vb128(word: u32) u7 {
    return @truncate(bits(word, 11, 5) | (bits(word, 0, 2) << 5));
}

inline fn va128(word: u32) u7 {
    return @truncate(bits(word, 16, 5) |
        (@as(u32, bit(word, 5)) << 5) |
        (@as(u32, bit(word, 10)) << 6));
}

/// VX128: three VMX128 registers.
pub const VX128 = struct {
    word: u32,

    pub inline fn vd(self: VX128) u7 {
        return vd128(self.word);
    }
    pub inline fn va(self: VX128) u7 {
        return va128(self.word);
    }
    pub inline fn vb(self: VX128) u7 {
        return vb128(self.word);
    }
};

/// VX128_1: a VMX128 load or store, addressed by a GPR pair.
pub const VX128_1 = struct {
    word: u32,

    pub inline fn vd(self: VX128_1) u7 {
        return vd128(self.word);
    }
    pub inline fn vs(self: VX128_1) u7 {
        return vd128(self.word);
    }
    pub inline fn ra(self: VX128_1) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn rb(self: VX128_1) u5 {
        return @truncate(bits(self.word, 11, 5));
    }
};

/// VX128_2: four VMX128 registers, the fourth only three bits wide.
pub const VX128_2 = struct {
    word: u32,

    pub inline fn vd(self: VX128_2) u7 {
        return vd128(self.word);
    }
    pub inline fn va(self: VX128_2) u7 {
        return va128(self.word);
    }
    pub inline fn vb(self: VX128_2) u7 {
        return vb128(self.word);
    }
    pub inline fn vc(self: VX128_2) u3 {
        return @truncate(bits(self.word, 6, 3));
    }
};

/// VX128_3: two VMX128 registers plus a five-bit immediate.
pub const VX128_3 = struct {
    word: u32,

    pub inline fn vd(self: VX128_3) u7 {
        return vd128(self.word);
    }
    pub inline fn vb(self: VX128_3) u7 {
        return vb128(self.word);
    }
    pub inline fn uimm(self: VX128_3) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn simm(self: VX128_3) i64 {
        return signExtend(bits(self.word, 16, 5), 5);
    }
};

/// VX128_4: two VMX128 registers, an immediate, and a two-bit lane selector.
pub const VX128_4 = struct {
    word: u32,

    pub inline fn vd(self: VX128_4) u7 {
        return vd128(self.word);
    }
    pub inline fn vb(self: VX128_4) u7 {
        return vb128(self.word);
    }
    pub inline fn imm(self: VX128_4) u5 {
        return @truncate(bits(self.word, 16, 5));
    }
    pub inline fn z(self: VX128_4) u2 {
        return @truncate(bits(self.word, 6, 2));
    }
};

/// VX128_5: three VMX128 registers plus a four-bit byte shift (vsldoi128).
pub const VX128_5 = struct {
    word: u32,

    pub inline fn vd(self: VX128_5) u7 {
        return vd128(self.word);
    }
    pub inline fn va(self: VX128_5) u7 {
        return va128(self.word);
    }
    pub inline fn vb(self: VX128_5) u7 {
        return vb128(self.word);
    }
    pub inline fn sh(self: VX128_5) u4 {
        return @truncate(bits(self.word, 6, 4));
    }
};

/// VX128_R: a VMX128 compare, whose record bit lands on CR6.
pub const VX128_R = struct {
    word: u32,

    pub inline fn vd(self: VX128_R) u7 {
        return vd128(self.word);
    }
    pub inline fn va(self: VX128_R) u7 {
        return va128(self.word);
    }
    pub inline fn vb(self: VX128_R) u7 {
        return vb128(self.word);
    }
    pub inline fn rc(self: VX128_R) bool {
        return bit(self.word, 6) != 0;
    }
};

/// VX128_P: two VMX128 registers plus a split eight-bit permute selector.
pub const VX128_P = struct {
    word: u32,

    pub inline fn vd(self: VX128_P) u7 {
        return vd128(self.word);
    }
    pub inline fn vb(self: VX128_P) u7 {
        return vb128(self.word);
    }
    pub inline fn uimm(self: VX128_P) u8 {
        return @truncate(bits(self.word, 16, 5) | (bits(self.word, 6, 3) << 5));
    }
};

test "primary opcode and record bits come out of the right end of the word" {
    // add. r3, r4, r5 -> 0x7c642a15
    const add_dot: u32 = 0x7c642a15;
    try std.testing.expectEqual(@as(u6, 31), primary(add_dot));
    const xo = XO{ .word = add_dot };
    try std.testing.expectEqual(@as(u5, 3), xo.rd());
    try std.testing.expectEqual(@as(u5, 4), xo.ra());
    try std.testing.expectEqual(@as(u5, 5), xo.rb());
    try std.testing.expect(xo.rc());
    try std.testing.expect(!xo.oe());
    try std.testing.expectEqual(@as(u9, 266), xo.xo());
}

test "D form splits a signed displacement from its registers" {
    // lwz r3, -8(r4) -> 0x8064fff8
    const lwz: u32 = 0x8064fff8;
    const d = D{ .word = lwz };
    try std.testing.expectEqual(@as(u6, 32), primary(lwz));
    try std.testing.expectEqual(@as(u5, 3), d.rd());
    try std.testing.expectEqual(@as(u5, 4), d.ra());
    try std.testing.expectEqual(@as(i64, -8), d.simm());
    try std.testing.expectEqual(@as(u64, 0xfff8), d.uimm());
}

test "branch displacements are scaled by four and sign-extended" {
    // b -4 -> 0x4bfffffc
    const back = I{ .word = 0x4bfffffc };
    try std.testing.expectEqual(@as(i64, -4), back.li());
    try std.testing.expect(!back.aa());
    try std.testing.expect(!back.lk());

    // bl +8 -> 0x48000009 (LK set)
    const call = I{ .word = 0x48000009 };
    try std.testing.expectEqual(@as(i64, 8), call.li());
    try std.testing.expect(call.lk());
}

test "SPR numbers put their two halves back in order" {
    // mtspr LR (SPR 8) encodes the halves swapped as 0x0100.
    const mtlr: u32 = 0x7c0803a6;
    const xfx = XFX{ .word = mtlr };
    try std.testing.expectEqual(@as(u10, 8), xfx.spr());
    // mtspr CTR (SPR 9)
    const mtctr: u32 = 0x7c0903a6;
    try std.testing.expectEqual(@as(u10, 9), (XFX{ .word = mtctr }).spr());
}

test "MD form reassembles the split shift and mask bound" {
    // rldicl r3, r4, 32, 32: sh 32 sets the sh5 bit, mb 32 sets the mb5 bit,
    // and both would read as 0 if the split halves were dropped.
    const rldicl: u32 = 0x78830022;
    const md = MD{ .word = rldicl };
    try std.testing.expectEqual(@as(u5, 4), md.rs());
    try std.testing.expectEqual(@as(u5, 3), md.ra());
    try std.testing.expectEqual(@as(u6, 32), md.sh());
    try std.testing.expectEqual(@as(u6, 32), md.mb());
    try std.testing.expectEqual(@as(u3, 0), md.xo());
    try std.testing.expect(!md.rc());
}

test "the PowerPC mask wraps when its start is past its stop" {
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), mask64(0, 63));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), mask64(0, 0));
    try std.testing.expectEqual(@as(u64, 0x0000000000000001), mask64(63, 63));
    // A wrapped mask keeps both ends and drops the middle.
    try std.testing.expectEqual(@as(u64, 0x8000000000000001), mask64(63, 0));
}

test "VMX128 register numbers are reassembled from every piece" {
    // Build a VX128 word whose VD is 5 in the low field and 3 in the high pair:
    // VD = 5 | (3 << 5) = 101.
    const word: u32 = (5 << 21) | (3 << 2);
    try std.testing.expectEqual(@as(u7, 101), (VX128{ .word = word }).vd());
    // VB low 5 bits = 7, high pair = 2 -> 7 | (2 << 5) = 71.
    const wordb: u32 = (7 << 11) | 2;
    try std.testing.expectEqual(@as(u7, 71), (VX128{ .word = wordb }).vb());
    // VA takes a third piece from architectural bit 21 (LSB 10).
    const worda: u32 = (9 << 16) | (1 << 5) | (1 << 10);
    try std.testing.expectEqual(@as(u7, 9 | 32 | 64), (VX128{ .word = worda }).va());
}
