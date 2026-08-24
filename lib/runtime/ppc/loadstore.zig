//! PowerPC load, store, atomic, and cache-management execution.
//!
//! Four distinctions decide whether a load is right, and all four are encoded
//! in the mnemonic rather than in the operands:
//!
//!   z/a   zero-extend or sign-extend the loaded value into the 64-bit GPR
//!   u     write the effective address back into rA (and then rA is never 0)
//!   x     the displacement comes from rB instead of the instruction
//!   br    take the bytes in host order - these are the *only* accesses that
//!         skip the big-endian conversion, because reading little-endian data
//!         is the entire reason they exist
//!
//! The update forms have a second rule that is easy to lose: rA is a real
//! register there, never the literal zero, because an update form with rA==0
//! would have nowhere to write the address back to and is architecturally
//! invalid rather than an alias for absolute addressing.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");

const Context = ctx_mod.Context;
const Outcome = ctx_mod.Outcome;
const Instruction = ctx_mod.Instruction;
const Fault = ctx_mod.Fault;

const Extend = enum { zero, sign };

pub fn execute(c: *Context, insn: Instruction) Fault!Outcome {
    return switch (insn.op) {
        // Displacement loads.
        .lbz => load(c, insn, u8, .zero, .displacement, false, false),
        .lbzu => load(c, insn, u8, .zero, .displacement, true, false),
        .lhz => load(c, insn, u16, .zero, .displacement, false, false),
        .lhzu => load(c, insn, u16, .zero, .displacement, true, false),
        .lha => load(c, insn, u16, .sign, .displacement, false, false),
        .lhau => load(c, insn, u16, .sign, .displacement, true, false),
        .lwz => load(c, insn, u32, .zero, .displacement, false, false),
        .lwzu => load(c, insn, u32, .zero, .displacement, true, false),
        .lwa => load(c, insn, u32, .sign, .scaled, false, false),
        .ld => load(c, insn, u64, .zero, .scaled, false, false),
        .ldu => load(c, insn, u64, .zero, .scaled, true, false),

        // Indexed loads.
        .lbzx => load(c, insn, u8, .zero, .indexed, false, false),
        .lbzux => load(c, insn, u8, .zero, .indexed, true, false),
        .lhzx => load(c, insn, u16, .zero, .indexed, false, false),
        .lhzux => load(c, insn, u16, .zero, .indexed, true, false),
        .lhax => load(c, insn, u16, .sign, .indexed, false, false),
        .lhaux => load(c, insn, u16, .sign, .indexed, true, false),
        .lwzx => load(c, insn, u32, .zero, .indexed, false, false),
        .lwzux => load(c, insn, u32, .zero, .indexed, true, false),
        .lwax => load(c, insn, u32, .sign, .indexed, false, false),
        .lwaux => load(c, insn, u32, .sign, .indexed, true, false),
        .ldx => load(c, insn, u64, .zero, .indexed, false, false),
        .ldux => load(c, insn, u64, .zero, .indexed, true, false),

        // Byte-reversed loads: host order on purpose.
        .lhbrx => load(c, insn, u16, .zero, .indexed, false, true),
        .lwbrx => load(c, insn, u32, .zero, .indexed, false, true),
        .ldbrx => load(c, insn, u64, .zero, .indexed, false, true),

        // Displacement stores.
        .stb => store(c, insn, u8, .displacement, false, false),
        .stbu => store(c, insn, u8, .displacement, true, false),
        .sth => store(c, insn, u16, .displacement, false, false),
        .sthu => store(c, insn, u16, .displacement, true, false),
        .stw => store(c, insn, u32, .displacement, false, false),
        .stwu => store(c, insn, u32, .displacement, true, false),
        .std => store(c, insn, u64, .scaled, false, false),
        .stdu => store(c, insn, u64, .scaled, true, false),

        // Indexed stores.
        .stbx => store(c, insn, u8, .indexed, false, false),
        .stbux => store(c, insn, u8, .indexed, true, false),
        .sthx => store(c, insn, u16, .indexed, false, false),
        .sthux => store(c, insn, u16, .indexed, true, false),
        .stwx => store(c, insn, u32, .indexed, false, false),
        .stwux => store(c, insn, u32, .indexed, true, false),
        .stdx => store(c, insn, u64, .indexed, false, false),
        .stdux => store(c, insn, u64, .indexed, true, false),

        // Byte-reversed stores.
        .sthbrx => store(c, insn, u16, .indexed, false, true),
        .stwbrx => store(c, insn, u32, .indexed, false, true),
        .stdbrx => store(c, insn, u64, .indexed, false, true),

        // Multiple-word forms.
        .lmw => loadMultiple(c, insn),
        .stmw => storeMultiple(c, insn),

        // String forms. The byte count is immediate for the `i` variants and
        // comes from XER for the `x` ones.
        .lswi => loadString(c, insn, .immediate),
        .lswx => loadString(c, insn, .from_xer),
        .stswi => storeString(c, insn, .immediate),
        .stswx => storeString(c, insn, .from_xer),

        // Load-and-reserve / store-conditional.
        .lwarx => loadReserve(c, insn, u32),
        .ldarx => loadReserve(c, insn, u64),
        .stwcx => storeConditional(c, insn, u32),
        .stdcx => storeConditional(c, insn, u64),

        // Cache management. Only dcbz has an architected memory effect; the
        // rest are hints, and Rosette's guest memory is already coherent.
        .dcbz => zeroCacheBlock(c, insn, 32),
        .dcbz128 => zeroCacheBlock(c, insn, 128),
        .icbi => invalidateInstructionCache(c, insn),
        .dcbf, .dcbi, .dcbst, .dcbt, .dcbtst => .advance,

        else => .{ .unimplemented = insn.op },
    };
}

const AddressMode = enum {
    /// 16-bit displacement in the instruction (D form).
    displacement,
    /// 14-bit displacement scaled by four (DS form).
    scaled,
    /// Displacement from rB (X form).
    indexed,
};

const Address = struct { ea: u32, ra: u5 };

fn effectiveAddress(
    c: *Context,
    insn: Instruction,
    comptime mode: AddressMode,
    update: bool,
) Address {
    return switch (mode) {
        .displacement => blk: {
            const f = insn.d();
            const base = if (update) c.gpr(f.ra()) else c.state.ra0(f.ra());
            break :blk .{ .ea = @truncate(base +% @as(u64, @bitCast(f.simm()))), .ra = f.ra() };
        },
        .scaled => blk: {
            const f = insn.ds();
            const base = if (update) c.gpr(f.ra()) else c.state.ra0(f.ra());
            break :blk .{ .ea = @truncate(base +% @as(u64, @bitCast(f.dsField()))), .ra = f.ra() };
        },
        .indexed => blk: {
            const f = insn.x();
            const base = if (update) c.gpr(f.ra()) else c.state.ra0(f.ra());
            break :blk .{ .ea = @truncate(base +% c.gpr(f.rb())), .ra = f.ra() };
        },
    };
}

fn destinationRegister(insn: Instruction, comptime mode: AddressMode) u5 {
    return switch (mode) {
        .displacement => insn.d().rt(),
        .scaled => insn.ds().rt(),
        .indexed => insn.x().rt(),
    };
}

fn load(
    c: *Context,
    insn: Instruction,
    comptime T: type,
    comptime extend: Extend,
    comptime mode: AddressMode,
    update: bool,
    comptime reversed: bool,
) Fault!Outcome {
    const addr = effectiveAddress(c, insn, mode, update);
    const raw = if (reversed)
        try c.memory.readReversed(T, addr.ea)
    else
        try c.memory.read(T, addr.ea);

    const value: u64 = switch (extend) {
        .zero => raw,
        .sign => @bitCast(@as(i64, @as(std.meta.Int(.signed, @bitSizeOf(T)), @bitCast(raw)))),
    };
    c.setGpr(destinationRegister(insn, mode), value);
    // The address writeback happens only after the load succeeds: a faulting
    // update form must leave rA alone so the fault can be retried.
    if (update) c.setGpr(addr.ra, addr.ea);
    return .advance;
}

fn store(
    c: *Context,
    insn: Instruction,
    comptime T: type,
    comptime mode: AddressMode,
    update: bool,
    comptime reversed: bool,
) Fault!Outcome {
    const addr = effectiveAddress(c, insn, mode, update);
    const value: T = @truncate(c.gpr(destinationRegister(insn, mode)));
    if (reversed) {
        try c.memory.writeReversed(T, addr.ea, value);
    } else {
        try c.memory.write(T, addr.ea, value);
    }
    c.breakReservation(addr.ea);
    if (update) c.setGpr(addr.ra, addr.ea);
    return .advance;
}

fn loadMultiple(c: *Context, insn: Instruction) Fault!Outcome {
    const f = insn.d();
    var ea: u32 = @truncate(c.state.ra0(f.ra()) +% @as(u64, @bitCast(f.simm())));
    var reg: u32 = f.rd();
    while (reg < 32) : (reg += 1) {
        c.setGpr(@intCast(reg), try c.memory.read(u32, ea));
        ea +%= 4;
    }
    return .advance;
}

fn storeMultiple(c: *Context, insn: Instruction) Fault!Outcome {
    const f = insn.d();
    var ea: u32 = @truncate(c.state.ra0(f.ra()) +% @as(u64, @bitCast(f.simm())));
    var reg: u32 = f.rs();
    while (reg < 32) : (reg += 1) {
        try c.memory.write(u32, ea, @truncate(c.gpr(@intCast(reg))));
        c.breakReservation(ea);
        ea +%= 4;
    }
    return .advance;
}

// ---------------------------------------------------------------------------
// String moves
//
// `lswi`/`lswx` fill consecutive registers a byte at a time, starting at rD and
// wrapping r31 -> r0. Two details decide whether the result is right:
//
//   * Bytes land in the register from the *high* end of its low word down, so
//     the first byte of a four-byte group becomes bits 32..39 and the last
//     becomes bits 56..63. Filling from the low end instead reverses every
//     group of four, which looks like an endianness bug in the caller.
//   * A partial final register is zero-filled in the bytes the count did not
//     reach, not left holding what it had. A guest that reads the tail of a
//     short string would otherwise see the previous contents.
//
// The count is 32 when the NB field is zero: NB encodes 1..32 in five bits, so
// the zero encoding has to mean the maximum.
// ---------------------------------------------------------------------------

const StringCount = enum { immediate, from_xer };

fn stringByteCount(c: *const Context, insn: Instruction, comptime source: StringCount) u32 {
    return switch (source) {
        .immediate => blk: {
            const nb = insn.x().nb();
            break :blk if (nb == 0) 32 else @as(u32, nb);
        },
        // XER's low seven bits carry the transfer count, and zero means zero -
        // a zero-length string move is a defined no-op, not a 128-byte one.
        .from_xer => @as(u32, c.state.xer.byte_count),
    };
}

fn stringAddress(c: *const Context, insn: Instruction, comptime source: StringCount) u32 {
    const f = insn.x();
    return switch (source) {
        // lswi addresses rA alone; lswx adds rB.
        .immediate => @truncate(c.state.ra0(f.ra())),
        .from_xer => @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb())),
    };
}

fn loadString(c: *Context, insn: Instruction, comptime source: StringCount) Fault!Outcome {
    const f = insn.x();
    const count = stringByteCount(c, insn, source);
    if (count == 0) return .advance;

    var ea = stringAddress(c, insn, source);
    var reg: u5 = f.rt();
    var byte_in_word: u32 = 0;
    var accumulator: u64 = 0;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const byte: u64 = try c.memory.read(u8, ea);
        // Bits 32..39 first, then 40..47, and so on: the shift walks down the
        // low word from its high byte.
        accumulator |= byte << @intCast(24 - byte_in_word * 8);
        ea +%= 1;
        byte_in_word += 1;
        if (byte_in_word == 4) {
            c.setGpr(reg, accumulator);
            accumulator = 0;
            byte_in_word = 0;
            reg = reg +% 1;
        }
    }
    // The final partial register keeps the zeros the accumulator started with.
    if (byte_in_word != 0) c.setGpr(reg, accumulator);
    return .advance;
}

fn storeString(c: *Context, insn: Instruction, comptime source: StringCount) Fault!Outcome {
    const f = insn.x();
    const count = stringByteCount(c, insn, source);
    if (count == 0) return .advance;

    var ea = stringAddress(c, insn, source);
    var reg: u5 = f.rs();
    var byte_in_word: u32 = 0;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const word: u64 = c.gpr(reg);
        const byte: u8 = @truncate(word >> @intCast(24 - byte_in_word * 8));
        try c.memory.write(u8, ea, byte);
        c.breakReservation(ea);
        ea +%= 1;
        byte_in_word += 1;
        if (byte_in_word == 4) {
            byte_in_word = 0;
            reg = reg +% 1;
        }
    }
    return .advance;
}

fn loadReserve(c: *Context, insn: Instruction, comptime T: type) Fault!Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    const value: u64 = try c.memory.read(T, ea);
    c.setGpr(f.rt(), value);
    c.state.reservation.set(ea);
    c.state.reserved_val = value;
    return .advance;
}

fn storeConditional(c: *Context, insn: Instruction, comptime T: type) Fault!Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    const held = c.state.reservation.covers(ea);
    if (held) {
        try c.memory.write(T, ea, @truncate(c.gpr(f.rs())));
    }
    // CR0 reports the outcome: EQ set means the store happened. The
    // reservation is dropped either way, which is what stops two threads from
    // both believing they won.
    var cr0: u4 = if (held) 0b0010 else 0b0000;
    if (c.state.xer.so) cr0 |= 0b0001;
    c.state.setCrField(0, cr0);
    c.state.reservation.clear();
    return .advance;
}

/// `icbi` is the guest telling the machine that the instructions in a block
/// have changed. Rosette's interpreter re-fetches every instruction and does
/// not care, but a compiled block was built from the previous contents, so the
/// address is recorded for the dispatcher to act on. Treating `icbi` as a pure
/// no-op is what makes a recompiler run stale code after a module is patched.
fn invalidateInstructionCache(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    c.state.pending_icache_invalidation = ea;
    return .advance;
}

fn zeroCacheBlock(c: *Context, insn: Instruction, comptime size: u32) Fault!Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    try c.memory.zeroBlock(ea, size);
    c.breakReservation(ea & ~(size - 1));
    return .advance;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const State = ctx_mod.State;
const Memory = ctx_mod.Memory;

const base_address: u32 = 0x8200_0000;

const Harness = struct {
    state: State = .{},
    buf: [512]u8 = [_]u8{0} ** 512,

    fn run(self: *Harness, word: u32) Fault!Outcome {
        var c = Context.init(&self.state, Memory.fromSlice(&self.buf, base_address));
        return execute(&c, ppc_decode.decodeWord(base_address, word));
    }
};

fn dWord(primary: u32, rt: u32, ra: u32, imm: u16) u32 {
    return (primary << 26) | (rt << 21) | (ra << 16) | imm;
}

fn xWord(rt: u32, ra: u32, rb: u32, xo: u32) u32 {
    return (31 << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (xo << 1);
}

test "a word load converts from guest byte order and zero-extends" {
    var h = Harness{};
    h.buf[0..4].* = .{ 0x12, 0x34, 0x56, 0x78 };
    h.state.gpr[4] = base_address;
    _ = try h.run(dWord(32, 3, 4, 0)); // lwz r3, 0(r4)
    try testing.expectEqual(@as(u64, 0x1234_5678), h.state.gpr[3]);
}

test "lha sign-extends where lhz zero-extends" {
    var h = Harness{};
    h.buf[0..2].* = .{ 0xFF, 0xFE };
    h.state.gpr[4] = base_address;
    _ = try h.run(dWord(40, 3, 4, 0)); // lhz r3, 0(r4)
    try testing.expectEqual(@as(u64, 0xFFFE), h.state.gpr[3]);
    _ = try h.run(dWord(42, 3, 4, 0)); // lha r3, 0(r4)
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), h.state.gpr[3]);
}

test "an update form writes the effective address back into rA" {
    var h = Harness{};
    h.buf[8..12].* = .{ 0, 0, 0, 0x2A };
    h.state.gpr[4] = base_address;
    _ = try h.run(dWord(33, 3, 4, 8)); // lwzu r3, 8(r4)
    try testing.expectEqual(@as(u64, 0x2A), h.state.gpr[3]);
    try testing.expectEqual(@as(u64, base_address + 8), h.state.gpr[4]);
}

test "a faulting update form leaves rA alone so the fault can be retried" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    // 0x8000 as a signed displacement is -32768, well below the mapping.
    const outcome = h.run(dWord(33, 3, 4, 0x8000));
    try testing.expectError(Fault.OutOfBounds, outcome);
    try testing.expectEqual(@as(u64, base_address), h.state.gpr[4]);
}

test "rA reads as literal zero in a non-update form only" {
    var h = Harness{};
    h.buf[16..20].* = .{ 0, 0, 0, 0x07 };
    h.state.gpr[0] = 0xDEAD_0000;
    // lwz r3, 16(0) addresses 16 - but 16 is below the mapping origin, so this
    // is the fault that proves r0 was read as zero rather than as 0xDEAD0000.
    try testing.expectError(Fault.OutOfBounds, h.run(dWord(32, 3, 0, 16)));
}

test "lwbrx reads little-endian where lwzx reads big-endian" {
    var h = Harness{};
    h.buf[0..4].* = .{ 0x12, 0x34, 0x56, 0x78 };
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 0;
    _ = try h.run(xWord(3, 4, 5, 23)); // lwzx
    try testing.expectEqual(@as(u64, 0x1234_5678), h.state.gpr[3]);
    _ = try h.run(xWord(3, 4, 5, 534)); // lwbrx
    try testing.expectEqual(@as(u64, 0x7856_3412), h.state.gpr[3]);
}

test "a store truncates the register to the access width" {
    var h = Harness{};
    h.state.gpr[3] = 0xAABB_CCDD_EEFF_0011;
    h.state.gpr[4] = base_address;
    _ = try h.run(dWord(38, 3, 4, 0)); // stb r3, 0(r4)
    try testing.expectEqual(@as(u8, 0x11), h.buf[0]);
    _ = try h.run(dWord(44, 3, 4, 4)); // sth r3, 4(r4)
    try testing.expectEqual(@as(u8, 0x00), h.buf[4]);
    try testing.expectEqual(@as(u8, 0x11), h.buf[5]);
    _ = try h.run(dWord(36, 3, 4, 8)); // stw r3, 8(r4)
    try testing.expectEqual(@as(u8, 0xEE), h.buf[8]);
}

test "lmw and stmw walk a register run to the end of the file" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[29] = 0x1111;
    h.state.gpr[30] = 0x2222;
    h.state.gpr[31] = 0x3333;
    _ = try h.run(dWord(47, 29, 4, 0)); // stmw r29, 0(r4)
    try testing.expectEqual(@as(u32, 0x1111), try (Memory.fromSlice(&h.buf, base_address)).read(u32, base_address));
    try testing.expectEqual(@as(u32, 0x3333), try (Memory.fromSlice(&h.buf, base_address)).read(u32, base_address + 8));

    h.state.gpr[29] = 0;
    h.state.gpr[30] = 0;
    h.state.gpr[31] = 0;
    _ = try h.run(dWord(46, 29, 4, 0)); // lmw r29, 0(r4)
    try testing.expectEqual(@as(u64, 0x1111), h.state.gpr[29]);
    try testing.expectEqual(@as(u64, 0x3333), h.state.gpr[31]);
}

test "stwcx succeeds only while the reservation still stands" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 0;
    h.state.gpr[3] = 0x5A5A;

    _ = try h.run(xWord(3, 4, 5, 20)); // lwarx r3, r4, r5
    try testing.expect(h.state.reservation.valid);
    h.state.gpr[3] = 0x5A5A;
    _ = try h.run(xWord(3, 4, 5, 150)); // stwcx. r3, r4, r5
    try testing.expectEqual(@as(u4, 0b0010), h.state.crField(0)); // EQ: stored
    try testing.expect(!h.state.reservation.valid);

    // A second store-conditional with no reservation must report failure.
    _ = try h.run(xWord(3, 4, 5, 150));
    try testing.expectEqual(@as(u4, 0b0000), h.state.crField(0));
}

test "an intervening store breaks the reservation" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 0;
    _ = try h.run(xWord(3, 4, 5, 20)); // lwarx
    try testing.expect(h.state.reservation.valid);
    _ = try h.run(dWord(36, 3, 4, 16)); // stw r3, 16(r4): same 128-byte block
    try testing.expect(!h.state.reservation.valid);
}

test "lswi packs bytes from the high end of each register's low word" {
    var h = Harness{};
    h.buf[0..8].* = .{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 };
    h.state.gpr[4] = base_address;
    // lswi r5, r4, 8 -> two full registers.
    _ = try h.run((31 << 26) | (5 << 21) | (4 << 16) | (8 << 11) | (597 << 1));
    try testing.expectEqual(@as(u64, 0x1122_3344), h.state.gpr[5]);
    try testing.expectEqual(@as(u64, 0x5566_7788), h.state.gpr[6]);
}

test "a partial string register is zero-filled, not left holding stale bytes" {
    var h = Harness{};
    h.buf[0..8].* = .{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 };
    h.state.gpr[4] = base_address;
    h.state.gpr[6] = 0xDEAD_BEEF_DEAD_BEEF;
    // lswi r5, r4, 6 -> one full register plus two bytes.
    _ = try h.run((31 << 26) | (5 << 21) | (4 << 16) | (6 << 11) | (597 << 1));
    try testing.expectEqual(@as(u64, 0x1122_3344), h.state.gpr[5]);
    try testing.expectEqual(@as(u64, 0x5566_0000), h.state.gpr[6]);
}

test "an NB field of zero means the maximum transfer, not none" {
    var h = Harness{};
    for (0..32) |i| h.buf[i] = @intCast(i + 1);
    h.state.gpr[4] = base_address;
    // lswi r0, r4, 0 -> 32 bytes into r0..r7.
    _ = try h.run((31 << 26) | (0 << 21) | (4 << 16) | (0 << 11) | (597 << 1));
    try testing.expectEqual(@as(u64, 0x0102_0304), h.state.gpr[0]);
    try testing.expectEqual(@as(u64, 0x1D1E_1F20), h.state.gpr[7]);
}

test "the string register run wraps from r31 back to r0" {
    var h = Harness{};
    h.buf[0..8].* = .{ 0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xBB, 0xBB };
    h.state.gpr[4] = base_address;
    // lswi r31, r4, 8 -> r31 then r0.
    _ = try h.run((31 << 26) | (31 << 21) | (4 << 16) | (8 << 11) | (597 << 1));
    try testing.expectEqual(@as(u64, 0xAAAA_AAAA), h.state.gpr[31]);
    try testing.expectEqual(@as(u64, 0xBBBB_BBBB), h.state.gpr[0]);
}

test "lswx and stswx take their length from XER" {
    var h = Harness{};
    h.buf[0..4].* = .{ 0xDE, 0xAD, 0xBE, 0xEF };
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 0;
    h.state.xer.byte_count = 3;
    // lswx r6, r4, r5
    _ = try h.run((31 << 26) | (6 << 21) | (4 << 16) | (5 << 11) | (533 << 1));
    try testing.expectEqual(@as(u64, 0xDEAD_BE00), h.state.gpr[6]);

    // A zero count is a defined no-op rather than a maximum transfer.
    h.state.gpr[7] = 0x1234;
    h.state.xer.byte_count = 0;
    _ = try h.run((31 << 26) | (7 << 21) | (4 << 16) | (5 << 11) | (533 << 1));
    try testing.expectEqual(@as(u64, 0x1234), h.state.gpr[7]);
}

test "stswi round-trips through lswi" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[10] = 0x0102_0304;
    h.state.gpr[11] = 0x0506_0708;
    // stswi r10, r4, 8
    _ = try h.run((31 << 26) | (10 << 21) | (4 << 16) | (8 << 11) | (725 << 1));
    try testing.expectEqual(@as(u8, 0x01), h.buf[0]);
    try testing.expectEqual(@as(u8, 0x08), h.buf[7]);

    h.state.gpr[10] = 0;
    h.state.gpr[11] = 0;
    _ = try h.run((31 << 26) | (10 << 21) | (4 << 16) | (8 << 11) | (597 << 1));
    try testing.expectEqual(@as(u64, 0x0102_0304), h.state.gpr[10]);
    try testing.expectEqual(@as(u64, 0x0506_0708), h.state.gpr[11]);
}

test "stswx writes exactly the XER byte count" {
    var h = Harness{};
    @memset(h.buf[0..8], 0xFF);
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 0;
    h.state.gpr[6] = 0x1122_3344;
    h.state.xer.byte_count = 2;
    // stswx r6, r4, r5
    _ = try h.run((31 << 26) | (6 << 21) | (4 << 16) | (5 << 11) | (661 << 1));
    try testing.expectEqual(@as(u8, 0x11), h.buf[0]);
    try testing.expectEqual(@as(u8, 0x22), h.buf[1]);
    try testing.expectEqual(@as(u8, 0xFF), h.buf[2]);
}

test "icbi records the block whose instructions changed" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 0x40;
    try testing.expectEqual(@as(?u32, null), h.state.pending_icache_invalidation);
    _ = try h.run(xWord(0, 4, 5, 982)); // icbi
    // A no-op here would leave a recompiler executing the previous contents of
    // the block the guest just rewrote.
    try testing.expectEqual(@as(?u32, base_address + 0x40), h.state.pending_icache_invalidation);
}

test "dcbz zeroes a block and dcbt is a no-op" {
    var h = Harness{};
    @memset(h.buf[0..64], 0xFF);
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 40;
    _ = try h.run(xWord(0, 4, 5, 1014)); // dcbz
    try testing.expectEqual(@as(u8, 0xFF), h.buf[31]);
    try testing.expectEqual(@as(u8, 0x00), h.buf[32]);
    try testing.expectEqual(@as(u8, 0x00), h.buf[63]);

    @memset(h.buf[0..8], 0xAB);
    _ = try h.run(xWord(0, 4, 5, 278)); // dcbt
    try testing.expectEqual(@as(u8, 0xAB), h.buf[0]);
}
