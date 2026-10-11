//! Offline production rectangle + pixel-frequency + robust rewrites. Never dispatches
//! shaders. Build with --dep rect --dep robust -Mroot=this_file
//! -Mrect=lib/gpu/vulkan/rect_list_expand.zig
//! -Mrobust=lib/gpu/vulkan/robust_access.zig -lc.
const std = @import("std");
const rect = @import("rect");
const robust = @import("robust");
const sampling = @import("sampling");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.c_allocator;
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.ExpectedInputAndOutputDirectories;
    const io = init.io;
    var input = try std.Io.Dir.cwd().openDir(io, args[1], .{ .iterate = true });
    defer input.close(io);
    var output = try std.Io.Dir.cwd().createDirPathOpen(io, args[2], .{});
    defer output.close(io);
    var iter = input.iterate();
    var modules: usize = 0;
    var expanded: usize = 0;
    while (try iter.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".spv")) continue;
        const bytes = try input.readFileAllocOptions(io, entry.name, allocator, .limited(32 << 20), .of(u32), null);
        defer allocator.free(bytes);
        const original = std.mem.bytesAsSlice(u32, bytes);
        const rectangle = try rect.expand(allocator, original);
        defer allocator.free(rectangle.words);
        const rewritten = if (rectangle.refusal == .none) rectangle.words else original;
        const frequency = try sampling.centerCoordinates(allocator, rewritten);
        defer allocator.free(frequency.words);
        const pixel = if (frequency.words.len != 0) frequency.words else rewritten;
        const hardened = try robust.harden(allocator, pixel);
        defer allocator.free(hardened.words);
        if (hardened.refusal != .none or hardened.stats.unclamped_dynamic_indices != 0) return error.UnsafeShader;
        const final = if (hardened.changed()) hardened.words else pixel;
        try output.writeFile(io, .{ .sub_path = entry.name, .data = std.mem.sliceAsBytes(final) });
        modules += 1;
        if (rectangle.refusal == .none) expanded += 1;
        std.debug.print("{s}: rectangle={s} outputs={d} uncovered={d} coordinates={s} centered_loads={d} removed={d}\n", .{ entry.name, rectangle.refusal.label(), rectangle.combined_outputs, hardened.stats.unclamped_dynamic_indices, @tagName(frequency.reason), frequency.centered_loads, frequency.removed });
    }
    std.debug.print("TOTAL modules={d} expanded={d}; offline only\n", .{ modules, expanded });
}
