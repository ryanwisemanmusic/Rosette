//! Software shader execution.
//!
//! Runs the IR directly, one invocation at a time. This is not a rendering
//! path — it is far too slow — it is a *reference*.
//!
//! ## Why an emulator needs a reference shader executor
//!
//! When a translated shader draws the wrong thing, there is no way to tell
//! whether the translation is wrong or the host driver compiled it differently,
//! because the only observable is the final image. Running the same IR here
//! gives a third answer that neither backend produced, and disagreement is then
//! attributable: if the interpreter and MSL agree and SPIR-V differs, the
//! SPIR-V backend is wrong; if both backends agree and the interpreter differs,
//! the interpreter or the IR is.
//!
//! That is worth more than its execution speed suggests, because "the image is
//! wrong" is otherwise an unattributable symptom.

const std = @import("std");
const ssa = @import("microcode_to_ssa.zig");
const contract = @import("xenia_shader_contract");

pub const Error = error{
    /// A source referencing a value the program has not defined.
    UndefinedValue,
    /// More values than the interpreter's register file holds.
    TooManyValues,
    UnsupportedOp,
};

pub const Vec4 = [4]f32;

pub const max_values: usize = ssa.max_instructions;

/// Execution state for one invocation.
pub const Invocation = struct {
    /// SSA values, defined as execution proceeds.
    values: [max_values]Vec4 = @splat(@splat(0)),
    defined: [max_values]bool = @splat(false),
    /// The guest's general purpose registers.
    registers: [contract.gpr_count]Vec4 = @splat(@splat(0)),
    /// Float constants.
    constants: [contract.float_constant_count]Vec4 = @splat(@splat(0)),
    interpolators: [contract.interpolator_count]Vec4 = @splat(@splat(0)),

    fn readSource(self: *const Invocation, source: ssa.Source) Error!Vec4 {
        const base: Vec4 = switch (source.kind) {
            .register => self.registers[source.index],
            .constant => self.constants[source.index],
            .interpolator => self.interpolators[source.index],
            .literal => blk: {
                if (source.index >= max_values) return error.UndefinedValue;
                // A literal source indexes an already-defined SSA value.
                if (!self.defined[source.index]) return error.UndefinedValue;
                break :blk self.values[source.index];
            },
        };

        // Swizzle, then absolute, then negate — the order the IR fixes and
        // both backends emit.
        var result: Vec4 = undefined;
        for (source.swizzle, 0..) |component, index| {
            result[index] = base[@intFromEnum(component)];
        }
        if (source.absolute) {
            for (&result) |*value| value.* = @abs(value.*);
        }
        if (source.negate) {
            for (&result) |*value| value.* = -value.*;
        }
        return result;
    }

    /// Execute one instruction.
    pub fn step(self: *Invocation, instruction: ssa.Instruction) Error!void {
        if (instruction.result >= max_values) return error.TooManyValues;
        if (!instruction.writesAnything()) return;

        const sources = instruction.sources[0..instruction.source_count];
        var operands: [3]Vec4 = @splat(@splat(0));
        for (sources, 0..) |source, index| {
            operands[index] = try self.readSource(source);
        }

        var computed: Vec4 = switch (instruction.op) {
            .mov => operands[0],
            .add => binary(operands[0], operands[1], add),
            .mul => binary(operands[0], operands[1], multiply),
            .min => binary(operands[0], operands[1], minimum),
            .max => binary(operands[0], operands[1], maximum),
            .mad => binary(binary(operands[0], operands[1], multiply), operands[2], add),
            .dot3 => @splat(operands[0][0] * operands[1][0] +
                operands[0][1] * operands[1][1] +
                operands[0][2] * operands[1][2]),
            .dot4 => @splat(operands[0][0] * operands[1][0] +
                operands[0][1] * operands[1][1] +
                operands[0][2] * operands[1][2] +
                operands[0][3] * operands[1][3]),
            .frac => unary(operands[0], fraction),
            .floor => unary(operands[0], floorOf),
            .rcp => @splat(reciprocal(operands[0][0])),
            .rsq => @splat(reciprocalSqrt(operands[0][0])),
            .exp2 => @splat(@exp2(operands[0][0])),
            .log2 => @splat(logTwo(operands[0][0])),
            .compare_ge => binary(operands[0], operands[1], greaterOrEqual),
            .compare_gt => binary(operands[0], operands[1], greaterThan),
        };

        if (instruction.saturate) {
            for (&computed) |*value| value.* = std.math.clamp(value.*, 0, 1);
        }

        // Only the masked components are written. A full write would clobber
        // components a later instruction expects to still hold their old value.
        var result = if (self.defined[instruction.result])
            self.values[instruction.result]
        else
            Vec4{ 0, 0, 0, 0 };
        for (instruction.write_mask, 0..) |enabled, index| {
            if (enabled) result[index] = computed[index];
        }
        self.values[instruction.result] = result;
        self.defined[instruction.result] = true;
    }

    /// Run a whole program.
    pub fn run(self: *Invocation, program: *const ssa.Program) Error!void {
        for (program.instructionSlice()) |instruction| {
            try self.step(instruction);
        }
    }

    pub fn valueOf(self: *const Invocation, index: u32) Error!Vec4 {
        if (index >= max_values or !self.defined[index]) return error.UndefinedValue;
        return self.values[index];
    }
};

fn binary(a: Vec4, b: Vec4, comptime f: fn (f32, f32) f32) Vec4 {
    var result: Vec4 = undefined;
    for (&result, 0..) |*value, index| value.* = f(a[index], b[index]);
    return result;
}

fn unary(a: Vec4, comptime f: fn (f32) f32) Vec4 {
    var result: Vec4 = undefined;
    for (&result, 0..) |*value, index| value.* = f(a[index]);
    return result;
}

fn add(a: f32, b: f32) f32 {
    return a + b;
}
fn multiply(a: f32, b: f32) f32 {
    return a * b;
}
fn minimum(a: f32, b: f32) f32 {
    return @min(a, b);
}
fn maximum(a: f32, b: f32) f32 {
    return @max(a, b);
}
fn greaterOrEqual(a: f32, b: f32) f32 {
    return if (a >= b) 1.0 else 0.0;
}
fn greaterThan(a: f32, b: f32) f32 {
    return if (a > b) 1.0 else 0.0;
}
fn fraction(a: f32) f32 {
    // x - floor(x), not truncation. frac(-1.25) is 0.75; truncation gives
    // -0.25 and tiles a texture backwards across the origin.
    return a - @floor(a);
}

fn floorOf(a: f32) f32 {
    return @floor(a);
}

/// The hardware clamps rather than producing an infinity.
///
/// A shader dividing by zero on real hardware gets a very large finite number,
/// not `inf`. Propagating `inf` makes every later operation `nan`, and the
/// pixel becomes transparent or black — a much louder artefact than the
/// hardware's own behaviour.
fn reciprocal(value: f32) f32 {
    if (value == 0) return std.math.floatMax(f32);
    const result = 1.0 / value;
    return if (std.math.isFinite(result)) result else std.math.floatMax(f32);
}

fn reciprocalSqrt(value: f32) f32 {
    if (value <= 0) return std.math.floatMax(f32);
    return 1.0 / @sqrt(value);
}

fn logTwo(value: f32) f32 {
    if (value <= 0) return -std.math.floatMax(f32);
    return @log2(value);
}

fn reg(index: u32) ssa.Source {
    return .{ .kind = .register, .index = index };
}

test "a move copies a register into a value" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 2, 3, 4 };
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = reg(0);
    try invocation.step(instruction);
    try std.testing.expectEqual(ssa.max_instructions, max_values);
    try std.testing.expectEqual(Vec4{ 1, 2, 3, 4 }, try invocation.valueOf(0));
}

test "arithmetic is component wise" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 2, 3, 4 };
    invocation.registers[1] = .{ 10, 20, 30, 40 };
    var instruction = ssa.Instruction{ .op = .add, .result = 0, .source_count = 2 };
    instruction.sources[0] = reg(0);
    instruction.sources[1] = reg(1);
    try invocation.step(instruction);
    try std.testing.expectEqual(Vec4{ 11, 22, 33, 44 }, try invocation.valueOf(0));
}

test "a dot product broadcasts its scalar to every component" {
    // A per-component result here would light geometry as though every normal
    // were unnormalised.
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 2, 3, 4 };
    invocation.registers[1] = .{ 1, 1, 1, 1 };
    var instruction = ssa.Instruction{ .op = .dot4, .result = 0, .source_count = 2 };
    instruction.sources[0] = reg(0);
    instruction.sources[1] = reg(1);
    try invocation.step(instruction);
    try std.testing.expectEqual(Vec4{ 10, 10, 10, 10 }, try invocation.valueOf(0));
}

test "dot3 ignores w" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 2, 3, 1000 };
    invocation.registers[1] = .{ 1, 1, 1, 1000 };
    var instruction = ssa.Instruction{ .op = .dot3, .result = 0, .source_count = 2 };
    instruction.sources[0] = reg(0);
    instruction.sources[1] = reg(1);
    try invocation.step(instruction);
    try std.testing.expectEqual(Vec4{ 6, 6, 6, 6 }, try invocation.valueOf(0));
}

test "modifiers apply as swizzle, then absolute, then negate" {
    // The order both backends emit. A different order gives a different answer
    // for every negative input.
    var invocation = Invocation{};
    invocation.registers[0] = .{ -1, 2, -3, 4 };
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .register, .index = 0, .absolute = true, .negate = true };
    try invocation.step(instruction);
    try std.testing.expectEqual(Vec4{ -1, -2, -3, -4 }, try invocation.valueOf(0));
}

test "a swizzle selects components before any modifier" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 2, 3, 4 };
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{
        .kind = .register,
        .index = 0,
        .swizzle = .{ .w, .z, .y, .x },
    };
    try invocation.step(instruction);
    try std.testing.expectEqual(Vec4{ 4, 3, 2, 1 }, try invocation.valueOf(0));
}

test "saturate clamps to the unit range" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ -1, 0.5, 2, 1 };
    var instruction = ssa.Instruction{
        .op = .mov,
        .result = 0,
        .source_count = 1,
        .saturate = true,
    };
    instruction.sources[0] = reg(0);
    try invocation.step(instruction);
    try std.testing.expectEqual(Vec4{ 0, 0.5, 1, 1 }, try invocation.valueOf(0));
}

test "a write mask preserves the components it does not write" {
    // Writing all four would clobber components a later instruction expects
    // to still hold their previous value.
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 1, 1, 1 };
    invocation.registers[1] = .{ 9, 9, 9, 9 };

    var first = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    first.sources[0] = reg(0);
    try invocation.step(first);

    var second = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    second.sources[0] = reg(1);
    second.write_mask = .{ true, false, true, false };
    try invocation.step(second);

    try std.testing.expectEqual(Vec4{ 9, 1, 9, 1 }, try invocation.valueOf(0));
}

test "a division by zero clamps rather than producing infinity" {
    // Real hardware returns a very large finite number. An inf propagates to
    // nan and the pixel goes black or transparent — much louder than the
    // hardware's behaviour, and misleading about the cause.
    var invocation = Invocation{};
    invocation.registers[0] = .{ 0, 0, 0, 0 };
    var instruction = ssa.Instruction{ .op = .rcp, .result = 0, .source_count = 1 };
    instruction.sources[0] = reg(0);
    try invocation.step(instruction);
    const result = try invocation.valueOf(0);
    try std.testing.expect(std.math.isFinite(result[0]));
    try std.testing.expectEqual(std.math.floatMax(f32), result[0]);
}

test "rsq of a non-positive value clamps" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ -4, 0, 0, 0 };
    var instruction = ssa.Instruction{ .op = .rsq, .result = 0, .source_count = 1 };
    instruction.sources[0] = reg(0);
    try invocation.step(instruction);
    try std.testing.expect(std.math.isFinite((try invocation.valueOf(0))[0]));
}

test "log2 of zero clamps rather than producing negative infinity" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 0, 0, 0, 0 };
    var instruction = ssa.Instruction{ .op = .log2, .result = 0, .source_count = 1 };
    instruction.sources[0] = reg(0);
    try invocation.step(instruction);
    try std.testing.expect(std.math.isFinite((try invocation.valueOf(0))[0]));
}

test "reading an undefined value is refused rather than reading zero" {
    // Returning zero would make an ordering bug in the translator look like a
    // shader that legitimately multiplied by zero.
    var invocation = Invocation{};
    try std.testing.expectError(error.UndefinedValue, invocation.valueOf(0));

    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .literal, .index = 5 };
    try std.testing.expectError(error.UndefinedValue, invocation.step(instruction));
}

test "a dead instruction leaves its destination undefined" {
    var invocation = Invocation{};
    const dead = ssa.Instruction{
        .op = .add,
        .result = 0,
        .write_mask = @splat(false),
    };
    try invocation.step(dead);
    try std.testing.expectError(error.UndefinedValue, invocation.valueOf(0));
}

test "a whole program runs in order" {
    var program = ssa.Program{ .stage = .pixel };
    var first = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    first.sources[0] = reg(0);
    try program.append(first);
    var second = ssa.Instruction{ .op = .add, .result = 1, .source_count = 2 };
    second.sources[0] = reg(0);
    second.sources[1] = reg(1);
    try program.append(second);

    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 1, 1, 1 };
    invocation.registers[1] = .{ 2, 2, 2, 2 };
    try invocation.run(&program);
    try std.testing.expectEqual(Vec4{ 1, 1, 1, 1 }, try invocation.valueOf(0));
    try std.testing.expectEqual(Vec4{ 3, 3, 3, 3 }, try invocation.valueOf(1));
}

test "comparisons produce one or zero, not a boolean" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1, 2, 3, 4 };
    invocation.registers[1] = .{ 4, 3, 2, 1 };
    var instruction = ssa.Instruction{ .op = .compare_gt, .result = 0, .source_count = 2 };
    instruction.sources[0] = reg(0);
    instruction.sources[1] = reg(1);
    try invocation.step(instruction);
    try std.testing.expectEqual(Vec4{ 0, 0, 1, 1 }, try invocation.valueOf(0));
}

test "mad multiplies before it adds" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 2, 2, 2, 2 };
    invocation.registers[1] = .{ 3, 3, 3, 3 };
    invocation.registers[2] = .{ 1, 1, 1, 1 };
    var instruction = ssa.Instruction{ .op = .mad, .result = 0, .source_count = 3 };
    instruction.sources[0] = reg(0);
    instruction.sources[1] = reg(1);
    instruction.sources[2] = reg(2);
    try invocation.step(instruction);
    // 2*3 + 1, not 2*(3+1).
    try std.testing.expectEqual(Vec4{ 7, 7, 7, 7 }, try invocation.valueOf(0));
}

test "frac returns the fractional part of negatives correctly" {
    var invocation = Invocation{};
    invocation.registers[0] = .{ 1.25, -1.25, 0, -0.5 };
    var instruction = ssa.Instruction{ .op = .frac, .result = 0, .source_count = 1 };
    instruction.sources[0] = reg(0);
    try invocation.step(instruction);
    const result = try invocation.valueOf(0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), result[0], 0.0001);
    // frac(-1.25) is 0.75, not -0.25: it is x - floor(x), and floor(-1.25) is
    // -2. Truncation instead of floor gives the wrong sign and tiles a
    // texture backwards.
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), result[1], 0.0001);
}
