//! Bounded static reader for JIT-generated code blocks.
//!
//! Register provenance in generated code has two possible answers, and until
//! now Rosette could only reach the first:
//!
//!   * the value was produced inside the current straight-line fragment, or
//!   * the register was **live-in** — produced by a predecessor block.
//!
//! Retained execution history cannot distinguish these on a first-observation
//! fault, and a forward decoder cannot either, because x86 has no way to step
//! backwards. What it does have is anchors: any address known to be an
//! instruction boundary lets a candidate block start be *verified* by decoding
//! forward and checking that the boundaries line up.
//!
//! This module owns that reconstruction. It is deliberately a reader, not an
//! interpreter: it follows no branch, executes nothing, allocates nothing, and
//! answers "I don't know" rather than guessing. The result is a decision about
//! where a register's value came from, available on the very first execution of
//! a fragment, which is exactly when the instruction ring is useless.

const std = @import("std");
const bounded_scan = @import("bounded_scan.zig");

/// Where a register's defining instruction was found, if anywhere.
pub const Origin = enum {
    /// No block start could be verified — the anchor is not reachable by any
    /// candidate decode within the window.
    block_unresolved,
    /// A block was reconstructed and the register is written inside it.
    defined_in_block,
    /// A block was reconstructed and the register is never written in it: the
    /// value is live-in from a predecessor. This is a *finding*, not a failure
    /// — it says precisely where to look next.
    live_in_to_block,
};

pub const Definition = struct {
    origin: Origin = .block_unresolved,
    /// How the search range terminated, when found adaptively.
    convergence: bounded_scan.Convergence = .unresolved,
    /// Window the answer was actually obtained at — an observation, not a
    /// setting.
    window_bytes: u64 = 0,
    /// Verified first byte of the reconstructed block.
    block_start: u64 = 0,
    /// Instructions between `block_start` and the anchor.
    block_length: u8 = 0,
    /// Address of the defining instruction, when `origin == .defined_in_block`.
    instruction_address: u64 = 0,
    /// Instructions back from the anchor to the definition.
    distance: u8 = 0,

    pub fn decided(self: Definition) bool {
        return self.origin != .block_unresolved;
    }
};

/// Block reconstruction uses the shared bounded-scan limits so it cannot drift
/// away from the other readers. Callers may still pass a narrower window.
pub const Limits = bounded_scan.Limits;
pub const default_limits: Limits = bounded_scan.Limits.block_reconstruction;

/// Reconstruct the instruction chain ending exactly at `anchor_rip` and report
/// where `register_matches` was last written before it.
///
/// `decodeAt(ctx, address) ?Decoded` must return the instruction at `address`
/// (length and whether it defines the register), or null when the bytes are not
/// readable. `Decoded.len == 0` is treated as undecodable.
///
/// The block start is chosen as the **earliest** candidate whose decode chain
/// lands exactly on the anchor. Earlier starts produce longer verified chains,
/// and a longer chain is strictly more evidence: every instruction in it is one
/// whose boundary was confirmed by the anchor.
pub fn findDefinition(
    comptime Ctx: type,
    ctx: Ctx,
    anchor_rip: u64,
    limits: Limits,
    comptime decodeAt: fn (Ctx, u64) ?Decoded,
) Definition {
    var best_start: ?u64 = null;
    var probe = anchor_rip -| limits.max_bytes;
    while (probe < anchor_rip) : (probe += 1) {
        var cursor = probe;
        var steps: u8 = 0;
        while (cursor < anchor_rip and steps < limits.max_instructions) : (steps += 1) {
            const decoded = decodeAt(ctx, cursor) orelse break;
            if (decoded.len == 0) break;
            cursor +|= decoded.len;
        }
        if (cursor == anchor_rip) {
            best_start = probe;
            break;
        }
    }
    const start = best_start orelse return .{};

    var result = Definition{
        .origin = .live_in_to_block,
        .block_start = start,
    };
    var cursor = start;
    var index: u8 = 0;
    while (cursor < anchor_rip and index < limits.max_instructions) : (index += 1) {
        const decoded = decodeAt(ctx, cursor) orelse break;
        if (decoded.len == 0) break;
        if (decoded.defines_register) {
            result.origin = .defined_in_block;
            result.instruction_address = cursor;
            result.distance = index;
        }
        cursor +|= decoded.len;
    }
    result.block_length = index;
    return result;
}

/// Reconstruct the block by *finding* the window rather than assuming one.
///
/// Widening can only move the block start earlier (an earlier probe that still
/// chains exactly onto the anchor means there was more block). So the answer is
/// converged the moment a wider window returns the same start: nothing further
/// back verifies. That is a detected boundary, and the run reports both the
/// window it needed and whether it converged.
pub fn findDefinitionAdaptive(
    comptime Ctx: type,
    ctx: Ctx,
    anchor_rip: u64,
    adaptive: bounded_scan.Adaptive,
    comptime decodeAt: fn (Ctx, u64) ?Decoded,
) Definition {
    var window = adaptive.initial_bytes;
    var best: Definition = .{};
    while (true) {
        var attempt = findDefinition(Ctx, ctx, anchor_rip, adaptive.limitsAt(window), decodeAt);
        attempt.window_bytes = window;
        if (attempt.decided()) {
            if (best.decided() and attempt.block_start == best.block_start) {
                // A wider window found the same start: the boundary is real.
                best = attempt;
                best.convergence = .converged;
                return best;
            }
            best = attempt;
        }
        const grown = adaptive.next(window) orelse break;
        window = grown;
    }
    if (!best.decided()) {
        best.convergence = .unresolved;
        return best;
    }
    // The ceiling arrived before two consecutive windows agreed.
    best.convergence = .ceiling_reached;
    return best;
}

pub const Decoded = struct {
    len: u8,
    /// The instruction writes the register being traced.
    defines_register: bool,
};

const TestByte = struct {
    len: u8,
    defines: bool,
};

const TestCtx = struct {
    base: u64,
    program: []const TestByte,

    fn decode(self: TestCtx, address: u64) ?Decoded {
        if (address < self.base) return null;
        const offset = address - self.base;
        if (offset >= self.program.len) return null;
        const b = self.program[offset];
        if (b.len == 0) return null;
        return .{ .len = b.len, .defines_register = b.defines };
    }
};

test "a definition inside the block is located with its distance" {
    // Byte layout, base 0x1000: an instruction begins at every offset listed.
    // 0x1000 len 3 (defines), 0x1003 len 2, 0x1005 len 4 -> anchor 0x1009.
    var program = [_]TestByte{.{ .len = 0, .defines = false }} ** 16;
    program[0] = .{ .len = 3, .defines = true };
    program[3] = .{ .len = 2, .defines = false };
    program[5] = .{ .len = 4, .defines = false };
    const ctx = TestCtx{ .base = 0x1000, .program = &program };

    const found = findDefinition(TestCtx, ctx, 0x1009, .{ .max_instructions = 24, .max_bytes = 16 }, TestCtx.decode);
    try std.testing.expectEqual(Origin.defined_in_block, found.origin);
    try std.testing.expectEqual(@as(u64, 0x1000), found.block_start);
    try std.testing.expectEqual(@as(u64, 0x1000), found.instruction_address);
    try std.testing.expectEqual(@as(u8, 0), found.distance);
    try std.testing.expect(found.decided());
}

test "a register never written in the block is reported as live-in, not unknown" {
    // This is the case the old code could not express. "No definition found"
    // and "the value comes from a predecessor block" are different findings,
    // and only the second tells you where to look.
    var program = [_]TestByte{.{ .len = 0, .defines = false }} ** 16;
    program[0] = .{ .len = 3, .defines = false };
    program[3] = .{ .len = 2, .defines = false };
    program[5] = .{ .len = 4, .defines = false };
    const ctx = TestCtx{ .base = 0x1000, .program = &program };

    const found = findDefinition(TestCtx, ctx, 0x1009, .{ .max_instructions = 24, .max_bytes = 16 }, TestCtx.decode);
    try std.testing.expectEqual(Origin.live_in_to_block, found.origin);
    try std.testing.expectEqual(@as(u64, 0x1000), found.block_start);
    try std.testing.expectEqual(@as(u8, 3), found.block_length);
    try std.testing.expect(found.decided());
}

test "the latest definition wins when a register is written twice" {
    var program = [_]TestByte{.{ .len = 0, .defines = false }} ** 16;
    program[0] = .{ .len = 3, .defines = true };
    program[3] = .{ .len = 2, .defines = true };
    program[5] = .{ .len = 4, .defines = false };
    const ctx = TestCtx{ .base = 0x1000, .program = &program };

    const found = findDefinition(TestCtx, ctx, 0x1009, .{ .max_instructions = 24, .max_bytes = 16 }, TestCtx.decode);
    try std.testing.expectEqual(@as(u64, 0x1003), found.instruction_address);
    try std.testing.expectEqual(@as(u8, 1), found.distance);
}

test "an adaptive search converges and reports the window it needed" {
    // Instructions at 0x1000(3) 0x1003(2) 0x1005(4) -> anchor 0x1009. The block
    // start is 0x1000; every window at or beyond 9 bytes must agree.
    var program = [_]TestByte{.{ .len = 0, .defines = false }} ** 64;
    program[0] = .{ .len = 3, .defines = true };
    program[3] = .{ .len = 2, .defines = false };
    program[5] = .{ .len = 4, .defines = false };
    const ctx = TestCtx{ .base = 0x1000, .program = &program };

    const found = findDefinitionAdaptive(TestCtx, ctx, 0x1009, .{
        .initial_bytes = 8,
        .ceiling_bytes = 64,
    }, TestCtx.decode);
    try std.testing.expectEqual(Origin.defined_in_block, found.origin);
    try std.testing.expectEqual(bounded_scan.Convergence.converged, found.convergence);
    try std.testing.expect(found.convergence.trustworthy());
    try std.testing.expectEqual(@as(u64, 0x1000), found.block_start);
}

test "a search that never converges reports the ceiling instead of pretending" {
    // Every byte decodes as length 1, so every wider window finds a strictly
    // earlier start and the answer never stabilises. Reporting this as a result
    // would be reporting the ceiling as if it were the block boundary.
    var program = [_]TestByte{.{ .len = 1, .defines = false }} ** 256;
    program[0] = .{ .len = 1, .defines = true };
    const ctx = TestCtx{ .base = 0x1000, .program = &program };

    const found = findDefinitionAdaptive(TestCtx, ctx, 0x1080, .{
        .initial_bytes = 8,
        .ceiling_bytes = 32,
        .max_instructions = 64,
    }, TestCtx.decode);
    try std.testing.expect(found.decided());
    try std.testing.expectEqual(bounded_scan.Convergence.ceiling_reached, found.convergence);
    try std.testing.expect(!found.convergence.trustworthy());
    try std.testing.expectEqual(@as(u64, 32), found.window_bytes);
}

test "an adaptive search over unreadable bytes stays unresolved" {
    const ctx = TestCtx{ .base = 0x1000, .program = &[_]TestByte{} };
    const found = findDefinitionAdaptive(TestCtx, ctx, 0x1009, .{}, TestCtx.decode);
    try std.testing.expectEqual(bounded_scan.Convergence.unresolved, found.convergence);
    try std.testing.expect(!found.decided());
}

test "an anchor no chain reaches is unresolved rather than guessed" {
    // Every candidate start decodes past the anchor, so no boundary is
    // verified. Reporting a definition here would be inventing one.
    var program = [_]TestByte{.{ .len = 0, .defines = false }} ** 16;
    program[0] = .{ .len = 5, .defines = true };
    program[5] = .{ .len = 5, .defines = true };
    const ctx = TestCtx{ .base = 0x1000, .program = &program };

    const found = findDefinition(TestCtx, ctx, 0x1009, .{ .max_instructions = 24, .max_bytes = 16 }, TestCtx.decode);
    try std.testing.expectEqual(Origin.block_unresolved, found.origin);
    try std.testing.expect(!found.decided());
}

test "unreadable bytes do not fabricate a block" {
    const ctx = TestCtx{ .base = 0x1000, .program = &[_]TestByte{} };
    const found = findDefinition(TestCtx, ctx, 0x1009, .{ .max_instructions = 24, .max_bytes = 16 }, TestCtx.decode);
    try std.testing.expectEqual(Origin.block_unresolved, found.origin);
}
