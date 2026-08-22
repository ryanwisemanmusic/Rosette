//! PowerPC AltiVec (VMX) execution.
//!
//! A vector register is 128 bits, and everything about how it is *read* depends
//! on the lane width the instruction names. The register is stored here as four
//! 32-bit words with word 0 at the high end, matching how it sits in guest
//! memory, so byte 0 is the most significant byte of word 0. Element index 0 is
//! therefore the leftmost element at every width - the opposite of the
//! little-endian intuition, and the reason `vperm`, `vmrgh*`, and `vsldoi` are
//! the three instructions most likely to be subtly reversed.
//!
//! `vperm` in particular reads its selector as an index into the 32-byte
//! concatenation of vA and vB, counted from vA's *first* byte. An implementation
//! that counts from the low end produces a permutation that is correct whenever
//! the pattern happens to be symmetric, which for a texture-swizzle table is
//! often enough to look like it works.
//!
//! The Xenon's VMX128 extension widens the register file to 128 entries. The
//! register file here is sized for that; the VMX128 *instructions* are decoded
//! but not yet executed, and report themselves as gaps rather than aliasing
//! down to their 32-register AltiVec cousins.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");
const state_mod = @import("state.zig");

const Context = ctx_mod.Context;
const Outcome = ctx_mod.Outcome;
const Instruction = ctx_mod.Instruction;
const Fault = ctx_mod.Fault;
const Vector = state_mod.Vector;

/// VSCR bits, given as architectural bit numbers.
pub const Vscr = struct {
    /// Saturation occurred, sticky.
    pub const sat: u32 = 1;
    /// Non-Java (fast) floating-point mode.
    pub const nj: u32 = 1 << 16;
};

fn readVr(c: *const Context, index: u5) Vector {
    return c.state.vr[index];
}

fn writeVr(c: *Context, index: u5, value: Vector) void {
    c.state.vr[index] = value;
}

/// The 16 bytes of a vector, in architectural order: byte 0 is the most
/// significant byte of word 0.
fn toBytes(v: Vector) [16]u8 {
    var out: [16]u8 = undefined;
    inline for (0..4) |word| {
        std.mem.writeInt(u32, out[word * 4 ..][0..4], v[word], .big);
    }
    return out;
}

fn fromBytes(bytes: [16]u8) Vector {
    var out: Vector = undefined;
    inline for (0..4) |word| {
        out[word] = std.mem.readInt(u32, bytes[word * 4 ..][0..4], .big);
    }
    return out;
}

/// View a vector as N elements of type T, element 0 leftmost.
fn toLanes(comptime T: type, v: Vector) [16 / @sizeOf(T)]T {
    const count = 16 / @sizeOf(T);
    const bytes = toBytes(v);
    var out: [count]T = undefined;
    inline for (0..count) |i| {
        out[i] = std.mem.readInt(T, bytes[i * @sizeOf(T) ..][0..@sizeOf(T)], .big);
    }
    return out;
}

fn fromLanes(comptime T: type, lanes: [16 / @sizeOf(T)]T) Vector {
    const count = 16 / @sizeOf(T);
    var bytes: [16]u8 = undefined;
    inline for (0..count) |i| {
        std.mem.writeInt(T, bytes[i * @sizeOf(T) ..][0..@sizeOf(T)], lanes[i], .big);
    }
    return fromBytes(bytes);
}

fn toFloats(v: Vector) [4]f32 {
    var out: [4]f32 = undefined;
    inline for (0..4) |i| out[i] = @bitCast(v[i]);
    return out;
}

fn fromFloats(values: [4]f32) Vector {
    var out: Vector = undefined;
    inline for (0..4) |i| out[i] = @bitCast(values[i]);
    return out;
}

fn setSaturated(c: *Context) void {
    c.state.vscr |= Vscr.sat;
}

/// A vector compare's Rc bit writes CR6: bit 0 means every lane matched, bit 2
/// means no lane did. Guests branch on both, so neither can be left unwritten.
fn recordCr6(c: *Context, insn: Instruction, result: Vector) void {
    if (!insn.rc()) return;
    var all: bool = true;
    var none: bool = true;
    for (result) |word| {
        if (word != 0xFFFF_FFFF) all = false;
        if (word != 0) none = false;
    }
    var field: u4 = 0;
    if (all) field |= 0b1000;
    if (none) field |= 0b0010;
    c.state.setCrField(6, field);
}

pub fn execute(c: *Context, insn: Instruction) Fault!Outcome {
    return switch (insn.op) {
        // -- memory ---------------------------------------------------------
        .lvx, .lvxl => loadVector(c, insn),
        .stvx, .stvxl => storeVector(c, insn),
        .lvebx => loadElement(c, insn, u8),
        .lvehx => loadElement(c, insn, u16),
        .lvewx => loadElement(c, insn, u32),
        .stvebx => storeElement(c, insn, u8),
        .stvehx => storeElement(c, insn, u16),
        .stvewx => storeElement(c, insn, u32),
        .lvsl => shiftControl(c, insn, .left),
        .lvsr => shiftControl(c, insn, .right),

        // -- logical ---------------------------------------------------------
        .vand => logical(c, insn, .andop),
        .vandc => logical(c, insn, .andc),
        .vor => logical(c, insn, .orop),
        .vnor => logical(c, insn, .nor),
        .vxor => logical(c, insn, .xorop),

        // -- integer add / subtract -------------------------------------------
        .vaddubm => addSub(c, insn, u8, .add, .modulo),
        .vadduhm => addSub(c, insn, u16, .add, .modulo),
        .vadduwm => addSub(c, insn, u32, .add, .modulo),
        .vsububm => addSub(c, insn, u8, .subtract, .modulo),
        .vsubuhm => addSub(c, insn, u16, .subtract, .modulo),
        .vsubuwm => addSub(c, insn, u32, .subtract, .modulo),
        .vaddubs => addSub(c, insn, u8, .add, .saturate),
        .vadduhs => addSub(c, insn, u16, .add, .saturate),
        .vadduws => addSub(c, insn, u32, .add, .saturate),
        .vsububs => addSub(c, insn, u8, .subtract, .saturate),
        .vsubuhs => addSub(c, insn, u16, .subtract, .saturate),
        .vsubuws => addSub(c, insn, u32, .subtract, .saturate),
        .vaddsbs => addSub(c, insn, i8, .add, .saturate),
        .vaddshs => addSub(c, insn, i16, .add, .saturate),
        .vaddsws => addSub(c, insn, i32, .add, .saturate),
        .vsubsbs => addSub(c, insn, i8, .subtract, .saturate),
        .vsubshs => addSub(c, insn, i16, .subtract, .saturate),
        .vsubsws => addSub(c, insn, i32, .subtract, .saturate),

        // -- integer max / min / average ---------------------------------------
        .vmaxub => minMax(c, insn, u8, .max),
        .vmaxuh => minMax(c, insn, u16, .max),
        .vmaxuw => minMax(c, insn, u32, .max),
        .vmaxsb => minMax(c, insn, i8, .max),
        .vmaxsh => minMax(c, insn, i16, .max),
        .vmaxsw => minMax(c, insn, i32, .max),
        .vminub => minMax(c, insn, u8, .min),
        .vminuh => minMax(c, insn, u16, .min),
        .vminuw => minMax(c, insn, u32, .min),
        .vminsb => minMax(c, insn, i8, .min),
        .vminsh => minMax(c, insn, i16, .min),
        .vminsw => minMax(c, insn, i32, .min),

        // -- shift and rotate ---------------------------------------------------
        .vslb => shift(c, insn, u8, .left),
        .vslh => shift(c, insn, u16, .left),
        .vslw => shift(c, insn, u32, .left),
        .vsrb => shift(c, insn, u8, .right),
        .vsrh => shift(c, insn, u16, .right),
        .vsrw => shift(c, insn, u32, .right),
        .vsrab => shift(c, insn, i8, .arithmetic),
        .vsrah => shift(c, insn, i16, .arithmetic),
        .vsraw => shift(c, insn, i32, .arithmetic),
        .vrlb => rotate(c, insn, u8),
        .vrlh => rotate(c, insn, u16),
        .vrlw => rotate(c, insn, u32),

        // -- compare -------------------------------------------------------------
        .vcmpequb => compareInteger(c, insn, u8, .equal),
        .vcmpequh => compareInteger(c, insn, u16, .equal),
        .vcmpequw => compareInteger(c, insn, u32, .equal),
        .vcmpgtub => compareInteger(c, insn, u8, .greater),
        .vcmpgtuh => compareInteger(c, insn, u16, .greater),
        .vcmpgtuw => compareInteger(c, insn, u32, .greater),
        .vcmpgtsb => compareInteger(c, insn, i8, .greater),
        .vcmpgtsh => compareInteger(c, insn, i16, .greater),
        .vcmpgtsw => compareInteger(c, insn, i32, .greater),
        .vcmpeqfp => compareFloat(c, insn, .equal),
        .vcmpgefp => compareFloat(c, insn, .greater_equal),
        .vcmpgtfp => compareFloat(c, insn, .greater),

        // -- merge, splat, permute, select -----------------------------------------
        .vmrghb => merge(c, insn, u8, .high),
        .vmrghh => merge(c, insn, u16, .high),
        .vmrghw => merge(c, insn, u32, .high),
        .vmrglb => merge(c, insn, u8, .low),
        .vmrglh => merge(c, insn, u16, .low),
        .vmrglw => merge(c, insn, u32, .low),
        .vspltb => splat(c, insn, u8),
        .vsplth => splat(c, insn, u16),
        .vspltw => splat(c, insn, u32),
        .vspltisb => splatImmediate(c, insn, i8),
        .vspltish => splatImmediate(c, insn, i16),
        .vspltisw => splatImmediate(c, insn, i32),
        .vperm => permute(c, insn),
        .vsel => selectBits(c, insn),
        .vsldoi => shiftDoubleOctet(c, insn),

        // -- floating point ----------------------------------------------------------
        .vaddfp => floatBinary(c, insn, .add),
        .vsubfp => floatBinary(c, insn, .subtract),
        .vmaxfp => floatBinary(c, insn, .max),
        .vminfp => floatBinary(c, insn, .min),
        .vmaddfp => floatMultiplyAdd(c, insn, false),
        .vnmsubfp => floatMultiplyAdd(c, insn, true),
        .vrefp => floatUnary(c, insn, .reciprocal),
        .vrsqrtefp => floatUnary(c, insn, .reciprocal_sqrt),
        .vrfim => floatUnary(c, insn, .floor),
        .vrfin => floatUnary(c, insn, .nearest),
        .vrfip => floatUnary(c, insn, .ceil),
        .vrfiz => floatUnary(c, insn, .truncate),
        .vcfsx => convertToFloat(c, insn, i32),
        .vcfux => convertToFloat(c, insn, u32),
        .vctsxs => convertToInteger(c, insn, i32),
        .vctuxs => convertToInteger(c, insn, u32),

        // -- status --------------------------------------------------------------------
        .mfvscr => moveFromVscr(c, insn),
        .mtvscr => moveToVscr(c, insn),

        else => .{ .unimplemented = insn.op },
    };
}

// ---------------------------------------------------------------------------
// Memory
// ---------------------------------------------------------------------------

/// A vector access ignores the low four address bits: it always touches the
/// aligned quadword containing the effective address, never a straddling one.
fn vectorAddress(c: *Context, insn: Instruction) u32 {
    const f = insn.x();
    return @truncate((c.state.ra0(f.ra()) +% c.gpr(f.rb())) & ~@as(u64, 15));
}

fn loadVector(c: *Context, insn: Instruction) Fault!Outcome {
    const ea = vectorAddress(c, insn);
    writeVr(c, insn.x().vd(), try c.memory.readVector(ea));
    return .advance;
}

fn storeVector(c: *Context, insn: Instruction) Fault!Outcome {
    const ea = vectorAddress(c, insn);
    try c.memory.writeVector(ea, readVr(c, insn.x().vs()));
    c.breakReservation(ea);
    return .advance;
}

fn loadElement(c: *Context, insn: Instruction, comptime T: type) Fault!Outcome {
    const f = insn.x();
    const raw: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    const size = @sizeOf(T);
    const ea = raw & ~@as(u32, size - 1);
    const index = (ea & 15) / size;
    // Only the addressed element is defined; the rest of the register is
    // architecturally undefined, and Rosette leaves it alone so a guest that
    // builds a vector one element at a time keeps its earlier elements.
    var lanes = toLanes(T, readVr(c, f.vd()));
    lanes[index] = try c.memory.read(T, ea);
    writeVr(c, f.vd(), fromLanes(T, lanes));
    return .advance;
}

fn storeElement(c: *Context, insn: Instruction, comptime T: type) Fault!Outcome {
    const f = insn.x();
    const raw: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    const size = @sizeOf(T);
    const ea = raw & ~@as(u32, size - 1);
    const index = (ea & 15) / size;
    const lanes = toLanes(T, readVr(c, f.vs()));
    try c.memory.write(T, ea, lanes[index]);
    c.breakReservation(ea);
    return .advance;
}

const ShiftSide = enum { left, right };

/// lvsl/lvsr build the byte-index vector that realigns an unaligned quadword
/// load, which is how a guest reads a vector that does not sit on a boundary.
fn shiftControl(c: *Context, insn: Instruction, comptime side: ShiftSide) Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    const sh: u8 = @truncate(ea & 15);
    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| {
        const index: u8 = @intCast(i);
        b.* = switch (side) {
            .left => sh +% index,
            .right => (16 - sh) +% index,
        };
    }
    writeVr(c, f.vd(), fromBytes(bytes));
    return .advance;
}

// ---------------------------------------------------------------------------
// Logical
// ---------------------------------------------------------------------------

const LogicalKind = enum { andop, andc, orop, nor, xorop };

fn logical(c: *Context, insn: Instruction, comptime kind: LogicalKind) Outcome {
    const f = insn.vx();
    const a = readVr(c, f.va());
    const b = readVr(c, f.vb());
    var out: Vector = undefined;
    inline for (0..4) |i| {
        out[i] = switch (kind) {
            .andop => a[i] & b[i],
            .andc => a[i] & ~b[i],
            .orop => a[i] | b[i],
            .nor => ~(a[i] | b[i]),
            .xorop => a[i] ^ b[i],
        };
    }
    writeVr(c, f.vd(), out);
    return .advance;
}

// ---------------------------------------------------------------------------
// Integer arithmetic
// ---------------------------------------------------------------------------

const AddSubKind = enum { add, subtract };
const Overflow = enum { modulo, saturate };

fn addSub(
    c: *Context,
    insn: Instruction,
    comptime T: type,
    comptime kind: AddSubKind,
    comptime mode: Overflow,
) Outcome {
    const f = insn.vx();
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(T, readVr(c, f.vb()));
    var out: @TypeOf(a) = undefined;
    var saturated = false;
    for (&out, a, b) |*o, x, y| {
        switch (mode) {
            .modulo => o.* = if (kind == .add) x +% y else x -% y,
            .saturate => {
                const pair = if (kind == .add)
                    @addWithOverflow(x, y)
                else
                    @subWithOverflow(x, y);
                if (pair[1] == 0) {
                    o.* = pair[0];
                } else {
                    saturated = true;
                    o.* = saturationBound(T, kind, x, y);
                }
            },
        }
    }
    if (saturated) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

fn saturationBound(comptime T: type, comptime kind: AddSubKind, x: T, y: T) T {
    const info = @typeInfo(T).int;
    if (info.signedness == .unsigned) {
        return if (kind == .add) std.math.maxInt(T) else 0;
    }
    // Signed: the bound is the one on the side the operands pushed toward.
    _ = y;
    return if (x < 0) std.math.minInt(T) else std.math.maxInt(T);
}

const MinMaxKind = enum { min, max };

fn minMax(c: *Context, insn: Instruction, comptime T: type, comptime kind: MinMaxKind) Outcome {
    const f = insn.vx();
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(T, readVr(c, f.vb()));
    var out: @TypeOf(a) = undefined;
    for (&out, a, b) |*o, x, y| {
        o.* = if (kind == .max) @max(x, y) else @min(x, y);
    }
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

const ShiftKind = enum { left, right, arithmetic };

/// A vector shift takes its count from the low bits of the *matching lane* of
/// vB, not from a scalar: each lane can shift by a different amount.
fn shift(c: *Context, insn: Instruction, comptime T: type, comptime kind: ShiftKind) Outcome {
    const f = insn.vx();
    const bits = @bitSizeOf(T);
    const ShiftAmount = std.math.Log2Int(T);
    const Unsigned = std.meta.Int(.unsigned, bits);
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(Unsigned, readVr(c, f.vb()));
    var out: @TypeOf(a) = undefined;
    for (&out, a, b) |*o, x, y| {
        const amount: ShiftAmount = @intCast(y % bits);
        o.* = switch (kind) {
            .left => x << amount,
            .right, .arithmetic => x >> amount,
        };
    }
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

fn rotate(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx();
    const bits = @bitSizeOf(T);
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(T, readVr(c, f.vb()));
    var out: @TypeOf(a) = undefined;
    for (&out, a, b) |*o, x, y| {
        o.* = std.math.rotl(T, x, @as(std.math.Log2Int(T), @intCast(y % bits)));
    }
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

// ---------------------------------------------------------------------------
// Compare
// ---------------------------------------------------------------------------

const CompareKind = enum { equal, greater, greater_equal };

fn compareInteger(
    c: *Context,
    insn: Instruction,
    comptime T: type,
    comptime kind: CompareKind,
) Outcome {
    const f = insn.vc();
    const bits = @bitSizeOf(T);
    const Unsigned = std.meta.Int(.unsigned, bits);
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(T, readVr(c, f.vb()));
    var out: [16 / @sizeOf(T)]Unsigned = undefined;
    for (&out, a, b) |*o, x, y| {
        const matched = switch (kind) {
            .equal => x == y,
            .greater => x > y,
            .greater_equal => x >= y,
        };
        // A vector compare writes all-ones or all-zeros, never 1 or 0: the
        // result is a mask meant to be fed straight into vsel.
        o.* = if (matched) std.math.maxInt(Unsigned) else 0;
    }
    const result = fromLanes(Unsigned, out);
    writeVr(c, f.vd(), result);
    recordCr6(c, insn, result);
    return .advance;
}

fn compareFloat(c: *Context, insn: Instruction, comptime kind: CompareKind) Outcome {
    const f = insn.vc();
    const a = toFloats(readVr(c, f.va()));
    const b = toFloats(readVr(c, f.vb()));
    var out: Vector = undefined;
    inline for (0..4) |i| {
        const matched = switch (kind) {
            .equal => a[i] == b[i],
            .greater => a[i] > b[i],
            .greater_equal => a[i] >= b[i],
        };
        out[i] = if (matched) 0xFFFF_FFFF else 0;
    }
    writeVr(c, f.vd(), out);
    recordCr6(c, insn, out);
    return .advance;
}

// ---------------------------------------------------------------------------
// Merge, splat, permute, select
// ---------------------------------------------------------------------------

const MergeHalf = enum { high, low };

fn merge(c: *Context, insn: Instruction, comptime T: type, comptime half: MergeHalf) Outcome {
    const f = insn.vx();
    const count = 16 / @sizeOf(T);
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(T, readVr(c, f.vb()));
    var out: [count]T = undefined;
    const base = if (half == .high) 0 else count / 2;
    inline for (0..count / 2) |i| {
        out[i * 2] = a[base + i];
        out[i * 2 + 1] = b[base + i];
    }
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

fn splat(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx();
    const count = 16 / @sizeOf(T);
    const source = toLanes(T, readVr(c, f.vb()));
    const index = @as(usize, f.uimm()) % count;
    var out: [count]T = undefined;
    for (&out) |*o| o.* = source[index];
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

fn splatImmediate(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx();
    const count = 16 / @sizeOf(T);
    const value: T = @truncate(f.simm());
    var out: [count]T = undefined;
    for (&out) |*o| o.* = value;
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

/// vperm indexes the 32-byte concatenation vA || vB, counting from vA's first
/// (most significant) byte. Only the low five bits of each selector are used.
fn permute(c: *Context, insn: Instruction) Outcome {
    const f = insn.va();
    const a = toBytes(readVr(c, f.va()));
    const b = toBytes(readVr(c, f.vb()));
    const selector = toBytes(readVr(c, f.vc()));
    var out: [16]u8 = undefined;
    for (&out, selector) |*o, sel| {
        const index = sel & 0x1F;
        o.* = if (index < 16) a[index] else b[index - 16];
    }
    writeVr(c, f.vd(), fromBytes(out));
    return .advance;
}

/// vsel is a bitwise select: each *bit* of vC picks between vA and vB, which is
/// what makes it compose with the all-ones/all-zeros masks the compares produce.
fn selectBits(c: *Context, insn: Instruction) Outcome {
    const f = insn.va();
    const a = readVr(c, f.va());
    const b = readVr(c, f.vb());
    const mask = readVr(c, f.vc());
    var out: Vector = undefined;
    inline for (0..4) |i| out[i] = (a[i] & ~mask[i]) | (b[i] & mask[i]);
    writeVr(c, f.vd(), out);
    return .advance;
}

fn shiftDoubleOctet(c: *Context, insn: Instruction) Outcome {
    const f = insn.va();
    const a = toBytes(readVr(c, f.va()));
    const b = toBytes(readVr(c, f.vb()));
    const sh: usize = f.shb();
    var concat: [32]u8 = undefined;
    @memcpy(concat[0..16], &a);
    @memcpy(concat[16..32], &b);
    var out: [16]u8 = undefined;
    @memcpy(&out, concat[sh .. sh + 16]);
    writeVr(c, f.vd(), fromBytes(out));
    return .advance;
}

// ---------------------------------------------------------------------------
// Floating point
// ---------------------------------------------------------------------------

const FloatBinaryKind = enum { add, subtract, max, min };

fn floatBinary(c: *Context, insn: Instruction, comptime kind: FloatBinaryKind) Outcome {
    const f = insn.vx();
    const a = toFloats(readVr(c, f.va()));
    const b = toFloats(readVr(c, f.vb()));
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        out[i] = switch (kind) {
            .add => a[i] + b[i],
            .subtract => a[i] - b[i],
            .max => @max(a[i], b[i]),
            .min => @min(a[i], b[i]),
        };
    }
    writeVr(c, f.vd(), fromFloats(out));
    return .advance;
}

/// vmaddfp is (vA * vC) + vB, and vnmsubfp is -((vA * vC) - vB). Both take vC
/// as the multiplier and vB as the addend, which is the opposite of the operand
/// order the mnemonic reads in.
fn floatMultiplyAdd(c: *Context, insn: Instruction, comptime negate_subtract: bool) Outcome {
    const f = insn.va();
    const a = toFloats(readVr(c, f.va()));
    const b = toFloats(readVr(c, f.vb()));
    const m = toFloats(readVr(c, f.vc()));
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        out[i] = if (negate_subtract)
            -@mulAdd(f32, a[i], m[i], -b[i])
        else
            @mulAdd(f32, a[i], m[i], b[i]);
    }
    writeVr(c, f.vd(), fromFloats(out));
    return .advance;
}

const FloatUnaryKind = enum { reciprocal, reciprocal_sqrt, floor, ceil, truncate, nearest };

fn floatUnary(c: *Context, insn: Instruction, comptime kind: FloatUnaryKind) Outcome {
    const f = insn.vx();
    const b = toFloats(readVr(c, f.vb()));
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        out[i] = switch (kind) {
            .reciprocal => 1.0 / b[i],
            .reciprocal_sqrt => 1.0 / @sqrt(b[i]),
            .floor => @floor(b[i]),
            .ceil => @ceil(b[i]),
            .truncate => @trunc(b[i]),
            .nearest => @round(b[i]),
        };
    }
    writeVr(c, f.vd(), fromFloats(out));
    return .advance;
}

/// vcfsx/vcfux divide by 2^UIMM after converting: the immediate is a fixed-point
/// scale, so ignoring it gives values 2^UIMM too large.
fn convertToFloat(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx();
    const lanes = toLanes(T, readVr(c, f.vb()));
    const scale = std.math.pow(f32, 2.0, @floatFromInt(f.uimm()));
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        const value: f32 = @floatFromInt(lanes[i]);
        out[i] = value / scale;
    }
    writeVr(c, f.vd(), fromFloats(out));
    return .advance;
}

fn convertToInteger(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx();
    const b = toFloats(readVr(c, f.vb()));
    const scale = std.math.pow(f32, 2.0, @floatFromInt(f.uimm()));
    var out: [4]T = undefined;
    var saturated = false;
    inline for (0..4) |i| {
        const scaled = @trunc(b[i] * scale);
        const min: f32 = @floatFromInt(std.math.minInt(T));
        const max: f32 = @floatFromInt(std.math.maxInt(T));
        if (std.math.isNan(scaled)) {
            out[i] = 0;
            saturated = true;
        } else if (scaled <= min) {
            out[i] = std.math.minInt(T);
            saturated = true;
        } else if (scaled >= max) {
            out[i] = std.math.maxInt(T);
            saturated = true;
        } else {
            out[i] = @intFromFloat(scaled);
        }
    }
    if (saturated) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

fn moveFromVscr(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx();
    // VSCR lands in the *low* word of the vector, which is word 3 here.
    writeVr(c, f.vd(), .{ 0, 0, 0, c.state.vscr });
    return .advance;
}

fn moveToVscr(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx();
    c.state.vscr = readVr(c, f.vb())[3];
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
    buf: [256]u8 = [_]u8{0} ** 256,

    fn run(self: *Harness, word: u32) Fault!Outcome {
        var c = Context.init(&self.state, Memory.fromSlice(&self.buf, base_address));
        return execute(&c, ppc_decode.decodeWord(base_address, word));
    }
};

fn vxWord(vd: u32, va: u32, vb: u32, xo: u32) u32 {
    return (4 << 26) | (vd << 21) | (va << 16) | (vb << 11) | xo;
}

fn vaWord(vd: u32, va: u32, vb: u32, vc: u32, xo: u32) u32 {
    return (4 << 26) | (vd << 21) | (va << 16) | (vb << 11) | (vc << 6) | xo;
}

fn vcWord(vd: u32, va: u32, vb: u32, rc: u32, xo: u32) u32 {
    return (4 << 26) | (vd << 21) | (va << 16) | (vb << 11) | (rc << 10) | xo;
}

test "lane zero is the leftmost element at every width" {
    const v: Vector = .{ 0x00010203, 0x04050607, 0x08090A0B, 0x0C0D0E0F };
    const bytes = toBytes(v);
    try testing.expectEqual(@as(u8, 0x00), bytes[0]);
    try testing.expectEqual(@as(u8, 0x0F), bytes[15]);
    const halves = toLanes(u16, v);
    try testing.expectEqual(@as(u16, 0x0001), halves[0]);
    try testing.expectEqual(@as(u16, 0x0E0F), halves[7]);
    try testing.expectEqual(v, fromLanes(u16, halves));
}

test "an integer add is modulo per lane at the named width" {
    var h = Harness{};
    h.state.vr[1] = .{ 0x00FF00FF, 0, 0, 0 };
    h.state.vr[2] = .{ 0x00010001, 0, 0, 0 };
    _ = try h.run(vxWord(3, 1, 2, 0)); // vaddubm
    try testing.expectEqual(@as(u32, 0x00000000), h.state.vr[3][0]);
    _ = try h.run(vxWord(3, 1, 2, 64)); // vadduhm
    try testing.expectEqual(@as(u32, 0x01000100), h.state.vr[3][0]);
}

test "a saturating add clamps and latches VSCR.SAT" {
    var h = Harness{};
    h.state.vr[1] = .{ 0xFFFFFFFF, 0, 0, 0 };
    h.state.vr[2] = .{ 0x01010101, 0, 0, 0 };
    _ = try h.run(vxWord(3, 1, 2, 512)); // vaddubs
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), h.state.vr[3][0]);
    try testing.expect(h.state.vscr & Vscr.sat != 0);
}

test "a compare writes an all-ones mask, not a one" {
    var h = Harness{};
    h.state.vr[1] = .{ 5, 7, 9, 11 };
    h.state.vr[2] = .{ 5, 0, 9, 0 };
    _ = try h.run(vcWord(3, 1, 2, 0, 134)); // vcmpequw
    try testing.expectEqual(Vector{ 0xFFFFFFFF, 0, 0xFFFFFFFF, 0 }, h.state.vr[3]);
}

test "a compare with Rc reports all-lanes and no-lanes into CR6" {
    var h = Harness{};
    h.state.vr[1] = .{ 1, 2, 3, 4 };
    h.state.vr[2] = .{ 1, 2, 3, 4 };
    _ = try h.run(vcWord(3, 1, 2, 1, 134));
    try testing.expectEqual(@as(u4, 0b1000), h.state.crField(6)); // all

    h.state.vr[2] = .{ 9, 9, 9, 9 };
    _ = try h.run(vcWord(3, 1, 2, 1, 134));
    try testing.expectEqual(@as(u4, 0b0010), h.state.crField(6)); // none

    h.state.vr[2] = .{ 1, 9, 9, 9 };
    _ = try h.run(vcWord(3, 1, 2, 1, 134));
    try testing.expectEqual(@as(u4, 0b0000), h.state.crField(6)); // mixed
}

test "vperm counts from vA's first byte, not from the low end" {
    var h = Harness{};
    h.state.vr[1] = .{ 0x00010203, 0x04050607, 0x08090A0B, 0x0C0D0E0F };
    h.state.vr[2] = .{ 0x10111213, 0x14151617, 0x18191A1B, 0x1C1D1E1F };
    // Selector 0,1,2,...,15 must reproduce vA exactly.
    h.state.vr[4] = .{ 0x00010203, 0x04050607, 0x08090A0B, 0x0C0D0E0F };
    _ = try h.run(vaWord(3, 1, 2, 4, 43)); // vperm
    try testing.expectEqual(h.state.vr[1], h.state.vr[3]);

    // Selector 16..31 must reproduce vB exactly.
    h.state.vr[4] = .{ 0x10111213, 0x14151617, 0x18191A1B, 0x1C1D1E1F };
    _ = try h.run(vaWord(3, 1, 2, 4, 43));
    try testing.expectEqual(h.state.vr[2], h.state.vr[3]);
}

test "vsel selects per bit so it composes with a compare mask" {
    var h = Harness{};
    h.state.vr[1] = .{ 0xAAAAAAAA, 0, 0, 0 };
    h.state.vr[2] = .{ 0x55555555, 0, 0, 0 };
    h.state.vr[4] = .{ 0x0000FFFF, 0, 0, 0 };
    _ = try h.run(vaWord(3, 1, 2, 4, 42)); // vsel
    try testing.expectEqual(@as(u32, 0xAAAA5555), h.state.vr[3][0]);
}

test "vmrghw interleaves the high halves and vmrglw the low" {
    var h = Harness{};
    h.state.vr[1] = .{ 1, 2, 3, 4 };
    h.state.vr[2] = .{ 5, 6, 7, 8 };
    _ = try h.run(vxWord(3, 1, 2, 140)); // vmrghw
    try testing.expectEqual(Vector{ 1, 5, 2, 6 }, h.state.vr[3]);
    _ = try h.run(vxWord(3, 1, 2, 396)); // vmrglw
    try testing.expectEqual(Vector{ 3, 7, 4, 8 }, h.state.vr[3]);
}

test "vspltw broadcasts the element the immediate names" {
    var h = Harness{};
    h.state.vr[2] = .{ 10, 20, 30, 40 };
    _ = try h.run(vxWord(3, 2, 2, 652)); // vspltw vD, vB, 2
    try testing.expectEqual(Vector{ 30, 30, 30, 30 }, h.state.vr[3]);
}

test "vspltisw sign-extends its five-bit immediate" {
    var h = Harness{};
    _ = try h.run(vxWord(3, 0x1F, 0, 908)); // vspltisw vD, -1
    try testing.expectEqual(Vector{ 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF }, h.state.vr[3]);
}

test "vsldoi slides a window across the concatenation of vA and vB" {
    var h = Harness{};
    h.state.vr[1] = .{ 0x00010203, 0x04050607, 0x08090A0B, 0x0C0D0E0F };
    h.state.vr[2] = .{ 0x10111213, 0x14151617, 0x18191A1B, 0x1C1D1E1F };
    const word = (4 << 26) | (3 << 21) | (1 << 16) | (2 << 11) | (4 << 6) | 44;
    _ = try h.run(word); // vsldoi vD, vA, vB, 4
    try testing.expectEqual(Vector{ 0x04050607, 0x08090A0B, 0x0C0D0E0F, 0x10111213 }, h.state.vr[3]);
}

test "a vector load ignores the low four address bits" {
    var h = Harness{};
    h.buf[0..16].* = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 7; // deliberately unaligned
    _ = try h.run((31 << 26) | (3 << 21) | (4 << 16) | (5 << 11) | (103 << 1)); // lvx
    try testing.expectEqual(@as(u32, 0x01020304), h.state.vr[3][0]);
}

test "lvsl builds the byte indices that realign an unaligned load" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 3;
    _ = try h.run((31 << 26) | (3 << 21) | (4 << 16) | (5 << 11) | (6 << 1)); // lvsl
    const bytes = toBytes(h.state.vr[3]);
    try testing.expectEqual(@as(u8, 3), bytes[0]);
    try testing.expectEqual(@as(u8, 18), bytes[15]);
}

test "vaddfp operates on four single-precision lanes" {
    var h = Harness{};
    h.state.vr[1] = fromFloats(.{ 1.0, 2.0, 3.0, 4.0 });
    h.state.vr[2] = fromFloats(.{ 0.5, 0.5, 0.5, 0.5 });
    _ = try h.run(vxWord(3, 1, 2, 10)); // vaddfp
    try testing.expectEqual([4]f32{ 1.5, 2.5, 3.5, 4.5 }, toFloats(h.state.vr[3]));
}

test "vcfsx applies the fixed-point scale in its immediate" {
    var h = Harness{};
    h.state.vr[2] = .{ 8, 16, 24, 32 };
    // UIMM = 3 -> divide by 8.
    _ = try h.run(vxWord(3, 3, 2, 842)); // vcfsx
    try testing.expectEqual([4]f32{ 1.0, 2.0, 3.0, 4.0 }, toFloats(h.state.vr[3]));
}

test "a VMX128 instruction reports itself rather than aliasing to AltiVec" {
    var h = Harness{};
    const outcome = try h.run(0x18000210); // vpermwi128
    try testing.expect(outcome.isGap());
    try testing.expectEqual(ppc_decode.Op.vpermwi128, outcome.unimplemented);
}
