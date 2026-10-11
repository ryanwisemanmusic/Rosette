//! Apply the exact live HDR resolve transform, then production robustness.
const std = @import("std");
const hdr = @import("hdr");
const robust = @import("robust");
pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.c_allocator;
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.ExpectedInputOutputMode;
    const bytes = try std.Io.Dir.cwd().readFileAllocOptions(init.io, args[1], allocator, .limited(4 << 20), .of(u32), null);
    defer allocator.free(bytes);
    const words = std.mem.bytesAsSlice(u32, bytes);
    const result = if (std.mem.eql(u8, args[3], "probe")) try hdr.rewriteUnpacksForProbe(allocator, words) else try hdr.rewrite(allocator, words);
    defer allocator.free(result.words);
    const corrected = if (result.words.len != 0) result.words else words;
    const hardened = try robust.harden(allocator, corrected);
    defer allocator.free(hardened.words);
    if (hardened.refusal != .none or hardened.stats.unclamped_dynamic_indices != 0) return error.UnsafeShader;
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = std.mem.sliceAsBytes(if (hardened.changed()) hardened.words else corrected) });
    std.debug.print("HDR_RESOLVE name={s} unpacks={d} robust_uncovered={d}\n", .{ result.name, result.unpacks, hardened.stats.unclamped_dynamic_indices });
}
