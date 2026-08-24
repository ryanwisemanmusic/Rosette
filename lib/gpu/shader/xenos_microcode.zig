//! Xenos shader microcode format parsing.
//!
//! A Xenos shader is a clause program: control-flow instructions select blocks
//! of ALU or fetch instructions. This file reads that structure — it does not
//! decode individual ALU operations, which `lib/gpu/xenos_shader.zig` already
//! does for the compact form Rosette's bridge uses.
//!
//! ## Structure first, semantics second
//!
//! The reason to parse structure separately is that structural errors are
//! detectable and semantic ones mostly are not. A control-flow instruction
//! pointing past the end of the blob, a clause that never terminates, a nesting
//! depth beyond the hardware's stack — all of these are checkable against
//! `pkg/common/xenia/shader-contract` and all of them mean the blob is not what
//! Rosette thinks it is. Whereas a wrongly decoded ALU op produces a shader
//! that compiles and draws the wrong thing.
//!
//! So a translator should establish structure before trusting any instruction,
//! and this file is where that check lives.

const std = @import("std");
const contract = @import("xenia_shader_contract");

pub const Error = error{
    /// The blob is not a whole number of dwords, or is outside the size bound.
    MalformedLength,
    /// A control-flow instruction addresses outside the blob.
    OutOfRange,
    /// A clause opens and never closes.
    UnterminatedClause,
    /// Nesting beyond the hardware's control-flow stack.
    NestingTooDeep,
    /// The program has no terminating instruction.
    NoTerminator,
};

/// One control-flow instruction, decoded structurally.
pub const ControlFlow = struct {
    kind: contract.ControlFlowKind,
    /// Address of the instruction block this selects, in dwords.
    address: u32 = 0,
    /// Instructions in that block.
    count: u32 = 0,
};

/// The structural shape of a program.
pub const Structure = struct {
    dword_count: usize,
    control_flow_count: u32,
    max_nesting: u32,
    has_terminator: bool,

    pub fn isWellFormed(self: Structure) bool {
        return self.has_terminator and self.max_nesting <= contract.max_control_flow_nesting;
    }
};

/// Check a blob's length against the contract before anything reads it.
pub fn validateLength(bytes: usize) Error!usize {
    if (!contract.isPlausibleMicrocodeLength(bytes)) return error.MalformedLength;
    return bytes / contract.microcode_dword_bytes;
}

/// Walk a control-flow list and report its structure.
///
/// Takes the already-decoded control-flow instructions rather than raw bits:
/// the bit layout differs between shader revisions, and the structural rules
/// do not. Keeping them apart means the rules are testable without a blob.
pub fn analyze(flow: []const ControlFlow, dword_count: usize) Error!Structure {
    var nesting: u32 = 0;
    var max_nesting: u32 = 0;
    var has_terminator = false;

    for (flow) |instruction| {
        if (instruction.kind == .nop) continue;

        // An address past the end means the blob is not what we think it is.
        if (instruction.count > 0) {
            const end = @as(u64, instruction.address) + instruction.count;
            if (end > dword_count) return error.OutOfRange;
        }

        if (instruction.kind.opensBlock()) {
            nesting += 1;
            if (nesting > contract.max_control_flow_nesting) return error.NestingTooDeep;
            max_nesting = @max(max_nesting, nesting);
        }
        if (instruction.kind == .loop_end or instruction.kind == .ret) {
            if (nesting == 0) return error.UnterminatedClause;
            nesting -= 1;
        }
        if (instruction.kind.isTerminal()) has_terminator = true;
    }

    if (nesting != 0) return error.UnterminatedClause;
    if (!has_terminator) return error.NoTerminator;

    return .{
        .dword_count = dword_count,
        .control_flow_count = @intCast(flow.len),
        .max_nesting = max_nesting,
        .has_terminator = has_terminator,
    };
}

/// Whether every constant index a program uses is inside its bank.
///
/// Reported rather than clamped. Clamping an out-of-range constant index reads
/// a different constant, so the shader runs and draws with the wrong values —
/// which is the failure mode this whole file exists to avoid.
pub fn constantIndicesInRange(indices: []const u32) bool {
    for (indices) |index| {
        if (!contract.isFloatConstantIndex(index)) return false;
    }
    return true;
}

test "a blob length must be dword aligned and bounded" {
    try std.testing.expectEqual(@as(usize, 1), try validateLength(4));
    try std.testing.expectEqual(@as(usize, 16), try validateLength(64));
    try std.testing.expectError(error.MalformedLength, validateLength(0));
    try std.testing.expectError(error.MalformedLength, validateLength(3));
    try std.testing.expectError(error.MalformedLength, validateLength(contract.max_shader_bytes + 4));
}

test "a minimal program is one terminating exec" {
    const flow = [_]ControlFlow{
        .{ .kind = .exec_end, .address = 0, .count = 4 },
    };
    const structure = try analyze(&flow, 16);
    try std.testing.expect(structure.isWellFormed());
    try std.testing.expectEqual(@as(u32, 0), structure.max_nesting);
    try std.testing.expectEqual(@as(u32, 1), structure.control_flow_count);
}

test "a program with no terminator is refused" {
    // Without a terminator the hardware runs off the end of the clause list.
    const flow = [_]ControlFlow{
        .{ .kind = .exec, .address = 0, .count = 4 },
    };
    try std.testing.expectError(error.NoTerminator, analyze(&flow, 16));
}

test "a clause addressing past the blob is refused" {
    // The check that catches a truncated fetch or a misidentified blob before
    // any instruction is trusted.
    const flow = [_]ControlFlow{
        .{ .kind = .exec_end, .address = 8, .count = 16 },
    };
    try std.testing.expectError(error.OutOfRange, analyze(&flow, 16));

    // Exactly reaching the end is fine.
    const exact = [_]ControlFlow{
        .{ .kind = .exec_end, .address = 8, .count = 8 },
    };
    _ = try analyze(&exact, 16);
}

test "an address near the top does not wrap into looking valid" {
    const flow = [_]ControlFlow{
        .{ .kind = .exec_end, .address = 0xFFFF_FFFF, .count = 2 },
    };
    try std.testing.expectError(error.OutOfRange, analyze(&flow, 16));
}

test "loops must close" {
    const unclosed = [_]ControlFlow{
        .{ .kind = .loop_start },
        .{ .kind = .exec_end, .address = 0, .count = 4 },
    };
    try std.testing.expectError(error.UnterminatedClause, analyze(&unclosed, 16));

    const closed = [_]ControlFlow{
        .{ .kind = .loop_start },
        .{ .kind = .exec, .address = 0, .count = 4 },
        .{ .kind = .loop_end },
        .{ .kind = .exec_end, .address = 4, .count = 4 },
    };
    const structure = try analyze(&closed, 16);
    try std.testing.expectEqual(@as(u32, 1), structure.max_nesting);
}

test "a close with nothing open is refused" {
    // Popping an empty stack is how a shader returns to an address that was
    // never pushed.
    const flow = [_]ControlFlow{
        .{ .kind = .loop_end },
        .{ .kind = .exec_end, .address = 0, .count = 4 },
    };
    try std.testing.expectError(error.UnterminatedClause, analyze(&flow, 16));
}

test "nesting is bounded by the hardware stack" {
    // Deeper than eight and the hardware overwrites its own stack, returning
    // to the wrong clause with nothing reporting a fault.
    var flow: [20]ControlFlow = undefined;
    var index: usize = 0;
    while (index < contract.max_control_flow_nesting + 1) : (index += 1) {
        flow[index] = .{ .kind = .loop_start };
    }
    try std.testing.expectError(error.NestingTooDeep, analyze(flow[0..index], 16));
}

test "nesting exactly at the limit is accepted" {
    var flow: [20]ControlFlow = undefined;
    var index: usize = 0;
    while (index < contract.max_control_flow_nesting) : (index += 1) {
        flow[index] = .{ .kind = .loop_start };
    }
    var closes: usize = 0;
    while (closes < contract.max_control_flow_nesting) : (closes += 1) {
        flow[index] = .{ .kind = .loop_end };
        index += 1;
    }
    flow[index] = .{ .kind = .exec_end, .address = 0, .count = 4 };
    index += 1;
    const structure = try analyze(flow[0..index], 16);
    try std.testing.expectEqual(contract.max_control_flow_nesting, structure.max_nesting);
}

test "nops are skipped rather than counted as structure" {
    const flow = [_]ControlFlow{
        .{ .kind = .nop },
        .{ .kind = .nop },
        .{ .kind = .exec_end, .address = 0, .count = 4 },
    };
    const structure = try analyze(&flow, 16);
    try std.testing.expect(structure.isWellFormed());
}

test "a call must return" {
    const flow = [_]ControlFlow{
        .{ .kind = .cond_call },
        .{ .kind = .ret },
        .{ .kind = .exec_end, .address = 0, .count = 4 },
    };
    const structure = try analyze(&flow, 16);
    try std.testing.expectEqual(@as(u32, 1), structure.max_nesting);
}

test "constant indices are reported, not clamped" {
    // Clamping reads a different constant, so the shader draws with the wrong
    // values and nothing reports a problem.
    try std.testing.expect(constantIndicesInRange(&[_]u32{ 0, 100, 511 }));
    try std.testing.expect(!constantIndicesInRange(&[_]u32{ 0, 512 }));
    try std.testing.expect(!constantIndicesInRange(&[_]u32{0xFFFF_FFFF}));
    try std.testing.expect(constantIndicesInRange(&[_]u32{}));
}
