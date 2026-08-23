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
//! The Xenon's VMX128 extension widens the register file to 128 entries and
//! adds its own encodings for most of these operations. Those live in vmx128.zig
//! and share the lane helpers below, because the two instruction sets differ in
//! how a register is *named*, not in what a lane means.

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
pub fn toBytes(v: Vector) [16]u8 {
    var out: [16]u8 = undefined;
    inline for (0..4) |word| {
        std.mem.writeInt(u32, out[word * 4 ..][0..4], v[word], .big);
    }
    return out;
}

pub fn fromBytes(bytes: [16]u8) Vector {
    var out: Vector = undefined;
    inline for (0..4) |word| {
        out[word] = std.mem.readInt(u32, bytes[word * 4 ..][0..4], .big);
    }
    return out;
}

/// View a vector as N elements of type T, element 0 leftmost.
pub fn toLanes(comptime T: type, v: Vector) [16 / @sizeOf(T)]T {
    const count = 16 / @sizeOf(T);
    const bytes = toBytes(v);
    var out: [count]T = undefined;
    inline for (0..count) |i| {
        out[i] = std.mem.readInt(T, bytes[i * @sizeOf(T) ..][0..@sizeOf(T)], .big);
    }
    return out;
}

pub fn fromLanes(comptime T: type, lanes: [16 / @sizeOf(T)]T) Vector {
    const count = 16 / @sizeOf(T);
    var bytes: [16]u8 = undefined;
    inline for (0..count) |i| {
        std.mem.writeInt(T, bytes[i * @sizeOf(T) ..][0..@sizeOf(T)], lanes[i], .big);
    }
    return fromBytes(bytes);
}

pub fn toFloats(v: Vector) [4]f32 {
    var out: [4]f32 = undefined;
    inline for (0..4) |i| out[i] = @bitCast(v[i]);
    return out;
}

pub fn fromFloats(values: [4]f32) Vector {
    var out: Vector = undefined;
    inline for (0..4) |i| out[i] = @bitCast(values[i]);
    return out;
}

pub fn setSaturated(c: *Context) void {
    c.state.vscr |= Vscr.sat;
}

/// A vector compare's Rc bit writes CR6: bit 0 means every lane matched, bit 2
/// means no lane did. Guests branch on both, so neither can be left unwritten.
pub fn recordCr6(c: *Context, insn: Instruction, result: Vector) void {
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

        // -- Xenon unaligned vector load/store ------------------------------------------
        .lvlx, .lvlxl => loadUnaligned(c, insn, .left),
        .lvrx, .lvrxl => loadUnaligned(c, insn, .right),
        .stvlx, .stvlxl => storeUnaligned(c, insn, .left),
        .stvrx, .stvrxl => storeUnaligned(c, insn, .right),

        // -- carry / borrow -------------------------------------------------------------
        .vaddcuw => carryOut(c, insn, .add),
        .vsubcuw => carryOut(c, insn, .subtract),

        // -- rounding average ------------------------------------------------------------
        .vavgub => average(c, insn, u8),
        .vavguh => average(c, insn, u16),
        .vavguw => average(c, insn, u32),
        .vavgsb => average(c, insn, i8),
        .vavgsh => average(c, insn, i16),
        .vavgsw => average(c, insn, i32),

        // -- multiply even / odd ----------------------------------------------------------
        .vmuleub => multiplyLanes(c, insn, u8, u16, .even),
        .vmuloub => multiplyLanes(c, insn, u8, u16, .odd),
        .vmulesb => multiplyLanes(c, insn, i8, i16, .even),
        .vmulosb => multiplyLanes(c, insn, i8, i16, .odd),
        .vmuleuh => multiplyLanes(c, insn, u16, u32, .even),
        .vmulouh => multiplyLanes(c, insn, u16, u32, .odd),
        .vmulesh => multiplyLanes(c, insn, i16, i32, .even),
        .vmulosh => multiplyLanes(c, insn, i16, i32, .odd),

        // -- multiply-accumulate -----------------------------------------------------------
        .vmhaddshs => multiplyHighAdd(c, insn, false),
        .vmhraddshs => multiplyHighAdd(c, insn, true),
        .vmladduhm => multiplyLowAdd(c, insn),
        .vmsumubm => multiplySum(c, insn, u8, u32, .modulo),
        .vmsummbm => multiplySumMixed(c, insn),
        .vmsumuhm => multiplySum(c, insn, u16, u32, .modulo),
        .vmsumuhs => multiplySum(c, insn, u16, u32, .saturate),
        .vmsumshm => multiplySum(c, insn, i16, i32, .modulo),
        .vmsumshs => multiplySum(c, insn, i16, i32, .saturate),

        // -- horizontal sums ------------------------------------------------------------------
        .vsumsws => sumAcross(c, insn, .all_four),
        .vsum2sws => sumAcross(c, insn, .pairs),
        .vsum4sbs => sumWithin(c, insn, i8, i32),
        .vsum4shs => sumWithin(c, insn, i16, i32),
        .vsum4ubs => sumWithin(c, insn, u8, u32),

        // -- pack -------------------------------------------------------------------------------
        .vpkuhum => pack(c, insn, u16, u8, .modulo),
        .vpkuwum => pack(c, insn, u32, u16, .modulo),
        .vpkuhus => pack(c, insn, u16, u8, .saturate),
        .vpkuwus => pack(c, insn, u32, u16, .saturate),
        .vpkshus => pack(c, insn, i16, u8, .saturate),
        .vpkswus => pack(c, insn, i32, u16, .saturate),
        .vpkshss => pack(c, insn, i16, i8, .saturate),
        .vpkswss => pack(c, insn, i32, i16, .saturate),
        .vpkpx => packPixel(c, insn),

        // -- unpack -----------------------------------------------------------------------------
        .vupkhsb => unpack(c, insn, i8, i16, .high),
        .vupklsb => unpack(c, insn, i8, i16, .low),
        .vupkhsh => unpack(c, insn, i16, i32, .high),
        .vupklsh => unpack(c, insn, i16, i32, .low),
        .vupkhpx => unpackPixel(c, insn, .high),
        .vupklpx => unpackPixel(c, insn, .low),

        // -- whole-register shifts ------------------------------------------------------------------
        .vsl => shiftWhole(c, insn, .left, .bits),
        .vsr => shiftWhole(c, insn, .right, .bits),
        .vslo => shiftWhole(c, insn, .left, .bytes),
        .vsro => shiftWhole(c, insn, .right, .bytes),

        // -- bounds compare and transcendental estimates ---------------------------------------------
        .vcmpbfp => compareBounds(c, insn),
        .vexptefp => floatUnary(c, insn, .exp2),
        .vlogefp => floatUnary(c, insn, .log2),

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

const FloatUnaryKind = enum { reciprocal, reciprocal_sqrt, floor, ceil, truncate, nearest, exp2, log2 };

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
            // The architecture only requires these to be estimates (relative
            // error under 1/32), but a correctly-rounded result is inside that
            // bound, so computing exactly is a legal implementation.
            .exp2 => std.math.exp2(b[i]),
            .log2 => std.math.log2(b[i]),
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

// ---------------------------------------------------------------------------
// Xenon unaligned vector load / store
//
// `lvlx`/`lvrx` exist to load a quadword that is not on a 16-byte boundary,
// which `lvx` cannot do because it discards the low four address bits. The pair
// splits the access: lvlx takes the bytes from the address to the end of its
// block and left-justifies them, lvrx takes the bytes before the address and
// right-justifies them, and a `vor` of the two at addresses A and A+16 rebuilds
// the unaligned quadword.
//
// The bytes the instruction does not reach are *zeroed*, not left alone. That
// is what makes the vor idiom work: if either half preserved the register's
// prior contents, the or would merge in stale bytes.
// ---------------------------------------------------------------------------

const UnalignedSide = enum { left, right };

fn loadUnaligned(c: *Context, insn: Instruction, comptime side: UnalignedSide) Fault!Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    const offset: usize = ea & 15;
    var bytes: [16]u8 = [_]u8{0} ** 16;
    switch (side) {
        .left => {
            // Bytes [EA, EA + 16 - offset) land at the front of the register.
            var i: usize = 0;
            while (i < 16 - offset) : (i += 1) {
                bytes[i] = try c.memory.read(u8, ea +% @as(u32, @intCast(i)));
            }
        },
        .right => {
            // Bytes [EA - offset, EA) land at the back of the register.
            var i: usize = 0;
            while (i < offset) : (i += 1) {
                bytes[16 - offset + i] = try c.memory.read(u8, ea - @as(u32, @intCast(offset - i)));
            }
        },
    }
    writeVr(c, f.vd(), fromBytes(bytes));
    return .advance;
}

fn storeUnaligned(c: *Context, insn: Instruction, comptime side: UnalignedSide) Fault!Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    const offset: usize = ea & 15;
    const bytes = toBytes(readVr(c, f.vs()));
    switch (side) {
        .left => {
            var i: usize = 0;
            while (i < 16 - offset) : (i += 1) {
                const at = ea +% @as(u32, @intCast(i));
                try c.memory.write(u8, at, bytes[i]);
                c.breakReservation(at);
            }
        },
        .right => {
            var i: usize = 0;
            while (i < offset) : (i += 1) {
                const at = ea - @as(u32, @intCast(offset - i));
                try c.memory.write(u8, at, bytes[16 - offset + i]);
                c.breakReservation(at);
            }
        },
    }
    return .advance;
}

// ---------------------------------------------------------------------------
// Carry, average, and the multiply family
// ---------------------------------------------------------------------------

/// `vaddcuw` and `vsubcuw` produce the carry/borrow *as a value*, one per word,
/// because a 128-bit add has to be built from four 32-bit ones and the carry
/// between them has to be visible to the next instruction.
fn carryOut(c: *Context, insn: Instruction, comptime kind: AddSubKind) Outcome {
    const f = insn.vx();
    const a = readVr(c, f.va());
    const b = readVr(c, f.vb());
    var out: Vector = undefined;
    inline for (0..4) |i| {
        out[i] = switch (kind) {
            .add => @intFromBool(@addWithOverflow(a[i], b[i])[1] != 0),
            // vsubcuw reports *no* borrow as 1, which is the complement of the
            // subtract overflow flag.
            .subtract => @intFromBool(@subWithOverflow(a[i], b[i])[1] == 0),
        };
    }
    writeVr(c, f.vd(), out);
    return .advance;
}

/// The AltiVec average rounds up: (a + b + 1) >> 1. The sum is computed one bit
/// wider than the lane so it cannot overflow before the shift.
fn average(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx();
    const info = @typeInfo(T).int;
    const Wide = std.meta.Int(info.signedness, info.bits + 2);
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(T, readVr(c, f.vb()));
    var out: @TypeOf(a) = undefined;
    for (&out, a, b) |*o, x, y| {
        const sum: Wide = @as(Wide, x) + @as(Wide, y) + 1;
        o.* = @intCast(sum >> 1);
    }
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

const LaneParity = enum { even, odd };

/// `vmule*`/`vmulo*` multiply alternating lanes into double-width results, which
/// is how AltiVec gets a full-precision product without a second instruction.
/// Element 0 is leftmost, so "even" means indices 0, 2, 4, ... counted from the
/// left - reading them from the right would take the wrong half of every pair.
fn multiplyLanes(
    c: *Context,
    insn: Instruction,
    comptime Src: type,
    comptime Dst: type,
    comptime parity: LaneParity,
) Outcome {
    const f = insn.vx();
    const dst_count = 16 / @sizeOf(Dst);
    const a = toLanes(Src, readVr(c, f.va()));
    const b = toLanes(Src, readVr(c, f.vb()));
    var out: [dst_count]Dst = undefined;
    inline for (0..dst_count) |i| {
        const index = i * 2 + @as(usize, if (parity == .even) 0 else 1);
        out[i] = @as(Dst, a[index]) *% @as(Dst, b[index]);
    }
    writeVr(c, f.vd(), fromLanes(Dst, out));
    return .advance;
}

/// Saturate a wide value into `T`, reporting whether it had to clamp.
pub fn saturate(comptime T: type, value: anytype) struct { value: T, clamped: bool } {
    const lo = std.math.minInt(T);
    const hi = std.math.maxInt(T);
    if (value < lo) return .{ .value = lo, .clamped = true };
    if (value > hi) return .{ .value = hi, .clamped = true };
    return .{ .value = @intCast(value), .clamped = false };
}

/// `vmhaddshs` keeps the *high* half of a 16x16 product before adding, which is
/// the fixed-point multiply a guest uses for fractional values. `vmhraddshs`
/// rounds that half instead of truncating it.
fn multiplyHighAdd(c: *Context, insn: Instruction, comptime rounded: bool) Outcome {
    const f = insn.va();
    const a = toLanes(i16, readVr(c, f.va()));
    const b = toLanes(i16, readVr(c, f.vb()));
    const addend = toLanes(i16, readVr(c, f.vc()));
    var out: [8]i16 = undefined;
    var clamped = false;
    for (&out, a, b, addend) |*o, x, y, z| {
        var product: i32 = @as(i32, x) * @as(i32, y);
        if (rounded) product += 0x4000;
        const shifted: i32 = product >> 15;
        const result = saturate(i16, shifted + @as(i32, z));
        clamped = clamped or result.clamped;
        o.* = result.value;
    }
    if (clamped) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(i16, out));
    return .advance;
}

fn multiplyLowAdd(c: *Context, insn: Instruction) Outcome {
    const f = insn.va();
    const a = toLanes(u16, readVr(c, f.va()));
    const b = toLanes(u16, readVr(c, f.vb()));
    const addend = toLanes(u16, readVr(c, f.vc()));
    var out: [8]u16 = undefined;
    for (&out, a, b, addend) |*o, x, y, z| o.* = x *% y +% z;
    writeVr(c, f.vd(), fromLanes(u16, out));
    return .advance;
}

/// `vmsum*` is a dot product per 32-bit lane: the products of the sub-lanes
/// inside each word are summed and added to the matching word of vC.
fn multiplySum(
    c: *Context,
    insn: Instruction,
    comptime Src: type,
    comptime Acc: type,
    comptime mode: Overflow,
) Outcome {
    const f = insn.va();
    const per_word = 4 / @sizeOf(Src);
    const Wide = std.meta.Int(@typeInfo(Acc).int.signedness, 64);
    const a = toLanes(Src, readVr(c, f.va()));
    const b = toLanes(Src, readVr(c, f.vb()));
    const addend = toLanes(Acc, readVr(c, f.vc()));
    var out: [4]Acc = undefined;
    var clamped = false;
    inline for (0..4) |word| {
        var total: Wide = addend[word];
        inline for (0..per_word) |sub| {
            const index = word * per_word + sub;
            total += @as(Wide, a[index]) * @as(Wide, b[index]);
        }
        switch (mode) {
            .modulo => out[word] = @truncate(@as(Wide, @bitCast(total))),
            .saturate => {
                const result = saturate(Acc, total);
                clamped = clamped or result.clamped;
                out[word] = result.value;
            },
        }
    }
    if (clamped) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(Acc, out));
    return .advance;
}

/// `vmsummbm` is the odd one out: vA's bytes are signed and vB's are unsigned,
/// so it cannot share the symmetric path above.
fn multiplySumMixed(c: *Context, insn: Instruction) Outcome {
    const f = insn.va();
    const a = toLanes(i8, readVr(c, f.va()));
    const b = toLanes(u8, readVr(c, f.vb()));
    const addend = toLanes(i32, readVr(c, f.vc()));
    var out: [4]i32 = undefined;
    inline for (0..4) |word| {
        var total: i64 = addend[word];
        inline for (0..4) |sub| {
            const index = word * 4 + sub;
            total += @as(i64, a[index]) * @as(i64, b[index]);
        }
        out[word] = @truncate(total);
    }
    writeVr(c, f.vd(), fromLanes(i32, out));
    return .advance;
}

const SumSpan = enum { all_four, pairs };

/// `vsumsws` reduces all four words into the last lane; `vsum2sws` reduces two
/// pairs into lanes 1 and 3. The lanes that receive nothing are zeroed, not
/// left holding vA - a guest reading them would otherwise see a partial sum.
fn sumAcross(c: *Context, insn: Instruction, comptime span: SumSpan) Outcome {
    const f = insn.vx();
    const a = toLanes(i32, readVr(c, f.va()));
    const addend = toLanes(i32, readVr(c, f.vb()));
    var out: [4]i32 = .{ 0, 0, 0, 0 };
    var clamped = false;
    switch (span) {
        .all_four => {
            var total: i64 = addend[3];
            for (a) |value| total += value;
            const result = saturate(i32, total);
            clamped = result.clamped;
            out[3] = result.value;
        },
        .pairs => {
            inline for (0..2) |pair| {
                const lane = pair * 2 + 1;
                var total: i64 = addend[lane];
                total += a[pair * 2];
                total += a[pair * 2 + 1];
                const result = saturate(i32, total);
                clamped = clamped or result.clamped;
                out[lane] = result.value;
            }
        },
    }
    if (clamped) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(i32, out));
    return .advance;
}

/// `vsum4*` sums the sub-lanes *within* each word and adds the matching word of
/// vB, leaving four independent accumulators rather than one.
fn sumWithin(c: *Context, insn: Instruction, comptime Src: type, comptime Acc: type) Outcome {
    const f = insn.vx();
    const per_word = 4 / @sizeOf(Src);
    const Wide = std.meta.Int(@typeInfo(Acc).int.signedness, 64);
    const a = toLanes(Src, readVr(c, f.va()));
    const addend = toLanes(Acc, readVr(c, f.vb()));
    var out: [4]Acc = undefined;
    var clamped = false;
    inline for (0..4) |word| {
        var total: Wide = addend[word];
        inline for (0..per_word) |sub| total += a[word * per_word + sub];
        const result = saturate(Acc, total);
        clamped = clamped or result.clamped;
        out[word] = result.value;
    }
    if (clamped) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(Acc, out));
    return .advance;
}

// ---------------------------------------------------------------------------
// Pack and unpack
//
// A pack takes vA and vB and produces one register of half-width lanes, vA's
// lanes first. The saturating forms are where the signedness matters twice:
// `vpkshus` reads *signed* halfwords and writes *unsigned* bytes, so a negative
// input clamps to zero rather than wrapping to 0xFF.
// ---------------------------------------------------------------------------

fn pack(
    c: *Context,
    insn: Instruction,
    comptime Src: type,
    comptime Dst: type,
    comptime mode: Overflow,
) Outcome {
    const f = insn.vx();
    const src_count = 16 / @sizeOf(Src);
    const a = toLanes(Src, readVr(c, f.va()));
    const b = toLanes(Src, readVr(c, f.vb()));
    var out: [16 / @sizeOf(Dst)]Dst = undefined;
    var clamped = false;
    inline for (0..src_count) |i| {
        const value = a[i];
        out[i] = switch (mode) {
            .modulo => @truncate(value),
            .saturate => blk: {
                const result = saturate(Dst, value);
                clamped = clamped or result.clamped;
                break :blk result.value;
            },
        };
    }
    inline for (0..src_count) |i| {
        const value = b[i];
        out[src_count + i] = switch (mode) {
            .modulo => @truncate(value),
            .saturate => blk: {
                const result = saturate(Dst, value);
                clamped = clamped or result.clamped;
                break :blk result.value;
            },
        };
    }
    if (clamped) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(Dst, out));
    return .advance;
}

/// `vpkpx` packs eight words into eight 1-5-5-5 pixels. The source bit
/// positions are not the low bits of each channel: the architecture takes bit 7
/// for the alpha bit and bits 8-12, 16-20, 24-28 for the three colour channels,
/// which is the layout a 8-8-8-8 pixel already has.
fn packPixel(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx();
    const a = toLanes(u32, readVr(c, f.va()));
    const b = toLanes(u32, readVr(c, f.vb()));
    var out: [8]u16 = undefined;
    inline for (0..4) |i| {
        out[i] = packOnePixel(a[i]);
        out[4 + i] = packOnePixel(b[i]);
    }
    writeVr(c, f.vd(), fromLanes(u16, out));
    return .advance;
}

fn packOnePixel(word: u32) u16 {
    // Architectural bit 7 -> result bit 15, then bits 8..12, 16..20, 24..28.
    const alpha: u16 = @intCast((word >> 24) & 1);
    const red: u16 = @intCast((word >> 19) & 0x1F);
    const green: u16 = @intCast((word >> 11) & 0x1F);
    const blue: u16 = @intCast((word >> 3) & 0x1F);
    return (alpha << 15) | (red << 10) | (green << 5) | blue;
}

const UnpackHalf = enum { high, low };

fn unpack(
    c: *Context,
    insn: Instruction,
    comptime Src: type,
    comptime Dst: type,
    comptime half: UnpackHalf,
) Outcome {
    const f = insn.vx();
    const dst_count = 16 / @sizeOf(Dst);
    const b = toLanes(Src, readVr(c, f.vb()));
    const base = if (half == .high) 0 else dst_count;
    var out: [dst_count]Dst = undefined;
    inline for (0..dst_count) |i| out[i] = b[base + i];
    writeVr(c, f.vd(), fromLanes(Dst, out));
    return .advance;
}

/// `vupkhpx` reverses `vpkpx`: the alpha bit is *sign-replicated* across the
/// whole byte, so a set alpha unpacks to 0xFF rather than to 1.
fn unpackPixel(c: *Context, insn: Instruction, comptime half: UnpackHalf) Outcome {
    const f = insn.vx();
    const b = toLanes(u16, readVr(c, f.vb()));
    const base: usize = if (half == .high) 0 else 4;
    var out: [4]u32 = undefined;
    inline for (0..4) |i| {
        const pixel = b[base + i];
        const alpha: u32 = if (pixel & 0x8000 != 0) 0xFF else 0x00;
        const red: u32 = (pixel >> 10) & 0x1F;
        const green: u32 = (pixel >> 5) & 0x1F;
        const blue: u32 = pixel & 0x1F;
        out[i] = (alpha << 24) | (red << 16) | (green << 8) | blue;
    }
    writeVr(c, f.vd(), fromLanes(u32, out));
    return .advance;
}

// ---------------------------------------------------------------------------
// Whole-register shifts
//
// These shift the register as one 128-bit quantity rather than lane by lane.
// The shift amount comes from the *last* byte of vB - the architecture requires
// every byte of vB to carry the same amount and leaves the result undefined
// otherwise, so reading one byte is both correct and cheaper than checking.
// ---------------------------------------------------------------------------

const WholeShiftUnit = enum { bits, bytes };

fn shiftWhole(
    c: *Context,
    insn: Instruction,
    comptime side: UnalignedSide,
    comptime unit: WholeShiftUnit,
) Outcome {
    const f = insn.vx();
    const source = toBytes(readVr(c, f.va()));
    const control = toBytes(readVr(c, f.vb()))[15];
    var out: [16]u8 = [_]u8{0} ** 16;

    switch (unit) {
        .bytes => {
            const amount: usize = (control >> 3) & 0xF;
            var i: usize = 0;
            while (i < 16 - amount) : (i += 1) {
                switch (side) {
                    .left => out[i] = source[i + amount],
                    .right => out[i + amount] = source[i],
                }
            }
        },
        .bits => {
            const amount: u3 = @intCast(control & 7);
            if (amount == 0) {
                out = source;
            } else {
                const carry: u3 = @intCast(8 - @as(u5, amount));
                var i: usize = 0;
                while (i < 16) : (i += 1) {
                    switch (side) {
                        .left => {
                            const next: u8 = if (i + 1 < 16) source[i + 1] else 0;
                            out[i] = (source[i] << amount) | (next >> carry);
                        },
                        .right => {
                            const prev: u8 = if (i > 0) source[i - 1] else 0;
                            out[i] = (source[i] >> amount) | (prev << carry);
                        },
                    }
                }
            }
        },
    }
    writeVr(c, f.vd(), fromBytes(out));
    return .advance;
}

/// `vcmpbfp` is a bounds test, not a comparison: each result word reports
/// whether vA[i] left the range [-vB[i], +vB[i]], with *zero* meaning in range.
/// Both bits clear is the success case, which is why Rc reports "none set".
fn compareBounds(c: *Context, insn: Instruction) Outcome {
    const f = insn.vc();
    const a = toFloats(readVr(c, f.va()));
    const b = toFloats(readVr(c, f.vb()));
    var out: Vector = undefined;
    inline for (0..4) |i| {
        var word: u32 = 0;
        if (!(a[i] <= b[i])) word |= 0x8000_0000;
        if (!(a[i] >= -b[i])) word |= 0x4000_0000;
        out[i] = word;
    }
    writeVr(c, f.vd(), out);
    // Only CR6 bit 2 is defined for vcmpbfp: set when every lane is in bounds.
    if (insn.rc()) {
        var all_in_bounds = true;
        for (out) |word| {
            if (word != 0) all_in_bounds = false;
        }
        c.state.setCrField(6, if (all_in_bounds) 0b0010 else 0b0000);
    }
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

test "lvlx and lvrx rebuild an unaligned quadword when ored together" {
    var h = Harness{};
    for (0..48) |i| h.buf[i] = @intCast(i + 1);
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 5; // deliberately unaligned

    _ = try h.run((31 << 26) | (3 << 21) | (4 << 16) | (5 << 11) | (519 << 1)); // lvlx v3
    h.state.gpr[5] = 5 + 16;
    _ = try h.run((31 << 26) | (4 << 21) | (4 << 16) | (5 << 11) | (551 << 1)); // lvrx v4
    _ = try h.run(vxWord(5, 3, 4, 1156)); // vor v5, v3, v4

    // The result must be the 16 bytes starting at the unaligned address.
    const bytes = toBytes(h.state.vr[5]);
    for (bytes, 0..) |byte, i| {
        try testing.expectEqual(@as(u8, @intCast(5 + i + 1)), byte);
    }
}

test "the half an unaligned load does not reach is zeroed, not preserved" {
    var h = Harness{};
    for (0..32) |i| h.buf[i] = 0xEE;
    h.state.vr[3] = .{ 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF };
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 12; // offset 12 -> only four bytes are in range
    _ = try h.run((31 << 26) | (3 << 21) | (4 << 16) | (5 << 11) | (519 << 1)); // lvlx
    const bytes = toBytes(h.state.vr[3]);
    try testing.expectEqual(@as(u8, 0xEE), bytes[3]);
    // Without the zero fill the vor idiom would merge stale bytes.
    try testing.expectEqual(@as(u8, 0x00), bytes[4]);
    try testing.expectEqual(@as(u8, 0x00), bytes[15]);
}

test "stvlx and stvrx write back exactly what the loads read" {
    var h = Harness{};
    for (0..48) |i| h.buf[i] = @intCast(i + 1);
    h.state.vr[3] = .{ 0xAABBCCDD, 0x11223344, 0x55667788, 0x99AABBCC };
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 32 + 3;
    _ = try h.run((31 << 26) | (3 << 21) | (4 << 16) | (5 << 11) | (647 << 1)); // stvlx
    h.state.gpr[5] = 32 + 3 + 16;
    _ = try h.run((31 << 26) | (3 << 21) | (4 << 16) | (5 << 11) | (679 << 1)); // stvrx

    const expected = toBytes(h.state.vr[3]);
    for (expected, 0..) |byte, i| {
        try testing.expectEqual(byte, h.buf[32 + 3 + i]);
    }
    // The byte before the range is untouched.
    try testing.expectEqual(@as(u8, 35), h.buf[34]);
}

test "vaddcuw reports a carry and vsubcuw reports the absence of a borrow" {
    var h = Harness{};
    h.state.vr[1] = .{ 0xFFFFFFFF, 1, 5, 5 };
    h.state.vr[2] = .{ 1, 1, 3, 7 };
    _ = try h.run(vxWord(3, 1, 2, 384)); // vaddcuw
    try testing.expectEqual(Vector{ 1, 0, 0, 0 }, h.state.vr[3]);
    _ = try h.run(vxWord(3, 1, 2, 1408)); // vsubcuw
    // 5-3 does not borrow (1); 5-7 does (0).
    try testing.expectEqual(Vector{ 1, 1, 1, 0 }, h.state.vr[3]);
}

test "the vector average rounds up rather than truncating" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(u32, .{ 3, 4, 0xFFFFFFFF, 0 });
    h.state.vr[2] = fromLanes(u32, .{ 4, 4, 0xFFFFFFFF, 0 });
    _ = try h.run(vxWord(3, 1, 2, 1154)); // vavguw
    // (3+4+1)>>1 = 4, not 3. The last lane proves the sum is computed wider
    // than the lane: 0xFFFFFFFF averaged with itself is itself.
    try testing.expectEqual([4]u32{ 4, 4, 0xFFFFFFFF, 0 }, toLanes(u32, h.state.vr[3]));

    h.state.vr[1] = fromLanes(i8, .{ -3, -4, 127, -128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    h.state.vr[2] = fromLanes(i8, .{ -4, -4, 127, -128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    _ = try h.run(vxWord(3, 1, 2, 1282)); // vavgsb
    const signed = toLanes(i8, h.state.vr[3]);
    try testing.expectEqual(@as(i8, -3), signed[0]); // (-3 + -4 + 1) >> 1
    try testing.expectEqual(@as(i8, 127), signed[2]);
    try testing.expectEqual(@as(i8, -128), signed[3]);
}

test "vmuleuh takes the even halfwords counted from the left" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(u16, .{ 2, 100, 3, 100, 4, 100, 5, 100 });
    h.state.vr[2] = fromLanes(u16, .{ 10, 200, 10, 200, 10, 200, 10, 200 });
    _ = try h.run(vxWord(3, 1, 2, 584)); // vmuleuh
    try testing.expectEqual([4]u32{ 20, 30, 40, 50 }, toLanes(u32, h.state.vr[3]));
    _ = try h.run(vxWord(3, 1, 2, 72)); // vmulouh
    try testing.expectEqual([4]u32{ 20000, 20000, 20000, 20000 }, toLanes(u32, h.state.vr[3]));
}

test "vmulesb keeps the sign that vmuleub would lose" {
    var h = Harness{};
    var lanes: [16]i8 = [_]i8{0} ** 16;
    lanes[0] = -2;
    h.state.vr[1] = fromLanes(i8, lanes);
    var other: [16]i8 = [_]i8{0} ** 16;
    other[0] = 3;
    h.state.vr[2] = fromLanes(i8, other);
    _ = try h.run(vxWord(3, 1, 2, 776)); // vmulesb
    try testing.expectEqual(@as(i16, -6), toLanes(i16, h.state.vr[3])[0]);
    _ = try h.run(vxWord(3, 1, 2, 520)); // vmuleub
    try testing.expectEqual(@as(u16, 254 * 3), toLanes(u16, h.state.vr[3])[0]);
}

test "vmhaddshs keeps the high half of the product and saturates the sum" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(i16, .{ 0x4000, 32767, 0, 0, 0, 0, 0, 0 });
    h.state.vr[2] = fromLanes(i16, .{ 0x4000, 32767, 0, 0, 0, 0, 0, 0 });
    h.state.vr[4] = fromLanes(i16, .{ 0, 32767, 0, 0, 0, 0, 0, 0 });
    _ = try h.run(vaWord(3, 1, 2, 4, 32)); // vmhaddshs
    const out = toLanes(i16, h.state.vr[3]);
    // (0x4000 * 0x4000) >> 15 = 0x2000.
    try testing.expectEqual(@as(i16, 0x2000), out[0]);
    // The second lane overflows and clamps, latching VSCR.SAT.
    try testing.expectEqual(@as(i16, 32767), out[1]);
    try testing.expect(h.state.vscr & Vscr.sat != 0);
}

test "vmladduhm is a plain modulo multiply-add on halfwords" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(u16, .{ 3, 0xFFFF, 0, 0, 0, 0, 0, 0 });
    h.state.vr[2] = fromLanes(u16, .{ 4, 2, 0, 0, 0, 0, 0, 0 });
    h.state.vr[4] = fromLanes(u16, .{ 5, 1, 0, 0, 0, 0, 0, 0 });
    _ = try h.run(vaWord(3, 1, 2, 4, 34)); // vmladduhm
    const out = toLanes(u16, h.state.vr[3]);
    try testing.expectEqual(@as(u16, 17), out[0]);
    // 0xFFFF * 2 + 1 wraps rather than saturating.
    try testing.expectEqual(@as(u16, 0xFFFF), out[1]);
}

test "vmsumuhm is a dot product inside each word" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(u16, .{ 2, 3, 0, 0, 0, 0, 0, 0 });
    h.state.vr[2] = fromLanes(u16, .{ 10, 20, 0, 0, 0, 0, 0, 0 });
    h.state.vr[4] = fromLanes(u32, .{ 1, 0, 0, 0 });
    _ = try h.run(vaWord(3, 1, 2, 4, 38)); // vmsumuhm
    // 2*10 + 3*20 + 1 = 81, all inside word 0.
    try testing.expectEqual([4]u32{ 81, 0, 0, 0 }, toLanes(u32, h.state.vr[3]));
}

test "vmsummbm mixes a signed multiplicand with an unsigned one" {
    var h = Harness{};
    var a: [16]i8 = [_]i8{0} ** 16;
    a[0] = -1;
    h.state.vr[1] = fromLanes(i8, a);
    var b: [16]u8 = [_]u8{0} ** 16;
    b[0] = 200;
    h.state.vr[2] = fromLanes(u8, b);
    h.state.vr[4] = fromLanes(i32, .{ 0, 0, 0, 0 });
    _ = try h.run(vaWord(3, 1, 2, 4, 37)); // vmsummbm
    // Reading vB as signed would give +56 here instead of -200.
    try testing.expectEqual(@as(i32, -200), toLanes(i32, h.state.vr[3])[0]);
}

test "vsumsws collapses four words into the last lane and zeroes the rest" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(i32, .{ 1, 2, 3, 4 });
    h.state.vr[2] = fromLanes(i32, .{ 100, 100, 100, 10 });
    _ = try h.run(vxWord(3, 1, 2, 1928)); // vsumsws
    try testing.expectEqual([4]i32{ 0, 0, 0, 20 }, toLanes(i32, h.state.vr[3]));
}

test "vsum2sws reduces pairs into lanes one and three" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(i32, .{ 1, 2, 3, 4 });
    h.state.vr[2] = fromLanes(i32, .{ 0, 10, 0, 20 });
    _ = try h.run(vxWord(3, 1, 2, 1672)); // vsum2sws
    try testing.expectEqual([4]i32{ 0, 13, 0, 27 }, toLanes(i32, h.state.vr[3]));
}

test "vsum4sbs accumulates within each word independently" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(i8, .{ 1, 2, 3, 4, 1, 1, 1, 1, 0, 0, 0, 0, -1, -1, -1, -1 });
    h.state.vr[2] = fromLanes(i32, .{ 0, 100, 0, 0 });
    _ = try h.run(vxWord(3, 1, 2, 1800)); // vsum4sbs
    try testing.expectEqual([4]i32{ 10, 104, 0, -4 }, toLanes(i32, h.state.vr[3]));
}

test "vpkuhum truncates where vpkuhus saturates" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(u16, .{ 0x0102, 0x00FF, 0x0100, 0, 0, 0, 0, 0 });
    h.state.vr[2] = fromLanes(u16, .{ 0, 0, 0, 0, 0, 0, 0, 0 });
    _ = try h.run(vxWord(3, 1, 2, 14)); // vpkuhum
    const truncated = toLanes(u8, h.state.vr[3]);
    try testing.expectEqual(@as(u8, 0x02), truncated[0]);
    try testing.expectEqual(@as(u8, 0x00), truncated[2]);

    _ = try h.run(vxWord(3, 1, 2, 142)); // vpkuhus
    const saturated = toLanes(u8, h.state.vr[3]);
    try testing.expectEqual(@as(u8, 0xFF), saturated[0]);
    try testing.expectEqual(@as(u8, 0xFF), saturated[2]);
    try testing.expect(h.state.vscr & Vscr.sat != 0);
}

test "vpkshus clamps a negative signed source to zero, not to 0xFF" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(i16, .{ -1, -32768, 300, 0, 0, 0, 0, 0 });
    h.state.vr[2] = fromLanes(i16, .{ 0, 0, 0, 0, 0, 0, 0, 0 });
    _ = try h.run(vxWord(3, 1, 2, 270)); // vpkshus
    const out = toLanes(u8, h.state.vr[3]);
    try testing.expectEqual(@as(u8, 0), out[0]);
    try testing.expectEqual(@as(u8, 0), out[1]);
    try testing.expectEqual(@as(u8, 255), out[2]);
}

test "a pack puts vA's lanes first and vB's second" {
    var h = Harness{};
    h.state.vr[1] = fromLanes(u16, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    h.state.vr[2] = fromLanes(u16, .{ 9, 10, 11, 12, 13, 14, 15, 16 });
    _ = try h.run(vxWord(3, 1, 2, 14)); // vpkuhum
    const out = toLanes(u8, h.state.vr[3]);
    try testing.expectEqual(@as(u8, 1), out[0]);
    try testing.expectEqual(@as(u8, 8), out[7]);
    try testing.expectEqual(@as(u8, 9), out[8]);
    try testing.expectEqual(@as(u8, 16), out[15]);
}

test "vupkhsb sign-extends where a zero-extend would lose the sign" {
    var h = Harness{};
    var lanes: [16]i8 = [_]i8{0} ** 16;
    lanes[0] = -1;
    lanes[8] = -2;
    h.state.vr[2] = fromLanes(i8, lanes);
    _ = try h.run(vxWord(3, 0, 2, 526)); // vupkhsb
    try testing.expectEqual(@as(i16, -1), toLanes(i16, h.state.vr[3])[0]);
    _ = try h.run(vxWord(3, 0, 2, 654)); // vupklsb
    try testing.expectEqual(@as(i16, -2), toLanes(i16, h.state.vr[3])[0]);
}

test "vpkpx and vupkhpx round-trip a pixel through the 1-5-5-5 layout" {
    var h = Harness{};
    // Alpha set, R=0x1F, G=0x00, B=0x1F in an 8-8-8-8 word.
    h.state.vr[1] = fromLanes(u32, .{ 0x01_F8_00_F8, 0, 0, 0 });
    h.state.vr[2] = fromLanes(u32, .{ 0, 0, 0, 0 });
    _ = try h.run(vxWord(3, 1, 2, 782)); // vpkpx
    const packed_pixel = toLanes(u16, h.state.vr[3])[0];
    try testing.expectEqual(@as(u16, 0x8000 | (0x1F << 10) | 0x1F), packed_pixel);

    h.state.vr[4] = h.state.vr[3];
    _ = try h.run(vxWord(5, 0, 4, 846)); // vupkhpx
    const unpacked = toLanes(u32, h.state.vr[5])[0];
    // Alpha comes back sign-replicated as 0xFF, not as 1.
    try testing.expectEqual(@as(u32, 0xFF_1F_00_1F), unpacked);
}

test "vslo and vsro shift the whole register by bytes" {
    var h = Harness{};
    h.state.vr[1] = .{ 0x00010203, 0x04050607, 0x08090A0B, 0x0C0D0E0F };
    h.state.vr[2] = fromLanes(u8, .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4 << 3 });
    _ = try h.run(vxWord(3, 1, 2, 1036)); // vslo
    try testing.expectEqual(Vector{ 0x04050607, 0x08090A0B, 0x0C0D0E0F, 0 }, h.state.vr[3]);
    _ = try h.run(vxWord(3, 1, 2, 1100)); // vsro
    try testing.expectEqual(Vector{ 0, 0x00010203, 0x04050607, 0x08090A0B }, h.state.vr[3]);
}

test "vsl and vsr shift the whole register by bits" {
    var h = Harness{};
    h.state.vr[1] = .{ 0x80000000, 0, 0, 1 };
    h.state.vr[2] = fromLanes(u8, .{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 });
    _ = try h.run(vxWord(3, 1, 2, 452)); // vsl
    // The bit shifted out of the top of one byte enters the next: a lane-wise
    // shift would leave the low word at 2 and lose the carry between bytes.
    try testing.expectEqual(Vector{ 0, 0, 0, 2 }, h.state.vr[3]);

    h.state.vr[1] = .{ 2, 0, 0, 0 };
    _ = try h.run(vxWord(3, 1, 2, 708)); // vsr
    try testing.expectEqual(Vector{ 1, 0, 0, 0 }, h.state.vr[3]);
}

test "vcmpbfp reports zero for a lane inside its bounds" {
    var h = Harness{};
    h.state.vr[1] = fromFloats(.{ 0.5, 2.0, -2.0, 1.0 });
    h.state.vr[2] = fromFloats(.{ 1.0, 1.0, 1.0, 1.0 });
    _ = try h.run(vcWord(3, 1, 2, 1, 966)); // vcmpbfp.
    const out = h.state.vr[3];
    try testing.expectEqual(@as(u32, 0), out[0]); // in bounds
    try testing.expectEqual(@as(u32, 0x8000_0000), out[1]); // above +vB
    try testing.expectEqual(@as(u32, 0x4000_0000), out[2]); // below -vB
    try testing.expectEqual(@as(u32, 0), out[3]); // exactly on the bound
    // Only CR6 bit 2 is defined, and only when every lane is in bounds.
    try testing.expectEqual(@as(u4, 0b0000), h.state.crField(6));

    h.state.vr[1] = fromFloats(.{ 0.5, 0.5, 0.5, 0.5 });
    _ = try h.run(vcWord(3, 1, 2, 1, 966));
    try testing.expectEqual(@as(u4, 0b0010), h.state.crField(6));
}

test "vexptefp and vlogefp are inverses within their estimate tolerance" {
    var h = Harness{};
    h.state.vr[2] = fromFloats(.{ 0.0, 1.0, 2.0, 3.0 });
    _ = try h.run(vxWord(3, 0, 2, 394)); // vexptefp
    try testing.expectEqual([4]f32{ 1.0, 2.0, 4.0, 8.0 }, toFloats(h.state.vr[3]));
    h.state.vr[4] = h.state.vr[3];
    _ = try h.run(vxWord(5, 0, 4, 458)); // vlogefp
    try testing.expectEqual([4]f32{ 0.0, 1.0, 2.0, 3.0 }, toFloats(h.state.vr[5]));
}

test "a VMX128 instruction reports itself rather than aliasing to AltiVec" {
    var h = Harness{};
    const outcome = try h.run(0x18000210); // vpermwi128
    try testing.expect(outcome.isGap());
    try testing.expectEqual(ppc_decode.Op.vpermwi128, outcome.unimplemented);
}
