//! Microcode to a small SSA shader IR.
//!
//! One IR with two backends is the point. Emitting MSL and SPIR-V directly from
//! microcode means every semantic decision — how a saturate is applied, what a
//! predicated write means, which swizzle a source carries — is made twice, and
//! the two answers drift. When they drift, a title renders correctly on one
//! backend and not the other, and the difference is attributed to the host
//! driver rather than to the translator.
//!
//! The IR is deliberately small: vector ALU operations over virtual registers,
//! with modifiers preserved rather than folded. Folding a negate into a
//! constant, or a saturate into the operation, is where a translator starts
//! being clever and starts being wrong.

const std = @import("std");
const contract = @import("xenia_shader_contract");

pub const Error = error{
    TooManyValues,
    InvalidRegister,
    InvalidConstant,
    InvalidExport,
};

/// Component selector. Four of these make a swizzle.
pub const Component = enum(u2) { x = 0, y = 1, z = 2, w = 3 };

pub const identity_swizzle = [4]Component{ .x, .y, .z, .w };

/// Where a value comes from.
pub const SourceKind = enum { register, constant, interpolator, literal };

pub const Source = struct {
    kind: SourceKind,
    index: u32,
    swizzle: [4]Component = identity_swizzle,
    negate: bool = false,
    absolute: bool = false,

    /// Whether this source carries a modifier a backend must emit.
    ///
    /// The order matters and is stated here so both backends agree: absolute
    /// is applied first, then negate. `-|x|` and `|-x|` differ for every
    /// negative input, and a backend that picks the other order produces
    /// lighting that is wrong only where a value happened to be negative.
    pub fn hasModifier(self: Source) bool {
        return self.negate or self.absolute or !self.isIdentitySwizzle();
    }

    pub fn isIdentitySwizzle(self: Source) bool {
        return std.meta.eql(self.swizzle, identity_swizzle);
    }
};

pub const Op = enum {
    mov,
    add,
    mul,
    mad,
    dot3,
    dot4,
    min,
    max,
    rcp,
    rsq,
    frac,
    floor,
    exp2,
    log2,
    compare_ge,
    compare_gt,

    pub fn arity(self: Op) u8 {
        return switch (self) {
            .mov, .rcp, .rsq, .frac, .floor, .exp2, .log2 => 1,
            .add, .mul, .dot3, .dot4, .min, .max, .compare_ge, .compare_gt => 2,
            .mad => 3,
        };
    }

    /// Whether the result is a scalar broadcast across all components.
    ///
    /// A dot product writes one value to every component. A backend that
    /// treats it as a vector operation writes the per-component products
    /// instead, and the geometry lights as though every normal were unnormalised.
    pub fn isScalarResult(self: Op) bool {
        return switch (self) {
            .dot3, .dot4, .rcp, .rsq, .exp2, .log2 => true,
            else => false,
        };
    }
};

/// One SSA instruction.
pub const Instruction = struct {
    op: Op,
    sources: [3]Source = @splat(.{ .kind = .register, .index = 0 }),
    source_count: u8 = 2,
    /// The SSA value this defines.
    result: u32,
    /// Clamp the result to [0, 1].
    saturate: bool = false,
    /// Write only these components of the destination.
    write_mask: [4]bool = @splat(true),

    pub fn writesAnything(self: Instruction) bool {
        for (self.write_mask) |enabled| {
            if (enabled) return true;
        }
        return false;
    }
};

pub const ExportTarget = enum { position, interpolator, color, depth };

pub const Export = struct {
    target: ExportTarget,
    index: u32,
    value: u32,
};

pub const max_instructions: usize = 1024;
pub const max_exports: usize = 32;

/// A translated program.
pub const Program = struct {
    stage: contract.ShaderStage,
    instructions: [max_instructions]Instruction = undefined,
    instruction_count: usize = 0,
    exports: [max_exports]Export = undefined,
    export_count: usize = 0,
    /// Highest SSA value defined. Values are dense from zero.
    value_count: u32 = 0,

    pub fn append(self: *Program, instruction: Instruction) Error!void {
        if (self.instruction_count == max_instructions) return error.TooManyValues;
        try self.validate(instruction);
        self.instructions[self.instruction_count] = instruction;
        self.instruction_count += 1;
        self.value_count = @max(self.value_count, instruction.result + 1);
    }

    fn validate(self: *const Program, instruction: Instruction) Error!void {
        _ = self;
        var index: u8 = 0;
        while (index < instruction.source_count) : (index += 1) {
            const source = instruction.sources[index];
            switch (source.kind) {
                .register => if (!contract.isGprIndex(source.index)) return error.InvalidRegister,
                .constant => if (!contract.isFloatConstantIndex(source.index)) return error.InvalidConstant,
                .interpolator => if (!contract.isInterpolatorIndex(source.index)) return error.InvalidRegister,
                .literal => {},
            }
        }
        return;
    }

    pub fn addExport(self: *Program, entry: Export) Error!void {
        if (self.export_count == max_exports) return error.TooManyValues;
        switch (entry.target) {
            .color => if (!contract.isColorExportIndex(self.stage, entry.index)) {
                return error.InvalidExport;
            },
            .depth => if (!self.stage.canExportDepth()) return error.InvalidExport,
            .interpolator => if (!contract.isInterpolatorIndex(entry.index)) {
                return error.InvalidExport;
            },
            .position => {},
        }
        self.exports[self.export_count] = entry;
        self.export_count += 1;
    }

    pub fn instructionSlice(self: *const Program) []const Instruction {
        return self.instructions[0..self.instruction_count];
    }

    pub fn exportSlice(self: *const Program) []const Export {
        return self.exports[0..self.export_count];
    }
};

test "arity matches the operation" {
    try std.testing.expectEqual(@as(u8, 1), Op.mov.arity());
    try std.testing.expectEqual(@as(u8, 2), Op.add.arity());
    try std.testing.expectEqual(@as(u8, 3), Op.mad.arity());
    try std.testing.expectEqual(@as(u8, 2), Op.dot4.arity());
}

test "dot products are scalar results" {
    // A backend treating these as vector operations writes per-component
    // products, and the geometry lights as though normals were unnormalised.
    try std.testing.expect(Op.dot3.isScalarResult());
    try std.testing.expect(Op.dot4.isScalarResult());
    try std.testing.expect(Op.rcp.isScalarResult());
    try std.testing.expect(!Op.add.isScalarResult());
    try std.testing.expect(!Op.mul.isScalarResult());
    try std.testing.expect(!Op.mov.isScalarResult());
}

test "an unmodified source needs no emission work" {
    const plain = Source{ .kind = .register, .index = 0 };
    try std.testing.expect(!plain.hasModifier());
    try std.testing.expect(plain.isIdentitySwizzle());
}

test "modifiers are preserved rather than folded" {
    // Folding a negate into a constant is where a translator starts being
    // clever and starts being wrong.
    const negated = Source{ .kind = .register, .index = 0, .negate = true };
    try std.testing.expect(negated.hasModifier());

    const swizzled = Source{
        .kind = .register,
        .index = 0,
        .swizzle = .{ .w, .z, .y, .x },
    };
    try std.testing.expect(swizzled.hasModifier());
    try std.testing.expect(!swizzled.isIdentitySwizzle());
}

test "an instruction records the value it defines" {
    var program = Program{ .stage = .pixel };
    try program.append(.{ .op = .add, .result = 0, .source_count = 2 });
    try program.append(.{ .op = .mul, .result = 1, .source_count = 2 });
    try std.testing.expectEqual(@as(usize, 2), program.instruction_count);
    try std.testing.expectEqual(@as(u32, 2), program.value_count);
}

test "an out of range register is refused" {
    // Clamping would read a different register and the shader would draw with
    // the wrong values while reporting success.
    var program = Program{ .stage = .pixel };
    var instruction = Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .register, .index = contract.gpr_count };
    try std.testing.expectError(error.InvalidRegister, program.append(instruction));

    instruction.sources[0] = .{ .kind = .constant, .index = contract.float_constant_count };
    try std.testing.expectError(error.InvalidConstant, program.append(instruction));

    instruction.sources[0] = .{ .kind = .interpolator, .index = contract.interpolator_count };
    try std.testing.expectError(error.InvalidRegister, program.append(instruction));
}

test "a literal source has no index bound" {
    var program = Program{ .stage = .pixel };
    var instruction = Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .literal, .index = 0xFFFF_FFFF };
    try program.append(instruction);
}

test "only a pixel shader can export colour or depth" {
    var pixel = Program{ .stage = .pixel };
    try pixel.addExport(.{ .target = .color, .index = 0, .value = 0 });
    try pixel.addExport(.{ .target = .depth, .index = 0, .value = 0 });
    try std.testing.expectError(
        error.InvalidExport,
        pixel.addExport(.{ .target = .color, .index = 4, .value = 0 }),
    );

    var vertex = Program{ .stage = .vertex };
    try std.testing.expectError(
        error.InvalidExport,
        vertex.addExport(.{ .target = .color, .index = 0, .value = 0 }),
    );
    try std.testing.expectError(
        error.InvalidExport,
        vertex.addExport(.{ .target = .depth, .index = 0, .value = 0 }),
    );
    // A vertex shader exports position and interpolators.
    try vertex.addExport(.{ .target = .position, .index = 0, .value = 0 });
    try vertex.addExport(.{ .target = .interpolator, .index = 15, .value = 0 });
    try std.testing.expectError(
        error.InvalidExport,
        vertex.addExport(.{ .target = .interpolator, .index = 16, .value = 0 }),
    );
}

test "a fully masked instruction writes nothing" {
    // Worth detecting: a write mask of all-false is dead code the backend
    // should not emit, and emitting it can define an SSA value nothing wrote.
    const dead = Instruction{
        .op = .add,
        .result = 0,
        .write_mask = @splat(false),
    };
    try std.testing.expect(!dead.writesAnything());
    const live = Instruction{ .op = .add, .result = 0 };
    try std.testing.expect(live.writesAnything());
}

test "a program refuses to exceed its instruction bound" {
    var program = Program{ .stage = .pixel };
    var index: usize = 0;
    while (index < max_instructions) : (index += 1) {
        try program.append(.{ .op = .mov, .result = @intCast(index), .source_count = 1 });
    }
    try std.testing.expectError(error.TooManyValues, program.append(.{ .op = .mov, .result = 0 }));
}

test "slices expose only what was appended" {
    var program = Program{ .stage = .vertex };
    try program.append(.{ .op = .add, .result = 0 });
    try program.addExport(.{ .target = .position, .index = 0, .value = 0 });
    try std.testing.expectEqual(@as(usize, 1), program.instructionSlice().len);
    try std.testing.expectEqual(@as(usize, 1), program.exportSlice().len);
}
