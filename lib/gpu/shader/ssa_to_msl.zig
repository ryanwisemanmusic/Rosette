//! Shader IR to Metal Shading Language.
//!
//! Emits MSL source text from the IR in `microcode_to_ssa.zig`. The IR is the
//! single place semantics are decided; this file is a transcription and should
//! contain no judgement about what an operation means.
//!
//! ## Modifier order is transcribed, not re-decided
//!
//! Absolute then negate: `-abs(x)`. This is stated in the IR and repeated here
//! only as an emission order. A backend that emits `abs(-x)` differs from the
//! other backend for every negative input, and the result is lighting that is
//! wrong only in shadow — which is attributed to the host driver rather than to
//! the translator.

const std = @import("std");
const ssa = @import("microcode_to_ssa.zig");

pub const Error = error{ OutputTooSmall, UnsupportedOp };

const Writer = struct {
    buffer: []u8,
    length: usize = 0,

    fn write(self: *Writer, text: []const u8) Error!void {
        if (self.length + text.len > self.buffer.len) return error.OutputTooSmall;
        @memcpy(self.buffer[self.length..][0..text.len], text);
        self.length += text.len;
    }

    fn print(self: *Writer, comptime format: []const u8, args: anytype) Error!void {
        const remaining = self.buffer[self.length..];
        const written = std.fmt.bufPrint(remaining, format, args) catch return error.OutputTooSmall;
        self.length += written.len;
    }
};

fn componentChar(component: ssa.Component) u8 {
    return switch (component) {
        .x => 'x',
        .y => 'y',
        .z => 'z',
        .w => 'w',
    };
}

fn opName(op: ssa.Op) Error![]const u8 {
    return switch (op) {
        .mov => "",
        .add => "+",
        .mul => "*",
        .mad => "fma",
        .dot3 => "dot3",
        .dot4 => "dot",
        .min => "min",
        .max => "max",
        .rcp => "1.0f /",
        .rsq => "rsqrt",
        .frac => "fract",
        .floor => "floor",
        .exp2 => "exp2",
        .log2 => "log2",
        .compare_ge => ">=",
        .compare_gt => ">",
    };
}

fn emitSource(writer: *Writer, source: ssa.Source) Error!void {
    // Absolute first, then negate: -abs(x), never abs(-x).
    if (source.negate) try writer.write("-");
    if (source.absolute) try writer.write("abs(");

    switch (source.kind) {
        .register => try writer.print("r{d}", .{source.index}),
        .constant => try writer.print("c[{d}]", .{source.index}),
        .interpolator => try writer.print("in.i{d}", .{source.index}),
        .literal => try writer.print("l{d}", .{source.index}),
    }

    if (!source.isIdentitySwizzle()) {
        try writer.write(".");
        for (source.swizzle) |component| {
            try writer.print("{c}", .{componentChar(component)});
        }
    }
    if (source.absolute) try writer.write(")");
}

fn emitWriteMask(writer: *Writer, mask: [4]bool) Error!void {
    if (mask[0] and mask[1] and mask[2] and mask[3]) return;
    try writer.write(".");
    const names = [_]u8{ 'x', 'y', 'z', 'w' };
    for (mask, 0..) |enabled, index| {
        if (enabled) try writer.print("{c}", .{names[index]});
    }
}

/// Emit one instruction.
pub fn emitInstruction(buffer: []u8, instruction: ssa.Instruction) Error![]const u8 {
    var writer = Writer{ .buffer = buffer };

    // A fully masked instruction is dead. Emitting it would define an SSA
    // value nothing wrote, which the host compiler then reads as uninitialised.
    if (!instruction.writesAnything()) {
        try writer.write("// dead: write mask is empty\n");
        return writer.buffer[0..writer.length];
    }

    try writer.print("float4 v{d}", .{instruction.result});
    try emitWriteMask(&writer, instruction.write_mask);
    try writer.write(" = ");
    if (instruction.saturate) try writer.write("saturate(");

    const name = try opName(instruction.op);
    const sources = instruction.sources[0..instruction.source_count];

    switch (instruction.op) {
        .mov => try emitSource(&writer, sources[0]),
        .add, .mul, .compare_ge, .compare_gt => {
            try emitSource(&writer, sources[0]);
            try writer.print(" {s} ", .{name});
            try emitSource(&writer, sources[1]);
        },
        .rcp => {
            try writer.print("{s} ", .{name});
            try emitSource(&writer, sources[0]);
        },
        .dot3 => {
            // dot3 on a float4 must not include w. Emitting a plain dot()
            // folds the w component into every lighting term.
            try writer.write("dot(");
            try emitSource(&writer, sources[0]);
            try writer.write(".xyz, ");
            try emitSource(&writer, sources[1]);
            try writer.write(".xyz)");
        },
        else => {
            try writer.print("{s}(", .{name});
            for (sources, 0..) |source, index| {
                if (index > 0) try writer.write(", ");
                try emitSource(&writer, source);
            }
            try writer.write(")");
        },
    }

    if (instruction.saturate) try writer.write(")");
    try writer.write(";\n");
    return writer.buffer[0..writer.length];
}

/// Emit a whole program body.
pub fn emitProgram(buffer: []u8, program: *const ssa.Program) Error![]const u8 {
    var length: usize = 0;
    for (program.instructionSlice()) |instruction| {
        const emitted = try emitInstruction(buffer[length..], instruction);
        length += emitted.len;
    }
    return buffer[0..length];
}

test "a move emits a plain assignment" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .mov, .result = 3, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .register, .index = 7 };
    try std.testing.expectEqualStrings("float4 v3 = r7;\n", try emitInstruction(&buffer, instruction));
}

test "absolute is applied inside the negate" {
    // -abs(x), not abs(-x). The two differ for every negative input, and the
    // difference shows up only in shadow.
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .register, .index = 1, .negate = true, .absolute = true };
    try std.testing.expectEqualStrings("float4 v0 = -abs(r1);\n", try emitInstruction(&buffer, instruction));
}

test "a swizzle is emitted only when it is not the identity" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{
        .kind = .register,
        .index = 1,
        .swizzle = .{ .w, .z, .y, .x },
    };
    try std.testing.expectEqualStrings("float4 v0 = r1.wzyx;\n", try emitInstruction(&buffer, instruction));

    instruction.sources[0].swizzle = ssa.identity_swizzle;
    try std.testing.expectEqualStrings("float4 v0 = r1;\n", try emitInstruction(&buffer, instruction));
}

test "a binary operation is infix" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .add, .result = 2, .source_count = 2 };
    instruction.sources[0] = .{ .kind = .register, .index = 0 };
    instruction.sources[1] = .{ .kind = .constant, .index = 5 };
    try std.testing.expectEqualStrings("float4 v2 = r0 + c[5];\n", try emitInstruction(&buffer, instruction));
}

test "dot3 excludes w" {
    // A plain dot() on float4 folds w into every lighting term, which darkens
    // or brightens surfaces depending on what happened to be in w.
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .dot3, .result = 1, .source_count = 2 };
    instruction.sources[0] = .{ .kind = .register, .index = 0 };
    instruction.sources[1] = .{ .kind = .register, .index = 1 };
    try std.testing.expectEqualStrings(
        "float4 v1 = dot(r0.xyz, r1.xyz);\n",
        try emitInstruction(&buffer, instruction),
    );
}

test "dot4 uses every component" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .dot4, .result = 1, .source_count = 2 };
    instruction.sources[0] = .{ .kind = .register, .index = 0 };
    instruction.sources[1] = .{ .kind = .register, .index = 1 };
    try std.testing.expectEqualStrings(
        "float4 v1 = dot(r0, r1);\n",
        try emitInstruction(&buffer, instruction),
    );
}

test "a three source operation emits every source" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .mad, .result = 0, .source_count = 3 };
    instruction.sources[0] = .{ .kind = .register, .index = 0 };
    instruction.sources[1] = .{ .kind = .register, .index = 1 };
    instruction.sources[2] = .{ .kind = .register, .index = 2 };
    try std.testing.expectEqualStrings(
        "float4 v0 = fma(r0, r1, r2);\n",
        try emitInstruction(&buffer, instruction),
    );
}

test "saturate wraps the whole expression" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{
        .op = .add,
        .result = 0,
        .source_count = 2,
        .saturate = true,
    };
    instruction.sources[0] = .{ .kind = .register, .index = 0 };
    instruction.sources[1] = .{ .kind = .register, .index = 1 };
    try std.testing.expectEqualStrings(
        "float4 v0 = saturate(r0 + r1);\n",
        try emitInstruction(&buffer, instruction),
    );
}

test "a partial write mask is emitted" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.write_mask = .{ true, false, true, false };
    instruction.sources[0] = .{ .kind = .register, .index = 1 };
    try std.testing.expectEqualStrings("float4 v0.xz = r1;\n", try emitInstruction(&buffer, instruction));
}

test "a dead instruction becomes a comment, not a definition" {
    // Emitting it would define an SSA value nothing wrote, which the host
    // compiler reads as uninitialised.
    var buffer: [256]u8 = undefined;
    const instruction = ssa.Instruction{
        .op = .add,
        .result = 0,
        .write_mask = @splat(false),
    };
    try std.testing.expectEqualStrings(
        "// dead: write mask is empty\n",
        try emitInstruction(&buffer, instruction),
    );
}

test "an interpolator source reads from the stage input" {
    var buffer: [256]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .interpolator, .index = 2 };
    try std.testing.expectEqualStrings("float4 v0 = in.i2;\n", try emitInstruction(&buffer, instruction));
}

test "an undersized buffer is refused rather than truncated" {
    // Truncated MSL would be handed to the host compiler as a syntax error
    // far from its cause.
    var buffer: [4]u8 = undefined;
    var instruction = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    instruction.sources[0] = .{ .kind = .register, .index = 0 };
    try std.testing.expectError(error.OutputTooSmall, emitInstruction(&buffer, instruction));
}

test "a program emits every instruction in order" {
    var program = ssa.Program{ .stage = .pixel };
    var first = ssa.Instruction{ .op = .mov, .result = 0, .source_count = 1 };
    first.sources[0] = .{ .kind = .register, .index = 0 };
    try program.append(first);
    var second = ssa.Instruction{ .op = .add, .result = 1, .source_count = 2 };
    second.sources[0] = .{ .kind = .register, .index = 0 };
    second.sources[1] = .{ .kind = .register, .index = 1 };
    try program.append(second);

    var buffer: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "float4 v0 = r0;\nfloat4 v1 = r0 + r1;\n",
        try emitProgram(&buffer, &program),
    );
}
