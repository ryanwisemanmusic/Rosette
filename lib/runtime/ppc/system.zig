//! PowerPC system, SPR, condition-register-transfer, and trap execution.
//!
//! Almost nothing here computes; it moves architected state between places the
//! guest can see. That makes the failure mode quiet: an SPR that silently reads
//! zero looks like a guest that decided not to use it, and an `sc` that
//! silently advances looks like a kernel call that succeeded. Both are avoided
//! the same way - an SPR Rosette does not model reports itself as a gap, and
//! `sc` is an outcome the caller has to handle rather than a no-op.
//!
//! The barriers (`sync`, `isync`, `eieio`, `lwsync`) are architecturally
//! meaningful and operationally free here: Rosette executes one guest
//! instruction at a time against one coherent guest memory, so there is no
//! reordering for them to prevent. They are listed explicitly rather than
//! falling into the default so that "no-op" is a decision on the record.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");

const Context = ctx_mod.Context;
const Outcome = ctx_mod.Outcome;
const Instruction = ctx_mod.Instruction;

pub fn execute(c: *Context, insn: Instruction) Outcome {
    return switch (insn.op) {
        .sc => systemCall(insn),

        // Barriers. See the module comment: no-ops by argument, not by default.
        .sync, .isync, .eieio => .advance,

        .mfspr => moveFromSpr(c, insn),
        .mtspr => moveToSpr(c, insn),
        .mftb => moveFromTimeBase(c, insn),

        .mfcr => moveFromCr(c, insn),
        .mtcrf => moveToCrFields(c, insn),
        .mcrxr => moveXerToCr(c, insn),

        .tw => trapRegister(c, insn, false),
        .td => trapRegister(c, insn, true),
        .twi => trapImmediate(c, insn, false),
        .tdi => trapImmediate(c, insn, true),

        .mfmsr => moveFromMsr(c, insn),
        .mtmsr, .mtmsrd => moveToMsr(c, insn),

        else => .{ .unimplemented = insn.op },
    };
}

fn systemCall(insn: Instruction) Outcome {
    return .{ .system_call = insn.sc().lev() };
}

fn moveFromSpr(c: *Context, insn: Instruction) Outcome {
    const f = insn.xfx();
    const value = c.state.readSpr(f.spr()) orelse return .{ .unimplemented = insn.op };
    c.setGpr(f.rd(), value);
    return .advance;
}

fn moveToSpr(c: *Context, insn: Instruction) Outcome {
    const f = insn.xfx();
    if (!c.state.writeSpr(f.spr(), c.gpr(f.rs()))) return .{ .unimplemented = insn.op };
    return .advance;
}

fn moveFromTimeBase(c: *Context, insn: Instruction) Outcome {
    const f = insn.xfx();
    // TBR 268 is the low half, 269 the high half. Anything else is a Xenon
    // performance counter Rosette does not model.
    const value: u64 = switch (f.tbr()) {
        268 => c.state.time_base & 0xFFFF_FFFF,
        269 => c.state.time_base >> 32,
        else => return .{ .unimplemented = insn.op },
    };
    c.setGpr(f.rd(), value);
    return .advance;
}

fn moveFromCr(c: *Context, insn: Instruction) Outcome {
    const f = insn.xfx();
    c.setGpr(f.rd(), c.state.cr);
    return .advance;
}

fn moveToCrFields(c: *Context, insn: Instruction) Outcome {
    const f = insn.xfx();
    const source: u32 = @truncate(c.gpr(f.rs()));
    // CRM selects fields from the high end: bit 7 of the mask is CR0.
    var mask: u32 = 0;
    var field: u3 = 0;
    while (true) : (field += 1) {
        if (f.crm() & (@as(u8, 0x80) >> field) != 0) {
            mask |= @as(u32, 0xF) << @intCast((7 - @as(u5, field)) * 4);
        }
        if (field == 7) break;
    }
    c.state.cr = (c.state.cr & ~mask) | (source & mask);
    return .advance;
}

fn moveXerToCr(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    var value: u4 = 0;
    if (c.state.xer.so) value |= 0b1000;
    if (c.state.xer.ov) value |= 0b0100;
    if (c.state.xer.ca) value |= 0b0010;
    c.state.setCrField(f.crfd(), value);
    // mcrxr is the only architected way to clear the sticky summary bit.
    c.state.xer.so = false;
    c.state.xer.ov = false;
    c.state.xer.ca = false;
    return .advance;
}

/// The TO field names five conditions; the trap fires if any selected one
/// holds. Bit 0 is the *most* significant of the five, as everywhere else.
fn trapConditionMet(to: u5, a: i64, b: i64) bool {
    const ua: u64 = @bitCast(a);
    const ub: u64 = @bitCast(b);
    if ((to >> 4) & 1 != 0 and a < b) return true; // signed less than
    if ((to >> 3) & 1 != 0 and a > b) return true; // signed greater than
    if ((to >> 2) & 1 != 0 and a == b) return true; // equal
    if ((to >> 1) & 1 != 0 and ua < ub) return true; // unsigned less than
    if ((to >> 0) & 1 != 0 and ua > ub) return true; // unsigned greater than
    return false;
}

fn trapRegister(c: *Context, insn: Instruction, comptime wide: bool) Outcome {
    const f = insn.x();
    const a = narrow(c.gpr(f.ra()), wide);
    const b = narrow(c.gpr(f.rb()), wide);
    return if (trapConditionMet(f.to(), a, b)) .trap else .advance;
}

fn trapImmediate(c: *Context, insn: Instruction, comptime wide: bool) Outcome {
    const f = insn.d();
    const a = narrow(c.gpr(f.ra()), wide);
    return if (trapConditionMet(f.to(), a, f.simm())) .trap else .advance;
}

/// `tw` compares the low words; `td` compares the full registers. Comparing
/// the wrong width turns a bounds check that should fire into one that does not.
fn narrow(value: u64, comptime wide: bool) i64 {
    return if (wide)
        @bitCast(value)
    else
        @as(i32, @truncate(@as(i64, @bitCast(value))));
}

fn moveFromMsr(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    c.setGpr(f.rd(), c.state.msr);
    return .advance;
}

fn moveToMsr(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    c.state.msr = c.gpr(f.rs());
    return .advance;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const State = ctx_mod.State;
const Memory = ctx_mod.Memory;
const Spr = @import("state.zig").Spr;

const Harness = struct {
    state: State = .{},
    buf: [64]u8 = [_]u8{0} ** 64,

    fn run(self: *Harness, word: u32) Outcome {
        var c = Context.init(&self.state, Memory.fromSlice(&self.buf, 0x8200_0000));
        return execute(&c, ppc_decode.decodeWord(0x8200_0000, word));
    }
};

/// Encode an XFX-form SPR access with the SPR number's halves swapped.
fn sprField(number: u10) u32 {
    const low: u32 = number & 0x1F;
    const high: u32 = (number >> 5) & 0x1F;
    return (low << 5) | high;
}

fn mtsprWord(rs: u32, spr: u10) u32 {
    return (31 << 26) | (rs << 21) | (sprField(spr) << 11) | (467 << 1);
}

fn mfsprWord(rd: u32, spr: u10) u32 {
    return (31 << 26) | (rd << 21) | (sprField(spr) << 11) | (339 << 1);
}

test "sc is an outcome the caller must handle, not a no-op" {
    var h = Harness{};
    const outcome = h.run(0x44000002); // sc
    try testing.expectEqual(@as(u7, 0), outcome.system_call);
}

test "mtspr and mfspr round-trip LR and CTR" {
    var h = Harness{};
    h.state.gpr[3] = 0x8205_1234;
    _ = h.run(mtsprWord(3, Spr.lr));
    try testing.expectEqual(@as(u64, 0x8205_1234), h.state.lr);
    _ = h.run(mfsprWord(4, Spr.lr));
    try testing.expectEqual(@as(u64, 0x8205_1234), h.state.gpr[4]);

    h.state.gpr[3] = 99;
    _ = h.run(mtsprWord(3, Spr.ctr));
    try testing.expectEqual(@as(u64, 99), h.state.ctr);
}

test "an SPR Rosette does not model reports itself instead of reading zero" {
    var h = Harness{};
    const outcome = h.run(mfsprWord(3, 700)); // not a Xenon SPR
    try testing.expect(outcome.isGap());
    try testing.expectEqual(ppc_decode.Op.mfspr, outcome.unimplemented);
    try testing.expectEqual(@as(u64, 0), h.state.gpr[3]); // untouched
}

test "mtcrf writes only the fields its mask selects" {
    var h = Harness{};
    h.state.cr = 0;
    h.state.gpr[3] = 0xFFFF_FFFF;
    // CRM = 0x80 selects CR0 only.
    const word: u32 = (31 << 26) | (3 << 21) | (0x80 << 12) | (144 << 1);
    _ = h.run(word);
    try testing.expectEqual(@as(u32, 0xF000_0000), h.state.cr);
}

test "mfcr reads the whole condition register" {
    var h = Harness{};
    h.state.cr = 0x1234_5678;
    _ = h.run((31 << 26) | (3 << 21) | (19 << 1));
    try testing.expectEqual(@as(u64, 0x1234_5678), h.state.gpr[3]);
}

test "mcrxr is the way the sticky overflow bit gets cleared" {
    var h = Harness{};
    h.state.xer.so = true;
    h.state.xer.ca = true;
    _ = h.run((31 << 26) | (0 << 23) | (512 << 1)); // mcrxr cr0
    try testing.expectEqual(@as(u4, 0b1010), h.state.crField(0));
    try testing.expect(!h.state.xer.so);
    try testing.expect(!h.state.xer.ca);
}

test "tw traps only when a selected condition holds" {
    var h = Harness{};
    h.state.gpr[3] = 5;
    h.state.gpr[4] = 10;
    // TO = 0b10000: trap if signed less than.
    const lt: u32 = (31 << 26) | (0b10000 << 21) | (3 << 16) | (4 << 11) | (4 << 1);
    try testing.expectEqual(Outcome.trap, h.run(lt));

    // TO = 0b01000: trap if signed greater than.
    const gt: u32 = (31 << 26) | (0b01000 << 21) | (3 << 16) | (4 << 11) | (4 << 1);
    try testing.expectEqual(Outcome.advance, h.run(gt));
}

test "tw compares the low words where td compares the full registers" {
    var h = Harness{};
    // Equal in the low word, different at 64 bits.
    h.state.gpr[3] = 0x0000_0001_0000_0005;
    h.state.gpr[4] = 0x0000_0000_0000_0005;
    const to_eq: u32 = 0b00100;
    const tw: u32 = (31 << 26) | (to_eq << 21) | (3 << 16) | (4 << 11) | (4 << 1);
    try testing.expectEqual(Outcome.trap, h.run(tw));
    const td: u32 = (31 << 26) | (to_eq << 21) | (3 << 16) | (4 << 11) | (68 << 1);
    try testing.expectEqual(Outcome.advance, h.run(td));
}

test "the barriers advance without pretending to be unimplemented" {
    var h = Harness{};
    try testing.expectEqual(Outcome.advance, h.run(0x7c0004ac)); // sync
    try testing.expectEqual(Outcome.advance, h.run(0x4c00012c)); // isync
    try testing.expectEqual(Outcome.advance, h.run(0x7c0006ac)); // eieio
}

test "mftb reads the two halves of the time base" {
    var h = Harness{};
    h.state.time_base = 0x1122_3344_5566_7788;
    const tbl: u32 = (31 << 26) | (3 << 21) | (sprField(268) << 11) | (371 << 1);
    _ = h.run(tbl);
    try testing.expectEqual(@as(u64, 0x5566_7788), h.state.gpr[3]);
    const tbu: u32 = (31 << 26) | (4 << 21) | (sprField(269) << 11) | (371 << 1);
    _ = h.run(tbu);
    try testing.expectEqual(@as(u64, 0x1122_3344), h.state.gpr[4]);
}
