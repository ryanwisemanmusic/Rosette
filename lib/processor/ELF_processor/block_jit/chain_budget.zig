//! The step's instruction budget and a helper's break request, kept in the
//! chain counter itself.
//!
//! Every block exit used to load three scratch words: the counter, to add
//! the block in; the break flag, which a helper sets when the glue must
//! run; and the budget, to compare the counter with. The exit checks run at
//! every block transition, and on the code-working-set benchmark (shuffled
//! ring, 1,024-8,192 hot blocks) taking the break load and its branch away
//! alone saved 1.6-3.6% of a block's time (2026-10-28).
//!
//! `Scratch.chain_count` now counts down: the glue starts it at the
//! instructions the step may still run (`start`), every exit takes its
//! block's instructions off and adds one block below `shift`, and a
//! negative count is a spent budget - one `subs` and one `b.mi`. A break
//! (`requestBreak`) makes the count negative too, by `break_offset`, far
//! past anything a budget reaches, and the glue adds that back before it
//! accounts the chain (`decode`). Only the chain's own thread writes either
//! word - every writer is a helper the chain called, or the glue - so the
//! request needs no ordering.
const a64 = @import("arm64_encode");
const core = @import("core.zig");

pub const shift = core.chain_count_shift;
pub const blocks_mask = core.chain_count_blocks_mask;

/// What a break takes off the count. A budget is at most a step's
/// instructions (16,384 in parallel mode), so the count stays negative
/// whatever the chain retires before its next exit.
pub const break_offset: u64 = 1 << 62;

/// The count for a chain that may retire `budget` instructions: it leaves
/// at the first exit that brings the total to `budget` or past it, as the
/// old `count >= budget` comparison did. A zero budget leaves at the first
/// exit.
pub fn start(budget: u64) u64 {
    return @bitCast((@as(i64, @intCast(budget)) - 1) << shift);
}

pub const Run = struct { blocks: u64, instructions: u64 };

/// What a chain started at `start(budget)` ran, from its final count.
/// `broke`: the chain's break flag, which says whether `break_offset` was
/// taken off. A count the chain did not start (nothing does that) reads as
/// no instructions rather than wrapping.
pub fn decode(count: u64, budget: u64, broke: bool) Run {
    const restored = if (broke) count +% break_offset else count;
    const remaining = @as(i64, @bitCast(restored)) >> shift;
    const ran = @as(i64, @intCast(budget)) - 1 -| remaining;
    return .{ .blocks = restored & blocks_mask, .instructions = if (ran < 0) 0 else @intCast(ran) };
}

/// Stop the chain at its next exit. Called by helpers on the chain's own
/// thread; a second request before the glue runs changes nothing.
pub fn requestBreak(scratch: *core.Scratch) void {
    if (scratch.chain_break != 0) return;
    scratch.chain_break = 1;
    scratch.chain_count -%= break_offset;
}

/// The exit's accounting: `count -= x0 << shift`, one more block, stored
/// back. Leaves N set when the chain must leave; the caller branches on
/// `.mi` once its own bookkeeping (which keeps NZCV) is done.
pub fn emitCount(c: anytype, count: a64.Reg, scratch: a64.Reg) !void {
    const offset: u32 = @offsetOf(core.Scratch, "chain_count");
    try c.emitChecked(a64.ldrImm(.doubleword, count, scratch, offset));
    try c.emit(a64.addSubShifted(.x64, .sub, true, count, count, 0, shift));
    try c.emitChecked(a64.addImm(.x64, count, count, 1));
    try c.emitChecked(a64.strImm(.doubleword, count, scratch, offset));
}

const std = @import("std");

test "a counted-down chain decodes to the blocks and instructions it ran, budget spent or not" {
    for ([_]u64{ 0, 1, 7, 2048, 16384 }) |budget| {
        for ([_]bool{ false, true }) |broke| {
            var count = start(budget);
            var ran: u64 = 0;
            var blocks: u64 = 0;
            var left = false;
            var requested = false;
            // Blocks of 1..13 instructions until the budget is spent.
            var size: u64 = 1;
            while (!left and blocks < 4000) : (size = size % 13 + 1) {
                if (broke and blocks == 2) {
                    var scratch: core.Scratch = .{ .chain_count = count };
                    requestBreak(&scratch);
                    requestBreak(&scratch);
                    count = scratch.chain_count;
                    requested = true;
                }
                count -%= size << shift;
                count +%= 1;
                ran += size;
                blocks += 1;
                left = @as(i64, @bitCast(count)) < 0;
                try std.testing.expectEqual(left, ran >= budget or (broke and blocks >= 3));
            }
            const run = decode(count, budget, requested);
            try std.testing.expectEqual(blocks, run.blocks);
            try std.testing.expectEqual(ran, run.instructions);
        }
    }
}
