//! Shader IR to SPIR-V.
//!
//! The Vulkan-side counterpart to `ssa_to_msl.zig`, emitting a SPIR-V module
//! from the same IR. Both backends read the IR and neither re-decides what an
//! operation means — that is the reason the IR exists.
//!
//! ## SPIR-V is a word stream with a header that must be right
//!
//! Unlike MSL, a malformed SPIR-V module is rejected by the driver with a
//! message about a word offset, which is a long way from the instruction that
//! produced it. The two things that go wrong first are the magic number and
//! the instruction word counts: a word count that disagrees with the actual
//! instruction length desynchronises the whole stream, so every instruction
//! after the mistake is garbage and the driver reports a problem at the end.
//!
//! So the emitter computes word counts from what it wrote rather than from
//! what it intended to write, and the tests check the stream is self-consistent
//! rather than checking individual opcodes.

const std = @import("std");
const ssa = @import("microcode_to_ssa.zig");

pub const Error = error{ OutputTooSmall, UnsupportedOp };

/// The SPIR-V magic number. A module not starting with this is rejected before
/// anything else is read.
pub const magic: u32 = 0x0723_0203;
pub const version_1_0: u32 = 0x0001_0000;
/// Generator magic. Zero is "unknown tool", which is legal.
pub const generator: u32 = 0;

/// The opcodes this backend emits.
pub const OpCode = enum(u16) {
    nop = 0,
    name = 5,
    type_float = 22,
    type_vector = 23,
    constant = 43,
    function = 54,
    function_end = 56,
    f_add = 129,
    f_mul = 133,
    f_negate = 127,
    dot = 148,
    ext_inst = 12,
};

pub const Module = struct {
    words: []u32,
    length: usize = 0,

    pub fn init(words: []u32) Module {
        return .{ .words = words };
    }

    /// The five-word module header.
    pub fn emitHeader(self: *Module, bound: u32) Error!void {
        try self.pushChecked(magic);
        try self.pushChecked(version_1_0);
        try self.pushChecked(generator);
        // The id bound is exclusive: every id used must be strictly less than
        // it. Emitting the highest id instead of one past it makes the driver
        // reject the last value in the module.
        try self.pushChecked(bound);
        try self.pushChecked(0);
    }

    fn pushChecked(self: *Module, word: u32) Error!void {
        if (self.length == self.words.len) return error.OutputTooSmall;
        self.words[self.length] = word;
        self.length += 1;
    }

    /// Emit one instruction, computing its word count from the operands given.
    ///
    /// The count is derived, never passed in. A hand-written count that
    /// disagrees with the operand list desynchronises the rest of the stream,
    /// and the driver reports the failure at the end of the module.
    pub fn emitInstruction(self: *Module, opcode: OpCode, operands: []const u32) Error!void {
        const word_count: u32 = @intCast(operands.len + 1);
        if (self.length + word_count > self.words.len) return error.OutputTooSmall;
        const first = (word_count << 16) | @intFromEnum(opcode);
        try self.pushChecked(first);
        for (operands) |operand| try self.pushChecked(operand);
    }

    pub fn slice(self: *const Module) []const u32 {
        return self.words[0..self.length];
    }
};

/// Decode an instruction's word count and opcode from its first word.
pub fn decodeInstructionWord(word: u32) struct { word_count: u16, opcode: u16 } {
    return .{
        .word_count = @intCast(word >> 16),
        .opcode = @truncate(word),
    };
}

/// Walk a module body and confirm every instruction's word count is consistent.
///
/// The check that catches a desynchronised stream at the point it happens,
/// rather than as a driver message about a word offset.
pub fn bodyIsSelfConsistent(words: []const u32) bool {
    var index: usize = 0;
    while (index < words.len) {
        const decoded = decodeInstructionWord(words[index]);
        if (decoded.word_count == 0) return false;
        if (index + decoded.word_count > words.len) return false;
        index += decoded.word_count;
    }
    return index == words.len;
}

/// The SPIR-V opcode for an IR operation.
pub fn opcodeFor(op: ssa.Op) Error!OpCode {
    return switch (op) {
        .add => .f_add,
        .mul => .f_mul,
        .dot3, .dot4 => .dot,
        .mov => .nop,
        else => error.UnsupportedOp,
    };
}

test "the header is five words and starts with the magic number" {
    // A module not starting with the magic is rejected before anything else
    // is read, so this is the first thing to get right.
    var storage: [16]u32 = undefined;
    var module = Module.init(&storage);
    try module.emitHeader(10);
    try std.testing.expectEqual(@as(usize, 5), module.length);
    try std.testing.expectEqual(magic, module.words[0]);
    try std.testing.expectEqual(version_1_0, module.words[1]);
    try std.testing.expectEqual(@as(u32, 10), module.words[3]);
    try std.testing.expectEqual(@as(u32, 0), module.words[4]);
}

test "the id bound is exclusive" {
    // Emitting the highest id rather than one past it makes the driver reject
    // the last value in the module.
    var storage: [16]u32 = undefined;
    var module = Module.init(&storage);
    const highest_id: u32 = 7;
    try module.emitHeader(highest_id + 1);
    try std.testing.expectEqual(@as(u32, 8), module.words[3]);
    try std.testing.expect(module.words[3] > highest_id);
}

test "an instruction's word count is derived from its operands" {
    var storage: [16]u32 = undefined;
    var module = Module.init(&storage);
    try module.emitInstruction(.f_add, &[_]u32{ 1, 2, 3, 4 });
    const decoded = decodeInstructionWord(module.words[0]);
    // Four operands plus the instruction word itself.
    try std.testing.expectEqual(@as(u16, 5), decoded.word_count);
    try std.testing.expectEqual(@intFromEnum(OpCode.f_add), decoded.opcode);
    try std.testing.expectEqual(@as(usize, 5), module.length);
}

test "an instruction with no operands is one word" {
    var storage: [4]u32 = undefined;
    var module = Module.init(&storage);
    try module.emitInstruction(.function_end, &[_]u32{});
    try std.testing.expectEqual(@as(u16, 1), decodeInstructionWord(module.words[0]).word_count);
}

test "a body of emitted instructions is self consistent" {
    // The property that catches a desynchronised stream at its cause rather
    // than as a driver message about a word offset.
    var storage: [32]u32 = undefined;
    var module = Module.init(&storage);
    try module.emitInstruction(.type_float, &[_]u32{ 1, 32 });
    try module.emitInstruction(.type_vector, &[_]u32{ 2, 1, 4 });
    try module.emitInstruction(.f_add, &[_]u32{ 2, 3, 4, 5 });
    try module.emitInstruction(.function_end, &[_]u32{});
    try std.testing.expect(bodyIsSelfConsistent(module.slice()));
}

test "a wrong word count is detected" {
    // Hand-built: a word claiming three words but followed by only one.
    const broken = [_]u32{ (3 << 16) | 1, 0 };
    try std.testing.expect(!bodyIsSelfConsistent(&broken));

    // A zero word count would loop forever if it were not rejected.
    const zero = [_]u32{ 0, 0 };
    try std.testing.expect(!bodyIsSelfConsistent(&zero));
}

test "an empty body is trivially consistent" {
    try std.testing.expect(bodyIsSelfConsistent(&[_]u32{}));
}

test "an oversized emission is refused rather than truncated" {
    // A truncated module fails in the driver with a message about a word
    // offset, a long way from the instruction that caused it.
    var storage: [3]u32 = undefined;
    var module = Module.init(&storage);
    try std.testing.expectError(
        error.OutputTooSmall,
        module.emitInstruction(.f_add, &[_]u32{ 1, 2, 3, 4 }),
    );
    // Nothing was written, so the stream is still consistent.
    try std.testing.expectEqual(@as(usize, 0), module.length);
}

test "a header that does not fit is refused" {
    var storage: [3]u32 = undefined;
    var module = Module.init(&storage);
    try std.testing.expectError(error.OutputTooSmall, module.emitHeader(1));
}

test "IR operations map to SPIR-V opcodes" {
    try std.testing.expectEqual(OpCode.f_add, try opcodeFor(.add));
    try std.testing.expectEqual(OpCode.f_mul, try opcodeFor(.mul));
    try std.testing.expectEqual(OpCode.dot, try opcodeFor(.dot3));
    try std.testing.expectEqual(OpCode.dot, try opcodeFor(.dot4));
    // An operation with no direct opcode is refused rather than silently
    // becoming a nop, which would drop the computation.
    try std.testing.expectError(error.UnsupportedOp, opcodeFor(.rsq));
    try std.testing.expectError(error.UnsupportedOp, opcodeFor(.frac));
}

test "both backends agree on which operations are scalar" {
    // The reason for a shared IR: dot3 and dot4 are scalar-result operations
    // in the IR, and both backends must treat them the same way.
    try std.testing.expect(ssa.Op.dot3.isScalarResult());
    try std.testing.expect(ssa.Op.dot4.isScalarResult());
    try std.testing.expectEqual(OpCode.dot, try opcodeFor(.dot3));
}
