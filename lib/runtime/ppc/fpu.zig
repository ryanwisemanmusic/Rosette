//! PowerPC floating-point execution.
//!
//! Every PowerPC FPR is a 64-bit double, including in the single-precision
//! instructions. `fadds` does not compute in float: it computes the
//! double-precision result, rounds *that* to single, and stores the rounded
//! value back as a double. Computing in f32 throughout gives a different answer
//! for operands whose exact product needs more than 24 bits, which is most of
//! them, so the round-to-single is a separate, explicit step here.
//!
//! The integer-conversion instructions do not store an integer in an integer
//! register - they store the integer's *bit pattern* in an FPR, which the guest
//! then spills with `stfd` or `stfiwx` and reloads as an integer. Treating the
//! destination as a numeric double would round the bits into garbage.
//!
//! FPSCR is modelled for what the guest reads back: the rounding mode, the
//! condition code that `fcmpu`/`fcmpo` write, and the sticky exception summary.
//! Full IEEE trap-enable emulation is a named gap rather than a silent one.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");

const Context = ctx_mod.Context;
const Outcome = ctx_mod.Outcome;
const Instruction = ctx_mod.Instruction;
const Fault = ctx_mod.Fault;

/// FPSCR bit positions, given as architectural bit numbers (0 = most
/// significant) and converted once here.
pub const Fpscr = struct {
    pub fn bit(comptime architectural: u5) u32 {
        return @as(u32, 1) << (31 - architectural);
    }
    /// Exception summary, sticky.
    pub const fx = bit(0);
    /// Any enabled exception, sticky.
    pub const fex = bit(1);
    /// Invalid operation summary, sticky.
    pub const vx = bit(2);
    /// Overflow, sticky.
    pub const ox = bit(3);
    /// Underflow, sticky.
    pub const ux = bit(4);
    /// Zero divide, sticky.
    pub const zx = bit(5);
    /// Inexact, sticky.
    pub const xx = bit(6);
    /// Invalid operation: signalling NaN.
    pub const vxsnan = bit(7);
    /// Invalid operation: invalid compare.
    pub const vxvc = bit(12);
    /// Fraction rounded.
    pub const fr = bit(14);
    /// Fraction inexact.
    pub const fi = bit(15);
    /// The four condition-code bits inside FPRF: architectural bits 16..19.
    pub const fpcc_shift: u5 = 31 - 19;
    pub const fpcc_mask: u32 = @as(u32, 0xF) << fpcc_shift;

    /// Rounding mode: architectural bits 30..31.
    pub const RoundingMode = enum(u2) {
        nearest = 0,
        toward_zero = 1,
        toward_positive = 2,
        toward_negative = 3,
    };

    pub fn roundingMode(fpscr: u32) RoundingMode {
        return @enumFromInt(@as(u2, @truncate(fpscr)));
    }
};

/// Set a sticky FPSCR bit and the summary bits it implies.
fn raise(c: *Context, flag: u32) void {
    c.state.fpscr |= flag | Fpscr.fx;
    if (flag & (Fpscr.vxsnan | Fpscr.vxvc) != 0) c.state.fpscr |= Fpscr.vx;
}

fn readFpr(c: *const Context, index: u5) f64 {
    return c.state.fpr[index];
}

fn writeFpr(c: *Context, index: u5, value: f64) void {
    c.state.fpr[index] = value;
}

/// Reinterpret an FPR as raw bits, for the conversion instructions that store
/// an integer pattern rather than a number.
fn fprBits(c: *const Context, index: u5) u64 {
    return @bitCast(c.state.fpr[index]);
}

fn writeFprBits(c: *Context, index: u5, bits: u64) void {
    c.state.fpr[index] = @bitCast(bits);
}

/// Round a double to single precision and back, as every `...s` form does.
fn toSingle(value: f64) f64 {
    return @floatCast(@as(f32, @floatCast(value)));
}

fn recordCr1(c: *Context, insn: Instruction) void {
    if (insn.rc()) c.state.updateCr1();
}

pub fn execute(c: *Context, insn: Instruction) Fault!Outcome {
    return switch (insn.op) {
        // -- loads and stores ---------------------------------------------
        .lfs => loadFloat(c, insn, f32, .displacement, false),
        .lfsu => loadFloat(c, insn, f32, .displacement, true),
        .lfsx => loadFloat(c, insn, f32, .indexed, false),
        .lfsux => loadFloat(c, insn, f32, .indexed, true),
        .lfd => loadFloat(c, insn, f64, .displacement, false),
        .lfdu => loadFloat(c, insn, f64, .displacement, true),
        .lfdx => loadFloat(c, insn, f64, .indexed, false),
        .lfdux => loadFloat(c, insn, f64, .indexed, true),
        .stfs => storeFloat(c, insn, f32, .displacement, false),
        .stfsu => storeFloat(c, insn, f32, .displacement, true),
        .stfsx => storeFloat(c, insn, f32, .indexed, false),
        .stfsux => storeFloat(c, insn, f32, .indexed, true),
        .stfd => storeFloat(c, insn, f64, .displacement, false),
        .stfdu => storeFloat(c, insn, f64, .displacement, true),
        .stfdx => storeFloat(c, insn, f64, .indexed, false),
        .stfdux => storeFloat(c, insn, f64, .indexed, true),
        .stfiwx => storeIntegerWord(c, insn),

        // -- arithmetic ----------------------------------------------------
        .faddx => binary(c, insn, .add, false),
        .faddsx => binary(c, insn, .add, true),
        .fsubx => binary(c, insn, .subtract, false),
        .fsubsx => binary(c, insn, .subtract, true),
        .fmulx => binary(c, insn, .multiply, false),
        .fmulsx => binary(c, insn, .multiply, true),
        .fdivx => binary(c, insn, .divide, false),
        .fdivsx => binary(c, insn, .divide, true),
        .fsqrtx => unary(c, insn, .sqrt, false),
        .fsqrtsx => unary(c, insn, .sqrt, true),
        .fresx => unary(c, insn, .reciprocal, true),
        .frsqrtex => unary(c, insn, .reciprocal_sqrt, false),

        // -- fused multiply-add --------------------------------------------
        .fmaddx => multiplyAdd(c, insn, false, false, false),
        .fmaddsx => multiplyAdd(c, insn, false, false, true),
        .fmsubx => multiplyAdd(c, insn, true, false, false),
        .fmsubsx => multiplyAdd(c, insn, true, false, true),
        .fnmaddx => multiplyAdd(c, insn, false, true, false),
        .fnmaddsx => multiplyAdd(c, insn, false, true, true),
        .fnmsubx => multiplyAdd(c, insn, true, true, false),
        .fnmsubsx => multiplyAdd(c, insn, true, true, true),

        // -- move and select ------------------------------------------------
        .fmrx => move(c, insn, .copy),
        .fnegx => move(c, insn, .negate),
        .fabsx => move(c, insn, .absolute),
        .fnabsx => move(c, insn, .negative_absolute),
        .fselx => select(c, insn),

        // -- convert ---------------------------------------------------------
        .frspx => roundToSingle(c, insn),
        .fctiwx => convertToInteger(c, insn, i32, false),
        .fctiwzx => convertToInteger(c, insn, i32, true),
        .fctidx => convertToInteger(c, insn, i64, false),
        .fctidzx => convertToInteger(c, insn, i64, true),
        .fcfidx => convertFromInteger(c, insn),

        // -- compare ----------------------------------------------------------
        .fcmpu => compare(c, insn, false),
        .fcmpo => compare(c, insn, true),

        // -- FPSCR ------------------------------------------------------------
        .mffsx => moveFromFpscr(c, insn),
        .mtfsfx => moveToFpscrFields(c, insn),
        .mtfsb0x => setFpscrBit(c, insn, 0),
        .mtfsb1x => setFpscrBit(c, insn, 1),
        .mtfsfix => moveToFpscrField(c, insn),
        .mcrfs => moveFpscrToCr(c, insn),

        else => .{ .unimplemented = insn.op },
    };
}

// ---------------------------------------------------------------------------
// Memory
// ---------------------------------------------------------------------------

const AddressMode = enum { displacement, indexed };

fn floatAddress(c: *Context, insn: Instruction, comptime mode: AddressMode, update: bool) struct { ea: u32, ra: u5 } {
    return switch (mode) {
        .displacement => blk: {
            const f = insn.d();
            const base = if (update) c.gpr(f.ra()) else c.state.ra0(f.ra());
            break :blk .{ .ea = @truncate(base +% @as(u64, @bitCast(f.simm()))), .ra = f.ra() };
        },
        .indexed => blk: {
            const f = insn.x();
            const base = if (update) c.gpr(f.ra()) else c.state.ra0(f.ra());
            break :blk .{ .ea = @truncate(base +% c.gpr(f.rb())), .ra = f.ra() };
        },
    };
}

fn floatRegister(insn: Instruction, comptime mode: AddressMode) u5 {
    return switch (mode) {
        .displacement => insn.d().fd(),
        .indexed => insn.x().fd(),
    };
}

fn loadFloat(
    c: *Context,
    insn: Instruction,
    comptime T: type,
    comptime mode: AddressMode,
    update: bool,
) Fault!Outcome {
    const addr = floatAddress(c, insn, mode, update);
    const value: f64 = if (T == f32)
        @floatCast(@as(f32, @bitCast(try c.memory.read(u32, addr.ea))))
    else
        @bitCast(try c.memory.read(u64, addr.ea));
    writeFpr(c, floatRegister(insn, mode), value);
    if (update) c.setGpr(addr.ra, addr.ea);
    return .advance;
}

fn storeFloat(
    c: *Context,
    insn: Instruction,
    comptime T: type,
    comptime mode: AddressMode,
    update: bool,
) Fault!Outcome {
    const addr = floatAddress(c, insn, mode, update);
    const value = readFpr(c, floatRegister(insn, mode));
    if (T == f32) {
        try c.memory.write(u32, addr.ea, @bitCast(@as(f32, @floatCast(value))));
    } else {
        try c.memory.write(u64, addr.ea, @bitCast(value));
    }
    c.breakReservation(addr.ea);
    if (update) c.setGpr(addr.ra, addr.ea);
    return .advance;
}

/// stfiwx stores the low word of the FPR's *bit pattern*, which is how a guest
/// gets the result of fctiwz into memory as an integer.
fn storeIntegerWord(c: *Context, insn: Instruction) Fault!Outcome {
    const f = insn.x();
    const ea: u32 = @truncate(c.state.ra0(f.ra()) +% c.gpr(f.rb()));
    try c.memory.write(u32, ea, @truncate(fprBits(c, f.fs())));
    c.breakReservation(ea);
    return .advance;
}

// ---------------------------------------------------------------------------
// Arithmetic
// ---------------------------------------------------------------------------

const BinaryKind = enum { add, subtract, multiply, divide };

fn binary(c: *Context, insn: Instruction, comptime kind: BinaryKind, comptime single: bool) Outcome {
    const f = insn.a();
    const a = readFpr(c, f.fa());
    // fmul takes its second operand from FC, not FB: the A form's operand slots
    // differ per instruction and swapping them silently multiplies the wrong
    // pair on any instruction whose FB and FC differ.
    const b = if (kind == .multiply) readFpr(c, f.fc()) else readFpr(c, f.fb());
    if (kind == .divide and b == 0.0 and !std.math.isNan(a)) raise(c, Fpscr.zx);
    var result: f64 = switch (kind) {
        .add => a + b,
        .subtract => a - b,
        .multiply => a * b,
        .divide => a / b,
    };
    if (single) result = toSingle(result);
    writeFpr(c, f.fd(), result);
    updateFprf(c, result);
    recordCr1(c, insn);
    return .advance;
}

const UnaryKind = enum { sqrt, reciprocal, reciprocal_sqrt };

fn unary(c: *Context, insn: Instruction, comptime kind: UnaryKind, comptime single: bool) Outcome {
    const f = insn.a();
    const b = readFpr(c, f.fb());
    var result: f64 = switch (kind) {
        .sqrt => @sqrt(b),
        .reciprocal => 1.0 / b,
        .reciprocal_sqrt => 1.0 / @sqrt(b),
    };
    if (single) result = toSingle(result);
    writeFpr(c, f.fd(), result);
    updateFprf(c, result);
    recordCr1(c, insn);
    return .advance;
}

/// fmadd computes (fA * fC) + fB with a single rounding. Rounding the product
/// first changes the last bit of a large fraction of results, which is exactly
/// the difference a game's physics integrator accumulates into a visible drift.
fn multiplyAdd(
    c: *Context,
    insn: Instruction,
    comptime subtract: bool,
    comptime negate: bool,
    comptime single: bool,
) Outcome {
    const f = insn.a();
    const a = readFpr(c, f.fa());
    const b = readFpr(c, f.fb());
    const cc = readFpr(c, f.fc());
    const addend = if (subtract) -b else b;
    var result = @mulAdd(f64, a, cc, addend);
    if (negate) result = -result;
    if (single) result = toSingle(result);
    writeFpr(c, f.fd(), result);
    updateFprf(c, result);
    recordCr1(c, insn);
    return .advance;
}

const MoveKind = enum { copy, negate, absolute, negative_absolute };

fn move(c: *Context, insn: Instruction, comptime kind: MoveKind) Outcome {
    const f = insn.x();
    // These are bit operations, not arithmetic: fneg of a NaN flips its sign
    // bit and leaves the payload, where `0 - x` would not.
    const bits = fprBits(c, f.fb());
    const sign: u64 = @as(u64, 1) << 63;
    const value: u64 = switch (kind) {
        .copy => bits,
        .negate => bits ^ sign,
        .absolute => bits & ~sign,
        .negative_absolute => bits | sign,
    };
    writeFprBits(c, f.fd(), value);
    recordCr1(c, insn);
    return .advance;
}

/// fsel is a branchless select on `fA >= 0`. A NaN in fA selects fB, because
/// the comparison is false for NaN - which is the whole point of the
/// instruction in a guest that cannot afford a mispredicted branch.
fn select(c: *Context, insn: Instruction) Outcome {
    const f = insn.a();
    const a = readFpr(c, f.fa());
    const value = if (a >= 0.0) readFpr(c, f.fc()) else readFpr(c, f.fb());
    writeFpr(c, f.fd(), value);
    recordCr1(c, insn);
    return .advance;
}

fn roundToSingle(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const value = toSingle(readFpr(c, f.fb()));
    writeFpr(c, f.fd(), value);
    updateFprf(c, value);
    recordCr1(c, insn);
    return .advance;
}

fn convertToInteger(
    c: *Context,
    insn: Instruction,
    comptime T: type,
    comptime truncate_toward_zero: bool,
) Outcome {
    const f = insn.x();
    const source = readFpr(c, f.fb());
    const rounded: f64 = if (truncate_toward_zero)
        @trunc(source)
    else switch (Fpscr.roundingMode(c.state.fpscr)) {
        .nearest => roundHalfToEven(source),
        .toward_zero => @trunc(source),
        .toward_positive => @ceil(source),
        .toward_negative => @floor(source),
    };

    // Out of range, or NaN, produces the saturated bound and raises the
    // invalid-conversion exception rather than wrapping into a plausible value.
    const min: f64 = @floatFromInt(std.math.minInt(T));
    const max: f64 = @floatFromInt(std.math.maxInt(T));
    var integer: T = undefined;
    if (std.math.isNan(source)) {
        integer = std.math.minInt(T);
        raise(c, Fpscr.vxsnan);
    } else if (rounded <= min) {
        integer = std.math.minInt(T);
    } else if (rounded >= max) {
        integer = std.math.maxInt(T);
    } else {
        integer = @intFromFloat(rounded);
    }

    // The result is a bit pattern in an FPR, not a number.
    const bits: u64 = if (T == i32)
        @as(u32, @bitCast(integer))
    else
        @bitCast(integer);
    writeFprBits(c, f.fd(), bits);
    recordCr1(c, insn);
    return .advance;
}

fn convertFromInteger(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const integer: i64 = @bitCast(fprBits(c, f.fb()));
    const value: f64 = @floatFromInt(integer);
    writeFpr(c, f.fd(), value);
    updateFprf(c, value);
    recordCr1(c, insn);
    return .advance;
}

fn roundHalfToEven(value: f64) f64 {
    const nearest = @round(value);
    if (@abs(value - @trunc(value)) != 0.5) return nearest;
    // @round breaks ties away from zero; IEEE round-to-nearest breaks them to
    // even, and the two differ on exactly the .5 cases a guest hits constantly
    // when quantising coordinates.
    return if (@mod(nearest, 2.0) == 0.0) nearest else nearest - std.math.sign(value);
}

fn compare(c: *Context, insn: Instruction, comptime ordered: bool) Outcome {
    const f = insn.x();
    const a = readFpr(c, f.fa());
    const b = readFpr(c, f.fb());
    const unordered = std.math.isNan(a) or std.math.isNan(b);
    const value: u4 = if (unordered)
        0b0001
    else if (a < b)
        0b1000
    else if (a > b)
        0b0100
    else
        0b0010;
    c.state.setCrField(f.crfd(), value);
    // FPCC mirrors the CR field the compare just wrote.
    c.state.fpscr = (c.state.fpscr & ~Fpscr.fpcc_mask) |
        (@as(u32, value) << Fpscr.fpcc_shift);
    if (unordered) {
        raise(c, Fpscr.vxsnan);
        if (ordered) raise(c, Fpscr.vxvc);
    }
    return .advance;
}

/// FPRF: the result class bits the guest reads back through mffs.
fn updateFprf(c: *Context, value: f64) void {
    const class: u4 = if (std.math.isNan(value))
        0b0001
    else if (value < 0.0)
        0b1000
    else if (value > 0.0)
        0b0100
    else
        0b0010;
    c.state.fpscr = (c.state.fpscr & ~Fpscr.fpcc_mask) |
        (@as(u32, class) << Fpscr.fpcc_shift);
}

// ---------------------------------------------------------------------------
// FPSCR access
// ---------------------------------------------------------------------------

fn moveFromFpscr(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    // FPSCR lands in the low word of the FPR's bit pattern, with the high word
    // architecturally undefined; Rosette writes ones there, matching hardware.
    writeFprBits(c, f.fd(), 0xFFFF_FFFF_0000_0000 | @as(u64, c.state.fpscr));
    recordCr1(c, insn);
    return .advance;
}

fn moveToFpscrFields(c: *Context, insn: Instruction) Outcome {
    const f = insn.xfl();
    const source: u32 = @truncate(fprBits(c, f.fb()));
    var mask: u32 = 0;
    var field: u3 = 0;
    while (true) : (field += 1) {
        if (f.fm() & (@as(u8, 0x80) >> field) != 0) {
            mask |= @as(u32, 0xF) << @intCast((7 - @as(u5, field)) * 4);
        }
        if (field == 7) break;
    }
    c.state.fpscr = (c.state.fpscr & ~mask) | (source & mask);
    recordCr1(c, insn);
    return .advance;
}

fn setFpscrBit(c: *Context, insn: Instruction, comptime value: u1) Outcome {
    const f = insn.x();
    const mask = @as(u32, 1) << (31 - @as(u5, f.rt()));
    c.state.fpscr = if (value != 0) c.state.fpscr | mask else c.state.fpscr & ~mask;
    recordCr1(c, insn);
    return .advance;
}

fn moveToFpscrField(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const shift: u5 = @intCast((7 - @as(u5, f.crfd())) * 4);
    const mask = @as(u32, 0xF) << shift;
    const imm: u32 = (f.rb() >> 1) & 0xF;
    c.state.fpscr = (c.state.fpscr & ~mask) | (imm << shift);
    recordCr1(c, insn);
    return .advance;
}

fn moveFpscrToCr(c: *Context, insn: Instruction) Outcome {
    const f = insn.x();
    const shift: u5 = @intCast((7 - @as(u5, f.crfs())) * 4);
    const field: u4 = @truncate(c.state.fpscr >> shift);
    c.state.setCrField(f.crfd(), field);
    // Reading a field through mcrfs clears the exception bits it copied out;
    // leaving them set is how a guest's error handler fires forever.
    c.state.fpscr &= ~(@as(u32, 0xF) << shift);
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

fn aWord(primary: u32, fd: u32, fa: u32, fb: u32, fc: u32, xo: u32, rc: u32) u32 {
    return (primary << 26) | (fd << 21) | (fa << 16) | (fb << 11) |
        (fc << 6) | (xo << 1) | rc;
}

fn xWord(primary: u32, fd: u32, fa: u32, fb: u32, xo: u32, rc: u32) u32 {
    return (primary << 26) | (fd << 21) | (fa << 16) | (fb << 11) | (xo << 1) | rc;
}

test "fadds rounds the double result to single, it does not compute in float" {
    var h = Harness{};
    // 1 + 2^-30: exact in double, not representable in single.
    h.state.fpr[1] = 1.0;
    h.state.fpr[2] = std.math.pow(f64, 2.0, -30.0);
    _ = try h.run(aWord(63, 3, 1, 2, 0, 21, 0)); // fadd f3, f1, f2
    try testing.expect(h.state.fpr[3] != 1.0);
    _ = try h.run(aWord(59, 3, 1, 2, 0, 21, 0)); // fadds f3, f1, f2
    try testing.expectEqual(@as(f64, 1.0), h.state.fpr[3]);
}

test "fmul takes its second operand from FC, not FB" {
    var h = Harness{};
    h.state.fpr[1] = 3.0;
    h.state.fpr[2] = 100.0; // FB, must be ignored
    h.state.fpr[4] = 5.0; // FC
    _ = try h.run(aWord(63, 3, 1, 2, 4, 25, 0)); // fmul f3, f1, f4
    try testing.expectEqual(@as(f64, 15.0), h.state.fpr[3]);
}

test "fmadd rounds once, not twice" {
    var h = Harness{};
    // (1 + 2^-28)^2 is 1 + 2^-27 + 2^-56. Rounding the product first drops the
    // 2^-56 term below the ulp of 1; the fused form keeps it, and subtracting
    // 1 then exposes it. The two answers differ by exactly that lost term.
    const x = 1.0 + std.math.pow(f64, 2.0, -28.0);
    h.state.fpr[1] = x;
    h.state.fpr[4] = x;
    h.state.fpr[2] = -1.0;
    _ = try h.run(aWord(63, 3, 1, 2, 4, 29, 0)); // fmadd f3, f1, f4, f2
    const fused = h.state.fpr[3];
    const rounded_product: f64 = x * x;
    const separate = rounded_product - 1.0;
    try testing.expect(fused != separate);
    try testing.expectEqual(std.math.pow(f64, 2.0, -27.0), separate);
    try testing.expectEqual(
        std.math.pow(f64, 2.0, -27.0) + std.math.pow(f64, 2.0, -56.0),
        fused,
    );
}

test "fneg flips the sign bit rather than subtracting" {
    var h = Harness{};
    h.state.fpr[2] = std.math.nan(f64);
    _ = try h.run(xWord(63, 3, 0, 2, 40, 0)); // fneg f3, f2
    try testing.expect(std.math.isNan(h.state.fpr[3]));
    try testing.expect(@as(u64, @bitCast(h.state.fpr[3])) >> 63 == 1);

    h.state.fpr[2] = -0.0;
    _ = try h.run(xWord(63, 3, 0, 2, 264, 0)); // fabs f3, f2
    try testing.expectEqual(@as(u64, 0), @as(u64, @bitCast(h.state.fpr[3])));
}

test "fsel picks the false arm for a NaN selector" {
    var h = Harness{};
    h.state.fpr[2] = 111.0; // FB, the negative arm
    h.state.fpr[4] = 222.0; // FC, the non-negative arm
    h.state.fpr[1] = 0.0;
    _ = try h.run(aWord(63, 3, 1, 2, 4, 23, 0));
    try testing.expectEqual(@as(f64, 222.0), h.state.fpr[3]);
    h.state.fpr[1] = -1.0;
    _ = try h.run(aWord(63, 3, 1, 2, 4, 23, 0));
    try testing.expectEqual(@as(f64, 111.0), h.state.fpr[3]);
    h.state.fpr[1] = std.math.nan(f64);
    _ = try h.run(aWord(63, 3, 1, 2, 4, 23, 0));
    try testing.expectEqual(@as(f64, 111.0), h.state.fpr[3]);
}

test "fctiwz stores an integer bit pattern, not a rounded number" {
    var h = Harness{};
    h.state.fpr[2] = -3.75;
    _ = try h.run(xWord(63, 3, 0, 2, 15, 0)); // fctiwz f3, f2
    const bits: u64 = @bitCast(h.state.fpr[3]);
    try testing.expectEqual(@as(u32, @bitCast(@as(i32, -3))), @as(u32, @truncate(bits)));
    // Reading the destination as a double would give a denormal, not -3.
    try testing.expect(h.state.fpr[3] != -3.0);
}

test "fctiw saturates instead of wrapping when the value will not fit" {
    var h = Harness{};
    h.state.fpr[2] = 4.0e9; // above INT32_MAX
    _ = try h.run(xWord(63, 3, 0, 2, 15, 0));
    const bits: u32 = @truncate(@as(u64, @bitCast(h.state.fpr[3])));
    try testing.expectEqual(@as(u32, @bitCast(@as(i32, std.math.maxInt(i32)))), bits);
}

test "fcfid reads its source as an integer pattern" {
    var h = Harness{};
    h.state.fpr[2] = @bitCast(@as(u64, @bitCast(@as(i64, -42))));
    _ = try h.run(xWord(63, 3, 0, 2, 846, 0)); // fcfid f3, f2
    try testing.expectEqual(@as(f64, -42.0), h.state.fpr[3]);
}

test "fcmpu reports unordered and mirrors the result into FPCC" {
    var h = Harness{};
    h.state.fpr[1] = 1.0;
    h.state.fpr[2] = 2.0;
    _ = try h.run(xWord(63, 0, 1, 2, 0, 0)); // fcmpu cr0, f1, f2
    try testing.expectEqual(@as(u4, 0b1000), h.state.crField(0)); // LT
    try testing.expectEqual(
        @as(u32, 0b1000),
        (h.state.fpscr & Fpscr.fpcc_mask) >> Fpscr.fpcc_shift,
    );

    h.state.fpr[2] = std.math.nan(f64);
    _ = try h.run(xWord(63, 0, 1, 2, 0, 0));
    try testing.expectEqual(@as(u4, 0b0001), h.state.crField(0)); // unordered
    try testing.expect(h.state.fpscr & Fpscr.vx != 0);
}

test "a single-precision load widens and a single-precision store narrows" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.fpr[3] = 0.5;
    _ = try h.run((52 << 26) | (3 << 21) | (4 << 16) | 0); // stfs f3, 0(r4)
    try testing.expectEqual(@as(u8, 0x3F), h.buf[0]); // big-endian 0x3F000000
    _ = try h.run((48 << 26) | (5 << 21) | (4 << 16) | 0); // lfs f5, 0(r4)
    try testing.expectEqual(@as(f64, 0.5), h.state.fpr[5]);
}

test "stfiwx spills the low word of the bit pattern" {
    var h = Harness{};
    h.state.gpr[4] = base_address;
    h.state.gpr[5] = 0;
    h.state.fpr[3] = @bitCast(@as(u64, 0x1122334455667788));
    _ = try h.run((31 << 26) | (3 << 21) | (4 << 16) | (5 << 11) | (983 << 1));
    try testing.expectEqual(@as(u8, 0x55), h.buf[0]);
    try testing.expectEqual(@as(u8, 0x88), h.buf[3]);
}

test "mcrfs clears the exception bits it copies out" {
    var h = Harness{};
    h.state.fpscr = Fpscr.fx | Fpscr.vx;
    _ = try h.run(xWord(63, 0, 0, 0, 64, 0)); // mcrfs cr0, fpscr0
    try testing.expectEqual(@as(u4, 0b1010), h.state.crField(0));
    try testing.expectEqual(@as(u32, 0), h.state.fpscr & 0xF000_0000);
}

test "Rc on a float instruction copies FPSCR's top nibble into CR1" {
    var h = Harness{};
    h.state.fpscr = 0xA000_0000;
    h.state.fpr[1] = 1.0;
    h.state.fpr[2] = 1.0;
    _ = try h.run(aWord(63, 3, 1, 2, 0, 21, 1)); // fadd. f3, f1, f2
    try testing.expectEqual(@as(u4, 0b1010), h.state.crField(1));
}
