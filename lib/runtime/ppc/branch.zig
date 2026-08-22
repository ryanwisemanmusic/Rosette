//! PowerPC branch and condition-register execution.
//!
//! Every conditional branch is driven by one five-bit BO field that encodes
//! two independent tests - a CTR test and a CR-bit test - plus whether CTR is
//! decremented at all. The five bits are numbered from the high end like the
//! rest of the architecture, and reading them from the low end instead gives a
//! branch that is usually right (BO patterns are near-symmetric) and sometimes
//! backwards, which is worse than always wrong.
//!
//! Two things happen regardless of whether the branch is taken:
//!   * CTR is decremented if BO says so, taken or not.
//!   * LR is written if LK is set, taken or not.
//! A `bdnz` that skipped the decrement on the not-taken path would never
//! terminate, and a `bl` that skipped LR on the not-taken path would return to
//! whatever was in LR before.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");

const Context = ctx_mod.Context;
const Outcome = ctx_mod.Outcome;
const Instruction = ctx_mod.Instruction;

/// The BO field, unpacked. Bit 0 is the *most* significant of the five.
const BranchOptions = struct {
    ignore_condition: bool,
    condition_wanted: u1,
    skip_ctr: bool,
    branch_if_ctr_zero: bool,

    fn decode(bo: u5) BranchOptions {
        return .{
            .ignore_condition = (bo >> 4) & 1 != 0,
            .condition_wanted = @truncate((bo >> 3) & 1),
            .skip_ctr = (bo >> 2) & 1 != 0,
            .branch_if_ctr_zero = (bo >> 1) & 1 != 0,
        };
    }
};

/// Evaluate BO against CTR and CR, applying the CTR decrement as a side effect.
fn shouldBranch(c: *Context, bo: u5, bi: u5) bool {
    const options = BranchOptions.decode(bo);
    if (!options.skip_ctr) {
        c.state.ctr = c.state.ctr -% 1;
    }
    const ctr_ok = options.skip_ctr or
        ((c.state.ctr != 0) != options.branch_if_ctr_zero);
    const cond_ok = options.ignore_condition or
        (c.state.crBit(bi) == options.condition_wanted);
    return ctr_ok and cond_ok;
}

pub fn execute(c: *Context, insn: Instruction) Outcome {
    return switch (insn.op) {
        .bx => unconditional(c, insn),
        .bcx => conditional(c, insn),
        .bclrx => toRegister(c, insn, .link),
        .bcctrx => toRegister(c, insn, .count),

        .crand => crLogical(c, insn, .andop),
        .crandc => crLogical(c, insn, .andc),
        .cror => crLogical(c, insn, .orop),
        .crorc => crLogical(c, insn, .orc),
        .crxor => crLogical(c, insn, .xorop),
        .crnand => crLogical(c, insn, .nand),
        .crnor => crLogical(c, insn, .nor),
        .creqv => crLogical(c, insn, .eqv),
        .mcrf => moveCrField(c, insn),

        else => .{ .unimplemented = insn.op },
    };
}

fn unconditional(c: *Context, insn: Instruction) Outcome {
    const f = insn.i();
    const target: u32 = if (f.aa())
        @truncate(@as(u64, @bitCast(f.li())))
    else
        insn.address +% @as(u32, @truncate(@as(u64, @bitCast(f.li()))));
    if (f.lk()) c.state.lr = insn.nextAddress();
    return .{ .branch = target };
}

fn conditional(c: *Context, insn: Instruction) Outcome {
    const f = insn.b();
    // LR is written before the condition is evaluated, and unconditionally.
    if (f.lk()) c.state.lr = insn.nextAddress();
    const taken = shouldBranch(c, f.bo(), f.bi());
    if (!taken) return .advance;
    const target: u32 = if (f.aa())
        @truncate(@as(u64, @bitCast(f.bd())))
    else
        insn.address +% @as(u32, @truncate(@as(u64, @bitCast(f.bd()))));
    return .{ .branch = target };
}

const IndirectSource = enum { link, count };

fn toRegister(c: *Context, insn: Instruction, comptime source: IndirectSource) Outcome {
    const f = insn.xl();
    // Read the target before LR is overwritten: `blrl` returns to its own
    // caller and then makes itself the next return address, and reading LR
    // after the write would send it to the instruction after itself.
    const raw = switch (source) {
        .link => c.state.lr,
        .count => c.state.ctr,
    };
    const target: u32 = @truncate(raw & ~@as(u64, 3));
    if (f.lk()) c.state.lr = insn.nextAddress();

    // bcctr must not decrement CTR: the encoding that would ask for it is
    // architecturally invalid, and honouring it would corrupt the loop counter
    // of the very branch reading it.
    const bo = switch (source) {
        .link => f.bo(),
        .count => f.bo() | 0b00100,
    };
    if (!shouldBranch(c, bo, f.bi())) return .advance;
    return .{ .branch = target };
}

const CrKind = enum { andop, andc, orop, orc, xorop, nand, nor, eqv };

fn crLogical(c: *Context, insn: Instruction, comptime kind: CrKind) Outcome {
    const f = insn.xl();
    const a = c.state.crBit(f.crba());
    const b = c.state.crBit(f.crbb());
    const value: u1 = switch (kind) {
        .andop => a & b,
        .andc => a & ~b,
        .orop => a | b,
        .orc => a | ~b,
        .xorop => a ^ b,
        .nand => ~(a & b),
        .nor => ~(a | b),
        .eqv => ~(a ^ b),
    };
    c.state.setCrBit(f.crbd(), value);
    return .advance;
}

fn moveCrField(c: *Context, insn: Instruction) Outcome {
    const f = insn.xl();
    c.state.setCrField(f.crfd(), c.state.crField(f.crfs()));
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
    buf: [64]u8 = [_]u8{0} ** 64,

    fn run(self: *Harness, address: u32, word: u32) Outcome {
        var c = Context.init(&self.state, Memory.fromSlice(&self.buf, 0x8200_0000));
        return execute(&c, ppc_decode.decodeWord(address, word));
    }
};

/// `bc BO, BI, BD` with the given link and absolute bits.
fn bcWord(bo: u32, bi: u32, bd: i32, aa: u32, lk: u32) u32 {
    const displacement: u32 = @as(u32, @bitCast(bd)) & 0xFFFC;
    return (16 << 26) | (bo << 21) | (bi << 16) | displacement | (aa << 1) | lk;
}

test "an unconditional branch is relative to its own address" {
    var h = Harness{};
    const outcome = h.run(0x8200_1000, 0x48000010); // b +16
    try testing.expectEqual(@as(u32, 0x8200_1010), outcome.branch);
    try testing.expectEqual(@as(u64, 0), h.state.lr); // no LK, no LR write
}

test "bl writes the return address before transferring" {
    var h = Harness{};
    const outcome = h.run(0x8200_1000, 0x48000011); // bl +16
    try testing.expectEqual(@as(u32, 0x8200_1010), outcome.branch);
    try testing.expectEqual(@as(u64, 0x8200_1004), h.state.lr);
}

test "a backward branch sign-extends its displacement" {
    var h = Harness{};
    const outcome = h.run(0x8200_1000, 0x4bfffff0); // b -16
    try testing.expectEqual(@as(u32, 0x8200_0FF0), outcome.branch);
}

test "bdnz decrements CTR on the not-taken path too" {
    var h = Harness{};
    // BO = 0b10000: decrement CTR, branch if CTR != 0, ignore the CR bit.
    h.state.ctr = 2;
    var outcome = h.run(0x8200_1000, bcWord(0b10000, 0, 8, 0, 0));
    try testing.expectEqual(@as(u32, 0x8200_1008), outcome.branch);
    try testing.expectEqual(@as(u64, 1), h.state.ctr);

    outcome = h.run(0x8200_1000, bcWord(0b10000, 0, 8, 0, 0));
    try testing.expectEqual(Outcome.advance, outcome);
    try testing.expectEqual(@as(u64, 0), h.state.ctr);
}

test "a conditional branch tests the CR bit the BO field names" {
    var h = Harness{};
    // BO = 0b01100: no CTR decrement, branch if CR[BI] == 1.
    h.state.setCrBit(2, 1); // CR0.EQ
    var outcome = h.run(0x8200_1000, bcWord(0b01100, 2, 12, 0, 0));
    try testing.expectEqual(@as(u32, 0x8200_100C), outcome.branch);

    h.state.setCrBit(2, 0);
    outcome = h.run(0x8200_1000, bcWord(0b01100, 2, 12, 0, 0));
    try testing.expectEqual(Outcome.advance, outcome);

    // BO = 0b00100: branch if CR[BI] == 0.
    outcome = h.run(0x8200_1000, bcWord(0b00100, 2, 12, 0, 0));
    try testing.expectEqual(@as(u32, 0x8200_100C), outcome.branch);
}

test "bl on a not-taken conditional still writes LR" {
    var h = Harness{};
    h.state.setCrBit(2, 0);
    const outcome = h.run(0x8200_1000, bcWord(0b01100, 2, 12, 0, 1));
    try testing.expectEqual(Outcome.advance, outcome);
    try testing.expectEqual(@as(u64, 0x8200_1004), h.state.lr);
}

test "blr returns through LR and blrl republishes its own return" {
    var h = Harness{};
    h.state.lr = 0x8205_0000;
    var outcome = h.run(0x8200_1000, 0x4e800020); // blr
    try testing.expectEqual(@as(u32, 0x8205_0000), outcome.branch);
    try testing.expectEqual(@as(u64, 0x8205_0000), h.state.lr);

    h.state.lr = 0x8205_0000;
    outcome = h.run(0x8200_1000, 0x4e800021); // blrl
    // The transfer uses the old LR; the new LR is this instruction's successor.
    try testing.expectEqual(@as(u32, 0x8205_0000), outcome.branch);
    try testing.expectEqual(@as(u64, 0x8200_1004), h.state.lr);
}

test "bctr branches through CTR without decrementing it" {
    var h = Harness{};
    h.state.ctr = 0x8203_0000;
    const outcome = h.run(0x8200_1000, 0x4e800420); // bctr
    try testing.expectEqual(@as(u32, 0x8203_0000), outcome.branch);
    try testing.expectEqual(@as(u64, 0x8203_0000), h.state.ctr);
}

test "an indirect target has its low two bits cleared" {
    var h = Harness{};
    h.state.lr = 0x8205_0003;
    const outcome = h.run(0x8200_1000, 0x4e800020);
    try testing.expectEqual(@as(u32, 0x8205_0000), outcome.branch);
}

test "the condition-register logical ops address single bits" {
    var h = Harness{};
    h.state.setCrBit(4, 1); // CR1.LT
    h.state.setCrBit(8, 0); // CR2.LT
    // cror crbD=0, crbA=4, crbB=8
    const cror: u32 = (19 << 26) | (0 << 21) | (4 << 16) | (8 << 11) | (449 << 1);
    _ = h.run(0x8200_1000, cror);
    try testing.expectEqual(@as(u1, 1), h.state.crBit(0));

    // crand of the same pair is zero.
    const crand: u32 = (19 << 26) | (1 << 21) | (4 << 16) | (8 << 11) | (257 << 1);
    _ = h.run(0x8200_1000, crand);
    try testing.expectEqual(@as(u1, 0), h.state.crBit(1));
}

test "mcrf copies a whole four-bit field" {
    var h = Harness{};
    h.state.setCrField(3, 0b1010);
    const mcrf: u32 = (19 << 26) | (0 << 23) | (3 << 18) | (0 << 1);
    _ = h.run(0x8200_1000, mcrf);
    try testing.expectEqual(@as(u4, 0b1010), h.state.crField(0));
}
