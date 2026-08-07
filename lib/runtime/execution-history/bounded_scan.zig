//! How far a bounded reader may look, and the primitives for looking.
//!
//! Three scans in `memory_access.zig` each carried their own limits and their
//! own stop rules: the tail-shape walk used 16 instructions / 64 bytes, the
//! CALL_POSSIBLE_RETURN witness used a 32-byte backward window, and the
//! block reconstruction used 24 instructions / 64 bytes. Three different
//! answers to one question, in one file, with no statement of which was
//! intended. The risk is not that they disagree today; it is that tuning one
//! and not the others reproduces exactly the coupling this codebase keeps
//! hitting.
//!
//! These limits are what makes the recognizers *bounded* — the property the
//! whole design rests on. They belong in one place, named, with the reasoning
//! attached.

const std = @import("std");

pub const Limits = struct {
    /// Instructions decoded in any single chain.
    max_instructions: u8,
    /// Bytes the scan may span from its origin.
    max_bytes: u64,

    /// Forward from a fault to the tail transfer. A generated dispatch tail is
    /// a handful of instructions; anything longer is a different fragment and
    /// following it would join unrelated blocks.
    pub const tail_shape: Limits = .{ .max_instructions = 16, .max_bytes = 64 };

    /// Backward from a fault to the comparison that guards it. The predicate
    /// and its branch sit immediately before the load, so this window only has
    /// to cover a compare plus a near jcc.
    pub const predicate_witness: Limits = .{ .max_instructions = 8, .max_bytes = 32 };

    /// Backward from a known boundary to reconstruct a basic block. Longer than
    /// the others because the whole point is to see as much of the fragment as
    /// can be verified.
    pub const block_reconstruction: Limits = .{ .max_instructions = 24, .max_bytes = 64 };

    /// Forward into a callee's prologue to decide whether it dereferences its
    /// first argument.
    pub const callee_prologue: Limits = .{ .max_instructions = 12, .max_bytes = 48 };

    pub fn withinBytes(self: Limits, origin: u64, cursor: u64) bool {
        if (cursor < origin) return false;
        return cursor - origin <= self.max_bytes;
    }
};

/// A search range that is *found* rather than declared.
///
/// A fixed window is a guess about how far back the interesting thing lies, and
/// a guess that is too small reports "not found" for something that is simply
/// out of reach — indistinguishable, from outside, from "not there". Growing
/// the window until the answer stops changing turns the boundary into an
/// observation: the scan reports the window it actually needed, and whether it
/// converged or hit its ceiling.
///
/// The ceiling does not disappear — an unbounded search is not a bounded
/// recognizer — but it stops being a semantic boundary and becomes a reported
/// safety limit.
pub const Adaptive = struct {
    /// First window tried.
    initial_bytes: u64 = 32,
    /// Hard stop. Reaching it is reported, never silently accepted as a result.
    ceiling_bytes: u64 = 512,
    /// Instruction budget at the widest window.
    max_instructions: u8 = 64,

    pub fn limitsAt(self: Adaptive, bytes: u64) Limits {
        return .{ .max_instructions = self.max_instructions, .max_bytes = bytes };
    }

    /// Window sequence: double until the ceiling, then stop.
    pub fn next(self: Adaptive, current: u64) ?u64 {
        if (current >= self.ceiling_bytes) return null;
        const grown = current *| 2;
        return @min(grown, self.ceiling_bytes);
    }
};

/// How an adaptive search terminated.
pub const Convergence = enum {
    /// Growing the window stopped changing the answer. The boundary is real.
    converged,
    /// The ceiling was reached while the answer was still moving. The result is
    /// the widest one obtained, and it may not be the true boundary.
    ceiling_reached,
    /// No window produced an answer at all.
    unresolved,

    pub fn trustworthy(self: Convergence) bool {
        return self == .converged;
    }
};

/// Result of walking forward from `origin` under `limits`.
pub const WalkOutcome = enum {
    /// A step callback asked to stop and the walk succeeded.
    matched,
    /// The instruction budget ran out.
    instruction_budget,
    /// The byte budget ran out.
    byte_budget,
    /// Bytes could not be decoded.
    undecodable,
};

pub const Walk = struct {
    outcome: WalkOutcome,
    /// Address the walk stopped at.
    cursor: u64,
    /// Instructions consumed.
    steps: u8,

    pub fn exhausted(self: Walk) bool {
        return self.outcome == .instruction_budget or self.outcome == .byte_budget;
    }
};

/// Walk forward decoding instructions, invoking `step` at each boundary.
///
/// `step` returns true to stop (`.matched`). `decodeLen` returns the
/// instruction length at an address, or null/0 when the bytes are not a
/// decodable instruction. Neither callback may follow control flow: this is a
/// reader, and a reader that chases branches is an interpreter.
pub fn walkForward(
    comptime Ctx: type,
    ctx: Ctx,
    origin: u64,
    limits: Limits,
    comptime decodeLen: fn (Ctx, u64) ?u8,
    comptime step: fn (Ctx, u64, u8) bool,
) Walk {
    var cursor = origin;
    var steps: u8 = 0;
    while (true) {
        if (steps >= limits.max_instructions) {
            return .{ .outcome = .instruction_budget, .cursor = cursor, .steps = steps };
        }
        if (!limits.withinBytes(origin, cursor)) {
            return .{ .outcome = .byte_budget, .cursor = cursor, .steps = steps };
        }
        const len = decodeLen(ctx, cursor) orelse {
            return .{ .outcome = .undecodable, .cursor = cursor, .steps = steps };
        };
        if (len == 0) {
            return .{ .outcome = .undecodable, .cursor = cursor, .steps = steps };
        }
        if (step(ctx, cursor, len)) {
            return .{ .outcome = .matched, .cursor = cursor, .steps = steps };
        }
        cursor +|= len;
        steps += 1;
    }
}

const TestCtx = struct {
    base: u64,
    lens: []const u8,
    stop_at: u64,

    fn decodeLen(self: TestCtx, address: u64) ?u8 {
        if (address < self.base) return null;
        const offset = address - self.base;
        if (offset >= self.lens.len) return null;
        const len = self.lens[offset];
        return if (len == 0) null else len;
    }

    fn step(self: TestCtx, address: u64, _: u8) bool {
        return address == self.stop_at;
    }
};

test "limits are distinct and named rather than repeated per call site" {
    try std.testing.expect(Limits.tail_shape.max_instructions != Limits.predicate_witness.max_instructions);
    try std.testing.expectEqual(@as(u64, 64), Limits.block_reconstruction.max_bytes);
    try std.testing.expect(Limits.withinBytes(Limits.tail_shape, 0x1000, 0x1040));
    try std.testing.expect(!Limits.withinBytes(Limits.tail_shape, 0x1000, 0x1041));
}

test "a walk that finds its target reports matched with the address" {
    var lens = [_]u8{0} ** 32;
    lens[0] = 3;
    lens[3] = 5;
    lens[8] = 4;
    const ctx = TestCtx{ .base = 0x1000, .lens = &lens, .stop_at = 0x1008 };
    const walk = walkForward(TestCtx, ctx, 0x1000, Limits.tail_shape, TestCtx.decodeLen, TestCtx.step);
    try std.testing.expectEqual(WalkOutcome.matched, walk.outcome);
    try std.testing.expectEqual(@as(u64, 0x1008), walk.cursor);
    try std.testing.expectEqual(@as(u8, 2), walk.steps);
}

test "the instruction budget stops the walk and says so" {
    var lens = [_]u8{1} ** 64;
    const ctx = TestCtx{ .base = 0x1000, .lens = &lens, .stop_at = 0xFFFF };
    const walk = walkForward(TestCtx, ctx, 0x1000, .{ .max_instructions = 4, .max_bytes = 64 }, TestCtx.decodeLen, TestCtx.step);
    try std.testing.expectEqual(WalkOutcome.instruction_budget, walk.outcome);
    try std.testing.expect(walk.exhausted());
    try std.testing.expectEqual(@as(u8, 4), walk.steps);
}

test "the byte budget stops the walk independently of the instruction count" {
    var lens = [_]u8{0} ** 64;
    var i: usize = 0;
    while (i < 64) : (i += 8) lens[i] = 8;
    const ctx = TestCtx{ .base = 0x1000, .lens = &lens, .stop_at = 0xFFFF };
    const walk = walkForward(TestCtx, ctx, 0x1000, .{ .max_instructions = 32, .max_bytes = 16 }, TestCtx.decodeLen, TestCtx.step);
    try std.testing.expectEqual(WalkOutcome.byte_budget, walk.outcome);
    try std.testing.expect(walk.exhausted());
}

test "undecodable bytes end the walk without inventing a boundary" {
    var lens = [_]u8{0} ** 32;
    lens[0] = 3;
    const ctx = TestCtx{ .base = 0x1000, .lens = &lens, .stop_at = 0xFFFF };
    const walk = walkForward(TestCtx, ctx, 0x1000, Limits.tail_shape, TestCtx.decodeLen, TestCtx.step);
    try std.testing.expectEqual(WalkOutcome.undecodable, walk.outcome);
    try std.testing.expectEqual(@as(u64, 0x1003), walk.cursor);
    try std.testing.expect(!walk.exhausted());
}
