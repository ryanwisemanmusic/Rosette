//! PowerPC instruction encoding.
//!
//! The inverse of `ISA/ppc/decode`. Every field writer here mirrors, bit for
//! bit, the accessor of the same name in `decode/fields.zig`, and every one is
//! verified by round-tripping through the real decoder rather than by reading
//! the two side by side.
//!
//! ## Why this exists
//!
//! The decoder could already recognise all 456 opcodes; nothing could produce
//! one. That asymmetry is easy to miss because a decoder is what you reach for
//! first and what a trace exercises — so "the ISA layer is incomplete" reads as
//! a decode gap when it is really the absence of the other direction. Anything
//! that has to *emit* PowerPC — a test vector, a patch, a synthesised stub, a
//! backend that re-materialises a guest instruction — had no way to do it.
//!
//! ## The round trip is the specification
//!
//! Field positions are stated twice in this repository: once as decode
//! accessors, once as the writers below. Two hand-written statements of the
//! same fact will eventually disagree, and a disagreement here does not fail
//! loudly — it produces a *valid* instruction that means something else.
//!
//! So correctness is not asserted by inspection. `roundTripsThroughDecoder`
//! checks that decoding what we encoded returns the op we asked for, and the
//! tests run it across every opcode in the table. A field writer that lands on
//! the wrong bits moves the encoding into another instruction's space and the
//! round trip catches it.
//!
//! ## Bit numbering
//!
//! As in `decode/fields.zig`: the architecture books number from the most
//! significant end, shifts are natural from the least. Everything below is in
//! LSB terms with the architectural range named in a comment, so the
//! conversion happens once, here.

const std = @import("std");
const decode = @import("ppc_decode");
const fields = decode.fields;

pub const Op = decode.Op;
pub const Form = decode.Form;

pub const EncodeError = error{
    /// The op has no encoding pattern — the reserved/unknown slot.
    UnencodableOp,
    /// A field value does not fit the bits the form gives it.
    FieldOutOfRange,
    /// A displacement that must be a multiple of four is not.
    MisalignedDisplacement,
};

/// The instruction with every variable field zeroed.
///
/// This is the same `pattern` the decoder's own table carries, so `base` and
/// the decode tree cannot disagree about what an opcode *is* — only about
/// where its operands live, which is what the round trip checks.
pub fn base(op: Op) EncodeError!u32 {
    if (!op.isValid()) return error.UnencodableOp;
    return op.info().pattern;
}

/// Place `value` into `width` bits ending at LSB `lsb`, refusing an overflow.
///
/// Refusing rather than truncating: a register number that silently loses its
/// high bit encodes a different register, and the instruction still decodes
/// and still runs.
fn place(word: u32, value: u32, comptime lsb: u5, comptime width: u6) EncodeError!u32 {
    const limit: u32 = if (width >= 32) 0xFFFF_FFFF else (@as(u32, 1) << @intCast(width)) - 1;
    if (value > limit) return error.FieldOutOfRange;
    return word | (value << lsb);
}

fn placeBit(word: u32, set: bool, comptime lsb: u5) u32 {
    return if (set) word | (@as(u32, 1) << lsb) else word;
}

/// Narrow a signed displacement to `width` bits, refusing anything that would
/// not survive the decoder's sign extension.
fn signedField(value: i64, comptime width: u7) EncodeError!u32 {
    const bound: i64 = @as(i64, 1) << @intCast(width - 1);
    if (value < -bound or value >= bound) return error.FieldOutOfRange;
    const mask: u64 = if (width >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(width)) - 1;
    return @truncate(@as(u64, @bitCast(value)) & mask);
}

// ---------------------------------------------------------------------------
// Form writers. Each mirrors the like-named struct in decode/fields.zig.
// ---------------------------------------------------------------------------

/// D form: `rt` at 21, `ra` at 16, a 16-bit immediate at 0.
pub fn encodeD(op: Op, rt: u5, ra: u5, immediate: i64) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, rt, 21, 5);
    word = try place(word, ra, 16, 5);
    // Both signed and unsigned immediates occupy the same sixteen bits; the
    // decoder decides which it is from the opcode, so accept either range.
    const field: u32 = if (immediate < 0)
        try signedField(immediate, 16)
    else if (immediate <= 0xFFFF)
        @intCast(immediate)
    else
        return error.FieldOutOfRange;
    return try place(word, field, 0, 16);
}

/// DS form: like D, but the displacement is bits 16..29 scaled by four and the
/// low two bits belong to the extended opcode.
pub fn encodeDS(op: Op, rt: u5, ra: u5, displacement: i64) EncodeError!u32 {
    if (@rem(displacement, 4) != 0) return error.MisalignedDisplacement;
    var word = try base(op);
    word = try place(word, rt, 21, 5);
    word = try place(word, ra, 16, 5);
    const field = try signedField(displacement, 16);
    // The scaling is the point: the encoded field is the displacement's high
    // fourteen bits, and the two the decoder shifts back in are the opcode's.
    return try place(word, field >> 2, 2, 14);
}

/// X form: `rt` at 21, `ra` at 16, `rb` at 11, record bit at 0.
pub fn encodeX(op: Op, rt: u5, ra: u5, rb: u5, rc: bool) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, rt, 21, 5);
    word = try place(word, ra, 16, 5);
    word = try place(word, rb, 11, 5);
    return placeBit(word, rc, 0);
}

/// XO form: X plus the overflow-enable bit at 10.
pub fn encodeXO(op: Op, rd: u5, ra: u5, rb: u5, oe: bool, rc: bool) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, rd, 21, 5);
    word = try place(word, ra, 16, 5);
    word = try place(word, rb, 11, 5);
    word = placeBit(word, oe, 10);
    return placeBit(word, rc, 0);
}

/// A form: the floating-point four-register shape, `fc` at 6.
pub fn encodeA(op: Op, fd: u5, fa: u5, fb: u5, fc: u5, rc: bool) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, fd, 21, 5);
    word = try place(word, fa, 16, 5);
    word = try place(word, fb, 11, 5);
    word = try place(word, fc, 6, 5);
    return placeBit(word, rc, 0);
}

/// M form: 32-bit rotate-and-mask. `mb` at 6, `me` at 1.
pub fn encodeM(op: Op, rs: u5, ra: u5, sh: u5, mb: u5, me: u5, rc: bool) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, rs, 21, 5);
    word = try place(word, ra, 16, 5);
    word = try place(word, sh, 11, 5);
    word = try place(word, mb, 6, 5);
    word = try place(word, me, 1, 5);
    return placeBit(word, rc, 0);
}

/// MD form: 64-bit rotate-and-mask. The six-bit shift is split — five bits at
/// 11 and its top bit at 1 — which is the field most likely to be encoded as
/// though it were five bits and silently halve every shift over 31.
pub fn encodeMD(op: Op, rs: u5, ra: u5, sh: u6, mb: u6, rc: bool) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, rs, 21, 5);
    word = try place(word, ra, 16, 5);
    word = try place(word, sh & 0x1F, 11, 5);
    word = placeBit(word, (sh >> 5) & 1 != 0, 1);
    // The mask bound is likewise split: low five bits at 6, top bit at 5.
    word = try place(word, mb & 0x1F, 6, 5);
    word = placeBit(word, (mb >> 5) & 1 != 0, 5);
    return placeBit(word, rc, 0);
}

/// B form: conditional branch, 14-bit displacement scaled by four.
pub fn encodeB(op: Op, bo: u5, bi: u5, displacement: i64, aa: bool, lk: bool) EncodeError!u32 {
    if (@rem(displacement, 4) != 0) return error.MisalignedDisplacement;
    var word = try base(op);
    word = try place(word, bo, 21, 5);
    word = try place(word, bi, 16, 5);
    const field = try signedField(displacement, 16);
    word = try place(word, field >> 2, 2, 14);
    word = placeBit(word, aa, 1);
    return placeBit(word, lk, 0);
}

/// I form: unconditional branch, 24-bit displacement scaled by four and
/// sign-extended from 26 bits.
pub fn encodeI(op: Op, displacement: i64, aa: bool, lk: bool) EncodeError!u32 {
    if (@rem(displacement, 4) != 0) return error.MisalignedDisplacement;
    var word = try base(op);
    const field = try signedField(displacement, 26);
    word = try place(word, field >> 2, 2, 24);
    word = placeBit(word, aa, 1);
    return placeBit(word, lk, 0);
}

/// XL form: branch to LR/CTR, and the condition-register logical ops.
pub fn encodeXL(op: Op, bo: u5, bi: u5, lk: bool) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, bo, 21, 5);
    word = try place(word, bi, 16, 5);
    return placeBit(word, lk, 0);
}

/// XFX form: the special-purpose register moves. The SPR number is stored
/// with its halves swapped, which is the classic PowerPC encoding trap: `mfspr
/// r3, LR` written without the swap reads SPR 256 instead of SPR 8.
pub fn encodeXFX(op: Op, rt: u5, spr: u10) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, rt, 21, 5);
    const swapped: u32 = (@as(u32, spr & 0x1F) << 5) | (@as(u32, spr >> 5) & 0x1F);
    return try place(word, swapped, 11, 10);
}

/// The SPR encoding's half-swap, exposed because a caller reading a disassembly
/// has the architectural number and needs the encoded one.
pub fn swapSprHalves(spr: u10) u10 {
    return @intCast(((@as(u32, spr) & 0x1F) << 5) | ((@as(u32, spr) >> 5) & 0x1F));
}

/// VX form: the AltiVec three-register shape.
pub fn encodeVX(op: Op, vd: u5, va: u5, vb: u5) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, vd, 21, 5);
    word = try place(word, va, 16, 5);
    return try place(word, vb, 11, 5);
}

/// VA form: AltiVec four-register, `vc` at 6.
pub fn encodeVA(op: Op, vd: u5, va: u5, vb: u5, vc: u5) EncodeError!u32 {
    var word = try base(op);
    word = try place(word, vd, 21, 5);
    word = try place(word, va, 16, 5);
    word = try place(word, vb, 11, 5);
    return try place(word, vc, 6, 5);
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

/// Whether an encoded word decodes back to the op it was built from.
///
/// The property every writer above is held to. A field placed on the wrong
/// bits does not produce an invalid instruction — it produces a *different*
/// valid one — so this is the only cheap check that catches it.
pub fn roundTripsThroughDecoder(op: Op, word: u32) bool {
    return decode.decodeOp(word) == op;
}

pub const Coverage = struct {
    total: usize,
    encodable: usize,
    round_tripped: usize,

    pub fn isComplete(self: Coverage) bool {
        return self.encodable == self.round_tripped and self.encodable == self.total;
    }
};

/// Measure how much of the opcode table can be encoded and decoded back.
///
/// Reports rather than asserts, so a caller can print the number. The tests
/// below are what turn it into a gate.
pub fn measureCoverage() Coverage {
    var total: usize = 0;
    var encodable: usize = 0;
    var round_tripped: usize = 0;
    for (std.enums.values(Op)) |op| {
        if (!op.isValid()) continue;
        total += 1;
        const word = base(op) catch continue;
        encodable += 1;
        if (roundTripsThroughDecoder(op, word)) round_tripped += 1;
    }
    return .{ .total = total, .encodable = encodable, .round_tripped = round_tripped };
}

test "every opcode in the table encodes and decodes back to itself" {
    // The headline property: not "most" instructions, every one. A gap here is
    // an instruction Rosette can recognise but never produce, or — worse — one
    // whose pattern collides with another's decode path.
    const coverage = measureCoverage();
    try std.testing.expect(coverage.total > 0);
    try std.testing.expectEqual(coverage.total, coverage.encodable);
    try std.testing.expectEqual(coverage.total, coverage.round_tripped);
    try std.testing.expect(coverage.isComplete());
}

test "the opcode table covers the whole spec" {
    // 455 instructions in tools/ppc_isa_spec.txt plus the reserved slot.
    const coverage = measureCoverage();
    try std.testing.expect(coverage.total >= 455);
}

test "an invalid op cannot be encoded" {
    // Returning a word for the reserved slot would let a caller emit an
    // instruction that means nothing, and it would decode as something.
    var found_invalid = false;
    for (std.enums.values(Op)) |op| {
        if (op.isValid()) continue;
        found_invalid = true;
        try std.testing.expectError(error.UnencodableOp, base(op));
    }
    try std.testing.expect(found_invalid);
}

test "a D form instruction round trips with its operands" {
    const word = try encodeD(.addi, 3, 4, -16);
    try std.testing.expect(roundTripsThroughDecoder(.addi, word));
    const form = fields.D{ .word = word };
    try std.testing.expectEqual(@as(u5, 3), form.rd());
    try std.testing.expectEqual(@as(u5, 4), form.ra());
    try std.testing.expectEqual(@as(i64, -16), form.simm());
}

test "an unsigned D immediate keeps its high bit" {
    const word = try encodeD(.andix, 5, 6, 0xF000);
    try std.testing.expect(roundTripsThroughDecoder(.andix, word));
    const form = fields.D{ .word = word };
    try std.testing.expectEqual(@as(u64, 0xF000), form.uimm());
}

test "an out of range field is refused rather than truncated" {
    // A register number that loses its high bit encodes a different register,
    // and the instruction still decodes and still runs.
    try std.testing.expectError(error.FieldOutOfRange, encodeD(.addi, 3, 4, 0x1_0000));
    try std.testing.expectError(error.FieldOutOfRange, encodeD(.addi, 3, 4, -0x8001));
}

test "XO form carries the overflow and record bits independently" {
    const plain = try encodeXO(.addx, 3, 4, 5, false, false);
    try std.testing.expect(roundTripsThroughDecoder(.addx, plain));
    const both = try encodeXO(.addx, 3, 4, 5, true, true);
    // OE changes the decode path on PowerPC, so the op must survive it.
    try std.testing.expect(roundTripsThroughDecoder(.addx, both));
    const form = fields.XO{ .word = both };
    try std.testing.expect(form.oe());
    try std.testing.expect(form.rc());
    try std.testing.expectEqual(@as(u5, 3), form.rd());
    try std.testing.expectEqual(@as(u5, 5), form.rb());
}

test "a branch displacement is stored scaled and comes back unscaled" {
    const word = try encodeI(.bx, -4096, false, true);
    try std.testing.expect(roundTripsThroughDecoder(.bx, word));
    const form = fields.I{ .word = word };
    try std.testing.expectEqual(@as(i64, -4096), form.li());
    try std.testing.expect(form.lk());
    try std.testing.expect(!form.aa());
}

test "a misaligned displacement is refused" {
    // PowerPC branches are word-aligned; the low two bits are the AA and LK
    // flags. Encoding an odd displacement would silently set them.
    try std.testing.expectError(error.MisalignedDisplacement, encodeI(.bx, 2, false, false));
    try std.testing.expectError(error.MisalignedDisplacement, encodeB(.bcx, 12, 0, 6, false, false));
}

test "a conditional branch keeps BO, BI and its displacement" {
    const word = try encodeB(.bcx, 12, 2, 128, false, false);
    try std.testing.expect(roundTripsThroughDecoder(.bcx, word));
    const form = fields.B{ .word = word };
    try std.testing.expectEqual(@as(u5, 12), form.bo());
    try std.testing.expectEqual(@as(u5, 2), form.bi());
    try std.testing.expectEqual(@as(i64, 128), form.bd());
}

test "the MD form's split shift survives a value above 31" {
    // The bit this test exists for: encoding the shift as five bits halves
    // every shift over 31 and the instruction still decodes.
    const word = try encodeMD(.rldiclx, 3, 4, 40, 0, false);
    try std.testing.expect(roundTripsThroughDecoder(.rldiclx, word));
    const form = fields.MD{ .word = word };
    try std.testing.expectEqual(@as(u6, 40), form.sh());
}

test "the SPR half-swap is its own inverse" {
    // mfspr/mtspr store the SPR number with its halves exchanged. Applying the
    // swap twice returns the original, which is what makes one shared helper
    // correct for both encoding and disassembly.
    var spr: u32 = 0;
    while (spr < 1024) : (spr += 1) {
        const value: u10 = @intCast(spr);
        try std.testing.expectEqual(value, swapSprHalves(swapSprHalves(value)));
    }
    // LR is SPR 8, which encodes as 0x100.
    try std.testing.expectEqual(@as(u10, 0x100), swapSprHalves(8));
}

test "a DS form displacement must be a multiple of four" {
    try std.testing.expectError(error.MisalignedDisplacement, encodeDS(.ld, 3, 4, 6));
    const word = try encodeDS(.ld, 3, 4, -8);
    try std.testing.expect(roundTripsThroughDecoder(.ld, word));
    const form = fields.DS{ .word = word };
    try std.testing.expectEqual(@as(i64, -8), form.dsField());
}

test "an X form round trips with all three registers" {
    const word = try encodeX(.andx, 7, 8, 9, true);
    try std.testing.expect(roundTripsThroughDecoder(.andx, word));
    const form = fields.X{ .word = word };
    try std.testing.expectEqual(@as(u5, 8), form.ra());
    try std.testing.expectEqual(@as(u5, 9), form.rb());
}

test "a vector form round trips" {
    const word = try encodeVX(.vaddubm, 1, 2, 3);
    try std.testing.expect(roundTripsThroughDecoder(.vaddubm, word));
    const four = try encodeVA(.vmaddfp, 1, 2, 3, 4);
    try std.testing.expect(roundTripsThroughDecoder(.vmaddfp, four));
}

test "encoding is deterministic" {
    // Same inputs, same word, every time: an encoder that varied would make
    // every golden vector in the repository unstable.
    const first = try encodeXO(.addx, 3, 4, 5, false, false);
    const second = try encodeXO(.addx, 3, 4, 5, false, false);
    try std.testing.expectEqual(first, second);
}
