//! Where a compiled block's code goes.
//!
//! A translated block is mostly code it almost never runs: the TLB probe and
//! helper call behind every hoisted or probed access, and an exit for every
//! check of the helpers' `abort`. In a real Xenia-compiled Halo 3 function
//! (RENDER's 2026-10-02 hot block) 181 of 1,682 words run every time and
//! about 1,340 are those paths. The emitter puts them in the assembler's cold
//! section (`emitBlock`), so the code a block runs on every execution - its
//! body, its exits and its chain hop - is one contiguous stretch, with the
//! cold paths after it.
//!
//! By default `install` lays the cold section right after the hot one. With
//! `Options.split_cold` (or `split_all`) it places the two apart instead,
//! hot parts of consecutive blocks side by side in hot pages of a 1 MiB
//! window and cold parts in that window's other pages
//! (`CodeCache.reserveSplit`), every branch between them within the window,
//! the reach of `cbz` and `b.cond`. The offline working-set benchmark
//! (`process/tests/code_working_set.zig`) measured that apart layout ahead
//! only beyond about 8,000 distinct hot blocks and behind it from about 512
//! to 4,096, the range Halo 3's main thread was estimated to run in, so
//! production keeps the contiguous layout and the split stays an offline
//! comparison. Either way the same instructions run, in the same order,
//! reached by the same branches.
const std = @import("std");
const a64 = @import("arm64_encode");
const CodeMemory = a64.code_memory.CodeCache;
const Assembler = a64.assembler.Assembler;
const Error = a64.assembler.Error || a64.code_memory.Error;

pub const Placed = struct { hot: []const u32, cold: []const u32 };

/// Offline control: place every block's cold paths apart, as
/// `Options.split_cold` would. Production leaves both off.
pub var split_all: bool = false;

/// Resolve `assembler`'s branches for where its code is placed, copy the code
/// there and make it visible to instruction fetch.
pub fn install(memory: *CodeMemory, assembler: *Assembler, split: bool) Error!Placed {
    if ((split or split_all) and assembler.cold_words.items.len != 0) placed: {
        const parts = memory.reserveSplit(assembler.words.items.len, assembler.cold_words.items.len) catch |err| switch (err) {
            // Larger than a window, or no window left: the contiguous
            // reservation below decides between placing it and a reset.
            error.OutOfCodeSpace => break :placed,
            else => return err,
        };
        const code = assembler.finishSplit(@intFromPtr(parts.hot.ptr), @intFromPtr(parts.cold.ptr)) catch |err| switch (err) {
            // Unreachable within a window; the contiguous layout still is.
            error.DisplacementTooFar => break :placed,
            else => return err,
        };
        memory.beginWrite();
        @memcpy(parts.hot, code.hot);
        @memcpy(parts.cold, code.cold);
        memory.endWrite(parts.hot);
        memory.endWrite(parts.cold);
        return .{ .hot = parts.hot, .cold = parts.cold };
    }
    const words = try assembler.finish();
    const code = try memory.reserve(words.len);
    memory.beginWrite();
    @memcpy(code, words);
    memory.endWrite(code);
    return .{ .hot = code, .cold = &.{} };
}
