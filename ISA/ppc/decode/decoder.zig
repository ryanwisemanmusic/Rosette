//! PowerPC instruction decoder.
//!
//! Decoding is two steps and no state: fetch four big-endian bytes, then run
//! the generated primary/extended decision tree. There is no prefix walk, no
//! ModRM, no instruction-length ambiguity, and no mode to thread through - the
//! whole reason a direct PPC front end is cheaper than re-decoding the x86 a
//! PowerPC JIT emitted.
//!
//! The decoded `Instruction` keeps the raw word rather than a copy of every
//! field. Field extraction is a shift and a mask, so pulling operands on demand
//! through the form accessors costs less than materialising a wide struct that
//! most handlers would read three fields out of.

const std = @import("std");

pub const fields = @import("fields.zig");
pub const opcode = @import("opcode.zig");
pub const table = @import("table.zig");

pub const Op = opcode.Op;
pub const Form = opcode.Form;
pub const Group = opcode.Group;
pub const Info = opcode.Info;

/// A decoded PowerPC instruction: its guest address, its raw big-endian word
/// already byte-swapped into host order, and its opcode identity.
pub const Instruction = struct {
    address: u32,
    word: u32,
    op: Op,

    pub fn info(self: Instruction) Info {
        return self.op.info();
    }

    pub fn form(self: Instruction) Form {
        return self.op.info().form;
    }

    pub fn group(self: Instruction) Group {
        return self.op.info().group;
    }

    pub fn isValid(self: Instruction) bool {
        return self.op.isValid();
    }

    /// True when this instruction ends a basic block: every branch, plus `sc`.
    pub fn endsBlock(self: Instruction) bool {
        return self.op.info().ends_block;
    }

    /// The address of the following instruction. PowerPC instructions are all
    /// four bytes, so this never depends on the decode.
    pub fn nextAddress(self: Instruction) u32 {
        return self.address +% 4;
    }

    /// The record bit, or false for an instruction that has no record bit.
    pub fn rc(self: Instruction) bool {
        const meta = self.op.info();
        if (!meta.has_rc) return false;
        // An AltiVec compare puts its record bit at architectural bit 21, not 31.
        return switch (meta.form) {
            .vc => fields.bit(self.word, 10) != 0,
            .vx128_r => fields.bit(self.word, 6) != 0,
            else => fields.bit(self.word, 0) != 0,
        };
    }

    /// The overflow-enable bit, or false for an instruction that has none.
    pub fn oe(self: Instruction) bool {
        if (!self.op.info().has_oe) return false;
        return fields.bit(self.word, 10) != 0;
    }

    /// The link bit, or false for an instruction that has none.
    pub fn lk(self: Instruction) bool {
        if (!self.op.info().has_lk) return false;
        return fields.bit(self.word, 0) != 0;
    }

    pub fn d(self: Instruction) fields.D {
        return .{ .word = self.word };
    }
    pub fn ds(self: Instruction) fields.DS {
        return .{ .word = self.word };
    }
    pub fn b(self: Instruction) fields.B {
        return .{ .word = self.word };
    }
    pub fn i(self: Instruction) fields.I {
        return .{ .word = self.word };
    }
    pub fn sc(self: Instruction) fields.SC {
        return .{ .word = self.word };
    }
    pub fn x(self: Instruction) fields.X {
        return .{ .word = self.word };
    }
    pub fn xl(self: Instruction) fields.XL {
        return .{ .word = self.word };
    }
    pub fn xfx(self: Instruction) fields.XFX {
        return .{ .word = self.word };
    }
    pub fn xfl(self: Instruction) fields.XFL {
        return .{ .word = self.word };
    }
    pub fn xs(self: Instruction) fields.XS {
        return .{ .word = self.word };
    }
    pub fn xo(self: Instruction) fields.XO {
        return .{ .word = self.word };
    }
    pub fn a(self: Instruction) fields.A {
        return .{ .word = self.word };
    }
    pub fn m(self: Instruction) fields.M {
        return .{ .word = self.word };
    }
    pub fn md(self: Instruction) fields.MD {
        return .{ .word = self.word };
    }
    pub fn mds(self: Instruction) fields.MDS {
        return .{ .word = self.word };
    }
    pub fn vx(self: Instruction) fields.VX {
        return .{ .word = self.word };
    }
    pub fn vc(self: Instruction) fields.VC {
        return .{ .word = self.word };
    }
    pub fn va(self: Instruction) fields.VA {
        return .{ .word = self.word };
    }
    pub fn vx128(self: Instruction) fields.VX128 {
        return .{ .word = self.word };
    }
    pub fn vx128_1(self: Instruction) fields.VX128_1 {
        return .{ .word = self.word };
    }
    pub fn vx128_2(self: Instruction) fields.VX128_2 {
        return .{ .word = self.word };
    }
    pub fn vx128_3(self: Instruction) fields.VX128_3 {
        return .{ .word = self.word };
    }
    pub fn vx128_4(self: Instruction) fields.VX128_4 {
        return .{ .word = self.word };
    }
    pub fn vx128_5(self: Instruction) fields.VX128_5 {
        return .{ .word = self.word };
    }
    pub fn vx128_r(self: Instruction) fields.VX128_R {
        return .{ .word = self.word };
    }
    pub fn vx128_p(self: Instruction) fields.VX128_P {
        return .{ .word = self.word };
    }
};

/// Decode one already-host-order instruction word.
pub fn decodeWord(address: u32, word: u32) Instruction {
    return .{ .address = address, .word = word, .op = table.decodeOp(word) };
}

/// Decode one instruction from four big-endian guest bytes.
pub fn decodeBytes(address: u32, code: *const [4]u8) Instruction {
    return decodeWord(address, std.mem.readInt(u32, code, .big));
}

/// Decode from a guest byte slice. Returns null when fewer than four bytes are
/// available: a truncated fetch is a memory fault, not an invalid opcode, and
/// the two need different handling upstream.
pub fn decodeSlice(address: u32, code: []const u8) ?Instruction {
    if (code.len < 4) return null;
    return decodeBytes(address, code[0..4]);
}

/// Decode a run of instructions into `out`, stopping at the end of the buffer
/// or after the instruction that ends the block. Returns how many were written.
pub fn decodeBlock(address: u32, code: []const u8, out: []Instruction) usize {
    var count: usize = 0;
    var offset: usize = 0;
    while (count < out.len and offset + 4 <= code.len) {
        const insn = decodeBytes(@truncate(address +% offset), code[offset..][0..4]);
        out[count] = insn;
        count += 1;
        offset += 4;
        if (insn.endsBlock()) break;
    }
    return count;
}

test "a big-endian word decodes to its opcode and operands" {
    // add. r3, r4, r5
    const bytes = [_]u8{ 0x7c, 0x64, 0x2a, 0x15 };
    const insn = decodeBytes(0x82000000, &bytes);
    try std.testing.expectEqual(Op.addx, insn.op);
    try std.testing.expectEqual(Form.xo, insn.form());
    try std.testing.expectEqual(Group.integer, insn.group());
    try std.testing.expect(insn.rc());
    try std.testing.expect(!insn.oe());
    try std.testing.expectEqual(@as(u5, 3), insn.xo().rd());
    try std.testing.expectEqual(@as(u32, 0x82000004), insn.nextAddress());
}

test "the Xenia prologue std encoding decodes as a DS-form store" {
    // std r28, -40(r1), observed at the first direct-PPC guest frontier.
    const bytes = [_]u8{ 0xfb, 0x81, 0xff, 0xd8 };
    const insn = decodeBytes(0x8258_dfe8, &bytes);
    try std.testing.expectEqual(Op.std, insn.op);
    try std.testing.expectEqual(@as(u5, 28), insn.ds().rs());
    try std.testing.expectEqual(@as(u5, 1), insn.ds().ra());
    try std.testing.expectEqual(@as(i64, -40), insn.ds().dsField());
}

test "little-endian bytes decode to something else entirely" {
    // The same word fed in host order is a different instruction. This is the
    // failure a missing byte swap produces: a clean decode of the wrong thing.
    const swapped = [_]u8{ 0x15, 0x2a, 0x64, 0x7c };
    const insn = decodeBytes(0x82000000, &swapped);
    try std.testing.expect(insn.op != Op.addx);
}

test "a short fetch is refused rather than decoded from padding" {
    try std.testing.expect(decodeSlice(0x82000000, &[_]u8{ 0x7c, 0x64 }) == null);
    try std.testing.expect(decodeSlice(0x82000000, &[_]u8{ 0x7c, 0x64, 0x2a, 0x15 }) != null);
}

test "block decode stops at the branch that ends it" {
    var out: [8]Instruction = undefined;
    const code = [_]u8{
        0x38, 0x60, 0x00, 0x01, // li r3, 1  (addi r3, 0, 1)
        0x38, 0x80, 0x00, 0x02, // li r4, 2
        0x7c, 0x64, 0x2a, 0x14, // add r3, r4, r5
        0x4e, 0x80, 0x00, 0x20, // blr
        0x38, 0xa0, 0x00, 0x03, // li r5, 3  (past the block end)
    };
    const count = decodeBlock(0x82000000, &code, &out);
    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expectEqual(Op.addi, out[0].op);
    try std.testing.expectEqual(Op.addx, out[2].op);
    try std.testing.expectEqual(Op.bclrx, out[3].op);
    try std.testing.expect(out[3].endsBlock());
}

test "an unallocated encoding decodes to invalid instead of guessing" {
    const insn = decodeWord(0x82000000, 0x04000000);
    try std.testing.expect(!insn.isValid());
    try std.testing.expectEqual(Op.invalid, insn.op);
}
