//! Xenon VMX128 execution.
//!
//! VMX128 is the Xbox 360's extension of AltiVec from 32 vector registers to
//! 128. It does not widen the instruction word to pay for the extra two bits:
//! every register number is reassembled from two or three scattered fields, and
//! reading only the low five bits yields register `n % 32` - a wrong-register
//! bug that reads as data corruption rather than as a decode fault. That
//! reassembly lives in ISA/ppc/decode/fields.zig; this module consumes it.
//!
//! Most VMX128 instructions are the AltiVec operation with wider register
//! fields, and share the lane helpers in vmx.zig because a lane means the same
//! thing in both. What is genuinely new is a handful of graphics-shaped
//! operations the Xenon added for its GPU pipeline: fused multiply-adds whose
//! destination is also a source, dot products that broadcast, an immediate word
//! swizzle, a rotate-and-insert, and the D3D vertex pack/unpack pair.
//!
//! Three of the multiply-adds name the destination register twice, once as a
//! source. `vmaddcfp128 vD, vA, vD, vB` multiplies by vD and adds vB;
//! `vmaddfp128 vD, vA, vB, vD` multiplies by vB and adds vD. Treating them as
//! the same shape gives the right answer only when vB and vD happen to be
//! equal, so the operand roles are spelled out per instruction here rather than
//! shared.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");
const state_mod = @import("state.zig");
const vmx = @import("vmx.zig");

const Context = ctx_mod.Context;
const Outcome = ctx_mod.Outcome;
const Instruction = ctx_mod.Instruction;
const Fault = ctx_mod.Fault;
const Vector = state_mod.Vector;

const toBytes = vmx.toBytes;
const fromBytes = vmx.fromBytes;
const toLanes = vmx.toLanes;
const fromLanes = vmx.fromLanes;
const toFloats = vmx.toFloats;
const fromFloats = vmx.fromFloats;
const saturate = vmx.saturate;

/// Read a register by its full seven-bit VMX128 number.
pub fn readVr(c: *const Context, index: u7) Vector {
    return c.state.vr[index];
}

pub fn writeVr(c: *Context, index: u7, value: Vector) void {
    c.state.vr[index] = value;
}

fn setSaturated(c: *Context) void {
    c.state.vscr |= vmx.Vscr.sat;
}

pub fn execute(c: *Context, insn: Instruction) Fault!Outcome {
    return switch (insn.op) {
        // -- memory (VX128_1) -----------------------------------------------
        .lvx128, .lvxl128 => loadVector(c, insn),
        .stvx128, .stvxl128 => storeVector(c, insn),
        .lvewx128 => loadElement(c, insn),
        .stvewx128 => storeElement(c, insn),
        .lvsl128 => shiftControl(c, insn, .left),
        .lvsr128 => shiftControl(c, insn, .right),
        .lvlx128, .lvlxl128 => loadUnaligned(c, insn, .left),
        .lvrx128, .lvrxl128 => loadUnaligned(c, insn, .right),
        .stvlx128, .stvlxl128 => storeUnaligned(c, insn, .left),
        .stvrx128, .stvrxl128 => storeUnaligned(c, insn, .right),

        // -- logical (VX128) --------------------------------------------------
        .vand128 => logical(c, insn, .andop),
        .vandc128 => logical(c, insn, .andc),
        .vor128 => logical(c, insn, .orop),
        .vnor128 => logical(c, insn, .nor),
        .vxor128 => logical(c, insn, .xorop),

        // -- single-precision arithmetic (VX128) -------------------------------
        .vaddfp128 => floatBinary(c, insn, .add),
        .vsubfp128 => floatBinary(c, insn, .subtract),
        .vmulfp128 => floatBinary(c, insn, .multiply),
        .vmaxfp128 => floatBinary(c, insn, .max),
        .vminfp128 => floatBinary(c, insn, .min),
        .vmaddcfp128 => multiplyAdd(c, insn, .multiply_by_dest),
        .vmaddfp128 => multiplyAdd(c, insn, .add_dest),
        .vnmsubfp128 => multiplyAdd(c, insn, .negate_multiply_by_dest),
        .vmsum3fp128 => dotProduct(c, insn, 3),
        .vmsum4fp128 => dotProduct(c, insn, 4),

        // -- integer shift and rotate (VX128) -----------------------------------
        .vslw128 => shiftWord(c, insn, u32, .left),
        .vsrw128 => shiftWord(c, insn, u32, .right),
        .vsraw128 => shiftWord(c, insn, i32, .arithmetic),
        .vrlw128 => rotateWord(c, insn),
        .vslo128 => shiftWhole(c, insn, .left),
        .vsro128 => shiftWhole(c, insn, .right),

        // -- merge, select, permute ----------------------------------------------
        .vmrghw128 => merge(c, insn, .high),
        .vmrglw128 => merge(c, insn, .low),
        .vsel128 => select(c, insn),
        .vperm128 => permute(c, insn),
        .vpermwi128 => permuteWordImmediate(c, insn),
        .vsldoi128 => shiftDoubleOctet(c, insn),
        .vrlimi128 => rotateInsert(c, insn),

        // -- pack and unpack (VX128) -----------------------------------------------
        .vpkuhum128 => pack(c, insn, u16, u8, .modulo),
        .vpkuwum128 => pack(c, insn, u32, u16, .modulo),
        .vpkuhus128 => pack(c, insn, u16, u8, .saturate),
        .vpkuwus128 => pack(c, insn, u32, u16, .saturate),
        .vpkshus128 => pack(c, insn, i16, u8, .saturate),
        .vpkswus128 => pack(c, insn, i32, u16, .saturate),
        .vpkshss128 => pack(c, insn, i16, i8, .saturate),
        .vpkswss128 => pack(c, insn, i32, i16, .saturate),
        .vupkhsb128 => unpack(c, insn, .high),
        .vupklsb128 => unpack(c, insn, .low),

        // -- compare (VX128_R) --------------------------------------------------------
        .vcmpequw128 => compareInteger(c, insn),
        .vcmpeqfp128 => compareFloat(c, insn, .equal),
        .vcmpgefp128 => compareFloat(c, insn, .greater_equal),
        .vcmpgtfp128 => compareFloat(c, insn, .greater),
        .vcmpbfp128 => compareBounds(c, insn),

        // -- convert and estimate (VX128_3) ---------------------------------------------
        .vcfpsxws128 => convertToInteger(c, insn, i32),
        .vcfpuxws128 => convertToInteger(c, insn, u32),
        .vcsxwfp128 => convertToFloat(c, insn, i32),
        .vcuxwfp128 => convertToFloat(c, insn, u32),
        .vrefp128 => floatUnary(c, insn, .reciprocal),
        .vrsqrtefp128 => floatUnary(c, insn, .reciprocal_sqrt),
        .vexptefp128 => floatUnary(c, insn, .exp2),
        .vlogefp128 => floatUnary(c, insn, .log2),
        .vrfim128 => floatUnary(c, insn, .floor),
        .vrfin128 => floatUnary(c, insn, .nearest),
        .vrfip128 => floatUnary(c, insn, .ceil),
        .vrfiz128 => floatUnary(c, insn, .truncate),
        .vspltw128 => splatWord(c, insn),
        .vspltisw128 => splatImmediate(c, insn),

        // -- D3D vertex formats -------------------------------------------------------------
        .vpkd3d128 => packD3d(c, insn),
        .vupkd3d128 => unpackD3d(c, insn),

        else => .{ .unimplemented = insn.op },
    };
}

// ---------------------------------------------------------------------------
// Memory
// ---------------------------------------------------------------------------

fn vx1Address(c: *Context, insn: Instruction) u32 {
    const f = insn.vx128_1();
    return @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
}

fn loadVector(c: *Context, insn: Instruction) Fault!Outcome {
    const f = insn.vx128_1();
    writeVr(c, f.vd(), try c.memory.readVector(vx1Address(c, insn) & ~@as(u32, 15)));
    return .advance;
}

fn storeVector(c: *Context, insn: Instruction) Fault!Outcome {
    const f = insn.vx128_1();
    const ea = vx1Address(c, insn) & ~@as(u32, 15);
    try c.memory.writeVector(ea, readVr(c, f.vs()));
    c.breakReservation(ea);
    return .advance;
}

fn loadElement(c: *Context, insn: Instruction) Fault!Outcome {
    const f = insn.vx128_1();
    const ea = vx1Address(c, insn) & ~@as(u32, 3);
    const index = (ea & 15) / 4;
    // Only the addressed word is defined; the rest of the register keeps what
    // it had, so a guest building a vector word by word does not lose the
    // words it already placed.
    var lanes = toLanes(u32, readVr(c, f.vd()));
    lanes[index] = try c.memory.read(u32, ea);
    writeVr(c, f.vd(), fromLanes(u32, lanes));
    return .advance;
}

fn storeElement(c: *Context, insn: Instruction) Fault!Outcome {
    const f = insn.vx128_1();
    const ea = vx1Address(c, insn) & ~@as(u32, 3);
    const index = (ea & 15) / 4;
    try c.memory.write(u32, ea, toLanes(u32, readVr(c, f.vs()))[index]);
    c.breakReservation(ea);
    return .advance;
}

const Side = enum { left, right };

fn shiftControl(c: *Context, insn: Instruction, comptime side: Side) Outcome {
    const f = insn.vx128_1();
    const ea = vx1Address(c, insn);
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

fn loadUnaligned(c: *Context, insn: Instruction, comptime side: Side) Fault!Outcome {
    const f = insn.vx128_1();
    const ea = vx1Address(c, insn);
    const offset: usize = ea & 15;
    var bytes: [16]u8 = [_]u8{0} ** 16;
    switch (side) {
        .left => {
            var i: usize = 0;
            while (i < 16 - offset) : (i += 1) {
                bytes[i] = try c.memory.read(u8, ea +% @as(u32, @intCast(i)));
            }
        },
        .right => {
            var i: usize = 0;
            while (i < offset) : (i += 1) {
                bytes[16 - offset + i] = try c.memory.read(u8, ea - @as(u32, @intCast(offset - i)));
            }
        },
    }
    writeVr(c, f.vd(), fromBytes(bytes));
    return .advance;
}

fn storeUnaligned(c: *Context, insn: Instruction, comptime side: Side) Fault!Outcome {
    const f = insn.vx128_1();
    const ea = vx1Address(c, insn);
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
// Logical and arithmetic
// ---------------------------------------------------------------------------

const LogicalKind = enum { andop, andc, orop, nor, xorop };

fn logical(c: *Context, insn: Instruction, comptime kind: LogicalKind) Outcome {
    const f = insn.vx128();
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

const FloatBinaryKind = enum { add, subtract, multiply, max, min };

fn floatBinary(c: *Context, insn: Instruction, comptime kind: FloatBinaryKind) Outcome {
    const f = insn.vx128();
    const a = toFloats(readVr(c, f.va()));
    const b = toFloats(readVr(c, f.vb()));
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        out[i] = switch (kind) {
            .add => a[i] + b[i],
            .subtract => a[i] - b[i],
            .multiply => a[i] * b[i],
            .max => @max(a[i], b[i]),
            .min => @min(a[i], b[i]),
        };
    }
    writeVr(c, f.vd(), fromFloats(out));
    return .advance;
}

/// The three VMX128 multiply-adds differ in which operand is the multiplier and
/// which is the addend, and all three read the destination register.
const MultiplyAddShape = enum {
    /// vD = (vA * vD) + vB
    multiply_by_dest,
    /// vD = (vA * vB) + vD
    add_dest,
    /// vD = -((vA * vD) - vB)
    negate_multiply_by_dest,
};

fn multiplyAdd(c: *Context, insn: Instruction, comptime shape: MultiplyAddShape) Outcome {
    const f = insn.vx128();
    const a = toFloats(readVr(c, f.va()));
    const b = toFloats(readVr(c, f.vb()));
    const d = toFloats(readVr(c, f.vd()));
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        out[i] = switch (shape) {
            .multiply_by_dest => @mulAdd(f32, a[i], d[i], b[i]),
            .add_dest => @mulAdd(f32, a[i], b[i], d[i]),
            .negate_multiply_by_dest => -@mulAdd(f32, a[i], d[i], -b[i]),
        };
    }
    writeVr(c, f.vd(), fromFloats(out));
    return .advance;
}

/// `vmsum3fp128` and `vmsum4fp128` are dot products that broadcast their scalar
/// result to every lane, which is what makes them usable directly as a scale.
fn dotProduct(c: *Context, insn: Instruction, comptime lanes: usize) Outcome {
    const f = insn.vx128();
    const a = toFloats(readVr(c, f.va()));
    const b = toFloats(readVr(c, f.vb()));
    var total: f32 = 0;
    inline for (0..lanes) |i| total = @mulAdd(f32, a[i], b[i], total);
    writeVr(c, f.vd(), fromFloats(.{ total, total, total, total }));
    return .advance;
}

const ShiftKind = enum { left, right, arithmetic };

fn shiftWord(c: *Context, insn: Instruction, comptime T: type, comptime kind: ShiftKind) Outcome {
    const f = insn.vx128();
    const a = toLanes(T, readVr(c, f.va()));
    const b = toLanes(u32, readVr(c, f.vb()));
    var out: [4]T = undefined;
    inline for (0..4) |i| {
        const amount: u5 = @intCast(b[i] & 31);
        out[i] = switch (kind) {
            .left => a[i] << amount,
            .right, .arithmetic => a[i] >> amount,
        };
    }
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

fn rotateWord(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128();
    const a = toLanes(u32, readVr(c, f.va()));
    const b = toLanes(u32, readVr(c, f.vb()));
    var out: [4]u32 = undefined;
    inline for (0..4) |i| {
        out[i] = std.math.rotl(u32, a[i], @as(u5, @intCast(b[i] & 31)));
    }
    writeVr(c, f.vd(), fromLanes(u32, out));
    return .advance;
}

/// The whole-register byte shift. The amount comes from the last byte of vB,
/// which the architecture requires to be replicated across the register.
fn shiftWhole(c: *Context, insn: Instruction, comptime side: Side) Outcome {
    const f = insn.vx128();
    const source = toBytes(readVr(c, f.va()));
    const amount: usize = (toBytes(readVr(c, f.vb()))[15] >> 3) & 0xF;
    var out: [16]u8 = [_]u8{0} ** 16;
    var i: usize = 0;
    while (i < 16 - amount) : (i += 1) {
        switch (side) {
            .left => out[i] = source[i + amount],
            .right => out[i + amount] = source[i],
        }
    }
    writeVr(c, f.vd(), fromBytes(out));
    return .advance;
}

const MergeHalf = enum { high, low };

fn merge(c: *Context, insn: Instruction, comptime half: MergeHalf) Outcome {
    const f = insn.vx128();
    const a = toLanes(u32, readVr(c, f.va()));
    const b = toLanes(u32, readVr(c, f.vb()));
    const base: usize = if (half == .high) 0 else 2;
    var out: [4]u32 = undefined;
    inline for (0..2) |i| {
        out[i * 2] = a[base + i];
        out[i * 2 + 1] = b[base + i];
    }
    writeVr(c, f.vd(), fromLanes(u32, out));
    return .advance;
}

/// `vsel128 vD, vA, vB, vD` takes its mask from the destination register, so the
/// mask has to be read before the result is written.
fn select(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128();
    const a = readVr(c, f.va());
    const b = readVr(c, f.vb());
    const mask = readVr(c, f.vd());
    var out: Vector = undefined;
    inline for (0..4) |i| out[i] = (a[i] & ~mask[i]) | (b[i] & mask[i]);
    writeVr(c, f.vd(), out);
    return .advance;
}

fn permute(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_2();
    const a = toBytes(readVr(c, f.va()));
    const b = toBytes(readVr(c, f.vb()));
    // The VX128_2 form carries only three bits of the selector register number,
    // which names one of the first eight vector registers.
    const selector = toBytes(readVr(c, @as(u7, f.vc())));
    var out: [16]u8 = undefined;
    for (&out, selector) |*o, sel| {
        const index = sel & 0x1F;
        o.* = if (index < 16) a[index] else b[index - 16];
    }
    writeVr(c, f.vd(), fromBytes(out));
    return .advance;
}

/// `vpermwi128` swizzles words by an immediate: two bits per destination lane,
/// with lane 0 taking the *high* pair. Reading the pairs from the low end
/// reverses the swizzle, which for a symmetric pattern still looks correct.
fn permuteWordImmediate(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_p();
    const source = toLanes(u32, readVr(c, f.vb()));
    const selector = f.uimm();
    var out: [4]u32 = undefined;
    inline for (0..4) |i| {
        const shift: u3 = @intCast(6 - i * 2);
        out[i] = source[(selector >> shift) & 3];
    }
    writeVr(c, f.vd(), fromLanes(u32, out));
    return .advance;
}

fn shiftDoubleOctet(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_5();
    const a = toBytes(readVr(c, f.va()));
    const b = toBytes(readVr(c, f.vb()));
    const sh: usize = f.sh();
    var concat: [32]u8 = undefined;
    @memcpy(concat[0..16], &a);
    @memcpy(concat[16..32], &b);
    var out: [16]u8 = undefined;
    @memcpy(&out, concat[sh .. sh + 16]);
    writeVr(c, f.vd(), fromBytes(out));
    return .advance;
}

/// `vrlimi128 vD, vB, IMM, z` rotates vB left by z words and merges the result
/// into vD under a four-bit lane mask. The mask is numbered from the *high*
/// end: bit 3 selects lane 0. It is the instruction a guest uses to overwrite
/// one component of a vector without disturbing the others, so an inverted mask
/// writes exactly the three lanes it was supposed to preserve.
fn rotateInsert(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_4();
    const source = toLanes(u32, readVr(c, f.vb()));
    const rotate: usize = f.z();
    var rotated: [4]u32 = undefined;
    inline for (0..4) |i| rotated[i] = source[(i + rotate) % 4];

    var out = toLanes(u32, readVr(c, f.vd()));
    const mask = f.imm();
    inline for (0..4) |lane| {
        const bit: u3 = @intCast(3 - lane);
        if ((mask >> bit) & 1 != 0) out[lane] = rotated[lane];
    }
    writeVr(c, f.vd(), fromLanes(u32, out));
    return .advance;
}

// ---------------------------------------------------------------------------
// Pack and unpack
// ---------------------------------------------------------------------------

const Overflow = enum { modulo, saturate };

fn pack(
    c: *Context,
    insn: Instruction,
    comptime Src: type,
    comptime Dst: type,
    comptime mode: Overflow,
) Outcome {
    const f = insn.vx128();
    const src_count = 16 / @sizeOf(Src);
    const a = toLanes(Src, readVr(c, f.va()));
    const b = toLanes(Src, readVr(c, f.vb()));
    var out: [16 / @sizeOf(Dst)]Dst = undefined;
    var clamped = false;
    inline for (0..src_count) |i| {
        out[i] = packOne(Dst, mode, a[i], &clamped);
        out[src_count + i] = packOne(Dst, mode, b[i], &clamped);
    }
    if (clamped) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(Dst, out));
    return .advance;
}

fn packOne(comptime Dst: type, comptime mode: Overflow, value: anytype, clamped: *bool) Dst {
    return switch (mode) {
        .modulo => @truncate(value),
        .saturate => blk: {
            const result = saturate(Dst, value);
            clamped.* = clamped.* or result.clamped;
            break :blk result.value;
        },
    };
}

fn unpack(c: *Context, insn: Instruction, comptime half: MergeHalf) Outcome {
    const f = insn.vx128();
    const b = toLanes(i8, readVr(c, f.vb()));
    const base: usize = if (half == .high) 0 else 8;
    var out: [8]i16 = undefined;
    inline for (0..8) |i| out[i] = b[base + i];
    writeVr(c, f.vd(), fromLanes(i16, out));
    return .advance;
}

// ---------------------------------------------------------------------------
// Compare
// ---------------------------------------------------------------------------

const CompareKind = enum { equal, greater, greater_equal };

fn recordCr6(c: *Context, insn: Instruction, result: Vector) void {
    if (!insn.rc()) return;
    var all = true;
    var none = true;
    for (result) |word| {
        if (word != 0xFFFF_FFFF) all = false;
        if (word != 0) none = false;
    }
    var field: u4 = 0;
    if (all) field |= 0b1000;
    if (none) field |= 0b0010;
    c.state.setCrField(6, field);
}

fn compareInteger(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_r();
    const a = toLanes(u32, readVr(c, f.va()));
    const b = toLanes(u32, readVr(c, f.vb()));
    var out: [4]u32 = undefined;
    inline for (0..4) |i| out[i] = if (a[i] == b[i]) 0xFFFF_FFFF else 0;
    const result = fromLanes(u32, out);
    writeVr(c, f.vd(), result);
    recordCr6(c, insn, result);
    return .advance;
}

fn compareFloat(c: *Context, insn: Instruction, comptime kind: CompareKind) Outcome {
    const f = insn.vx128_r();
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

fn compareBounds(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_r();
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
    if (insn.rc()) {
        var in_bounds = true;
        for (out) |word| {
            if (word != 0) in_bounds = false;
        }
        c.state.setCrField(6, if (in_bounds) 0b0010 else 0b0000);
    }
    return .advance;
}

// ---------------------------------------------------------------------------
// Convert, estimate, splat
// ---------------------------------------------------------------------------

const FloatUnaryKind = enum {
    reciprocal,
    reciprocal_sqrt,
    exp2,
    log2,
    floor,
    ceil,
    truncate,
    nearest,
};

fn floatUnary(c: *Context, insn: Instruction, comptime kind: FloatUnaryKind) Outcome {
    const f = insn.vx128_3();
    const b = toFloats(readVr(c, f.vb()));
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        out[i] = switch (kind) {
            .reciprocal => 1.0 / b[i],
            .reciprocal_sqrt => 1.0 / @sqrt(b[i]),
            .exp2 => std.math.exp2(b[i]),
            .log2 => std.math.log2(b[i]),
            .floor => @floor(b[i]),
            .ceil => @ceil(b[i]),
            .truncate => @trunc(b[i]),
            .nearest => @round(b[i]),
        };
    }
    writeVr(c, f.vd(), fromFloats(out));
    return .advance;
}

fn convertToInteger(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx128_3();
    const b = toFloats(readVr(c, f.vb()));
    const scale = std.math.pow(f32, 2.0, @floatFromInt(f.uimm()));
    var out: [4]T = undefined;
    var clamped = false;
    inline for (0..4) |i| {
        const scaled = @trunc(b[i] * scale);
        const min: f32 = @floatFromInt(std.math.minInt(T));
        const max: f32 = @floatFromInt(std.math.maxInt(T));
        if (std.math.isNan(scaled)) {
            out[i] = 0;
            clamped = true;
        } else if (scaled <= min) {
            out[i] = std.math.minInt(T);
            clamped = true;
        } else if (scaled >= max) {
            out[i] = std.math.maxInt(T);
            clamped = true;
        } else {
            out[i] = @intFromFloat(scaled);
        }
    }
    if (clamped) setSaturated(c);
    writeVr(c, f.vd(), fromLanes(T, out));
    return .advance;
}

fn convertToFloat(c: *Context, insn: Instruction, comptime T: type) Outcome {
    const f = insn.vx128_3();
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

fn splatWord(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_3();
    const source = toLanes(u32, readVr(c, f.vb()));
    const value = source[f.uimm() & 3];
    writeVr(c, f.vd(), fromLanes(u32, .{ value, value, value, value }));
    return .advance;
}

fn splatImmediate(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_3();
    const value: i32 = @truncate(f.simm());
    writeVr(c, f.vd(), fromLanes(i32, .{ value, value, value, value }));
    return .advance;
}

// ---------------------------------------------------------------------------
// D3D vertex formats
//
// `vpkd3d128` and `vupkd3d128` are one instruction each with seven sub-formats
// selected by an immediate. They exist because the Xenon's vertex fetch reads
// packed formats the shader wants as floats, and the conversions are not
// generic: each format has its own bit layout, its own scale, and its own
// destination lanes.
//
// The unpacked floats are not normalised values. The conversions produce a
// float in a fixed binade with the payload in its mantissa - 3.0 + x*2^-22 for
// the 16-bit formats, 1.0 + x*2^-23 for D3DCOLOR - and the shader finishes the
// job with a multiply-add it already had to emit. Producing a "nicer" value
// here would break every guest that does that arithmetic.
// ---------------------------------------------------------------------------

/// The Xenos half-precision format: 1 sign, 5 exponent, 10 mantissa, with no
/// infinity or NaN encoding - exponent 31 is an ordinary value with extended
/// range. Denormals flush to zero.
fn xenosHalfToFloat(value: u16) f32 {
    var mantissa: u32 = value & 0x3FF;
    var exponent: u32 = (value >> 10) & 0x1F;
    if (exponent == 0) {
        mantissa = 0;
        // Bias the result to zero rather than to the smallest normal.
        exponent = @bitCast(@as(i32, -112));
    }
    const bits: u32 = (@as(u32, value & 0x8000) << 16) |
        ((exponent +% 112) << 23) | (mantissa << 13);
    return @bitCast(bits);
}

fn floatToXenosHalf(value: f32) u16 {
    const bits: u32 = @bitCast(value);
    const magnitude = bits & 0x7FFF_FFFF;
    var result: u32 = undefined;
    if (magnitude >= 0x47FF_E000) {
        // The format has no infinity, so an out-of-range value saturates to the
        // largest representable magnitude instead of becoming Inf.
        result = 0x7FFF;
    } else if (magnitude < 0x3880_0000) {
        result = 0;
    } else {
        result = (magnitude +% 0xC800_0000) >> 13 & 0x7FFF;
    }
    return @intCast(result | ((bits & 0x8000_0000) >> 16));
}

const D3dFormat = enum(u3) {
    d3dcolor = 0,
    short_2 = 1,
    uint_2101010 = 2,
    float16_2 = 3,
    short_4 = 4,
    float16_4 = 5,
    ulong_4202020 = 6,
    reserved = 7,
};

const float_3: u32 = 0x4040_0000;
const float_1: u32 = 0x3F80_0000;
const quiet_nan: u32 = 0x7FC0_0000;
/// 3.0 with a 16-bit payload of -0x8000: the one input that overflows the
/// 16-bit unpack, reported as a NaN rather than as a plausible number.
const short_overflow: u32 = 0x403F_8000;

/// The 4-20-20-20 format keeps signed XYZ at the same 3.0-biased scale as
/// the other normalized Xenos formats, but gives each channel a 20-bit
/// payload. W is unsigned and uses the 1.0 binade. These are the exact
/// saturation/overflow constants used by Xenia's Xenos vector emitter.
const ulong_min_xyz: u32 = 0x4038_0001;
const ulong_max_xyz: u32 = 0x4047_FFFF;
const ulong_min_w: u32 = 0x4040_0000;
const ulong_max_w: u32 = 0x4040_000F;
const ulong_overflow: u32 = 0x4038_0000;

fn unpackD3d(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_3();
    const format: D3dFormat = @enumFromInt(@as(u3, @truncate(f.uimm() >> 2)));
    const source = toLanes(u32, readVr(c, f.vb()));
    var out: [4]u32 = undefined;

    switch (format) {
        .d3dcolor => {
            // ARGB packed in the last lane becomes RGBA across all four, each
            // as 1.0 with the byte in the low mantissa bits.
            const packed_color = source[3];
            out[0] = float_1 | ((packed_color >> 16) & 0xFF);
            out[1] = float_1 | ((packed_color >> 8) & 0xFF);
            out[2] = float_1 | (packed_color & 0xFF);
            out[3] = float_1 | ((packed_color >> 24) & 0xFF);
        },
        .short_2 => {
            out[0] = shortToBiasedFloat(@truncate(source[3] >> 16));
            out[1] = shortToBiasedFloat(@truncate(source[3]));
            out[2] = 0;
            out[3] = float_1;
        },
        .short_4 => {
            out[0] = shortToBiasedFloat(@truncate(source[2] >> 16));
            out[1] = shortToBiasedFloat(@truncate(source[2]));
            out[2] = shortToBiasedFloat(@truncate(source[3] >> 16));
            out[3] = shortToBiasedFloat(@truncate(source[3]));
        },
        .uint_2101010 => {
            // Red 0-9, green 10-19, blue 20-29, alpha 30-31, all in the last
            // lane. The three colour channels are signed 10-bit; alpha is not.
            const value = source[3];
            inline for (0..3) |i| {
                const raw: u32 = (value >> @intCast(i * 10)) & 0x3FF;
                out[i] = biasedFloatBits(float_3, signExtend10(raw));
            }
            out[3] = float_1 +% ((value >> 30) & 3);
        },
        .float16_2 => {
            out[0] = @bitCast(xenosHalfToFloat(@truncate(source[3] >> 16)));
            out[1] = @bitCast(xenosHalfToFloat(@truncate(source[3])));
            out[2] = 0;
            out[3] = float_1;
        },
        .float16_4 => {
            out[0] = @bitCast(xenosHalfToFloat(@truncate(source[2] >> 16)));
            out[1] = @bitCast(xenosHalfToFloat(@truncate(source[2])));
            out[2] = @bitCast(xenosHalfToFloat(@truncate(source[3] >> 16)));
            out[3] = @bitCast(xenosHalfToFloat(@truncate(source[3])));
        },
        .ulong_4202020 => {
            // The packed 64-bit value is w_z_y_x: x occupies bits 0..19,
            // y bits 20..39, z bits 40..59, and w bits 60..63. The high and
            // low words live in lanes 2 and 3, respectively, just as they do
            // for SHORT_4 and FLOAT16_4.
            const high = source[2];
            const low = source[3];
            const x = low & 0xF_FFFF;
            const y = ((high & 0xFF) << 12) | (low >> 20);
            const z = (high >> 8) & 0xF_FFFF;
            const w = high >> 28;
            out[0] = biasedFloatBitsWithOverflow(float_3, signExtend20(x), ulong_overflow);
            out[1] = biasedFloatBitsWithOverflow(float_3, signExtend20(y), ulong_overflow);
            out[2] = biasedFloatBitsWithOverflow(float_3, signExtend20(z), ulong_overflow);
            out[3] = float_1 +% w;
        },
        .reserved => return .{ .unimplemented = insn.op },
    }

    writeVr(c, f.vd(), fromLanes(u32, out));
    return .advance;
}

fn signExtend10(value: u32) i32 {
    const shifted: i32 = @bitCast(value << 22);
    return shifted >> 22;
}

fn signExtend20(value: u32) i32 {
    const shifted: i32 = @bitCast(value << 12);
    return shifted >> 12;
}

/// Add a signed payload into a float's mantissa. The result is `base` plus
/// `payload * ulp(base)`, which is the representation the guest's shader
/// arithmetic expects.
fn biasedFloatBits(base: u32, payload: i32) u32 {
    return biasedFloatBitsWithOverflow(base, payload, short_overflow);
}

fn biasedFloatBitsWithOverflow(base: u32, payload: i32, overflow: u32) u32 {
    const sum: u32 = base +% @as(u32, @bitCast(payload));
    return if (sum == overflow) quiet_nan else sum;
}

fn shortToBiasedFloat(value: u16) u32 {
    return biasedFloatBits(float_3, @as(i16, @bitCast(value)));
}

fn packD3d(c: *Context, insn: Instruction) Outcome {
    const f = insn.vx128_4();
    const format: D3dFormat = @enumFromInt(@as(u3, @truncate(f.imm() >> 2)));
    const source = toLanes(u32, readVr(c, f.vb()));
    var packed_lanes: [4]u32 = .{ 0, 0, 0, 0 };

    switch (format) {
        .d3dcolor => {
            // The inverse of the unpack: RGBA lanes back into one ARGB word.
            packed_lanes[3] = (biasedByte(source[3]) << 24) |
                (biasedByte(source[0]) << 16) |
                (biasedByte(source[1]) << 8) |
                biasedByte(source[2]);
        },
        .short_2 => {
            packed_lanes[3] = (@as(u32, biasedShort(source[0])) << 16) |
                biasedShort(source[1]);
        },
        .short_4 => {
            packed_lanes[2] = (@as(u32, biasedShort(source[0])) << 16) |
                biasedShort(source[1]);
            packed_lanes[3] = (@as(u32, biasedShort(source[2])) << 16) |
                biasedShort(source[3]);
        },
        .uint_2101010 => {
            inline for (0..3) |i| {
                const channel: u32 = @as(u32, @bitCast(source[i] -% float_3)) & 0x3FF;
                packed_lanes[3] |= channel << @intCast(i * 10);
            }
            packed_lanes[3] |= ((source[3] -% float_1) & 3) << 30;
        },
        .float16_2 => {
            packed_lanes[3] = (@as(u32, floatToXenosHalf(@bitCast(source[0]))) << 16) |
                floatToXenosHalf(@bitCast(source[1]));
        },
        .float16_4 => {
            packed_lanes[2] = (@as(u32, floatToXenosHalf(@bitCast(source[0]))) << 16) |
                floatToXenosHalf(@bitCast(source[1]));
            packed_lanes[3] = (@as(u32, floatToXenosHalf(@bitCast(source[2]))) << 16) |
                floatToXenosHalf(@bitCast(source[3]));
        },
        .ulong_4202020 => {
            const x = pack4202020Lane(source[0], ulong_min_xyz, ulong_max_xyz, 0xF_FFFF);
            const y = pack4202020Lane(source[1], ulong_min_xyz, ulong_max_xyz, 0xF_FFFF);
            const z = pack4202020Lane(source[2], ulong_min_xyz, ulong_max_xyz, 0xF_FFFF);
            const w = pack4202020Lane(source[3], ulong_min_w, ulong_max_w, 0xF);
            packed_lanes[2] = (w << 28) | (z << 8) | (y >> 12);
            packed_lanes[3] = (y << 20) | x;
        },
        .reserved => return .{ .unimplemented = insn.op },
    }

    // `pack` chooses how many low words are merged into the old destination;
    // `z` shifts that payload toward the high end. This is a real merge, not
    // simply a write to lanes 2/3: vertex code uses it to assemble a packed
    // word while preserving the other words in vD.
    const previous = toLanes(u32, readVr(c, f.vd()));
    const out = mergePackedD3d(previous, packed_lanes, @truncate(f.imm() & 3), f.z());
    writeVr(c, f.vd(), fromLanes(u32, out));
    return .advance;
}

fn pack4202020Lane(bits: u32, min_bits: u32, max_bits: u32, mask: u32) u32 {
    const value: f32 = @bitCast(bits);
    const clamped = if (std.math.isNan(value) or value < @as(f32, @bitCast(min_bits)))
        min_bits
    else if (value > @as(f32, @bitCast(max_bits)))
        max_bits
    else
        bits;
    return clamped & mask;
}

fn mergePackedD3d(previous: [4]u32, packed_lanes: [4]u32, pack_selector: u2, shift: u2) [4]u32 {
    var out = previous;
    switch (pack_selector) {
        0 => {},
        1 => switch (shift) {
            0 => out[3] = packed_lanes[3],
            1 => out[2] = packed_lanes[3],
            2 => out[1] = packed_lanes[3],
            3 => out[0] = packed_lanes[3],
        },
        2 => switch (shift) {
            0 => {
                out[2] = packed_lanes[2];
                out[3] = packed_lanes[3];
            },
            1 => {
                out[1] = packed_lanes[2];
                out[2] = packed_lanes[3];
            },
            2 => {
                out[0] = packed_lanes[2];
                out[1] = packed_lanes[3];
            },
            3 => out[0] = packed_lanes[3],
        },
        3 => switch (shift) {
            0 => {
                out[2] = packed_lanes[2];
                out[3] = packed_lanes[3];
            },
            1 => {
                out[1] = packed_lanes[2];
                out[2] = packed_lanes[3];
            },
            2 => {
                out[0] = packed_lanes[2];
                out[1] = packed_lanes[3];
            },
            3 => out[3] = packed_lanes[2],
        },
    }
    return out;
}

fn biasedByte(bits: u32) u32 {
    return bits & 0xFF;
}

fn biasedShort(bits: u32) u16 {
    return @truncate(bits -% float_3);
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

/// Build a VX128 word with seven-bit register numbers spread across the fields
/// the encoding actually uses.
fn vx128Word(op: ppc_decode.Op, vd: u7, va: u7, vb: u7) u32 {
    const base = op.info().pattern;
    var word = base;
    word |= (@as(u32, vd) & 0x1F) << 21;
    word |= ((@as(u32, vd) >> 5) & 3) << 2;
    word |= (@as(u32, va) & 0x1F) << 16;
    word |= ((@as(u32, va) >> 5) & 1) << 5;
    word |= ((@as(u32, va) >> 6) & 1) << 10;
    word |= (@as(u32, vb) & 0x1F) << 11;
    word |= ((@as(u32, vb) >> 5) & 3) << 0;
    return word;
}

fn vx1Word(op: ppc_decode.Op, vd: u7, ra: u5, rb: u5) u32 {
    const base = op.info().pattern;
    var word = base;
    word |= (@as(u32, vd) & 0x1F) << 21;
    word |= ((@as(u32, vd) >> 5) & 3) << 2;
    word |= @as(u32, ra) << 16;
    word |= @as(u32, rb) << 11;
    return word;
}

fn vx4Word(op: ppc_decode.Op, vd: u7, vb: u7, imm: u5, z: u2) u32 {
    var word = op.info().pattern;
    word |= (@as(u32, vd) & 0x1F) << 21;
    word |= ((@as(u32, vd) >> 5) & 3) << 2;
    word |= (@as(u32, vb) & 0x1F) << 11;
    word |= ((@as(u32, vb) >> 5) & 3) << 0;
    word |= @as(u32, imm) << 16;
    word |= @as(u32, z) << 6;
    return word;
}

fn vxPWord(op: ppc_decode.Op, vd: u7, vb: u7, uimm: u8) u32 {
    var word = op.info().pattern;
    word |= (@as(u32, vd) & 0x1F) << 21;
    word |= ((@as(u32, vd) >> 5) & 3) << 2;
    word |= (@as(u32, vb) & 0x1F) << 11;
    word |= ((@as(u32, vb) >> 5) & 3) << 0;
    // The eight-bit selector is split: five bits in the VA slot, three more
    // alongside the register high bits.
    word |= (@as(u32, uimm) & 0x1F) << 16;
    word |= ((@as(u32, uimm) >> 5) & 7) << 6;
    return word;
}

fn vx3Word(op: ppc_decode.Op, vd: u7, vb: u7, uimm: u5) u32 {
    const base = op.info().pattern;
    var word = base;
    word |= (@as(u32, vd) & 0x1F) << 21;
    word |= ((@as(u32, vd) >> 5) & 3) << 2;
    word |= (@as(u32, vb) & 0x1F) << 11;
    word |= ((@as(u32, vb) >> 5) & 3) << 0;
    word |= @as(u32, uimm) << 16;
    return word;
}

test "a VMX128 register number is reassembled from every field" {
    var h = Harness{};
    // Registers 100 and 71 both alias low registers if the high bits are lost.
    h.state.vr[100] = .{ 1, 2, 3, 4 };
    h.state.vr[71] = .{ 10, 20, 30, 40 };
    const word = vx128Word(.vaddfp128, 96, 100, 71);
    h.state.vr[100] = fromFloats(.{ 1, 2, 3, 4 });
    h.state.vr[71] = fromFloats(.{ 10, 20, 30, 40 });
    _ = try h.run(word);
    try testing.expectEqual([4]f32{ 11, 22, 33, 44 }, toFloats(h.state.vr[96]));
    // The 32-register aliases must be untouched.
    try testing.expectEqual(Vector{ 0, 0, 0, 0 }, h.state.vr[4]);
    try testing.expectEqual(Vector{ 0, 0, 0, 0 }, h.state.vr[7]);
    try testing.expectEqual(Vector{ 0, 0, 0, 0 }, h.state.vr[0]);
}

test "the VMX128 logical ops work on the wide register file" {
    var h = Harness{};
    h.state.vr[80] = .{ 0xF0F0F0F0, 0, 0, 0 };
    h.state.vr[81] = .{ 0xFF00FF00, 0, 0, 0 };
    _ = try h.run(vx128Word(.vand128, 82, 80, 81));
    try testing.expectEqual(@as(u32, 0xF000F000), h.state.vr[82][0]);
    _ = try h.run(vx128Word(.vor128, 82, 80, 81));
    try testing.expectEqual(@as(u32, 0xFFF0FFF0), h.state.vr[82][0]);
    _ = try h.run(vx128Word(.vxor128, 82, 80, 81));
    try testing.expectEqual(@as(u32, 0x0FF00FF0), h.state.vr[82][0]);
}

test "vmaddfp128 adds the destination, vmaddcfp128 multiplies by it" {
    var h = Harness{};
    h.state.vr[10] = fromFloats(.{ 2, 2, 2, 2 }); // vA
    h.state.vr[11] = fromFloats(.{ 3, 3, 3, 3 }); // vB
    h.state.vr[12] = fromFloats(.{ 5, 5, 5, 5 }); // vD

    _ = try h.run(vx128Word(.vmaddfp128, 12, 10, 11));
    // (2 * 3) + 5
    try testing.expectEqual([4]f32{ 11, 11, 11, 11 }, toFloats(h.state.vr[12]));

    h.state.vr[12] = fromFloats(.{ 5, 5, 5, 5 });
    _ = try h.run(vx128Word(.vmaddcfp128, 12, 10, 11));
    // (2 * 5) + 3 - a different answer from the same three registers.
    try testing.expectEqual([4]f32{ 13, 13, 13, 13 }, toFloats(h.state.vr[12]));
}

test "vmsum3fp128 ignores the fourth lane and broadcasts the result" {
    var h = Harness{};
    h.state.vr[10] = fromFloats(.{ 1, 2, 3, 1000 });
    h.state.vr[11] = fromFloats(.{ 4, 5, 6, 1000 });
    _ = try h.run(vx128Word(.vmsum3fp128, 12, 10, 11));
    try testing.expectEqual([4]f32{ 32, 32, 32, 32 }, toFloats(h.state.vr[12]));
    _ = try h.run(vx128Word(.vmsum4fp128, 12, 10, 11));
    try testing.expectEqual([4]f32{ 1000032, 1000032, 1000032, 1000032 }, toFloats(h.state.vr[12]));
}

test "vsel128 takes its mask from the destination register" {
    var h = Harness{};
    h.state.vr[20] = .{ 0xAAAAAAAA, 0, 0, 0 };
    h.state.vr[21] = .{ 0x55555555, 0, 0, 0 };
    h.state.vr[22] = .{ 0x0000FFFF, 0, 0, 0 };
    _ = try h.run(vx128Word(.vsel128, 22, 20, 21));
    try testing.expectEqual(@as(u32, 0xAAAA5555), h.state.vr[22][0]);
}

test "vpermwi128 reads its two-bit selectors from the high end" {
    var h = Harness{};
    h.state.vr[30] = fromLanes(u32, .{ 10, 20, 30, 40 });
    // Selector 0b00_01_10_11 -> lanes 0,1,2,3.
    _ = try h.run(vxPWord(.vpermwi128, 31, 30, 0b00_01_10_11));
    try testing.expectEqual([4]u32{ 10, 20, 30, 40 }, toLanes(u32, h.state.vr[31]));

    // Reversing the selector must reverse the lanes, not leave them alone.
    _ = try h.run(vxPWord(.vpermwi128, 31, 30, 0b11_10_01_00));
    try testing.expectEqual([4]u32{ 40, 30, 20, 10 }, toLanes(u32, h.state.vr[31]));
}

test "vrlimi128 writes only the lanes its mask names, counted from the high end" {
    var h = Harness{};
    h.state.vr[40] = fromLanes(u32, .{ 1, 2, 3, 4 }); // vB
    h.state.vr[41] = fromLanes(u32, .{ 90, 91, 92, 93 }); // vD
    // IMM = 0b1000 -> lane 0 only, rotate 0.
    _ = try h.run(vx4Word(.vrlimi128, 41, 40, 0b1000, 0));
    try testing.expectEqual([4]u32{ 1, 91, 92, 93 }, toLanes(u32, h.state.vr[41]));

    // IMM = 0b0001 -> lane 3 only.
    h.state.vr[41] = fromLanes(u32, .{ 90, 91, 92, 93 });
    _ = try h.run(vx4Word(.vrlimi128, 41, 40, 0b0001, 0));
    try testing.expectEqual([4]u32{ 90, 91, 92, 4 }, toLanes(u32, h.state.vr[41]));
}

test "vrlimi128 rotates the source before inserting it" {
    var h = Harness{};
    h.state.vr[40] = fromLanes(u32, .{ 1, 2, 3, 4 });
    h.state.vr[41] = fromLanes(u32, .{ 0, 0, 0, 0 });
    // Rotate by two words, write every lane.
    _ = try h.run(vx4Word(.vrlimi128, 41, 40, 0b1111, 2));
    try testing.expectEqual([4]u32{ 3, 4, 1, 2 }, toLanes(u32, h.state.vr[41]));
}

test "a VMX128 vector load and store round-trip through guest memory" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 16;
    h.state.vr[70] = .{ 0x01020304, 0x05060708, 0x090A0B0C, 0x0D0E0F10 };
    _ = try h.run(vx1Word(.stvx128, 70, 4, 5));
    try testing.expectEqual(@as(u8, 0x01), h.buf[16]);
    try testing.expectEqual(@as(u8, 0x10), h.buf[31]);
    _ = try h.run(vx1Word(.lvx128, 71, 4, 5));
    try testing.expectEqual(h.state.vr[70], h.state.vr[71]);
}

test "vspltw128 and vspltisw128 fill every lane" {
    var h = Harness{};
    h.state.vr[60] = fromLanes(u32, .{ 7, 8, 9, 10 });
    _ = try h.run(vx3Word(.vspltw128, 61, 60, 2));
    try testing.expectEqual([4]u32{ 9, 9, 9, 9 }, toLanes(u32, h.state.vr[61]));
    _ = try h.run(vx3Word(.vspltisw128, 61, 0, 0x1F));
    try testing.expectEqual([4]i32{ -1, -1, -1, -1 }, toLanes(i32, h.state.vr[61]));
}

test "a VMX128 compare writes a mask and reports CR6 under Rc" {
    var h = Harness{};
    h.state.vr[50] = fromLanes(u32, .{ 1, 2, 3, 4 });
    h.state.vr[51] = fromLanes(u32, .{ 1, 2, 3, 4 });
    var word = vx128Word(.vcmpequw128, 52, 50, 51);
    word |= 1 << 6; // Rc
    _ = try h.run(word);
    try testing.expectEqual(Vector{ 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF }, h.state.vr[52]);
    try testing.expectEqual(@as(u4, 0b1000), h.state.crField(6));
}

test "the D3DCOLOR format round-trips through pack and unpack" {
    var h = Harness{};
    // A = 0x12, R = 0x34, G = 0x56, B = 0x78.
    h.state.vr[60] = fromLanes(u32, .{ 0, 0, 0, 0x12345678 });
    _ = try h.run(vx3Word(.vupkd3d128, 61, 60, 0));
    const unpacked = toLanes(u32, h.state.vr[61]);
    // Each lane is 1.0 with the channel byte in the low mantissa bits, and the
    // ARGB source becomes RGBA lanes.
    try testing.expectEqual(@as(u32, 0x3F800000 | 0x34), unpacked[0]);
    try testing.expectEqual(@as(u32, 0x3F800000 | 0x56), unpacked[1]);
    try testing.expectEqual(@as(u32, 0x3F800000 | 0x78), unpacked[2]);
    try testing.expectEqual(@as(u32, 0x3F800000 | 0x12), unpacked[3]);

    h.state.vr[62] = h.state.vr[61];
    _ = try h.run(vx4Word(.vpkd3d128, 63, 62, 1, 0)); // type 0, pack 1
    try testing.expectEqual(@as(u32, 0x12345678), toLanes(u32, h.state.vr[63])[3]);
}

test "the SHORT_2 format biases into the 3.0 binade and flags its overflow" {
    var h = Harness{};
    h.state.vr[60] = fromLanes(u32, .{ 0, 0, 0, (1 << 16) | 0xFFFF });
    _ = try h.run(vx3Word(.vupkd3d128, 61, 60, 1 << 2));
    const out = toLanes(u32, h.state.vr[61]);
    try testing.expectEqual(@as(u32, 0x40400000 + 1), out[0]);
    // -1 lands one ulp below 3.0.
    try testing.expectEqual(@as(u32, 0x40400000 - 1), out[1]);
    try testing.expectEqual(@as(u32, 0), out[2]);
    try testing.expectEqual(@as(u32, 0x3F800000), out[3]);

    // -0x8000 is the one input that overflows the format; it reports NaN.
    h.state.vr[60] = fromLanes(u32, .{ 0, 0, 0, 0x8000_0000 });
    _ = try h.run(vx3Word(.vupkd3d128, 61, 60, 1 << 2));
    try testing.expectEqual(@as(u32, 0x7FC00000), toLanes(u32, h.state.vr[61])[0]);
}

test "the FLOAT16_2 format converts through the Xenos half encoding" {
    var h = Harness{};
    // 1.0 and 2.0 as Xenos halves.
    const one: u32 = 0x3C00;
    const two: u32 = 0x4000;
    h.state.vr[60] = fromLanes(u32, .{ 0, 0, 0, (one << 16) | two });
    _ = try h.run(vx3Word(.vupkd3d128, 61, 60, 3 << 2));
    const out = toFloats(h.state.vr[61]);
    try testing.expectEqual(@as(f32, 1.0), out[0]);
    try testing.expectEqual(@as(f32, 2.0), out[1]);
    try testing.expectEqual(@as(f32, 0.0), out[2]);
    try testing.expectEqual(@as(f32, 1.0), out[3]);
}

test "a Xenos half saturates instead of becoming infinity" {
    // The format has no Inf encoding, so a large value has to clamp.
    try testing.expectEqual(@as(u16, 0x7FFF), floatToXenosHalf(1.0e30));
    try testing.expectEqual(@as(u16, 0xFFFF), floatToXenosHalf(-1.0e30));
    try testing.expectEqual(@as(f32, 1.0), xenosHalfToFloat(0x3C00));
    try testing.expectEqual(@as(f32, -2.0), xenosHalfToFloat(0xC000));
    // Denormals flush to zero rather than becoming tiny normals.
    try testing.expectEqual(@as(f32, 0.0), xenosHalfToFloat(0x0001));
}

test "the 4-20-20-20 vertex format unpacks signed fields and unsigned W" {
    var h = Harness{};
    const x: u32 = 0x12345;
    const y: u32 = 0xFFFFF; // -1 after sign extension.
    const z: u32 = 0x80000; // The negative endpoint maps to quiet NaN.
    const w: u32 = 0xA;
    const high = (w << 28) | (z << 8) | (y >> 12);
    const low = (y << 20) | x;
    h.state.vr[60] = fromLanes(u32, .{ 0, 0, high, low });

    _ = try h.run(vx3Word(.vupkd3d128, 61, 60, 6 << 2));
    const out = toLanes(u32, h.state.vr[61]);
    try testing.expectEqual(float_3 + x, out[0]);
    try testing.expectEqual(float_3 - 1, out[1]);
    try testing.expectEqual(quiet_nan, out[2]);
    try testing.expectEqual(float_1 + w, out[3]);
}

test "vpkd3d128 packs 4-20-20-20 and honors the 64-bit merge" {
    var h = Harness{};
    const x: u32 = 0x12345;
    const y: u32 = 0xFFFFF;
    const z: u32 = 0x34567;
    const w: u32 = 0xA;
    h.state.vr[62] = fromLanes(u32, .{
        float_3 + x,
        biasedFloatBits(float_3, signExtend20(y)),
        float_3 + z,
        float_3 + w,
    });
    h.state.vr[63] = fromLanes(u32, .{ 0xAAAA_AAAA, 0xBBBB_BBBB, 0xCCCC_CCCC, 0xDDDD_DDDD });

    // Type 6, pack 2, shift 0: replace the low 64 bits and preserve the high
    // two words from the old destination.
    _ = try h.run(vx4Word(.vpkd3d128, 63, 62, (6 << 2) | 2, 0));
    try testing.expectEqual(
        [4]u32{ 0xAAAA_AAAA, 0xBBBB_BBBB, 0xA345_67FF, 0xFFF1_2345 },
        toLanes(u32, h.state.vr[63]),
    );
}
